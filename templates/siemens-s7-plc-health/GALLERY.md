# Gallery submission: templates.coreflux.org

This template's entry on templates.coreflux.org: the submission form field by field, in the form's order, then the
page text under `## Content`. The gallery hands out only the notebooks and this page, so the Content is self-contained
about the template; the rest of this folder is the fuller record.

| Field | Limit | Value |
|---|---|---|
| Title * | ≤ 75 | Siemens S7 PLC health: cycle times, error OBs and a health loop |
| Short description * | ≤ 100 | Cycle times, error-OB calls and a health loop from S7-300/S7-1500 PLCs into a UNS and TimescaleDB. |
| Content | Markdown | the `## Content` section below |
| Category | one | Manufacturing |
| Broker version * | one | 2.22.0 |
| Difficulty * | one | advanced |
| GitHub repository | optional | https://github.com/zboardio/coreflux/tree/main/templates/siemens-s7-plc-health |
| Tags | ≤ 8 | `PLC` · `Siemens S7` · `industrial` · `health monitoring` · `uns` · `Python` · `timescaledb` · `grafana` |
| .lotnb files | ≤ 5, ≤ 5 MB each | `siemens-s7-plc-health-s7-300.lotnb` · `siemens-s7-plc-health-s7-1500.lotnb` · `siemens-s7-plc-health-simulator.lotnb` |

**Broker version:** the notebooks need 2.22 or newer and are verified on 2.22.0. The form's choices seen on
2026-11-11 were `2.14.3`, `v2.2` and `v2.0`: if it still offers no 2.22, pick none of those blindly; ask the gallery to
add it, and the Prerequisites state the requirement in any case.

## Content

## Summary

Health, cycle-time metrics and diagnostics from **Siemens S7 PLCs**, read with the broker's native `SIEMENS_S7` connector into a **Unified Namespace** and a TimescaleDB historian. One template, one notebook per PLC family: the **S7-300** (and the S7-400 by the same rules) and the **S7-1500**, from firmware V2.x, with no licence and no Web API in the PLC.
A small set of blocks in the PLC measures every cycle, counts every call of each error OB with its start information, and closes one record a second in a ring. The broker reads the whole ring in one request, so nothing is lost between two reads. The PLC also shows a counter that the broker writes straight back: when the echo stops, or a wrong value comes back, you know the data path is broken although the reads look fine.
It is the pattern we run on a real CPU 315-2 PN/DP, read over PN and MPI at once, and on a real CPU 1511-1 PN with firmware V2.6 inside an existing program, generalised to one example PLC per family.

## Key features

- **Every cycle, in the PLC:** the minimum, average and maximum cycle time per second and a histogram, the communication load on an S7-1500, the boot stamp and the previous boot's counters.
- **Nothing lost between reads:** a ring of 120 one-second records, read whole every 30 s, so an outage of up to 90 s loses nothing; a read that is not atomic is handled by a read contract that refuses half-written and stale records and counts each refusal.
- **Error OBs counted, not sampled:** OB80, OB82 and OB86 on an S7-300; OB80, OB82, OB83, OB86, OB121 and OB122 on an S7-1500, each with its newest start information in Siemens' words, in both the S7-1500 and the classic S7-300/400 form.
- **The diagnostic buffer with Siemens' texts** on an S7-300: the newest ten entries, and for a restart the cause of the STOP before it.
- **A health loop per path:** the PLC's `Life` byte comes back as `Echo`; the PLC moves on only when it sees its value return, so a dead action, a refused write or a second writer shows even while the reads look healthy.
- **STOP seen from outside:** the DBs stay readable in STOP, so a frozen record counter with the path still online means the CPU is not scanning.
- **A historian that keeps facts and evidence apart:** every record once, whichever path delivered it, and per path when it arrived and its hash; roll-ups at 5 minutes and 1 hour, the raw rows for 180 days.
- **A simulator** that answers the routes' reads byte for byte, so everything after the route runs with no PLC.

## Who is this for?

Automation and maintenance engineers who want to know how their Siemens PLCs are doing, from the outside and over time: cycle-time drift, error OBs a program calls thousands of times a second, restarts and their causes, a CPU in STOP, a communication path that fails quietly. Also anyone who has to judge PLCs without a recent firmware or a Web API.

## What you will see

- `acme/site01/Automation/PLC01/PN/CycleAvg` as `{"value":0.48,"timestamp":"2026-11-03T12:00:02.000Z","datatype":"number","status":"Good","units":"ms"}`, stamped with the PLC's own time of the record.
- On an S7-300, `LastDiagEvent`: `0x4302, Mode transition from STARTUP to RUN`; after a restart the entry before it names the STOP's cause.
- On an S7-1500, `LastFault`: `OB122, fault id 0x42 I/O access error, reading, FC 72, area 0x01 Direct (peripheral) access to inputs, 420 calls since the boot`, and `OB122Events` counting.
- Per path, three verdicts from the broker: `CpuScanning`, `Health` with `ok`, `stalled`, `corrupt` or `unknown`, and `DeviceStatus` with `online`, `stale` or `offline`.
- In TimescaleDB: one row a second per PLC, every read with its duration and what it refused, every verdict change, every error-OB call and buffer entry with its text, and the fleet in one row per PLC.

## Architecture

**The read chain**
- The read tick publishes one read request every 10 s, in turn over the three DBs.
- The route reads the whole DB and answers on `siemens/site01/<PLC>/PN/<Kind>/raw`.
- The decode action hands the answer to the `S7PerfDecode` Python script, which publishes one decoded message per read.
- The store route turns each decoded message into one `plc_ingest()` call in TimescaleDB; the UNS action publishes the newest values as retained leaves under `acme/site01/Automation/<PLC>/PN/`.

**The verdicts**
- The route polls the record counter `Seq` every 5 s; the scan action turns a frozen counter into `CpuScanning` false.
- The liveness action judges each path by the age of its last good read or heartbeat.
- Every change of a verdict also goes to the historian.

**The health loop**
- The route polls `Life` every second; the echo action writes it straight back through the route.
- The PLC moves `Life` on only when its own value returns, counts a loss after 5 s and counts a wrong value as `BadEcho`.

## Included notebooks

- `siemens-s7-plc-health-s7-300.lotnb`, for an S7-300 or S7-400 read over PN: the decoder, the S7 route, the store route and six actions. Its last section adds a second path, MPI through an Ethernet gateway.
- `siemens-s7-plc-health-s7-1500.lotnb`, for an S7-1500 read over PN: the same decoder and store route, its route and six actions.
- `siemens-s7-plc-health-simulator.lotnb`, for running with no PLC: both example PLCs simulated, answering the routes' read topics, with STOP and RUN from a topic. Deploy a family notebook **without its Route cell** when you use it.

The decoder and the store route are the same in both family notebooks, so the two run side by side on one broker. Each notebook also documents a Rule that keeps clients off the raw plane; it is not a cell, because Community refuses Rules: they need a Growth or Enterprise licence.
**Verified on 2.22.0:**
every cell of the three notebooks deployed on fresh brokers, 47 cells, 58 checks passed, no runtime error in the broker log. The family notebooks ran their real S7 routes against two mock PLCs that speak S7, with a real TimescaleDB behind the store route and Grafana on the historian. The checks cover whole-ring reads and the read contract, both forms of error-OB start information, the diagnostic buffer with Siemens' texts, the health loop stopped and fed a wrong value, STOP and RUN, the PLC gone, the second path read byte-identical over both paths, a fourth connector refused, the licence use of each notebook, and the simulator path into the UNS and the historian.

## Prerequisites

- Coreflux broker **2.22 or newer**: the actions publish retained leaves with `PUBLISH … RETAIN` and read JSON from a Python return value, which 2.14 cannot.
- **Licence:** each notebook fits the Community tier alone, and so do both family notebooks together. Measured on 2.22.0 Community: either family notebook alone uses 2 connectors of 3 and 12 actions of 24; both together 3 connectors and 22 actions; the S7-300 with its second path 3 connectors and 16 actions alone; a family notebook without its route plus the simulator 1 connector and 12 actions. A second PLC of either family is one more connector, beyond Community.
- **The kit's blocks in the CPU:** DB880 `DB_PerfMon`, DB881 `DB_PerfDiag` and DB882 `DB_PerfHealth`, from the template's TIA external source for the family, `perf_kit.scl`, with its guide; both are in the template's GitHub folder. On an S7-1500: PUT/GET allowed, which is hardware configuration, and optimized block access off on the three DBs.
- **A TimescaleDB** 2.11 or newer on PostgreSQL 16 or newer, with the template's SQL applied, from its GitHub folder: the schema, the fleet functions, Siemens' texts and two roles, `uns_writer` for the store route, which can only insert, and `grafana_reader`, which can only read. Without it the UNS still works and the store route logs that it cannot connect.
- **Environment and secret on the broker**, entered in the Hub under System Config, ENV and Secrets: `TIMESCALE_HOST`, `TIMESCALE_DB` and `TIMESCALE_USER` as ENV, `TIMESCALE_PASSWORD` as a SECRET.
- **The secret-store key pinned:** `COREFLUX_SECRET_KEY`, base64 of 32 random bytes, set on the broker container before you enter the secret. Unpinned, the key is derived from the machine and a restore onto other hardware cannot read the secret.
- **Anonymous login off.** Routes publish under an empty user name, which is also what an anonymous client presents, so the documented Rule is only sound with anonymous login off.
- The broker on the network of the PLCs, port 102. S7 has no authentication.

## Topic and data dictionary

**Raw plane**
- `siemens/site01/<PLC>/PN/<Kind>/read`: `go`, one whole-DB read; `<Kind>` is `PerfMon`, `PerfDiag` or `PerfHealth`.
- `siemens/site01/<PLC>/PN/<Kind>/raw`: the connector's answer, `{"success":true,"count":2058,"data":{"value_0":131140,…}}`.
- `siemens/site01/<PLC>/PN/<Kind>/decoded`: one JSON message per read for the historian.
- `siemens/site01/<PLC>/PN/Transition/decoded`: one message per change of a verdict.
- `siemens/site01/<PLC>/PN/PerfMon/Seq`, `…/PerfHealth/Life` and `…/PerfHealth/Echo/set`: the heartbeat and the health loop.
**UNS leaves**
All under `acme/site01/Automation/<PLC>/PN/`, retained, each the five-key envelope of `value`, `timestamp`, `datatype`, `status` and `units`:
- `CycleMin`, `CycleAvg`, `CycleMax`: ms, the newest one-second record.
- `CommLoad`: %, from `RT_INFO` on an S7-1500; -1 with status Bad on an S7-300, which has none.
- `OB80Events`, `OB82Events`, `OB86Events`, and on an S7-1500 `OB83Events`, `OB121Events`, `OB122Events`: calls since the boot.
- `LastFault`: the newest error-OB call in words. `LastDiagEvent`, S7-300 only: the newest buffer entry with Siemens' text.
- `BootTime`, `ReadDuration` in ms, `ClockSkew` in s.
- `CpuScanning`: false once `Seq` has not moved for 10 s.
- `Health`: `ok`, `stalled`, `corrupt` for 300 s after a wrong echo, `unknown` while the CPU is not scanning.
- `DeviceStatus`: `online` up to 20 s since the last good read or heartbeat, `stale` up to 90 s, `offline` beyond.
- `_asset`: the model, order number, route, endpoint and every leaf with its units and cadence.
**Simulator**
- `siemens/site01/_sim/<PLC>/mode`: publish `STOP` or `RUN`, retained.

## Quick start

**A] Without a PLC**
1. On a broker 2.22 or newer, open `siemens-s7-plc-health-s7-300.lotnb` or the S7-1500 one, and run every cell except the **Route** cell and the **Rules**.
2. Run `siemens-s7-plc-health-simulator.lotnb`.
3. Subscribe to `acme/site01/Automation/#`. Within 30 s the leaves fill.
4. Publish `STOP` with the retain flag to `siemens/site01/_sim/PLC01/mode`: `CpuScanning` turns false and `Health` unknown, while `DeviceStatus` stays online. Publish `RUN`: a new `BootTime`.

**B] With your PLC**
1. Put the kit's blocks into the CPU with the family's guide, and check the first read the guide describes.
2. Apply the template's SQL to your TimescaleDB, and set the ENV and the SECRET on the broker.
3. In the family notebook, put your CPU's address into the Route cell, and your `plc_id` into `PLCS` in the decoder cell and into the registry.
4. Run the cells in order: Python, Route, Storage, Actions. With a Growth or Enterprise licence, create your accounts and add the documented Rule.
5. Follow "How to verify" at the end of the notebook: decoded reads without an error, the leaves, a STOP seen within about 10 s.

## How it works

**The read contract**
A whole-DB read spans many CPU cycles while the ring moves on. The header comes first, so everything in it is older than the records. A record is accepted only when its number is not newer than the header's, it sits in the slot its number belongs to, it is not about to be overwritten during the read, and its stamp is a date. Everything else is counted by reason. The kit keeps the ring over a warm restart, and the same rules refuse the previous boot's records. Decoding is stateless and the database dedupes, so a broker restart is safe.

**Facts and evidence**
`plc_ingest()` stores every record once and, per path, when it first arrived and its content hash: two paths can be compared byte for byte, and no roll-up counts a record twice.

**STOP from outside**
In STOP the DBs stay readable and frozen. A record counter that stands still while the route still answers means the CPU is not scanning, and the network is fine. The values the program writes, the LEDs among them, are then the last ones of RUN and are not shown as current.

**Two forms of start information**
In a project migrated from an S7-300, some error OBs of an S7-1500 keep the classic start information. The kit records both forms in the same slot and marks the classic one with bit 7 of the event class; the decoder and the database read each in Siemens' own words.

**The second path, S7-300 only**
An S7-300 can be read over PN and, at the same time, over MPI through an Ethernet gateway. Each path has its own `DeviceStatus` and its own health loop, which locates a fault: MPI down with PN up is the gateway or the MPI bus; PN down with MPI up is the PN port or its switch; both down is power, the shared network or the broker's side; a frozen counter on a path that answers is the CPU itself. The S7-300 notebook's last section adds it in three steps: two lines in the decoder's `PLCS`, one route, and the registry's paths. It is a third connector: it fits Community alone, but not next to the S7-1500 notebook.

## Measured on real CPUs

**S7-300, a CPU 315-2 PN/DP running only these blocks**
- A whole `DB_PerfMon` of 8,232 bytes reads in 1.5 s over MPI at 187.5 kbit/s through an ACCON-NetLink, and in 0.3 s over PN, with a 240-byte PDU.
- Both paths delivered the same bytes: no record differed in two runs.
- With the blocks the CPU ran about 2,080 cycles a second, 0.48 ms on average. A loaded CPU serves communication between its other work, so measure on yours.

**S7-1500, a CPU 1511-1 PN, firmware V2.6, inside an existing program**
- The kit goes in without touching the program: its own program-cycle and startup OBs, and one call at the end of each error OB.
- A whole `DB_PerfMon` reads in about 0.02 s over PN with a 480-byte PDU.
- The program's unwired I/O called OB122 about 1,900 times a second; the kit counted all of them, over 56 million in eight hours, at about 0.1 ms a call.
- STOP was reported as not scanning about 10 s later, with the DBs still readable.
- The program cannot read the diagnostic buffer on this family, and this CPU refuses it to an outside S7 reader too: the error-OB records take its place.

## Production readiness

- Run the broker on the OT network and never route port 102 from an office network: S7 has no authentication.
- With a Growth or Enterprise licence, create the accounts and the documented Rule before any client connects. On Community there is no topic fence: give applications no broker account they do not need.
- One PLC per family fits Community; more PLCs need a licence with more connectors.
- Records are stamped by the CPU: give the CPU a correct clock, ideally from NTP, and watch `ClockSkew`.
- An error OB that is called all the time costs about 0.1 ms per call on a CPU 1511; in a healthy program the cost is not measurable.
- Back up the broker's volume and the database, and keep `COREFLUX_SECRET_KEY` in your password manager.

## How to customize

- **Your PLC:** the address, rack and slot in the Route cell; the DB numbers if you chose others; in `PLCS` the `plc_id`, model, order number and endpoint, and the same `plc_id` in the registry. If you run both family notebooks, keep their decoder cells equal.
- **Your UNS root:** replace `acme/site01` everywhere, and `siemens/site01` for the raw plane.
- **More PLCs:** per PLC one route per path, the six actions with the PLC key changed in their topics and in the trailing argument of each Python call, one entry in `PLCS`, one registry row. The decoder and the store route are shared.
- **Another reading interval:** change the read tick and `read_s` in `PLCS` together, and keep a read of the ring well inside its 120 s.

## Security notes

- Publishing on `siemens/#` writes into the PLC or makes the route read. The documented Rule `S7RawPlanePublish`, for Growth or Enterprise, admits only root and the broker's own identity. On Community a forged message can write only the one echo byte, which the health loop then reports as corrupt, or cause a read.
- The database password is a broker SECRET, never in a notebook.
- `uns_writer` can only insert, so a stolen broker credential cannot rewrite the history; `grafana_reader` can only read.

## Field notes

- **PUT/GET is hardware configuration on an S7-1500:** a download in RUN does not load it, and every read is refused until the hardware is downloaded, which stops the CPU.
- **A startup OB created as a program-cycle OB runs every cycle,** and nothing warns: the restart count ran to 32,767.
- **TIA Portal V15.1 reads an external source with LF line endings as STL.** Keep the sources CRLF.
- **Siemens' texts and meanings are reproduced from the manuals, with their source per row, and not all are confirmed on a CPU yet.** On the S7-1500 only OB122 has been measured so far. A code whose description does not match what your CPU did is a finding: corrections are welcome as a pull request in the template's GitHub repository.

&nbsp;
