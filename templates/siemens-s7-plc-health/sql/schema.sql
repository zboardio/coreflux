-- Metrics and diagnostics of Siemens S7 PLCs read by the health kit, TimescaleDB, keyed by plc_id. One database for
-- every PLC the broker reads: the example registry holds PLC01, an S7-300, and PLC02, an S7-1500.
--
-- FACTS and EVIDENCE are apart, or every roll-up doubles: a fact is one row whichever path delivered it first,
-- plc_arrival holds one row per fact per path. The same read over two paths can then be compared byte for byte.
-- plc_ingest() takes one decoded read, as the store route sends it. The writer role can only INSERT, so everything
-- here dedupes with ON CONFLICT DO NOTHING and nothing is ever updated.
--
-- Idempotent: safe to re-run. Apply in this order: schema.sql, plc_fleet.sql, s7_1500_ob_fault.sql, s7_event_text.sql,
-- then role.sql (README.md of this folder).

CREATE EXTENSION IF NOT EXISTS timescaledb;

-- STABLE, not IMMUTABLE: make_timestamptz depends on the time-zone database.
CREATE OR REPLACE FUNCTION plc_stamp(stamp_date integer, stamp_time integer, tz text DEFAULT 'UTC')
RETURNS timestamptz LANGUAGE sql STABLE AS $$
  SELECT make_timestamptz(stamp_date / 10000, (stamp_date / 100) % 100, stamp_date % 100,
                          stamp_time / 10000000, (stamp_time / 100000) % 100,
                          ((stamp_time / 1000) % 100) + (stamp_time % 1000) / 1000.0, tz)
$$;

-- The firmware version from plc_diag_state.firmware_hex, DB_PerfDiag.IdFirmware: the 28-byte SZL 0x0111 index 7 record
-- as RDSYSST wrote it — Index (2), MlfB (20), BGTyp (2), Ausbg (2: 'V' and the major), Ausbe (2: minor, patch).
-- NULL when it is not that shape: the panel then shows the raw hex. The order number, serial and station name are
-- ASCII and arrive as text already (the decoder's _text()).
CREATE OR REPLACE FUNCTION plc_firmware(firmware_hex text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN length($1) = 56 AND $1 ~ '^[0-9a-fA-F]+$' AND lower(substr($1, 49, 2)) = '56'
              THEN 'V' || get_byte(decode($1, 'hex'), 25) || '.' || get_byte(decode($1, 'hex'), 26) || '.'
                   || get_byte(decode($1, 'hex'), 27) END
$$;

CREATE TABLE IF NOT EXISTS plc_registry (
    plc_id      text PRIMARY KEY,
    clock_zone  text NOT NULL DEFAULT 'UTC',   -- what the CPU's clock is set to
    description text
);
-- family, model, order_no: what a fleet table shows per PLC; the decoder's PLCS holds the same.
ALTER TABLE plc_registry ADD COLUMN IF NOT EXISTS family text, ADD COLUMN IF NOT EXISTS model text, ADD COLUMN IF NOT EXISTS order_no text;
-- The example PLCs, one per family: replace them with yours (plc_id as the decoder's PLCS names it).
INSERT INTO plc_registry (plc_id, clock_zone, description)
VALUES ('acme-site01-plc01', 'UTC', 'CPU 315-2 PN/DP, read over PN')
ON CONFLICT (plc_id) DO NOTHING;
UPDATE plc_registry SET family = 's7-300', model = 'CPU 315-2 PN/DP', order_no = '6ES7 315-2EH13-0AB0'
WHERE plc_id = 'acme-site01-plc01' AND family IS NULL;
-- RD_SYS_T on an S7-1500 is UTC, whatever the CPU's local-time setting: clock_zone 'UTC' always.
INSERT INTO plc_registry (plc_id, clock_zone, description, family, model, order_no)
VALUES ('acme-site01-plc02', 'UTC', 'CPU 1511-1 PN, FW V2.6, PN only (PUT/GET)', 's7-1500', 'CPU 1511-1 PN', '6ES7 511-1AK02-0AB0')
ON CONFLICT (plc_id) DO NOTHING;
-- The fleet columns (the fleet overview and the path-aware detail page). The MODEL is the
-- hardware (plc_model, plc_fleet.sql: family, the interfaces it offers, the default maximum cycle time); these are the
-- DEVICE: `paths` = the reading paths IN USE, in the decoder's PLCS order (a 315-2 PN/DP may be read over PN only; every
-- path-shaped panel and rule iterates this list, never a hard-coded MPI/PN), `area` = where it sits (the fleet's filter),
-- `watchdog_ms` = its configured maximum cycle time (NULL = the model's default), `firmware` = as configured, shown when
-- the CPU does not report one (an S7-1500 on TIA V15.1 has no Get_IM_Data). Filled once per PLC, never overwritten.
-- These rows and the decoder's PLCS are kept equal by hand: one registry row per PLC the broker reads, its paths in
-- PLCS order. A second path added later: UPDATE plc_registry SET paths = '{PN,MPI}' WHERE plc_id = '…'.
ALTER TABLE plc_registry ADD COLUMN IF NOT EXISTS paths text[], ADD COLUMN IF NOT EXISTS area text,
                         ADD COLUMN IF NOT EXISTS watchdog_ms integer, ADD COLUMN IF NOT EXISTS firmware text;
UPDATE plc_registry SET paths = '{PN}', area = 'site01' WHERE plc_id = 'acme-site01-plc01' AND paths IS NULL;
UPDATE plc_registry SET paths = '{PN}', area = 'site01', firmware = 'V2.6' WHERE plc_id = 'acme-site01-plc02' AND paths IS NULL;
-- Since 2026-11-19 a PLC REGISTERS ITSELF: the broker sends its row once a minute (the decoder's registration(), kind
-- "Register"), plc_ingest() inserts it when missing and its model into plc_model the same way; nothing here per PLC. The two
-- rows above predate that and stay. A change to a registered row (area, watchdog_ms …) is an UPDATE: the writer cannot.

-- One per record, first path wins.
CREATE TABLE IF NOT EXISTS plc_cycle (
    ts_plc        timestamptz NOT NULL,   -- from the PLC's stamp, deterministic, so the dedupe works
    ts_received   timestamptz NOT NULL DEFAULT now(),
    plc_id        text        NOT NULL,
    boot_date     integer     NOT NULL,
    boot_time     integer     NOT NULL,
    seq           integer     NOT NULL,
    window_ms     smallint,
    cycles        integer,
    cyc_min_ms    real,
    cyc_max_ms    real,
    cyc_avg_ms    real,
    comm_load_pct real,                   -- NULL when the PLC sends -1
    hist          integer[],              -- index 1..8 = PLC Hist[0..7]
    flags         integer,                -- WORD: a smallint would overflow on bit 15
    ob80_cnt      smallint
);
SELECT create_hypertable('plc_cycle', 'ts_plc', chunk_time_interval => INTERVAL '1 day', if_not_exists => TRUE);
CREATE UNIQUE INDEX IF NOT EXISTS plc_cycle_uk ON plc_cycle (plc_id, boot_date, boot_time, seq, ts_plc);
-- The newest record of ONE PLC (plc_latest, the detail tiles): without it a PLC that stopped delivering is found by walking
-- back through every PLC's records (86,400 a day each). Created on compressed chunks too (measured on 2.30.1).
CREATE INDEX IF NOT EXISTS plc_cycle_plc_ts ON plc_cycle (plc_id, ts_plc DESC);

-- One per fact per path: when it first came, and a hash of its bytes. 7 days are enough to compare the paths.
CREATE TABLE IF NOT EXISTS plc_arrival (
    ts_plc      timestamptz NOT NULL,
    ts_received timestamptz NOT NULL DEFAULT now(),
    plc_id      text        NOT NULL,
    via         text        NOT NULL,
    kind        text        NOT NULL,
    fact_key    text        NOT NULL,
    fact_hash   text        NOT NULL
);
SELECT create_hypertable('plc_arrival', 'ts_plc', chunk_time_interval => INTERVAL '1 day', if_not_exists => TRUE);
CREATE UNIQUE INDEX IF NOT EXISTS plc_arrival_uk ON plc_arrival (plc_id, via, kind, fact_key, ts_plc);
SELECT add_retention_policy('plc_arrival', INTERVAL '7 days', if_not_exists => TRUE);

-- One per read, ok or not: the transport's own record, per path and DB.
CREATE TABLE IF NOT EXISTS plc_read (
    ts          timestamptz NOT NULL DEFAULT now(),
    plc_id      text        NOT NULL,
    via         text        NOT NULL,
    db_name     text        NOT NULL,
    read_ms     integer,
    bytes       integer,
    accepted    integer,
    rej_empty   integer,
    rej_future  integer,
    rej_slot    integer,
    rej_old     integer,
    rej_stamp   integer,
    decode_ms   real,
    error       text
);
SELECT create_hypertable('plc_read', 'ts', chunk_time_interval => INTERVAL '1 day', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS plc_read_path ON plc_read (plc_id, via, db_name, ts DESC);
-- Records of an EARLIER boot the read offered (2026-11-22): the previous boot's tail, still in the ring after a restart.
-- How many of them were new to the historian is in plc_cycle (plc_ingest() files them under that boot).
ALTER TABLE plc_read ADD COLUMN IF NOT EXISTS earlier integer;

-- One per boot, as DB_PerfMon's header names it.
CREATE TABLE IF NOT EXISTS plc_boot (
    plc_id        text    NOT NULL,
    boot_date     integer NOT NULL,
    boot_time     integer NOT NULL,
    ts_boot       timestamptz,
    restart_count integer,
    edges_ms      real[],
    PRIMARY KEY (plc_id, boot_date, boot_time)
);
-- When this node first stored the boot (2026-11-10): the order of boots BY ARRIVAL, which a CPU clock that was not set
-- (an S7-1500 starts at 2012-01-01) or that jumps back cannot disturb, as ts_boot and boot_date can. Filled by the
-- default on insert (plc_ingest names no value; ON CONFLICT DO NOTHING keeps the first); rows stored before the column
-- existed keep NULL — nothing to recover them from — and sort after it (the boots table, the cycle tiles' current boot).
ALTER TABLE plc_boot ADD COLUMN IF NOT EXISTS first_seen timestamptz;
ALTER TABLE plc_boot ALTER COLUMN first_seen SET DEFAULT now();

-- How a boot ended, as OB100 kept it in DB_PerfDiag before zeroing anything.
CREATE TABLE IF NOT EXISTS plc_boot_end (
    plc_id    text    NOT NULL,
    boot_date integer NOT NULL,
    boot_time integer NOT NULL,
    last_seq  integer,
    ob80      integer,
    ob86      integer,
    ob82      integer,
    PRIMARY KEY (plc_id, boot_date, boot_time)
);

-- Each fault an error OB recorded before stopping the CPU.
CREATE TABLE IF NOT EXISTS plc_fault (
    plc_id     text    NOT NULL,
    fault_date integer NOT NULL,
    fault_time integer NOT NULL,
    ts_fault   timestamptz,
    fault_ob   smallint,
    ev_class   smallint,
    flt_id     smallint,
    PRIMARY KEY (plc_id, fault_date, fault_time)
);

-- One per diagnostic-buffer entry, stored as the CPU gave it.
CREATE TABLE IF NOT EXISTS plc_diag_event (
    ts_plc      timestamptz NOT NULL,
    ts_received timestamptz NOT NULL DEFAULT now(),
    plc_id      text        NOT NULL,
    event_id    integer     NOT NULL,
    priority    smallint,
    ob_nr       smallint,
    entry_hex   text        NOT NULL
);
SELECT create_hypertable('plc_diag_event', 'ts_plc', chunk_time_interval => INTERVAL '30 days', if_not_exists => TRUE);
CREATE UNIQUE INDEX IF NOT EXISTS plc_diag_event_uk ON plc_diag_event (plc_id, event_id, entry_hex, ts_plc);
-- Bytes 6-7 and 8-11 of the entry (info 1, info 2), and the STOP cause: info 1 on a STOP to STARTUP (0x4301) or a class-1
-- restart request (0x1381-0x1388, 0x138A-0x138D), where it is the event ID of the STOP before (OB100 start information,
-- A5E02790053-01 §13.2), else NULL. Added 2026-11-03 to the live table; the decoder sends all three (diag_entry). The
-- rows stored before carry them in entry_hex only, and a re-offered entry is a conflict, so they are filled from it once.
ALTER TABLE plc_diag_event ADD COLUMN IF NOT EXISTS info1 integer, ADD COLUMN IF NOT EXISTS info2 bigint, ADD COLUMN IF NOT EXISTS cause_id integer;
UPDATE plc_diag_event
SET info1 = ('x' || substr(entry_hex, 13, 4))::bit(16)::integer,
    info2 = ('x' || lpad(substr(entry_hex, 17, 8), 16, '0'))::bit(64)::bigint,
    cause_id = CASE WHEN (event_id = 0x4301 OR event_id BETWEEN 0x1381 AND 0x1388 OR event_id BETWEEN 0x138A AND 0x138D)
                     AND ('x' || substr(entry_hex, 13, 4))::bit(16)::integer <> 0
                    THEN ('x' || substr(entry_hex, 13, 4))::bit(16)::integer END
WHERE info1 IS NULL AND entry_hex ~ '^[0-9a-fA-F]{40}$';

-- DB_PerfDiag's state, per read. The SZL parts stay raw until each is proven on the CPU: ret holds its answer per step.
-- Identity: order_no, serial, station as text; firmware_hex raw, read as text by plc_firmware().
CREATE TABLE IF NOT EXISTS plc_diag_state (
    ts              timestamptz NOT NULL DEFAULT now(),
    plc_id          text        NOT NULL,
    via             text        NOT NULL,
    diag_seq        integer,
    ret             integer[],
    order_no        text,
    firmware_hex    text,
    serial          text,
    station         text,
    led_count       integer,
    led_hex         text,
    mod_count       integer,
    mod_hex         text,
    protection_hex  text,
    connections_hex text
);
SELECT create_hypertable('plc_diag_state', 'ts', chunk_time_interval => INTERVAL '7 days', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS plc_diag_state_plc_ts ON plc_diag_state (plc_id, ts DESC);   -- the newest state of one PLC
-- DB_PerfDiag layout 2, the S7-1500 (2026-11-10, PLC02): the same row per read, these columns instead of the SZL ones,
-- NULL on an S7-300's rows. led: LED's RET_VAL for 1 RUN/STOP, 2 ERROR, 3 MAINT (1 off, 2/3 colour 1/2 on, 4/5 flashing,
-- 6 alternating, negative = refused); rt_ret: RT_INFO's RET_VAL for modes 11, 23, 24, 25; comm_load_pct and the cycle
-- from RT_INFO; mod_*: ModuleStates, reserved by the kit (zero until it reads them); im0_hex: I&M0, reserved (no
-- Get_IM_Data on TIA V15.1 / FW V2.6). One ALTER per column: a hypertable with compression takes them one at a time.
ALTER TABLE plc_diag_state ADD COLUMN IF NOT EXISTS led integer[];
ALTER TABLE plc_diag_state ADD COLUMN IF NOT EXISTS rt_ret integer[];
ALTER TABLE plc_diag_state ADD COLUMN IF NOT EXISTS im_status integer;
ALTER TABLE plc_diag_state ADD COLUMN IF NOT EXISTS comm_load_pct real;
ALTER TABLE plc_diag_state ADD COLUMN IF NOT EXISTS cyc_longest_ms real;
ALTER TABLE plc_diag_state ADD COLUMN IF NOT EXISTS cyc_shortest_ms real;
ALTER TABLE plc_diag_state ADD COLUMN IF NOT EXISTS cyc_last_ms real;
ALTER TABLE plc_diag_state ADD COLUMN IF NOT EXISTS mod_ret integer;
ALTER TABLE plc_diag_state ADD COLUMN IF NOT EXISTS mod_configured_hex text;
ALTER TABLE plc_diag_state ADD COLUMN IF NOT EXISTS mod_problem_hex text;
ALTER TABLE plc_diag_state ADD COLUMN IF NOT EXISTS im0_hex text;

-- The S7-1500's error OBs (DB_PerfDiag layout 2, one slot each for OB80, 82, 83, 86, 121, 122): the newest call of each
-- OB, one row per call the reads saw (a busy OB, such as the bench's OB122 at 2,000 calls a second, gives one per read;
-- an idle one a single row). calls = the OB's calls since the boot at that read: the rate is its rise between two rows of
-- one boot. The start information as the kit packs it; plc_ob_call_text (s7_1500_ob_fault.sql) names every code.
-- An S7-300 records its faults in plc_fault instead (count, then STOP). Events: kept forever, no policy.
CREATE TABLE IF NOT EXISTS plc_ob_call (
    ts_plc      timestamptz NOT NULL,   -- the newest call's stamp, RD_SYS_T: UTC
    ts_received timestamptz NOT NULL DEFAULT now(),
    plc_id      text        NOT NULL,
    via         text        NOT NULL,
    ob_nr       smallint    NOT NULL,
    calls       bigint,                 -- DInt
    ev_class    smallint,
    fault_id    smallint,
    info1       integer,                -- WORDs: a smallint would overflow on bit 15
    info2       integer,
    info3       integer
);
SELECT create_hypertable('plc_ob_call', 'ts_plc', chunk_time_interval => INTERVAL '30 days', if_not_exists => TRUE);
CREATE UNIQUE INDEX IF NOT EXISTS plc_ob_call_uk ON plc_ob_call (plc_id, ob_nr, ts_plc);

-- How a boot ended, per error OB (layout 2 keeps all six counters at the startup OB; plc_boot_end has OB80/82/86 only).
CREATE TABLE IF NOT EXISTS plc_boot_end_ob (
    plc_id    text     NOT NULL,
    boot_date integer  NOT NULL,
    boot_time integer  NOT NULL,
    ob_nr     smallint NOT NULL,
    calls     bigint,
    PRIMARY KEY (plc_id, boot_date, boot_time, ob_nr)
);

-- The health loop as the PLC sees it: each path's slot, per read over each path.
CREATE TABLE IF NOT EXISTS plc_health (
    ts            timestamptz NOT NULL DEFAULT now(),
    plc_id        text        NOT NULL,
    via           text        NOT NULL,   -- the path that read it
    slot          text        NOT NULL,   -- the path it describes
    life          smallint,
    echo          smallint,
    bad_echo      integer,
    age_s         integer,
    losses        integer,
    last_loss_date integer,
    last_loss_time integer,
    healthy       boolean,
    seen          boolean
);
SELECT create_hypertable('plc_health', 'ts', chunk_time_interval => INTERVAL '7 days', if_not_exists => TRUE);

-- The broker's own verdicts, one row per change: CpuScanning, DeviceStatus and Health per path, as S7PLC01Scan,
-- S7PLC01Liveness and S7PLC01Uns publish them to the UNS, sent to the store route as kind Transition.
-- The Overview's tiles show the newest row — the same answer as the Hub, within 10 s of a STOP — and derive one from
-- the stored reads only while this table is empty (the 90 s margin of the first acceptance run, 2026-11-04). ts is
-- the broker's clock at the change; prev is NULL on the first verdict after a broker start. A few rows a day; kept forever.
CREATE TABLE IF NOT EXISTS plc_state_change (
    ts      timestamptz NOT NULL,
    plc_id  text        NOT NULL,
    via     text        NOT NULL,   -- the path judged (for Health: the slot it describes)
    signal  text        NOT NULL,   -- CpuScanning | DeviceStatus | Health
    value   text        NOT NULL,   -- true/false · online/stale/offline · ok/stalled/corrupt/unknown
    prev    text,
    PRIMARY KEY (plc_id, via, signal, ts)
);

-- The boot a restart's leftover ring slots can belong to (2026-11-22): the boot of this PLC the historian stored last
-- before the current one (by first_seen, the arrival order a CPU clock cannot disturb), its newest stored record and,
-- when known, its last Seq from plc_boot_end. SECURITY DEFINER because the writer may INSERT only: it reads these three
-- tables here and nowhere else, and gets back four numbers and a stamp.
CREATE OR REPLACE FUNCTION plc_tail_anchor(pid text, cur_date integer, cur_time integer)
RETURNS TABLE (boot_date integer, boot_time integer, max_seq integer, max_ts timestamptz, last_seq integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  WITH p AS (SELECT b.boot_date, b.boot_time FROM plc_boot b
             WHERE b.plc_id = pid AND NOT (b.boot_date = cur_date AND b.boot_time = cur_time)
             ORDER BY b.first_seen DESC NULLS LAST, b.ts_boot DESC NULLS LAST LIMIT 1)
  SELECT p.boot_date, p.boot_time, c.seq, c.ts_plc, e.last_seq
  FROM p
  JOIN LATERAL (SELECT x.seq, x.ts_plc FROM plc_cycle x
                WHERE x.plc_id = pid AND x.boot_date = p.boot_date AND x.boot_time = p.boot_time
                ORDER BY x.seq DESC LIMIT 1) c ON true
  LEFT JOIN plc_boot_end e ON e.plc_id = pid AND e.boot_date = p.boot_date AND e.boot_time = p.boot_time
$$;

CREATE OR REPLACE FUNCTION plc_ingest(msg jsonb) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    pid   text := msg->>'plc_id';
    route text := msg->>'via';
    kind  text := msg->>'kind';
    zone  text;
    hdr   jsonb := msg->'header';
    rej   jsonb := coalesce(msg->'rejected', '{}'::jsonb);
    prev  record;
    cur_ts timestamptz;
BEGIN
    IF kind = 'Register' THEN
        -- The PLC as the broker's decoder declares it (PLCS): added when missing, never overwritten. Its model too, with
        -- the interfaces unknown until plc_fleet.sql lists the model (that file's rows win on every apply).
        -- ON CONFLICT DO NOTHING WITHOUT a conflict target: with one, PostgreSQL requires SELECT on the target column, and
        -- the writer has INSERT only on plc_model (measured 2026-11-19: "permission denied for table plc_model"). Each
        -- table has one unique key, so nothing else changes. A registration that fails for any other reason must not fail
        -- the store route's statement: a failed statement there was measured to cost neighbouring messages too, so it
        -- becomes a WARNING in the database log.
        BEGIN
            INSERT INTO plc_model (model, family, interfaces, description)
            VALUES (msg->>'model', msg->>'family', '{}', 'registered by the broker; not yet listed in plc_fleet.sql')
            ON CONFLICT DO NOTHING;
            INSERT INTO plc_registry (plc_id, clock_zone, description, family, model, order_no, paths, area, firmware)
            VALUES (pid, coalesce(msg->>'clock_zone', 'UTC'), msg->>'description', msg->>'family', msg->>'model', msg->>'order_no',
                    ARRAY(SELECT jsonb_array_elements_text(msg->'paths')), msg->>'area', msg->>'firmware')
            ON CONFLICT DO NOTHING;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'plc_ingest: registration of % failed: %', pid, SQLERRM;
        END;
        RETURN;
    END IF;
    IF kind = 'Transition' THEN
        INSERT INTO plc_state_change (ts, plc_id, via, signal, value, prev)
        VALUES (coalesce((msg->>'at')::timestamptz, now()), pid, route, msg->>'signal', msg->>'value', msg->>'prev')
        ON CONFLICT DO NOTHING;
        RETURN;
    END IF;

    SELECT clock_zone INTO zone FROM plc_registry WHERE plc_id = pid;
    zone := coalesce(zone, 'UTC');

    INSERT INTO plc_read (plc_id, via, db_name, read_ms, bytes, accepted, rej_empty, rej_future, rej_slot, rej_old, rej_stamp, decode_ms, error, earlier)
    VALUES (pid, route, kind, (msg->>'read_ms')::integer, (msg->>'bytes')::integer, jsonb_array_length(coalesce(msg->'records', '[]'::jsonb)),
            (rej->>'empty')::integer, (rej->>'future')::integer, (rej->>'slot')::integer, (rej->>'old')::integer, (rej->>'stamp')::integer,
            (msg->>'decode_ms')::real, msg->>'error', jsonb_array_length(coalesce(msg->'earlier', '[]'::jsonb)));
    IF msg ? 'error' THEN
        RETURN;
    END IF;

    IF kind = 'PerfMon' THEN
        INSERT INTO plc_boot (plc_id, boot_date, boot_time, ts_boot, restart_count, edges_ms)
        SELECT pid, (hdr->>'boot_date')::integer, (hdr->>'boot_time')::integer,
               CASE WHEN (hdr->>'boot_date')::integer > 0 THEN plc_stamp((hdr->>'boot_date')::integer, (hdr->>'boot_time')::integer, zone) END,
               (hdr->>'restart_count')::integer, ARRAY(SELECT jsonb_array_elements_text(hdr->'edges_ms')::real)
        ON CONFLICT DO NOTHING;

        INSERT INTO plc_cycle (ts_plc, plc_id, boot_date, boot_time, seq, window_ms, cycles, cyc_min_ms, cyc_max_ms, cyc_avg_ms, comm_load_pct, hist, flags, ob80_cnt)
        SELECT plc_stamp(r.stamp_date, r.stamp_time, zone), pid, (hdr->>'boot_date')::integer, (hdr->>'boot_time')::integer, r.seq,
               (hdr->>'window_ms')::smallint, r.cycles, r.cyc_min_ms, r.cyc_max_ms, r.cyc_avg_ms, NULLIF(r.comm_load_pct, -1),
               ARRAY(SELECT jsonb_array_elements_text(r.hist)::integer), r.flags, r.ob80_cnt
        FROM jsonb_to_recordset(msg->'records') AS r(seq integer, stamp_date integer, stamp_time integer, cycles integer, cyc_min_ms real,
             cyc_max_ms real, cyc_avg_ms real, comm_load_pct real, hist jsonb, flags integer, ob80_cnt smallint, hash text)
        ON CONFLICT DO NOTHING;

        INSERT INTO plc_arrival (ts_plc, plc_id, via, kind, fact_key, fact_hash)
        SELECT plc_stamp(r.stamp_date, r.stamp_time, zone), pid, route, 'cycle', (hdr->>'boot_date') || '/' || (hdr->>'boot_time') || '/' || r.seq, r.hash
        FROM jsonb_to_recordset(msg->'records') AS r(seq integer, stamp_date integer, stamp_time integer, hash text)
        ON CONFLICT DO NOTHING;

        -- The previous boot's tail (2026-11-22, measured on the 1511): a boot that ends between two reads with no STOP
        -- the reader can see (a power loss, a download of a few seconds) leaves its last records in the ring, and the new
        -- boot starts Seq at 1. The decoder offers those slots as "earlier"; they are filed under the boot stored last
        -- before this one, and only where they CONTINUE it: Seq above its newest stored record, at most its last Seq
        -- when known, stamped before this boot, and one record a second from that newest record (2 s + 1 % of slack).
        -- Records of a boot the historian never saw fail that test and are dropped, as before.
        IF jsonb_array_length(coalesce(msg->'earlier', '[]'::jsonb)) > 0 AND (hdr->>'boot_date')::integer > 0 THEN
            cur_ts := plc_stamp((hdr->>'boot_date')::integer, (hdr->>'boot_time')::integer, zone);
            SELECT * INTO prev FROM plc_tail_anchor(pid, (hdr->>'boot_date')::integer, (hdr->>'boot_time')::integer);
            IF prev.boot_date IS NOT NULL THEN
                -- Both statements filter with the anchor read once into prev, so they file the same records.
                INSERT INTO plc_arrival (ts_plc, plc_id, via, kind, fact_key, fact_hash)
                SELECT t.ts, pid, route, 'cycle', prev.boot_date || '/' || prev.boot_time || '/' || t.seq, t.hash
                FROM (SELECT plc_stamp(r.stamp_date, r.stamp_time, zone) AS ts, r.*
                      FROM jsonb_to_recordset(msg->'earlier') AS r(seq integer, stamp_date integer, stamp_time integer, cycles integer,
                           cyc_min_ms real, cyc_max_ms real, cyc_avg_ms real, comm_load_pct real, hist jsonb, flags integer,
                           ob80_cnt smallint, hash text)) t
                WHERE t.seq > prev.max_seq AND (prev.last_seq IS NULL OR t.seq <= prev.last_seq) AND t.ts < cur_ts
                  AND abs(extract(epoch FROM t.ts - prev.max_ts) - (t.seq - prev.max_seq)) <= 2 + 0.01 * (t.seq - prev.max_seq)
                ON CONFLICT DO NOTHING;

                INSERT INTO plc_cycle (ts_plc, plc_id, boot_date, boot_time, seq, window_ms, cycles, cyc_min_ms, cyc_max_ms, cyc_avg_ms, comm_load_pct, hist, flags, ob80_cnt)
                SELECT t.ts, pid, prev.boot_date, prev.boot_time, t.seq, (hdr->>'window_ms')::smallint, t.cycles, t.cyc_min_ms, t.cyc_max_ms,
                       t.cyc_avg_ms, NULLIF(t.comm_load_pct, -1), ARRAY(SELECT jsonb_array_elements_text(t.hist)::integer), t.flags, t.ob80_cnt
                FROM (SELECT plc_stamp(r.stamp_date, r.stamp_time, zone) AS ts, r.*
                      FROM jsonb_to_recordset(msg->'earlier') AS r(seq integer, stamp_date integer, stamp_time integer, cycles integer,
                           cyc_min_ms real, cyc_max_ms real, cyc_avg_ms real, comm_load_pct real, hist jsonb, flags integer,
                           ob80_cnt smallint, hash text)) t
                WHERE t.seq > prev.max_seq AND (prev.last_seq IS NULL OR t.seq <= prev.last_seq) AND t.ts < cur_ts
                  AND abs(extract(epoch FROM t.ts - prev.max_ts) - (t.seq - prev.max_seq)) <= 2 + 0.01 * (t.seq - prev.max_seq)
                ON CONFLICT DO NOTHING;
            END IF;
        END IF;

    ELSIF kind = 'PerfDiag' THEN
        IF (msg#>>'{boot_end,date}')::integer > 0 THEN
            INSERT INTO plc_boot_end (plc_id, boot_date, boot_time, last_seq, ob80, ob86, ob82)
            VALUES (pid, (msg#>>'{boot_end,date}')::integer, (msg#>>'{boot_end,time}')::integer, (msg#>>'{boot_end,last_seq}')::integer,
                    (msg#>>'{boot_end,ob80}')::integer, (msg#>>'{boot_end,ob86}')::integer, (msg#>>'{boot_end,ob82}')::integer)
            ON CONFLICT DO NOTHING;
        END IF;
        IF (msg#>>'{fault,count}')::integer > 0 AND (msg#>>'{fault,date}')::integer > 0 THEN
            INSERT INTO plc_fault (plc_id, fault_date, fault_time, ts_fault, fault_ob, ev_class, flt_id)
            VALUES (pid, (msg#>>'{fault,date}')::integer, (msg#>>'{fault,time}')::integer,
                    plc_stamp((msg#>>'{fault,date}')::integer, (msg#>>'{fault,time}')::integer, zone),
                    (msg#>>'{fault,ob}')::smallint, (msg#>>'{fault,ev_class}')::smallint, (msg#>>'{fault,flt_id}')::smallint)
            ON CONFLICT DO NOTHING;
        END IF;
        IF msg->>'layout' = '2' THEN
            -- DB_PerfDiag layout 2 (S7-1500, S7-1200): no SZL copies and no diagnostic buffer; the error OBs' slots instead. Its
            -- newest call is "newest", not "fault", so the plc_fault insert above never takes it (see plc_ob_call).
            INSERT INTO plc_diag_state (plc_id, via, diag_seq, led, rt_ret, im_status, comm_load_pct, cyc_longest_ms, cyc_shortest_ms,
                                        cyc_last_ms, mod_ret, mod_configured_hex, mod_problem_hex, im0_hex)
            VALUES (pid, route, (msg->>'diag_seq')::integer, ARRAY(SELECT jsonb_array_elements_text(msg->'led')::integer),
                    ARRAY(SELECT jsonb_array_elements_text(msg->'rt_ret')::integer), (msg->>'im_status')::integer,
                    (msg->>'comm_load_pct')::real, (msg->>'cyc_longest_ms')::real, (msg->>'cyc_shortest_ms')::real,
                    (msg->>'cyc_last_ms')::real, (msg->>'mod_ret')::integer, msg->>'mod_configured_hex', msg->>'mod_problem_hex',
                    msg->>'im0_hex');
            INSERT INTO plc_ob_call (ts_plc, plc_id, via, ob_nr, calls, ev_class, fault_id, info1, info2, info3)
            SELECT plc_stamp(s.last_date, s.last_time, zone), pid, route, s.ob, s.calls, s.ev_class, s.fault_id, s.info1, s.info2, s.info3
            FROM jsonb_to_recordset(msg->'ob_slots') AS s(ob smallint, calls bigint, last_date integer, last_time integer, ev_class smallint,
                                                           fault_id smallint, info1 integer, info2 integer, info3 integer)
            WHERE s.calls > 0 AND s.last_date > 0
            ON CONFLICT DO NOTHING;
            IF (msg#>>'{boot_end,date}')::integer > 0 THEN
                INSERT INTO plc_boot_end_ob (plc_id, boot_date, boot_time, ob_nr, calls)
                SELECT pid, (msg#>>'{boot_end,date}')::integer, (msg#>>'{boot_end,time}')::integer, p.ob, p.calls
                FROM jsonb_to_recordset(msg->'prev_count') AS p(ob smallint, calls bigint)
                ON CONFLICT DO NOTHING;
            END IF;
            RETURN;
        END IF;
        INSERT INTO plc_diag_state (plc_id, via, diag_seq, ret, order_no, firmware_hex, serial, station, led_count, led_hex, mod_count, mod_hex, protection_hex, connections_hex)
        VALUES (pid, route, (msg->>'diag_seq')::integer, ARRAY(SELECT jsonb_array_elements_text(msg->'ret')::integer), msg->>'order_no', msg->>'firmware_hex',
                msg->>'serial', msg->>'station', (msg->>'led_count')::integer, msg->>'led_hex', (msg->>'mod_count')::integer, msg->>'mod_hex',
                msg->>'protection_hex', msg->>'connections_hex');
        INSERT INTO plc_diag_event (ts_plc, plc_id, event_id, priority, ob_nr, entry_hex, info1, info2, cause_id)
        SELECT plc_stamp(e.stamp_date, e.stamp_time, zone), pid, e.event_id, e.priority, e.ob_nr, e.entry_hex, e.info1, e.info2, e.cause_id
        FROM jsonb_to_recordset(msg->'entries') AS e(event_id integer, priority smallint, ob_nr smallint, stamp_date integer, stamp_time integer,
                                                     entry_hex text, info1 integer, info2 bigint, cause_id integer)
        ON CONFLICT DO NOTHING;
        INSERT INTO plc_arrival (ts_plc, plc_id, via, kind, fact_key, fact_hash)
        SELECT plc_stamp(e.stamp_date, e.stamp_time, zone), pid, route, 'diag', e.event_id::text, e.entry_hex
        FROM jsonb_to_recordset(msg->'entries') AS e(event_id integer, stamp_date integer, stamp_time integer, entry_hex text)
        ON CONFLICT DO NOTHING;

    ELSIF kind = 'PerfHealth' THEN
        INSERT INTO plc_health (plc_id, via, slot, life, echo, bad_echo, age_s, losses, last_loss_date, last_loss_time, healthy, seen)
        SELECT pid, route, s.key, (s.value->>'life')::smallint, (s.value->>'echo')::smallint, (s.value->>'bad_echo')::integer, (s.value->>'age_s')::integer,
               (s.value->>'losses')::integer, (s.value->>'last_loss_date')::integer, (s.value->>'last_loss_time')::integer,
               (s.value->>'healthy')::boolean, (s.value->>'seen')::boolean
        FROM jsonb_each(msg->'slots') AS s;
    END IF;
END
$$;

-- ── Retention with degrading granularity (at least 6 months of trend) ──────────────
--
--   tier      relations                                          kept       compressed   refreshed
--   raw       plc_cycle, plc_read, plc_health, plc_diag_state    180 days   after 7 days  —
--   evidence  plc_arrival                                        7 days     no            —
--   5 min     plc_cycle_5m                                       2 years    no            every 5 min, window now-1h … now-5min
--   1 hour    plc_cycle_1h, plc_read_1h, plc_health_1h          forever    no            every hour,  window now-3h … now-1h
--   events    plc_diag_event, plc_boot, plc_boot_end, plc_fault  forever    no            —   (a few rows a day: no policy)
--
-- Every bucket is materialized within hours of its raw rows arriving (the refresh windows above), and the raw rows go
-- at 180 days: each bucket is in its aggregate ~180 days before its raw data is dropped. The rows that arrive late
-- arrive within minutes (the ring holds 2 min; plc_read and plc_health are stamped now()), well inside every window.
--
-- TWO THINGS NEVER TO DO once raw retention has run (measured on 2.30.1, 2026-11-03):
--   * refresh an aggregate by hand over a range older than 180 days: a refresh over a region whose raw chunks were
--     dropped DELETES the aggregate's rows there. The policies never reach that far; a manual
--     refresh_continuous_aggregate(…, NULL, …) does.
--   * DROP an aggregate: its history older than 180 days exists only in it. The one migration below refuses to.
-- WITH DATA backfills an aggregate once, when it is created; IF NOT EXISTS skips it on every later apply.
-- materialized_only = false (real time): a query also sees the newest buckets not materialized yet, from raw.
-- Compressed raw chunks and the aggregates: a routine refresh never reads one (its window ends days before the 7-day
-- compression); the one-time backfill and a late insert into a compressed chunk (DML on compressed chunks, ON CONFLICT
-- included, works since 2.11) do, which only costs time. The compression settings below apply to chunks compressed
-- after a change; a re-apply on a database with compressed chunks prints a NOTICE saying so, nothing else.

ALTER TABLE plc_cycle SET (timescaledb.compress, timescaledb.compress_segmentby = 'plc_id',
                           timescaledb.compress_orderby = 'ts_plc DESC, boot_date, boot_time, seq');   -- every unique-key column
ALTER TABLE plc_read SET (timescaledb.compress, timescaledb.compress_segmentby = 'plc_id, via, db_name',
                          timescaledb.compress_orderby = 'ts DESC');
ALTER TABLE plc_health SET (timescaledb.compress, timescaledb.compress_segmentby = 'plc_id, via, slot',
                            timescaledb.compress_orderby = 'ts DESC');
ALTER TABLE plc_diag_state SET (timescaledb.compress, timescaledb.compress_segmentby = 'plc_id, via',
                                timescaledb.compress_orderby = 'ts DESC');
SELECT add_compression_policy('plc_cycle', INTERVAL '7 days', if_not_exists => TRUE);
SELECT add_compression_policy('plc_read', INTERVAL '7 days', if_not_exists => TRUE);
SELECT add_compression_policy('plc_health', INTERVAL '7 days', if_not_exists => TRUE);
SELECT add_compression_policy('plc_diag_state', INTERVAL '7 days', if_not_exists => TRUE);
SELECT add_retention_policy('plc_cycle', INTERVAL '180 days', if_not_exists => TRUE);
SELECT add_retention_policy('plc_read', INTERVAL '180 days', if_not_exists => TRUE);
SELECT add_retention_policy('plc_health', INTERVAL '180 days', if_not_exists => TRUE);
SELECT add_retention_policy('plc_diag_state', INTERVAL '180 days', if_not_exists => TRUE);

-- The one migration: plc_cycle_1h was created on 2026-11-03 without comm_load_pct, the window counts and the skew. An
-- aggregate's query cannot be altered, so it is dropped and created again — only while plc_cycle still holds every hour
-- the aggregate does (true before the first 180-day retention run), or the hours only the aggregate holds would be lost.
DO $$
BEGIN
    IF to_regclass('public.plc_cycle_1h') IS NOT NULL AND NOT EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema = 'public' AND table_name = 'plc_cycle_1h' AND column_name = 'skew_min_s') THEN
        IF (SELECT min(bucket) FROM plc_cycle_1h) < (SELECT time_bucket('1 hour', min(ts_plc)) FROM plc_cycle) THEN
            RAISE EXCEPTION 'plc_cycle_1h holds hours plc_cycle no longer has: recreating it would lose them';
        END IF;
        DROP MATERIALIZED VIEW plc_cycle_1h;
    END IF;
END
$$;

-- The cycle roll-ups, the same columns at 5 min and 1 h. Weighted where an average is averaged again: a panel over
-- buckets takes sum(cyc_avg_ms * cycles) / sum(cycles), and cycles/s = sum(cycles) * 1000 / sum(window_ms).
-- comm_load_pct is NULL on an S7-300 (it sends -1). win_* = windows with that flag bit (0 first after boot, 1 OB80,
-- 2 RT_INFO error); skew_min_s = the smallest read time − PLC stamp in the bucket, the clock-skew trend.
CREATE MATERIALIZED VIEW IF NOT EXISTS plc_cycle_5m WITH (timescaledb.continuous, timescaledb.materialized_only = false) AS
SELECT plc_id, time_bucket('5 minutes', ts_plc) AS bucket,
       count(*) AS windows, sum(window_ms) AS window_ms, sum(cycles) AS cycles,
       min(cyc_min_ms) AS cyc_min_ms, max(cyc_max_ms) AS cyc_max_ms,
       sum(cyc_avg_ms * cycles) / nullif(sum(cycles), 0) AS cyc_avg_ms,
       avg(comm_load_pct) AS comm_load_pct,
       sum(hist[1]) AS h0, sum(hist[2]) AS h1, sum(hist[3]) AS h2, sum(hist[4]) AS h3,
       sum(hist[5]) AS h4, sum(hist[6]) AS h5, sum(hist[7]) AS h6, sum(hist[8]) AS h7,
       sum(ob80_cnt) AS ob80,
       count(*) FILTER (WHERE flags & 1 > 0) AS win_first, count(*) FILTER (WHERE flags & 2 > 0) AS win_ob80,
       count(*) FILTER (WHERE flags & 4 > 0) AS win_rt_error,
       min(extract(epoch FROM ts_received - ts_plc)) AS skew_min_s
FROM plc_cycle GROUP BY plc_id, bucket WITH DATA;
SELECT add_continuous_aggregate_policy('plc_cycle_5m', start_offset => INTERVAL '1 hour', end_offset => INTERVAL '5 minutes',
                                       schedule_interval => INTERVAL '5 minutes', if_not_exists => TRUE);
SELECT add_retention_policy('plc_cycle_5m', INTERVAL '2 years', if_not_exists => TRUE);

CREATE MATERIALIZED VIEW IF NOT EXISTS plc_cycle_1h WITH (timescaledb.continuous, timescaledb.materialized_only = false) AS
SELECT plc_id, time_bucket('1 hour', ts_plc) AS bucket,
       count(*) AS windows, sum(window_ms) AS window_ms, sum(cycles) AS cycles,
       min(cyc_min_ms) AS cyc_min_ms, max(cyc_max_ms) AS cyc_max_ms,
       sum(cyc_avg_ms * cycles) / nullif(sum(cycles), 0) AS cyc_avg_ms,
       avg(comm_load_pct) AS comm_load_pct,
       sum(hist[1]) AS h0, sum(hist[2]) AS h1, sum(hist[3]) AS h2, sum(hist[4]) AS h3,
       sum(hist[5]) AS h4, sum(hist[6]) AS h5, sum(hist[7]) AS h6, sum(hist[8]) AS h7,
       sum(ob80_cnt) AS ob80,
       count(*) FILTER (WHERE flags & 1 > 0) AS win_first, count(*) FILTER (WHERE flags & 2 > 0) AS win_ob80,
       count(*) FILTER (WHERE flags & 4 > 0) AS win_rt_error,
       min(extract(epoch FROM ts_received - ts_plc)) AS skew_min_s
FROM plc_cycle GROUP BY plc_id, bucket WITH DATA;
SELECT add_continuous_aggregate_policy('plc_cycle_1h', start_offset => INTERVAL '3 hours', end_offset => INTERVAL '1 hour',
                                       schedule_interval => INTERVAL '1 hour', if_not_exists => TRUE);

-- Reads per path and DB per hour. Averages again over hours: sum(read_ms_avg * (reads - errors)) / sum(reads - errors).
CREATE MATERIALIZED VIEW IF NOT EXISTS plc_read_1h WITH (timescaledb.continuous, timescaledb.materialized_only = false) AS
SELECT plc_id, via, db_name, time_bucket('1 hour', ts) AS bucket,
       count(*) AS reads, count(*) FILTER (WHERE error IS NOT NULL) AS errors,
       avg(read_ms) FILTER (WHERE error IS NULL) AS read_ms_avg, max(read_ms) FILTER (WHERE error IS NULL) AS read_ms_max,
       sum(bytes) AS bytes, sum(accepted) AS accepted,
       sum(rej_future) AS rej_future, sum(rej_slot) AS rej_slot, sum(rej_old) AS rej_old, sum(rej_stamp) AS rej_stamp
FROM plc_read GROUP BY plc_id, via, db_name, bucket WITH DATA;
SELECT add_continuous_aggregate_policy('plc_read_1h', start_offset => INTERVAL '3 hours', end_offset => INTERVAL '1 hour',
                                       schedule_interval => INTERVAL '1 hour', if_not_exists => TRUE);

-- The health loop per hour, per reading path (via) and described path (slot). Losses and BadEcho are the PLC's counters
-- since boot: the max is the level; max − min is the rise within the hour unless the CPU booted in it.
CREATE MATERIALIZED VIEW IF NOT EXISTS plc_health_1h WITH (timescaledb.continuous, timescaledb.materialized_only = false) AS
SELECT plc_id, via, slot, time_bucket('1 hour', ts) AS bucket,
       count(*) AS samples, max(age_s) AS age_s_max,
       min(losses) AS losses_min, max(losses) AS losses_max,
       min(bad_echo) AS bad_echo_min, max(bad_echo) AS bad_echo_max,
       count(*) FILTER (WHERE healthy IS FALSE) AS unhealthy
FROM plc_health GROUP BY plc_id, via, slot, bucket WITH DATA;
SELECT add_continuous_aggregate_policy('plc_health_1h', start_offset => INTERVAL '3 hours', end_offset => INTERVAL '1 hour',
                                       schedule_interval => INTERVAL '1 hour', if_not_exists => TRUE);
