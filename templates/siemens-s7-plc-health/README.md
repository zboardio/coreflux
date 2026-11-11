# siemens-s7-plc-health

**Status: in progress, not yet in the catalogue.** The PLC side runs on a real S7-300 and on a real S7-1500 (firmware V2.6), each read by a Coreflux 2.22 broker into a database and dashboards. What this folder holds today is the PLC side: the blocks and one guide per family. The notebooks, SQL and dashboards are still to come.

Health, cycle-time metrics and diagnostics from Siemens S7 PLCs, read into Coreflux with the native `SIEMENS_S7` connector. A small set of blocks in the PLC measures every cycle, counts every error-OB call and closes one record a second. The broker reads those records, so nothing is lost between two polls, and the PLC writes a health counter that the broker echoes back on each path.

One template, one folder per PLC family. What the broker reads is the same on every family: the cycle records (`DB_PerfMon`, byte-identical), the health loop (`DB_PerfHealth`) and a diagnostics block (`DB_PerfDiag`) whose header names its family. The PLC code differs, because each family reads its diagnostics differently.

| Folder | Family | Status |
|---|---|---|
| [`s7-300/`](s7-300/TIA-PROJECT.md) | S7-300, and the S7-400 by the same rules | runs on a CPU 315-2 PN/DP, read over MPI and PN at once |
| [`s7-1500/`](s7-1500/TIA-PROJECT.md) | S7-1500 | runs on a CPU 1511-1 PN, firmware V2.6, added to a project that already ran a program; read over PN |

Each folder holds `TIA-PROJECT.md`, the one guide from the IP address to the first read, and `plc/`, the blocks as a TIA external source.

## What the blocks give, by family

| | S7-300 | S7-1500 |
|---|---|---|
| Cycle time: min, max and average per second, and a histogram | `OB1_PREV_CYCLE` | `RUNTIME`, in the kit's own program-cycle OB |
| Communication load | not available | `RT_INFO` |
| Error OBs: counted, with the last start information | OB80, OB82, OB86 | OB80, OB82, OB83, OB86, OB121, OB122, each with S7-1500 or classic (S7-300/400 style) start information |
| Identity | SZL `0111`, `011C` | from the reader's configuration (`Get_IM_Data` is not in TIA V15.1 for FW V2.x) |
| LEDs | SZL `0074` | `LED` |
| Diagnostic buffer | the newest 10 entries, SZL `00A0` | not readable from the program on this family |
| Boot stamp, and the previous boot's counters | OB100 | the kit's own startup OB |
| Health loop, one byte written back per path | yes | yes |

**Firmware.** The S7-1500 blocks need nothing newer than firmware V2.x and no licence. That matters because monitoring through the S7-1500 Web API starts at firmware V2.8, with the diagnostic buffer from V3.1 and the runtime figures from V4.1, so it cannot see the many CPUs still running older firmware.

**Why count in the PLC.** A buffer only holds what fits. On the S7-1500 bench, an existing program accessing I/O that was not wired filled the whole diagnostic buffer, about 1,000 entries, in under half a second, and a power cut a few minutes later left no trace in it. A counter per error OB, with the last start information, survives that.

## Measured on the S7-300

A CPU 315-2 PN/DP with a 240-byte PDU, through the `SIEMENS_S7` connector on a Coreflux 2.22 broker. The CPU ran only these blocks, with no I/O cards or remote I/O connected.

| Read | MPI at 187.5 kbit/s, through an ACCON-NetLink | PN |
|---|---|---|
| `DB_PerfMon`, 8,232 bytes | **1.5 s** | **0.3 s** |
| `DB_PerfDiag`, 644 bytes | 0.12 s | 0.02 s |

- **Both paths deliver the same bytes:** no record differed in either of two runs, with 92 and 22 records present in both reads.
- **The cycle with these blocks:** about 2,080 cycles a second, 0.48 ms on average, 2 ms at most. There is no figure yet for this CPU without them.
- **These are from a CPU running almost nothing.** The same CPU ran a real application at around 40 ms a cycle. A CPU serves communication between its other work, so expect longer reads on a loaded one, and measure on yours.
- **A read is not atomic.** One read spans many CPU scans, and a read does find records newer than the header it read first. The decoder allows for that, and refuses those until the next read.

## Measured on the S7-1500

A CPU 1511-1 PN, firmware V2.6, engineered in TIA Portal V15.1. The kit was added to a project migrated from an S7-300 that already ran a program, with its I/O configured but not wired. Read over PN with PUT/GET, through the `SIEMENS_S7` connector on a Coreflux 2.22 broker.

- **The kit goes into an existing program without touching it.** Its own program-cycle OB and startup OB, and one call at the end of each error OB the project has. The source generates without errors in TIA V15.1.
- **A whole `DB_PerfMon`, 8,232 bytes, reads in about 0.02 s** over PN with a 480-byte PDU (a direct S7 read; `DB_PerfDiag`, 324 bytes, in about 1 ms).
- **The cycle:** about 20 ms with the existing program, 40 to 50 cycles a second, communication load 6 %.
- **Error OBs called all the time are counted, at a price.** The existing program caused about 1,900 OB122 calls a second. The kit counted all of them, over 56 million in eight hours, with the block and address of the last one. The average cycle rose from 19.8 ms to 24.9 ms, about 0.1 ms a call.
- **Both forms of start information end in the same record.** In a migrated project some error OBs keep the classic S7-300/400 start information and are written in STL. The guide gives the call for each form and language, and a reader tells the form from one bit of the record.
- **STOP is seen from outside.** The DBs stay readable, the record counter stands still, and the broker reports the CPU as not scanning about 10 s later. The values the program wrote, the LEDs among them, are then the last ones of RUN: a reader must not show them as current.
- **The program cannot read the diagnostic buffer on this family, and this CPU refuses it to an outside S7 reader too.** The error-OB records are what the kit offers in its place.

Not yet exercised on this CPU: the records of OB80, OB82, OB83, OB86 and OB121 (no such event on the bench so far), and the module states.

Still to come: LoT notebooks with a simulator, the SQL, the dashboards, `VERIFICATION.md` and `GALLERY.md`.
