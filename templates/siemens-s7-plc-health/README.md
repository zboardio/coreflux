# siemens-s7-plc-health

**Status: in progress, not yet in the catalogue.** The PLC side runs on a real S7-300 and is being ported to the S7-1500. The notebooks, SQL and dashboards are still to come.

Health, cycle-time metrics and diagnostics from Siemens S7 PLCs, read into Coreflux with the native `SIEMENS_S7` connector. A small set of blocks in the PLC measures every cycle, counts every error-OB call and closes one record a second. The broker reads those records, so nothing is lost between two polls, and the PLC writes a health counter that the broker echoes back on each path.

One template, one folder per PLC family. What the broker reads is the same on every family: the cycle records (`DB_PerfMon`, byte-identical), the health loop (`DB_PerfHealth`) and a diagnostics block (`DB_PerfDiag`) whose header names its family. The PLC code differs, because each family reads its diagnostics differently.

| Folder | Family | Status |
|---|---|---|
| [`s7-300/`](s7-300/TIA-PROJECT.md) | S7-300, and the S7-400 by the same rules | runs on a CPU 315-2 PN/DP, read over MPI and PN at once |
| [`s7-1500/`](s7-1500/TIA-PROJECT.md) | S7-1500 | added to an existing project on a CPU 1511-1 PN, firmware V2.6 |

Each folder holds `TIA-PROJECT.md`, the one guide from the IP address to the first read, and `plc/`, the blocks as a TIA external source.

## What the blocks give, by family

| | S7-300 | S7-1500 |
|---|---|---|
| Cycle time: min, max and average per second, and a histogram | `OB1_PREV_CYCLE` | `RUNTIME`, in the kit's own program-cycle OB |
| Communication load | not available | `RT_INFO` |
| Error OBs: counted, with the last start information | OB80, OB82, OB86 | OB80, OB82, OB83, OB86, OB121, OB122 |
| Identity | SZL `0111`, `011C` | `Get_IM_Data` |
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

Still to come: the S7-1500 measurements, LoT notebooks with a simulator, the SQL, the dashboards, `VERIFICATION.md` and `GALLERY.md`.
