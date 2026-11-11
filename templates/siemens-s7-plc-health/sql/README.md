# The historian: TimescaleDB

What the store route writes into, and what the dashboards read. One database for every PLC the broker reads, keyed by
`plc_id`. TimescaleDB 2.11 or newer on PostgreSQL 16 or newer; verified on `timescale/timescaledb-ha:pg17.11-ts2.30.1`.
The quick-start stack applies these files on the database's first start (`../compose/initdb/`).

## Apply

Every file is idempotent: run them again after an update, in this order.

```bash
psql -v ON_ERROR_STOP=1 -d plc -f schema.sql
psql -v ON_ERROR_STOP=1 -d plc -f plc_fleet.sql
psql -v ON_ERROR_STOP=1 -d plc -f s7_1500_ob_fault.sql
psql -v ON_ERROR_STOP=1 -d plc -f s7_event_text.sql
psql -v ON_ERROR_STOP=1 -d plc -v db=plc -v writer_password="$UNS_WRITER_PASSWORD" \
     -v reader_password="$GRAFANA_READER_PASSWORD" -f role.sql
```

| File | What |
|---|---|
| `schema.sql` | the tables, `plc_ingest()` (one decoded read in, every fact once, the evidence per path), the PLC registry, retention and the 5-minute and 1-hour roll-ups |
| `plc_fleet.sql` | the PLC models, the derived states as functions (one definition for the tiles, the fleet table and the alert rules), `plc_latest` (one row per PLC) |
| `s7_1500_ob_fault.sql` | Siemens' meaning of each error-OB code, both forms of start information, and the view `plc_ob_call_text` |
| `s7_event_text.sql` | Siemens' text of each S7-300/400 diagnostic-buffer event ID, and the view `plc_diag_event_text` |
| `role.sql` | `uns_writer` (the store route: INSERT only, and SELECT on `plc_registry`) and `grafana_reader` (SELECT only) |

**The registry.** `schema.sql` registers the two example PLCs, `acme-site01-plc01` (an S7-300) and `acme-site01-plc02`
(an S7-1500). Use your own ids, the same as in the decoder's `PLCS` table, one row per PLC, with its `paths` in the
order `PLCS` lists them. A row is written once and never overwritten by a re-apply: change one with `UPDATE`.

**Retention.** Raw rows 180 days (compressed after 7), the per-path evidence 7 days, the 5-minute roll-up 2 years, the
1-hour roll-ups and the events forever. About 1 GB per PLC in steady state at one record a second, then about 15 MB a
year. Never refresh a roll-up by hand over a range older than 180 days: its raw rows are gone, and the refresh would
delete the roll-up's rows there.

## Siemens' texts

`s7_event_text.csv` and `s7_1500_ob_fault.csv` are the sources; the two `.sql` files and the decoder's text tables are
generated from them.

- **Diagnostic-buffer events (S7-300/400):** Siemens' published event texts, from "System Software for S7-300/400 System
  and Standard Functions", Volume 2/2, A5E02790053-01, chapter 35, with the section and page of every row. They are the
  texts TIA shows for those event IDs; where the manual prints a typo, it is kept as printed.
- **Error-OB start information (S7-1500):** Siemens' meaning of each code, both forms: the S7-1500 form from the TIA
  Portal help, "Functional description of S7-1500 CPUs" (one page per OB, linked per row), and the classic S7-300/400
  form, which an S7-1500 project migrated from an S7-300 can keep, from A5E02789976-01 and A5E02790053-01 (page cited).

**These are reproduced meanings, and only some are confirmed on a CPU.** On the S7-1500 so far only OB122 (both forms)
has been measured; the classic OB82 and OB86 interfaces were measured, never a value an S7-1500 puts in them. A code
whose description does not match what your CPU did, a text that differs from what your TIA shows, an event or code that
is missing: each is a finding, and **corrections and additions are welcome as a pull request** against the CSV, with the
source of the correction (a manual page, or what your CPU and TIA showed).
