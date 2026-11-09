# Build the TIA project

**Tested on:** CPU 315-2 PN/DP, `6ES7 315-2EH13-0AB0`. **Needs:** TIA Portal with STEP 7 Professional, because STEP 7 Basic does not cover the S7-300.

There are two ways in:

- **The project archive in `tia/`:** *Project → Retrieve*, then set your CPU and addresses (step 2). The blocks, their numbers and the OB calls are already done, so continue at step 8.
- **Your own project, from source:** follow every step. Use this when the CPU already runs a program.

The addresses below are examples: use your own.

## The blocks at a glance

| Number | FC | DB | Called from |
|---|---|---|---|
| **880** | `FC_PerfMon`, the main function | `DB_PerfMon` | **OB1, first network** |
| 881 | `FC_PerfDiag` | `DB_PerfDiag` | `FC_PerfMon` |
| 882 | `FC_PerfHealth` | `DB_PerfHealth` | `FC_PerfMon` |
| 883 | `FC_PerfStamp` | | the other FCs |
| 884 | `FC_PerfBoot` | | **OB100** |
| 885 | `FC_PerfFault` | | **OB80, OB82, OB86** |

**A DB has the same number as the FC that writes it.** The `880` range is used because even crowded programs rarely reach it.

- `FC_PerfMon` measures the cycle and closes one record per second into `DB_PerfMon`, the header and ring of cycle records. It runs the two below it.
- `FC_PerfDiag` reads the CPU's diagnostics, one request at a time, into `DB_PerfDiag`, along with the last fault and the previous boot.
- `FC_PerfHealth` runs each path's health loop in `DB_PerfHealth`, one counter per path.
- `FC_PerfStamp` gives the clock as two DINTs. `FC_PerfBoot` keeps the previous boot's counters and stamps the new boot. `FC_PerfFault` counts and records a fault.
- *PLC data types* holds `typPerfRecord` and `typPerfHealthSlot`, which have no number.

## 1. Start from the right project

**A download replaces what is in the CPU.** Blocks that are in the CPU but not in the project are deleted.

- **The CPU already runs a program:** work in that program's project. If you do not have it, use *Online → Upload device as new station* first, and keep a copy.
- **A spare CPU:** new project, *Add new device → Controllers → SIMATIC S7-300 → CPU*. Pick your order number and the firmware the CPU really has, from *Online & diagnostics → General*.

**A hardware download stops the CPU.** Choose the moment.

## 2. Set the addresses

*Device view → the CPU → Properties.*

| Setting | Where | Value |
|---|---|---|
| PN address | *PROFINET interface [X2] → Ethernet addresses*: add a subnet, *Set IP address in the project* | e.g. `192.168.1.10` / `255.255.255.0` |
| Router | same place | only if the reader is on another subnet |
| MPI address | *MPI/DP interface [X1] → MPI address* | leave what the bus uses; the example is `2` |
| Protection | *Protection* | *No protection* to start with. A protected CPU is a separate check |
| Connection resources | *Communication* or *Connection resources* | one free OP connection per path, on top of what is in use |

Note the *Maximum cycle time* (*Cycle*), and the cycle times now in *Online & diagnostics → Cycle time*. You compare against them in step 9.

## 3. Create the OBs

*Program blocks → Add new block → Organization block*, language LAD, for each one the program does not have yet. A hand-made OB carries the header the CPU defines, such as `OB1_PREV_CYCLE`, and nothing imported can overwrite your own code.

OB1, OB100, OB80, OB82 and OB86 are needed. They get their calls in step 7.

## 4. Import the code

1. *External source files → Add new external file →* `plc/perf_kit.scl`.
2. Right-click it, *Generate blocks from source.* The file has Windows line endings (CRLF), and must keep them: an older TIA, V15.1 for one, reads the code of a file saved with Unix line endings (LF) as STL and fails on its first statement, while the DBs still compile. If you edit the file, use an editor that keeps CRLF.
3. Read the result in the *Info* tab. Any error: stop here, and **read the first error, at the top of the list.** The rest usually follow from it.

## 5. Confirm the blocks and set their numbers

Check that every block in *The blocks at a glance* was created. TIA gives each generated block the next free number, so set them by hand from that table: on each block, *Properties → General → Numbering → Manual.* Check the `880` range is free first.

**The DB numbers matter:** the broker addresses them by number. If you pick others, use them in the route too.

## 6. Reading from outside

On an S7-300 there is less to set than on newer CPUs:

| Setting on an S7-1200/1500 | On an S7-300 |
|---|---|
| *Permit access with PUT/GET* | does not exist: the access is always on, subject to the protection level (step 2) |
| *Optimized block access* off | does not exist: every DB has absolute offsets |

Check these in each DB's *Properties → Attributes*:

| Attribute | `DB_PerfMon` | `DB_PerfDiag` | `DB_PerfHealth` | Why |
|---|---|---|---|---|
| *Only store in load memory* | off | off | off | such a DB cannot be read at run time |
| *Data block write-protected in the device* | off | off | off | `DB_PerfHealth` takes the `Echo` bytes, and the CPU writes all three |
| *Non-retain* | off | **off** | off | `DB_PerfDiag` must keep why the CPU stopped |

## 7. The OB calls

**The CPU runs these OBs itself, on its own event: OB1 every cycle, OB100 at start-up, the others on a fault. Never call one from OB1.** What goes in each is the line below, inside that OB.

**Do all five. Nothing fails if you miss one:** an empty OB compiles and downloads, and the records still flow, but a boot is never stamped and a fault never recorded. An empty OB80, OB82 or OB86 also stops the CPU reacting to that fault at all.

**Use LAD.** An OB a program already has is usually LAD, and a new network leaves the rest of it alone. TIA can create a new OB in SCL, but an S7-300 has no SCL network inside a LAD block, so an existing OB takes no text. Each call is a box: drag the FC from *Program blocks* into a new network, or find `STP` in *Instructions*, and fill in its inputs. The `#` names are in each OB's own header, its *Temp* section. Keep your own code in them.

**Title every network,** so whoever opens a system OB later can see why it was changed.

| Where | Network title | Drag in | Input | Wire to |
|---|---|---|---|---|
| OB1, first network | Performance Monitor | `FC_PerfMon` | `PrevCycle_ms` | `#OB1_PREV_CYCLE` |
| OB100 | Performance Boot Log | `FC_PerfBoot` | none |  |
| OB80 | Performance Diagnostic | `FC_PerfFault` | `OB_Nr` | `80` |
| OB80 | Performance Diagnostic | `FC_PerfFault` | `EvClass` | `#OB80_EV_CLASS` |
| OB80 | Performance Diagnostic | `FC_PerfFault` | `FltId` | `#OB80_FLT_ID` |
| OB80, next network | Stop the CPU, as with no OB | `STP` | none |  |
| OB82 | Performance Diagnostic | `FC_PerfFault` | `OB_Nr` | `82` |
| OB82 | Performance Diagnostic | `FC_PerfFault` | `EvClass` | `#OB82_EV_CLASS` |
| OB82 | Performance Diagnostic | `FC_PerfFault` | `FltId` | `#OB82_FLT_ID` |
| OB82, next network | Stop the CPU, as with no OB | `STP` | none |  |
| OB86 | Performance Diagnostic | `FC_PerfFault` | `OB_Nr` | `86` |
| OB86 | Performance Diagnostic | `FC_PerfFault` | `EvClass` | `#OB86_EV_CLASS` |
| OB86 | Performance Diagnostic | `FC_PerfFault` | `FltId` | `#OB86_FLT_ID` |
| OB86, next network | Stop the CPU, as with no OB | `STP` | none |  |

**`STP` keeps the reaction the CPU has with no OB at all:** on an S7-300, a missing OB80, OB82 or OB86 normally means STOP on that event, so an OB that only counted would silently remove it. Leave it out only if your safety concept says so. If the OB already has its own reaction, keep that and add just the `FC_PerfFault` box.

## 8. Compile, compare, download

1. *Compile → Hardware and software (rebuild all).*
2. Open each DB and compare the *Offset* column. **A read addresses bytes, so these must match exactly:**

   | DB | Tag | Offset |
   |---|---|---|
   | `DB_PerfMon` | `WriteIdx` | 6.0 |
   | `DB_PerfMon` | `Seq` | 8.0 |
   | `DB_PerfMon` | `Edges_ms` | 16.0 |
   | `DB_PerfMon` | `OB80Total` | 52.0 |
   | `DB_PerfMon` | `BootDate` | 64.0 |
   | `DB_PerfMon` | `Ring` | 72.0 |
   | `DB_PerfMon` | `IsStarted` | 8232.0 |
   | `DB_PerfDiag` | `DiagSeq` | 4.0 |
   | `DB_PerfDiag` | `FaultOB` | 8.0 |
   | `DB_PerfDiag` | `PrevBootDate` | 24.0 |
   | `DB_PerfDiag` | `Ret` | 48.0 |
   | `DB_PerfDiag` | `IdOrder` | 72.0 |
   | `DB_PerfDiag` | `DiagBuffer` | 444.0 |
   | `DB_PerfDiag` | `Step` | 644.0 |
   | `DB_PerfHealth` | `MPI.Life` | 8.0 |
   | `DB_PerfHealth` | `MPI.Echo` | 9.0 |
   | `DB_PerfHealth` | `PN.Life` | 26.0 |
   | `DB_PerfHealth` | `PN.Echo` | 27.0 |

3. *Download to device,* over whichever path you reach the CPU on today. Read the list of actions before accepting it: look for blocks about to be deleted.
4. Start the CPU. The PN address is live from this download on: check it answers a ping.
5. **Set the CPU's clock to UTC,** in *Online & diagnostics → Functions → Set time.* A local clock has daylight-saving ambiguity. If it must stay local, record the zone wherever you store the data.

## 9. Confirm it runs

A watch table:

| Tag | Expect |
|---|---|
| `DB_PerfMon.Seq`, `WriteIdx` | `Seq` up by 1 each second, `WriteIdx` following, 0 to 119 |
| `DB_PerfMon.BootDate`, `BootTime`, `RestartCount` | today, and 1 or more, after a restart of the CPU. **Still 0 means OB100 has no call:** step 7 |
| `DB_PerfMon.Ring[0].CycMax_ms`, `Cycles` | filled |
| `DB_PerfDiag.Step` | 0 to 3 once, then 4 to 8 repeating, one step every 2 seconds |
| `DB_PerfDiag.Ret[0..7]`, `RetDiagBuffer` | 0, or a code telling which SZL this CPU refuses |
| `DB_PerfHealth.MPI.Life`, `PN.Life` | 1 and still, until a reader confirms them |

Compare the cycle times with step 2.

**Set the histogram once, before comparing anything:** `DB_PerfMon.Edges_ms` holds the buckets' upper edges. The default is `2 | 5 | 10 | 20 | 40 | 60 | 100` ms, to separate an idle CPU from one running a real program. A cycle reads in whole milliseconds.

## 10. The first read

Close any online monitoring first: on MPI it shares the bus and changes the timing.

```lot
DEFINE ROUTE S7ReadTest WITH TYPE SIEMENS_S7
    ADD S7_CONFIG
        WITH IP "192.168.1.10"
        WITH CPU_TYPE "S7300"
        WITH RACK 0
        WITH SLOT 2
        WITH PORT 102
        WITH CONNECTION_TYPE "OP"
        WITH READ_TIMEOUT 30000
        WITH WRITE_TIMEOUT 30000
    ADD EVENT ReadAll
        WITH SOURCE_TOPIC "s7test/cmd/read"
        WITH DESTINATION_TOPIC "s7test/res/read"
        WITH QUERY "{operation: READ, address: DB880.DBD0, data_type: DWORD, count: 2058}"
```

Publish anything to `s7test/cmd/read`. `s7test/res/read` answers with `{"success":true,…,"count":2058,"data":{"value_0":131140,…}}`: that first value is `16#00020044`, `LayoutVersion` 2 and `RecordSize` 68, and it proves the addressing. Remove the route afterwards.

**Over MPI, through an Ethernet gateway,** use the gateway's IP. With an ACCON-NetLink in addressed mode, `SLOT` is the CPU's MPI address, not its real slot, and `CONNECTION_TYPE "OP"` is required.

| You see | It means |
|---|---|
| `Received error from PLC: Address out of range.` | wrong DB number, or a DB shorter than the read |
| `Siemens S7 PLC is not connected` | the route has no connection: check the address and port 102 |
| Route says added, but stays `Disconnected` | read the broker log; a tier limit is one cause, and each `ADD EVENT` counts as an action |

## 11. Archive the project

*Project → Archive*, with restorable data discarded, gives a `.zap` file. It opens in the TIA version it was saved with or a newer one, as long as that version still supports the S7-300.

## Optional: the read test

`plc/read_probe.scl` shows what a whole-DB read delivers over your hardware path and what it costs the CPU: it rewrites a scan counter across 8,232 bytes every cycle, so one read shows how many scans it spans. It is separate from the blocks above, and you do not need it to run them.

1. Import it as in step 4 and set the numbers: `FC_ReadProbe` `FC889`, `DB_ReadProbe` `DB889`.
2. OB1, a network of its own: drag in `FC_ReadProbe`, and wire `PrevCycle_ms` to `#OB1_PREV_CYCLE`.
3. In a watch table on `DB_ReadProbe`: `Scan` counts fast, and `InitNext` and `InitDone` reach 64 and TRUE within a second.
4. Read it as in step 10, with `DB889.DBD0` and `count: 2058`. The first value is `1347571522`, `16#50524F42`, the letters `PROB`.

To remove it: delete the OB1 call, `FC_ReadProbe`, `DB_ReadProbe` and `typProbeStripe`, then download.
