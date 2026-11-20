-- The role the broker's store route authenticates as. Apply AFTER schema.sql and the other files. It can append and do
-- nothing else, so a compromised broker credential cannot rewrite history. plc_registry alone can be read: it holds
-- the clock zone.
--
-- The passwords are not in this file:
--   psql … -v db="$DB" -v writer_password="$UNS_WRITER_PASSWORD" -v reader_password="$GRAFANA_READER_PASSWORD" -f role.sql

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'uns_writer') THEN
        CREATE ROLE uns_writer LOGIN;
    END IF;
END
$$;

ALTER ROLE uns_writer WITH PASSWORD :'writer_password';

GRANT CONNECT ON DATABASE :"db" TO uns_writer;
GRANT USAGE ON SCHEMA public TO uns_writer;
GRANT INSERT ON plc_cycle, plc_arrival, plc_read, plc_boot, plc_boot_end, plc_fault, plc_diag_event, plc_diag_state, plc_health,
                plc_state_change, plc_ob_call, plc_boot_end_ob TO uns_writer;
GRANT SELECT ON plc_registry TO uns_writer;
-- A PLC registers itself (plc_ingest kind "Register", 2026-11-19): INSERT … ON CONFLICT DO NOTHING, so INSERT only — the
-- writer still cannot change or delete a row of either table.
GRANT INSERT ON plc_registry, plc_model TO uns_writer;

-- The role Grafana reads as: it can read the PLC's history and do nothing else. Re-running this file sets its password
-- to the value given again, so the Grafana datasource must be given the same value.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'grafana_reader') THEN
        CREATE ROLE grafana_reader LOGIN;
    END IF;
END
$$;

ALTER ROLE grafana_reader WITH PASSWORD :'reader_password';

GRANT CONNECT ON DATABASE :"db" TO grafana_reader;
GRANT USAGE ON SCHEMA public TO grafana_reader;

-- SELECT on every plc_* table, view and continuous aggregate (plc_cycle_5m, plc_cycle_1h, plc_read_1h, plc_health_1h:
-- a continuous aggregate is a view, relkind 'v') that exists now. A table added to
-- schema.sql later is covered on the next apply, because this file runs after schema.sql.
DO $$
DECLARE
    rel record;
BEGIN
    FOR rel IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE n.nspname = 'public' AND c.relname LIKE 'plc\_%' AND c.relkind IN ('r', 'p', 'v', 'm') LOOP
        EXECUTE format('GRANT SELECT ON public.%I TO grafana_reader', rel.relname);
    END LOOP;
END
$$;

-- And on what the schema's owner creates in public from now on, between two applies. Give the kit a database of
-- its own, so that is only the kit's schema.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO grafana_reader;

-- Deliberately NOT granted: INSERT, UPDATE, DELETE, TRUNCATE, CREATE, and nothing outside public.
