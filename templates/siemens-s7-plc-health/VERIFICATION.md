# Verification

Run 2026-11-22 22:14 UTC on a fresh `coreflux/coreflux-mqtt-broker:2.22.0` broker
(`sha256:704360cfb20d…`, durability on, default accounts) in local Docker,
by the template's maintainers. The run deploys every code cell in notebook order (Rules last),
runs the simulator, then checks what arrives on the wire with an MQTT 5 observer.

**Cells deployed: 47/47 accepted. Checks: 58/58 passed. Runtime errors in the broker log: 0.**

## Deploy verdicts

| notebook | entity | verdict |
|---|---|---|
| `siemens-s7-plc-health-s7-1500.lotnb.md` | `PYTHON S7PerfDecode` | accepted |
| `siemens-s7-plc-health-s7-1500.lotnb.md` | `ROUTE S7PLC02PN` | accepted |
| `siemens-s7-plc-health-s7-1500.lotnb.md` | `ROUTE S7Store` | accepted |
| `siemens-s7-plc-health-s7-1500.lotnb.md` | `ACTION S7PLC02ReadTick` | accepted |
| `siemens-s7-plc-health-s7-1500.lotnb.md` | `ACTION S7PLC02Decode` | accepted |
| `siemens-s7-plc-health-s7-1500.lotnb.md` | `ACTION S7PLC02Echo` | accepted |
| `siemens-s7-plc-health-s7-1500.lotnb.md` | `ACTION S7PLC02Scan` | accepted |
| `siemens-s7-plc-health-s7-1500.lotnb.md` | `ACTION S7PLC02Liveness` | accepted |
| `siemens-s7-plc-health-s7-1500.lotnb.md` | `ACTION S7PLC02Uns` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `PYTHON S7PerfDecode` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ROUTE S7PLC01PN` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ROUTE S7Store` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ACTION S7PLC01ReadTick` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ACTION S7PLC01Decode` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ACTION S7PLC01Echo` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ACTION S7PLC01Scan` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ACTION S7PLC01Liveness` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ACTION S7PLC01Uns` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `PYTHON S7PerfDecode` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ROUTE S7PLC01PN` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ROUTE S7Store` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ACTION S7PLC01ReadTick` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ACTION S7PLC01Decode` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ACTION S7PLC01Echo` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ACTION S7PLC01Scan` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ACTION S7PLC01Liveness` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ACTION S7PLC01Uns` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `PYTHON S7PerfDecode` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ROUTE S7Store` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ACTION S7PLC01ReadTick` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ACTION S7PLC01Decode` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ACTION S7PLC01Echo` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ACTION S7PLC01Scan` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ACTION S7PLC01Liveness` | accepted |
| `siemens-s7-plc-health-s7-300.lotnb.md` | `ACTION S7PLC01Uns` | accepted |
| `siemens-s7-plc-health-simulator.lotnb.md` | `PYTHON S7KitSim` | accepted |
| `siemens-s7-plc-health-simulator.lotnb.md` | `ACTION S7SimTick` | accepted |
| `siemens-s7-plc-health-simulator.lotnb.md` | `ACTION S7SimEcho` | accepted |
| `siemens-s7-plc-health-simulator.lotnb.md` | `ACTION S7SimRead` | accepted |
| `siemens-s7-plc-health-s7-1500.lotnb.md` | `PYTHON S7PerfDecode` | accepted |
| `siemens-s7-plc-health-s7-1500.lotnb.md` | `ROUTE S7Store` | accepted |
| `siemens-s7-plc-health-s7-1500.lotnb.md` | `ACTION S7PLC02ReadTick` | accepted |
| `siemens-s7-plc-health-s7-1500.lotnb.md` | `ACTION S7PLC02Decode` | accepted |
| `siemens-s7-plc-health-s7-1500.lotnb.md` | `ACTION S7PLC02Echo` | accepted |
| `siemens-s7-plc-health-s7-1500.lotnb.md` | `ACTION S7PLC02Scan` | accepted |
| `siemens-s7-plc-health-s7-1500.lotnb.md` | `ACTION S7PLC02Liveness` | accepted |
| `siemens-s7-plc-health-s7-1500.lotnb.md` | `ACTION S7PLC02Uns` | accepted |

## Checks

| # | what is checked | result | evidence |
|---|---|---|---|
| L1 | the S7-1500 notebook alone fits Community (≤ 3 connectors, ≤ 24 actions) | PASS | 2 connectors, 12 actions {'regular': 6, 'routeEvents': 5, 'pythonScripts': 1} |
| L2 | both family notebooks on one broker fit Community | PASS | 3 connectors, 22 actions {'regular': 12, 'routeEvents': 9, 'pythonScripts': 1} |
| A1 | route S7PLC01PN connected (the S7 routes by the mock's host name) | PASS | Connected/Green, errors {'total': 0, 'consecutive': 0, 'rate': 0} |
| A1 | route S7PLC02PN connected (the S7 routes by the mock's host name) | PASS | Connected/Green, errors {'total': 0, 'consecutive': 0, 'rate': 0} |
| A1 | route S7Store connected (the S7 routes by the mock's host name) | PASS | Connected/Green, errors {'total': 0, 'consecutive': 0, 'rate': 0} |
| A2 | PLC01: all three DBs read whole over PN, none failed, each with a duration | PASS | PN PerfDiag 4 0 9; PN PerfHealth 3 0 2; PN PerfMon 3 0 10 |
| A3 | PLC01: one-second records stored contiguous, each once; the previous boot's slots offered and refused | PASS | 98 rows, seq 1..98, 15 refused as newer than the header |
| A2 | PLC02: all three DBs read whole over PN, none failed, each with a duration | PASS | PN PerfDiag 4 0 32; PN PerfHealth 3 0 3; PN PerfMon 3 0 15 |
| A3 | PLC02: one-second records stored contiguous, each once; the previous boot's slots offered and refused | PASS | 97 rows, seq 1..97, 15 refused as newer than the header |
| A4 | PLC01 (S7-300): the diagnostic buffer stored with Siemens' texts, the STOP cause of the restart named | PASS | 0x4301 Mode transition from STOP to STARTUP / 0x4304; 0x4302 Mode transition from STARTUP to RUN / - |
| A5 | plc_cycle keeps the PLCs apart: CommLoad NULL on the S7-300 (it sends -1), RT_INFO's on the S7-1500 | PASS | acme-site01-plc01=NULL,acme-site01-plc02=3.0 |
| A6 | PLC02 (S7-1500): OB122's newest call per read, the count rising (the mock calls it ~2,000 times a second) | PASS | 4/t |
| A7 | PLC02: every error-OB call in Siemens' words, both forms: OB82 and OB86 classic, OB122 S7-1500 form | PASS | OB82 classic 16#39/16#42 Diagnostic interrupt, incoming event: a problem, or a component requires maintenance / classic, input module 256, Module is defective, External fault, Channel fault, Channel i |
| A7b | a classic OB122 through the notebook's decoder and plc_ingest() as uns_writer: block, I/O area and access type, address | PASS | OB122 classic 16#42 I/O access error, reading / FC 72 / I/O area, word access / 256 |
| A8 | plc_latest: one row per PLC, with its family | PASS | acme-site01-plc01 s7-300, acme-site01-plc02 s7-1500 |
| A21 | uns_writer cannot read the history or the text tables | PASS | ERROR:  permission denied for table plc_cycle; ERROR:  permission denied for table plc_event_text; ERROR:  permission denied for table plc_ob_call |
| A22 | grafana_reader reads the history, the fleet view and the texts, and cannot write | PASS | 195, 2, 9, 2, 6, 2 |
| A9 | PLC01: every leaf of its family retained under PN for a fresh subscriber, nothing under another path | PASS | 15 leaves + _asset |
| A10 | PLC01: each leaf the five-key envelope (units on numbers only), ISO-8601 UTC | PASS |  |
| A11 | PLC01: _asset names the route, the model and every leaf | PASS | {"kind": "native-route", "route": "S7PLC01PN", "endpoint": "192.168.1.10:102", "via": "the CPU's own PN port", "raw": "siemens/site01/PLC01/ |
| A12 | PLC01: CpuScanning true, Health ok, DeviceStatus online | PASS | {'CpuScanning': True, 'Health': 'ok', 'DeviceStatus': 'online'} |
| A13 | PLC01: CycleMax carries the PLC's stamp of a stored record | PASS | 2026-11-22T22:05:04.573Z, 1 record |
| A9 | PLC02: every leaf of its family retained under PN for a fresh subscriber, nothing under another path | PASS | 17 leaves + _asset |
| A10 | PLC02: each leaf the five-key envelope (units on numbers only), ISO-8601 UTC | PASS |  |
| A11 | PLC02: _asset names the route, the model and every leaf | PASS | {"kind": "native-route", "route": "S7PLC02PN", "endpoint": "192.168.1.20:102", "via": "the CPU's own PN port", "raw": "siemens/site01/PLC02/ |
| A12 | PLC02: CpuScanning true, Health ok, DeviceStatus online | PASS | {'CpuScanning': True, 'Health': 'ok', 'DeviceStatus': 'online'} |
| A13 | PLC02: CycleMax carries the PLC's stamp of a stored record | PASS | 2026-11-22T22:05:03.579Z, 1 record |
| A14 | PLC01: CommLoad -1 with status Bad; LastDiagEvent with Siemens' text; LastFault from DB_PerfDiag | PASS | {'value': -1.0, 'timestamp': '2026-11-22T22:05:04.573Z', 'datatype': 'number', 'status': 'Bad', 'units': '%'} / 0x4302, Mode transition from STARTUP to RUN / OB80, event class 0x39, fault id 0x01 |
| A15 | PLC02: LastFault the newest error-OB call in words, OB122Events counting the flood, CommLoad from RT_INFO | PASS | {'LastFault': 'OB122, fault id 0x42 I/O access error, reading, FC 72, area 0x01 Direct (peripheral) access to inputs, 185421 calls since the boot', 'OB122Events': 185421, 'OB83Events': 0, 'CommLoad':  |
| A16 | PLC01: echo action stopped → Health stalled; back → ok; the PLC counted the loss | PASS | stalled then ok, PLC Losses 1 |
| A17 | PLC02: a wrong value written to Echo → Health corrupt, the PLC counted BadEcho | PASS | corrupt, BadEcho 1 |
| A18 | STOP: CpuScanning false on both PLCs, both still online, Health unknown | PASS | CpuScanning [False, False], DeviceStatus ['online', 'online'], Health ['unknown', 'unknown'] |
| A19 | RUN again: CpuScanning true on both; Health judged again | PASS | CpuScanning [True, True], PLC01 Health ok |
| A20 | PLC01: every verdict change in plc_state_change (online, the faults, STOP and RUN) | PASS | uScanning ->true; PN DeviceStatus ->online; PN Health ->ok; PN Health ok>stalled; PN Health stalled>ok; PN CpuScanning true>false; PN Health ok>unknown; PN CpuScanning false>true; PN Health unknown>ok |
| A20 | PLC02: every verdict change in plc_state_change (online, the faults, STOP and RUN) | PASS | PN DeviceStatus ->online; PN CpuScanning ->true; PN Health ->ok; PN Health ok>corrupt; PN CpuScanning true>false; PN Health corrupt>unknown; PN CpuScanning false>true; PN Health unknown>corrupt |
| G1 | Grafana: the datasource (uid timescale-edge) connects as grafana_reader | PASS | Database Connection OK |
| G2 | Grafana: the fleet and both family dashboards provisioned, the alert rules loaded | PASS | dashboards ['plc-detail-s7-1200', 'plc-detail-s7-1500', 'plc-detail-s7-300', 'plc-fleet'], 27 rules |
| G3 | Grafana: no error in its log after the run's faults | PASS | 0 errors (in the notes below) |
| B1 | the Rule is refused on Community, as the notebooks say (it needs Growth or Enterprise); the same text in both notebooks | PASS | Failed to add Rule. RBAC / Topic Access Control rules require a Growth or Enterprise license. Please contact Coreflux: <a href="https://coreflux.org/contact">Co |
| L3 | the S7-300 notebook alone fits Community | PASS | 2 connectors, 12 actions {'regular': 6, 'routeEvents': 5, 'pythonScripts': 1} |
| C1 | the second path deployed as documented: PLCS edited, route S7PLC01MPI, the registry's paths | PASS | edit True, decoder Python script 'S7PerfDecode' added succe, route Connector 'S7PLC01MPI' added successfully!, sql  |
| L4 | the S7-300 notebook with its second path fits Community alone (3 connectors) | PASS | 3 connectors, 16 actions {'regular': 6, 'routeEvents': 9, 'pythonScripts': 1} |
| C2 | PLC01: all three DBs read over MPI and over PN, none failed | PASS | MPI PerfDiag 2 0; MPI PerfHealth 2 0; MPI PerfMon 2 0; PN PerfDiag 2 0; PN PerfHealth 3 0; PN PerfMon 2 0 |
| C3 | the same records arrived over both paths, byte-identical, each stored once | PASS | 87 records on both paths, 0 differ |
| C4 | the MPI branch of the UNS: CpuScanning true, Health ok, DeviceStatus online; PN's Health still ok | PASS | MPI {'CpuScanning': True, 'Health': 'ok', 'DeviceStatus': 'online'}, PN Health ok |
| C5 | plc_registry names both paths, in PLCS order | PASS | {PN,MPI} |
| D1 | Community refuses a fourth connector: the S7-300 with its second path and the S7-1500 do not fit one broker together | PASS | Tier limit exceeded: Maximum allowed connectors are 3. Please contact Coreflux: <a href="https://coreflux.org/contact">Coreflux</a> / {'message': 'Connector lim |
| D2 | the PLC gone: DeviceStatus stale on both paths | PASS | {'PN': 'stale', 'MPI': 'stale'} |
| L5 | the S7-300 notebook and the simulator fit Community | PASS | 1 connectors, 12 actions {'regular': 9, 'routeEvents': 1, 'pythonScripts': 2} |
| L6 | both family notebooks and the simulator fit Community | PASS | 1 connectors, 18 actions {'regular': 15, 'routeEvents': 1, 'pythonScripts': 2} |
| S1 | simulator, PLC01 (S7-300): every leaf, CycleAvg about 0.48 ms, CommLoad -1, the buffer's newest entry in words, all well | PASS | {'CycleMin': 0.41, 'CycleAvg': 0.512, 'CycleMax': 2.0, 'CommLoad': -1.0, 'OB80Events': 0, 'OB82Events': 0, 'OB86Events': 0, 'CpuScanning': True, 'BootTime': '2026-11-22T22:11:26.733Z', 'LastFault': 'n |
| S2 | simulator, PLC02 (S7-1500): every leaf, CycleAvg about 20 ms, CommLoad about 6 %, OB122 counting, LastFault in words | PASS | {'CycleMin': 17.6, 'CycleAvg': 21.983, 'CycleMax': 25.983, 'CommLoad': 6.41, 'OB80Events': 0, 'OB82Events': 1, 'OB86Events': 0, 'CpuScanning': True, 'BootTime': '2026-11-22T22:11:26.748Z', 'LastFault' |
| S3 | simulator: each leaf the five-key envelope | PASS |  |
| S4 | simulator → historian: one-second records of both PLCs, contiguous, no failed read | PASS | acme-site01-plc01 67 67, acme-site01-plc02 68 68; 0 failed reads |
| S5 | simulator → historian: PLC02's error-OB calls in words (classic OB82, OB122), PLC01's buffer entries with text | PASS | OB122 S7-1500 I/O access error, reading / OB82 classic Diagnostic interrupt, incoming event: a problem, or a component requires maintenance # 0x4301 Mode transition from STOP to STARTUP / 0x4302 Mode  |
| S6 | simulator STOP (mode topic): CpuScanning false, Health unknown, the path still online | PASS | False, unknown, online |
| S7 | simulator RUN: CpuScanning true, a new BootTime, the STOP entry (0x4304) in the historian's diagnostic buffer | PASS | True, BootTime 2026-11-22T22:11:26.733Z → 2026-11-22T22:13:25.540Z, 0x4304 rows 1 |
| S8 | simulator: the echo action stopped → Health stalled, back → ok | PASS | stalled, ok |

## Runtime errors (broker log)

None.

## Measured alongside

- Stack: the template's own compose/docker-compose.yml, Grafana included.
- Licence, the S7-1500 notebook alone: tier Community, connectors 2 of 3, actions 12 of 24 `{"regular": 6, "routeEvents": 5, "pythonScripts": 1}`
- Licence, both family notebooks: tier Community, connectors 3 of 3, actions 22 of 24 `{"regular": 12, "routeEvents": 9, "pythonScripts": 1}`
- The Rule on Community 2.22.0: refused: Failed to add Rule. RBAC / Topic Access Control rules require a Growth or Enterprise license. Please contact Coreflux: <a href="https://coreflux.org/contact">Coreflux.org</a>. | {'message': 'RBAC / To
- Licence, the S7-300 notebook alone: tier Community, connectors 2 of 3, actions 12 of 24 `{"regular": 6, "routeEvents": 5, "pythonScripts": 1}`
- Licence, the S7-300 notebook with its second path: tier Community, connectors 3 of 3, actions 16 of 24 `{"regular": 6, "routeEvents": 9, "pythonScripts": 1}`
- A fourth connector (S7PLC02PN next to the S7-300 with two paths): refused: Tier limit exceeded: Maximum allowed connectors are 3. Please contact Coreflux: <a href="https://coreflux.org/contact">Coreflux</a> | {'message': 'Connector lim
- Licence, the S7-300 notebook without its Route, and the simulator: tier Community, connectors 1 of 3, actions 12 of 24 `{"regular": 9, "routeEvents": 1, "pythonScripts": 2}`
- Licence, both family notebooks without their Routes, and the simulator: tier Community, connectors 1 of 3, actions 18 of 24 `{"regular": 15, "routeEvents": 1, "pythonScripts": 2}`
