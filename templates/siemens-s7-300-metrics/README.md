# siemens-s7-300-metrics

**Status: in progress. Not in the catalogue and not verified yet.** What a whole-DB read delivers on a real CPU is being measured, and it sets the design of the metrics blocks.

Cycle-time metrics and diagnostics from a Siemens S7-300, read into Coreflux with the native `SIEMENS_S7` connector. The test bench reads one CPU over two hardware paths at once, MPI through an Ethernet gateway and the CPU's own PN port, and the same data on two independent chains is what lets you tell a cable fault from a stopped CPU.

| File | What |
|---|---|
| [`TIA-PROJECT.md`](TIA-PROJECT.md) | the one guide for building the TIA project, from the IP address to the first read |
| [`plc/read_probe.scl`](plc/read_probe.scl) | stage 1: the read test, as a TIA external source. **Not yet compiled in TIA** |
| `tia/` | the archived TIA project, added once the guide has been followed on hardware |

Still to come: the metrics blocks, LoT notebooks with a simulator, the SQL, the dashboards, `VERIFICATION.md` and `GALLERY.md`.
