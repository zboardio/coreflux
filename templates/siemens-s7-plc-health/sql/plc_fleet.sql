-- The fleet layer of the historian: the PLC MODELS, the derived states as functions, and plc_latest, one row per PLC.
-- Read by the template's Grafana (plc-fleet, plc-detail-<family>) and its alert rules (rules-plc.yml), so a tile, the
-- fleet table and a rule give one answer from one definition.
--
-- Two levels, both data: a MODEL is what the hardware is (plc_model: family, the interfaces it offers, the default
-- maximum cycle time); a PLC is one device (plc_registry, schema.sql: its model, area, watchdog and the PATHS IN USE).
-- Everything path-shaped iterates plc_registry.paths; the family decides only what truly differs (layout 1 with the
-- diagnostic buffer on an S7-300, layout 2 with the error-OB slots, LEDs and RT_INFO on an S7-1500).
--
-- Idempotent: safe to re-run. Apply after schema.sql (it needs plc_registry and the tables) and before role.sql, whose
-- loop grants SELECT on every plc_* relation to grafana_reader. The writer gets nothing here: plc_ingest() reads none
-- of it. Functions are STABLE, run as the caller (grafana_reader), EXECUTE is PUBLIC's by default. Every lookup is by
-- plc_id on an index (schema.sql: plc_cycle_plc_ts, plc_diag_state_plc_ts, plc_read_path, plc_state_change's key), so
-- plc_latest costs the same per PLC whatever the fleet's history.

CREATE TABLE IF NOT EXISTS plc_model (
    model               text    PRIMARY KEY,            -- as plc_registry.model names it, e.g. 'CPU 1511-1 PN'
    family              text    NOT NULL,               -- s7-300 | s7-1500: the DB_PerfDiag layout, the detail page's family sections
    interfaces          text[]  NOT NULL,               -- what the hardware OFFERS (TIA's X1, X2 …); the paths in use: plc_registry.paths
    watchdog_default_ms integer NOT NULL DEFAULT 150,   -- TIA's preset maximum cycle time; a PLC's own: plc_registry.watchdog_ms
    description         text
);
-- Git is the source: a re-apply puts every row back as written here.
INSERT INTO plc_model (model, family, interfaces, watchdog_default_ms, description) VALUES
    ('CPU 315-2 PN/DP', 's7-300', '{X1 MPI/DP,X2 PN}', 150, 'S7-300, an MPI/DP interface and one PROFINET interface'),
    ('CPU 1511-1 PN', 's7-1500', '{X1 PN}', 150, 'S7-1500, one PROFINET interface (two ports)')
ON CONFLICT (model) DO UPDATE SET family = EXCLUDED.family, interfaces = EXCLUDED.interfaces,
                                  watchdog_default_ms = EXCLUDED.watchdog_default_ms, description = EXCLUDED.description;

-- ── the PLC as data ───────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION plc_paths(p text) RETURNS text[] LANGUAGE sql STABLE AS $$
  SELECT coalesce((SELECT paths FROM plc_registry WHERE plc_id = p), '{}')
$$;

CREATE OR REPLACE FUNCTION plc_family(p text) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT coalesce(r.family, m.family) FROM plc_registry r LEFT JOIN plc_model m ON m.model = r.model WHERE r.plc_id = p
$$;

-- The maximum cycle time the alerts and the cycle panels compare with: the PLC's own, else its model's preset, else 150.
CREATE OR REPLACE FUNCTION plc_watchdog_ms(p text) RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT coalesce(r.watchdog_ms, m.watchdog_default_ms, 150) FROM plc_registry r LEFT JOIN plc_model m ON m.model = r.model
  WHERE r.plc_id = p
$$;

-- The firmware it runs: what the CPU reports (an S7-300's SZL 0x0111 index 7, read by plc_firmware(); the raw hex when
-- the record has another shape), else as configured (plc_registry.firmware: an S7-1500 on FW V2.6 reports none).
CREATE OR REPLACE FUNCTION plc_firmware_of(p text) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT coalesce((SELECT coalesce(plc_firmware(d.firmware_hex), d.firmware_hex) FROM plc_diag_state d
                   WHERE d.plc_id = p AND plc_family(p) = 's7-300' AND d.firmware_hex IS NOT NULL AND d.ts > now() - interval '1 day'
                   ORDER BY d.ts DESC LIMIT 1),
                  (SELECT firmware FROM plc_registry WHERE plc_id = p))
$$;

-- ── the evidence ─────────────────────────────────────────────────────────────────────────────────────────────
-- The broker sends anything for this PLC: a read, failed or not, in the last 90 s (3 PerfMon reads of a path).
-- False = the broker, its route or the store is gone: every tile then says NO DATA rather than guess.
CREATE OR REPLACE FUNCTION plc_alive(p text) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM plc_read WHERE plc_id = p AND ts > now() - interval '90 seconds')
$$;

-- The newest read without error on one path (any DB, or one DB), within a day; NULL = none.
CREATE OR REPLACE FUNCTION plc_last_ok(p text, path text, dbs text[] DEFAULT '{PerfMon,PerfDiag,PerfHealth}') RETURNS timestamptz
LANGUAGE sql STABLE AS $$
  SELECT max(r.ts) FROM unnest(dbs) AS k(db),
         LATERAL (SELECT ts FROM plc_read WHERE plc_id = p AND via = path AND db_name = k.db AND error IS NULL
                  AND ts > now() - interval '1 day' ORDER BY ts DESC LIMIT 1) r
$$;

-- … on any of the PLC's paths.
CREATE OR REPLACE FUNCTION plc_last_ok(p text) RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT max(plc_last_ok(p, x)) FROM unnest(plc_paths(p)) AS x
$$;

-- The broker's newest verdict (plc_state_change: CpuScanning, DeviceStatus, Health) on a path, at a time; NULL = none.
CREATE OR REPLACE FUNCTION plc_verdict(p text, path text, sig text, at timestamptz DEFAULT now()) RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT value FROM plc_state_change WHERE plc_id = p AND via = path AND signal = sig AND ts <= at ORDER BY ts DESC LIMIT 1
$$;

-- The broker's verdicts over the PLC's paths at a time: 'run' (CpuScanning true on an online path), 'unreachable'
-- (verdicts stored, no path online), 'frozen' (an online path says CpuScanning false, none says true), 'unknown' (online,
-- no CpuScanning verdict yet), NULL = no DeviceStatus verdict on any path (a fresh historian: the reads decide). The
-- fleet's state timeline evaluates it at every change.
CREATE OR REPLACE FUNCTION plc_verdict_state(p text, at timestamptz DEFAULT now()) RETURNS text LANGUAGE sql STABLE AS $$
  WITH v AS (SELECT plc_verdict(p, x, 'DeviceStatus', at) AS ds, plc_verdict(p, x, 'CpuScanning', at) AS sc
             FROM unnest(plc_paths(p)) AS x)
  SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM v WHERE ds IS NOT NULL) THEN NULL
              WHEN EXISTS (SELECT 1 FROM v WHERE ds = 'online' AND sc = 'true') THEN 'run'
              WHEN NOT EXISTS (SELECT 1 FROM v WHERE ds = 'online') THEN 'unreachable'
              WHEN EXISTS (SELECT 1 FROM v WHERE ds = 'online' AND sc = 'false') THEN 'frozen'
              ELSE 'unknown' END
$$;

-- Before the first verdict, the reads decide, and a frozen Seq is PROVEN, never assumed from an age: reads = a PerfMon
-- read without error in the last 90 s; frozen = that read is stamped after the newest record's arrival, so it brought no
-- record (one transaction stamps a read and the records it brought with the same now()). The newest record is the one
-- with the newest PLC stamp (an index lookup), whose arrival is the newest arrival: the first path wins every record.
CREATE OR REPLACE FUNCTION plc_read_proof(p text, OUT reads boolean, OUT frozen boolean) LANGUAGE sql STABLE AS $$
  SELECT coalesce(pm.t > now() - interval '90 seconds', false),
         coalesce(pm.t > coalesce(rec.t, '-infinity') + interval '1 second', false)
  FROM (SELECT max(plc_last_ok(p, x, '{PerfMon}')) AS t FROM unnest(plc_paths(p)) AS x) pm
  LEFT JOIN LATERAL (SELECT ts_received AS t FROM plc_cycle WHERE plc_id = p AND ts_plc > now() - interval '2 days'
                     ORDER BY ts_plc DESC LIMIT 1) rec ON true
$$;

-- ── the derived states (detail tiles 101, 102, 103, 107; plc_latest; rules-plc.yml) ──────────────────────────────
-- `OFFSET 0` on a one-row subquery whose value a CASE reads several times: without it Postgres pulls the subquery up
-- and evaluates the function once per reference (measured: plc_latest 4× slower at 50 PLCs).
-- Path status: 1 online, 2 stale, 0 offline — the broker's DeviceStatus, else a read without error in 90 s; NULL = the
-- broker sends nothing for this PLC.
CREATE OR REPLACE FUNCTION plc_path_state(p text, path text) RETURNS smallint LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN NOT plc_alive(p) THEN NULL
              WHEN d.v = 'online' THEN 1 WHEN d.v = 'stale' THEN 2 WHEN d.v = 'offline' THEN 0
              WHEN plc_last_ok(p, path) > now() - interval '90 seconds' THEN 1 ELSE 0 END::smallint
  FROM (SELECT plc_verdict(p, path, 'DeviceStatus') AS v OFFSET 0) d
$$;

-- CPU scanning: 1 scanning, 0 not scanning (online, Seq frozen), NULL unknown (no path online, no verdict, no data).
CREATE OR REPLACE FUNCTION plc_scanning(p text) RETURNS smallint LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN NOT plc_alive(p) THEN NULL
              WHEN s.v = 'run' THEN 1 WHEN s.v = 'frozen' THEN 0 WHEN s.v IS NOT NULL THEN NULL
              WHEN NOT pr.reads THEN NULL WHEN pr.frozen THEN 0 ELSE 1 END::smallint
  FROM (SELECT plc_verdict_state(p) AS v OFFSET 0) s CROSS JOIN (SELECT * FROM plc_read_proof(p) OFFSET 0) pr
$$;

-- CPU state: 3 RUN, 2 STARTUP, 1 STOP — FAULT, 0 STOP (or HALT), -1 UNREACHABLE, -2 UNKNOWN (a path online,
-- no CpuScanning verdict yet), NULL NO DATA. Online but frozen: STARTUP when the newest mode-transition entry of the
-- diagnostic buffer (class 4, priority byte 0xFF) entered STARTUP (6) after the last record, or a boot stamped under
-- 5 min ago has no record yet; STOP — FAULT when an error OB recorded a fault after the last record (S7-300, plc_fault).
CREATE OR REPLACE FUNCTION plc_cpu_state(p text) RETURNS smallint LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN NOT plc_alive(p) THEN NULL
              WHEN s.v = 'run' THEN 3
              WHEN s.v = 'unreachable' THEN -1
              WHEN s.v = 'unknown' THEN -2
              WHEN s.v IS NULL AND NOT pr.reads THEN -1
              WHEN s.v IS NULL AND NOT pr.frozen THEN 3
              WHEN (m.entered = '6' AND m.ts_plc > coalesce(rec.plc_t, '-infinity'))
                OR (b.ts_boot > now() - interval '5 minutes' AND NOT EXISTS (SELECT 1 FROM plc_cycle c WHERE c.plc_id = p
                    AND c.boot_date = b.boot_date AND c.boot_time = b.boot_time AND c.ts_plc > now() - interval '2 days')) THEN 2
              WHEN f.t > coalesce(rec.plc_t, '-infinity') THEN 1
              ELSE 0 END::smallint
  FROM (SELECT plc_verdict_state(p) AS v OFFSET 0) s
  CROSS JOIN (SELECT * FROM plc_read_proof(p) OFFSET 0) pr
  CROSS JOIN (SELECT max(ts_fault) AS t FROM plc_fault WHERE plc_id = p) f
  LEFT JOIN LATERAL (SELECT ts_plc AS plc_t FROM plc_cycle WHERE plc_id = p AND ts_plc > now() - interval '2 days'
                     ORDER BY ts_plc DESC LIMIT 1) rec ON true
  LEFT JOIN LATERAL (SELECT boot_date, boot_time, ts_boot FROM plc_boot WHERE plc_id = p
                     ORDER BY boot_date DESC, boot_time DESC LIMIT 1) b ON true
  LEFT JOIN LATERAL (SELECT ts_plc, substr(entry_hex, 8, 1) AS entered FROM plc_diag_event
                     WHERE plc_id = p AND lower(substr(entry_hex, 5, 2)) = 'ff' AND event_id >> 12 = 4
                       AND ts_plc > now() - interval '30 days' ORDER BY ts_plc DESC LIMIT 1) m ON true
$$;

CREATE OR REPLACE FUNCTION plc_state_text(state smallint) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE state WHEN 3 THEN 'RUN' WHEN 2 THEN 'STARTUP' WHEN 1 THEN 'STOP — FAULT' WHEN 0 THEN 'STOP'
                    WHEN -1 THEN 'UNREACHABLE' WHEN -2 THEN 'UNKNOWN' ELSE 'NO DATA' END
$$;

-- Health loop of one slot (= a path, DB_PerfHealth): 0 OK, 1 STALLED, 2 CORRUPT, 3 NOT JUDGED (the CPU not scanning,
-- or no path online), NULL no data. The broker's Health verdict, else the newest row of the last 90 s.
CREATE OR REPLACE FUNCTION plc_health_state(p text, slot_name text) RETURNS smallint LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN NOT plc_alive(p) THEN NULL
              WHEN s.v = 'unreachable' THEN 3
              WHEN h.v = 'ok' THEN 0 WHEN h.v = 'stalled' THEN 1 WHEN h.v = 'corrupt' THEN 2 WHEN h.v = 'unknown' THEN 3
              WHEN r.n = 0 THEN NULL
              WHEN pr.reads AND pr.frozen THEN 3
              WHEN r.rose THEN 2 WHEN r.age > 15 THEN 1 ELSE 0 END::smallint
  FROM (SELECT plc_verdict_state(p) AS v OFFSET 0) s
  CROSS JOIN (SELECT plc_verdict(p, slot_name, 'Health') AS v OFFSET 0) h
  CROSS JOIN (SELECT * FROM plc_read_proof(p) OFFSET 0) pr
  CROSS JOIN (SELECT count(*) AS n, (array_agg(bad_echo ORDER BY ts DESC))[1] > (array_agg(bad_echo ORDER BY ts))[1] AS rose,
                     (array_agg(age_s ORDER BY ts DESC))[1] AS age
              FROM plc_health WHERE plc_id = p AND slot = slot_name AND ts > now() - interval '90 seconds') r
$$;

-- Seconds the CPU has been PROVEN not scanning (rule plc_not_scanning, fires above 30 s): with verdicts, since
-- CpuScanning went false on an online path while none says true; before them, since the first PerfMon read without
-- error that brought no new record. 0 while the broker sends nothing (plc_unreachable's business).
CREATE OR REPLACE FUNCTION plc_seconds_frozen(p text) RETURNS double precision LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN NOT plc_alive(p) THEN 0
              WHEN s.v IS NOT NULL THEN CASE WHEN s.v <> 'frozen' THEN 0 ELSE coalesce(
                (SELECT extract(epoch FROM now() - min(f.ts)) FROM unnest(plc_paths(p)) AS x,
                        LATERAL (SELECT value, ts FROM plc_state_change WHERE plc_id = p AND via = x AND signal = 'CpuScanning'
                                 ORDER BY ts DESC LIMIT 1) f
                 WHERE f.value = 'false' AND plc_verdict(p, x, 'DeviceStatus') = 'online'), 0) END
              WHEN NOT pr.reads THEN 0
              ELSE coalesce((SELECT extract(epoch FROM now() - min(q.ts)) FROM plc_read q
                             WHERE q.plc_id = p AND q.db_name = 'PerfMon' AND q.error IS NULL AND q.ts > now() - interval '1 day'
                               AND q.ts > coalesce((SELECT ts_received FROM plc_cycle WHERE plc_id = p AND ts_plc > now() - interval '2 days'
                                                    ORDER BY ts_plc DESC LIMIT 1), '-infinity') + interval '1 second'), 0) END
  FROM (SELECT plc_verdict_state(p) AS v OFFSET 0) s CROSS JOIN (SELECT * FROM plc_read_proof(p) OFFSET 0) pr
$$;

-- Error-OB activity in the last 24 h. S7-300: the ring's OB80 calls plus the faults an error OB recorded before a STOP
-- (OB82/OB86 are counted per boot only). S7-1500: the calls of its six error OBs (plc_ob_call holds the count since the
-- boot at each newest call: the rise since 24 h ago, or the whole count when the CPU booted since). Not "faults": a
-- program can call OB122 2,000 times a second on purpose (the bench does).
CREATE OR REPLACE FUNCTION plc_faults_24h(p text) RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN plc_family(p) = 's7-1500' THEN
           (SELECT coalesce(sum(CASE WHEN o.prior IS NOT NULL AND o.prior <= o.cur THEN o.cur - o.prior ELSE o.cur END), 0)
            FROM (SELECT (SELECT calls FROM plc_ob_call WHERE plc_id = p AND ob_nr = k.ob AND ts_plc > now() - interval '24 hours'
                          ORDER BY ts_plc DESC LIMIT 1) AS cur,
                         (SELECT calls FROM plc_ob_call WHERE plc_id = p AND ob_nr = k.ob AND ts_plc <= now() - interval '24 hours'
                          ORDER BY ts_plc DESC LIMIT 1) AS prior
                  FROM unnest('{80,82,83,86,121,122}'::smallint[]) AS k(ob)) o
            WHERE o.cur IS NOT NULL)
         ELSE (SELECT coalesce(sum(ob80), 0) FROM plc_cycle_1h WHERE plc_id = p AND bucket > now() - interval '24 hours')
              + (SELECT count(*) FROM plc_fault WHERE plc_id = p AND ts_fault > now() - interval '24 hours') END::bigint
$$;

-- ── plc_latest: one row per PLC, the fleet overview in one query ──────────────────────────────────────────────
-- area/family/model never NULL ('(none)', '(unknown)'), so the fleet's multi-value filters see every PLC. A filter on
-- them is applied to plc_registry before any state is derived. severity orders the fleet worst first:
-- 5 STOP — FAULT or UNREACHABLE · 4 STOP · 3 NO DATA or UNKNOWN · 2 STARTUP, a path not online, the health loop stalled or
-- corrupt, or the cycle at 80 % of the watchdog · 1 error-OB activity in 24 h or the cycle at 50 % · 0 nothing to see.
-- Each state is derived ONCE per PLC: `OFFSET 0` keeps Postgres from pulling a one-row LATERAL up into the outer query,
-- which would call plc_cpu_state() again for every column that reads it (measured: 4× slower at 50 PLCs, 530 ms against 130).
-- Dropped and created, so a changed column list applies.
DROP VIEW IF EXISTS plc_latest;
CREATE VIEW plc_latest AS
SELECT r.plc_id, coalesce(r.area, '(none)') AS area, coalesce(r.family, m.family, '(unknown)') AS family,
       coalesce(r.model, '(unknown)') AS model, r.order_no,
       coalesce(plc_firmware_of(r.plc_id), '(unknown)') AS firmware,
       coalesce(r.paths, '{}') AS paths, cardinality(coalesce(r.paths, '{}')) AS paths_total, ps.paths_online, ps.path_states,
       a.alive, st.state, plc_state_text(st.state) AS state_text, hs.health,
       c.cyc_avg_ms, c.cyc_max_ms, c5.cyc_max_5m_ms, w.watchdog_ms,
       round((c5.cyc_max_5m_ms / w.watchdog_ms * 100)::numeric, 1) AS cyc_max_pct,
       fz.faults_24h,
       lo.last_ok, extract(epoch FROM now() - lo.last_ok) AS data_age_s,
       (SELECT max(ts_boot) FROM plc_boot b WHERE b.plc_id = r.plc_id) AS last_boot,
       CASE WHEN st.state IN (-1, 1) THEN 5 WHEN st.state = 0 THEN 4 WHEN st.state IS NULL OR st.state = -2 THEN 3
            WHEN st.state = 2 OR ps.paths_online < cardinality(coalesce(r.paths, '{}')) OR hs.health IN (1, 2)
                 OR c5.cyc_max_5m_ms >= 0.8 * w.watchdog_ms THEN 2
            WHEN fz.faults_24h > 0 OR c5.cyc_max_5m_ms >= 0.5 * w.watchdog_ms THEN 1
            ELSE 0 END AS severity
FROM plc_registry r
LEFT JOIN plc_model m ON m.model = r.model
CROSS JOIN LATERAL (SELECT coalesce(r.watchdog_ms, m.watchdog_default_ms, 150) AS watchdog_ms) w
CROSS JOIN LATERAL (SELECT plc_alive(r.plc_id) AS alive OFFSET 0) a
CROSS JOIN LATERAL (SELECT plc_cpu_state(r.plc_id) AS state OFFSET 0) st
CROSS JOIN LATERAL (SELECT plc_last_ok(r.plc_id) AS last_ok OFFSET 0) lo
CROSS JOIN LATERAL (SELECT plc_faults_24h(r.plc_id) AS faults_24h OFFSET 0) fz
LEFT JOIN LATERAL (SELECT count(*) FILTER (WHERE q.s = 1) AS paths_online,
                          string_agg(u.x || ' ' || CASE q.s WHEN 1 THEN 'online' WHEN 2 THEN 'stale' WHEN 0 THEN 'offline' ELSE 'no data' END,
                                     ' · ' ORDER BY u.i) AS path_states
                   FROM unnest(r.paths) WITH ORDINALITY AS u(x, i), LATERAL (SELECT plc_path_state(r.plc_id, u.x) AS s OFFSET 0) q) ps ON true
LEFT JOIN LATERAL (SELECT CASE WHEN bool_or(q.h = 2) THEN 2 WHEN bool_or(q.h = 1) THEN 1 WHEN bool_or(q.h = 0) THEN 0
                               WHEN bool_or(q.h = 3) THEN 3 END::smallint AS health
                   FROM unnest(r.paths) AS x, LATERAL (SELECT plc_health_state(r.plc_id, x) AS h OFFSET 0) q) hs ON true
LEFT JOIN LATERAL (SELECT cyc_avg_ms, cyc_max_ms FROM plc_cycle WHERE plc_id = r.plc_id AND ts_plc > now() - interval '2 days'
                   ORDER BY ts_plc DESC LIMIT 1) c ON true
LEFT JOIN LATERAL (SELECT max(cyc_max_ms) AS cyc_max_5m_ms FROM plc_cycle
                   WHERE plc_id = r.plc_id AND ts_plc > now() - interval '5 minutes') c5 ON true;

-- role.sql's pattern: SELECT for the reader, when it exists (role.sql creates it, and grants this again on every apply).
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'grafana_reader') THEN
        GRANT SELECT ON plc_model, plc_latest TO grafana_reader;
    END IF;
END
$$;
