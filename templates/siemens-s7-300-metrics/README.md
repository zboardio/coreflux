# siemens-s7-300-metrics

**Status: in progress, not yet in the catalogue.** The PLC side runs on a real CPU. The notebooks, SQL and dashboards are still to come.

Cycle-time metrics and diagnostics from a Siemens S7-300, read into Coreflux with the native `SIEMENS_S7` connector. The test bench reads one CPU over two hardware paths at once, MPI through an Ethernet gateway and the CPU's own PN port, and the same data on two independent chains is what lets you tell a cable fault from a stopped CPU.

| File | What |
|---|---|
| [`TIA-PROJECT.md`](TIA-PROJECT.md) | the one guide for the TIA project, from the IP address to the first read |
| [`plc/perf_kit.scl`](plc/perf_kit.scl) | the metrics and diagnostics blocks, as a TIA external source |
| [`plc/read_probe.scl`](plc/read_probe.scl) | optional: a test of what a whole-DB read delivers on your hardware path |
| `tia/` | the archived TIA project |

## Measured

A CPU 315-2 PN/DP with a 240-byte PDU, through the `SIEMENS_S7` connector on a Coreflux 2.22 broker. The CPU ran only these blocks, with no I/O cards or remote I/O connected.

| Read | MPI at 187.5 kbit/s, through an ACCON-NetLink | PN |
|---|---|---|
| `DB_PerfMon`, 8,232 bytes | **1.5 s** | **0.3 s** |
| `DB_PerfDiag`, 644 bytes | 0.12 s | 0.02 s |

- **Both paths deliver the same bytes:** no record differed in either of two runs, with 92 and 22 records present in both reads.
- **The cycle with these blocks:** about 2,080 cycles a second, 0.48 ms on average, 2 ms at most. There is no figure yet for this CPU without them.
- **These are from a CPU running almost nothing.** The same CPU ran a real application at around 40 ms a cycle. A CPU serves communication between its other work, so expect longer reads on a loaded one, and measure on yours.
- **A read is not atomic.** One read spans many CPU scans, and a read does find records newer than the header it read first. The decoder allows for that, and refuses those until the next read.

Still to come: LoT notebooks with a simulator, the SQL, the dashboards, `VERIFICATION.md` and `GALLERY.md`.
