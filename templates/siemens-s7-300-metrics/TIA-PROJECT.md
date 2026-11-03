# Build the TIA project

One guide, in the order you do it. Stage 1 is the read test and stands alone. Stage 2 repeats the same steps for the metrics blocks.

**Tested on:** CPU 315-2 PN/DP, `6ES7 315-2EH13-0AB0`. **Needs:** TIA Portal with STEP 7 Professional, because STEP 7 Basic does not cover the S7-300.

**`plc/read_probe.scl` has not been through a TIA compile yet.** A compile error here is the first thing to fix, so please report it.

| Stage | What goes into the CPU | State |
|---|---|---|
| 1 | one DB, one FC, one UDT, a call in OB1 | source ready |
| 2 | the metrics DBs, FCs and FB, plus OB100, OB80, OB82 and OB86 | written after stage 1, because stage 1's numbers size them |

The addresses below are examples: use your own.

## 1. Start from the right project

**A download replaces what is in the CPU.** Blocks that are in the CPU but not in the project are deleted.

- **The CPU already runs a program:** work in that program's project. If you do not have it, use *Online → Upload device as new station* first, and keep a copy.
- **A spare CPU:** new project, *Add new device → Controllers → SIMATIC S7-300 → CPU*. Pick your order number and the firmware the CPU really has, from *Online & diagnostics → General*.

**A hardware download stops the CPU.** Choose the moment.

## 2. Set the addresses

*Device view → the CPU → Properties.*

| Setting | Where | Value |
|---|---|---|
| PN address | *PROFINET interface [X2] → Ethernet addresses*: add a subnet, *Set IP address in the project* | e.g. `192.0.2.131` / `255.255.255.0` |
| Router | same place | only if the reader is on another subnet |
| MPI address | *MPI/DP interface [X1] → MPI address* | leave what the bus uses; the example is `2` |
| Protection | *Protection* | *No protection* for this test. A protected CPU is a separate check later |
| Connection resources | *Communication* or *Connection resources* | one free OP connection per path, on top of what is in use |

Note the *Maximum cycle time* (*Cycle*), and the cycle times shown now in *Online & diagnostics → Cycle time*. You compare against them in step 9.

## 3. System OBs

Add these by hand, *Program blocks → Add new block → Organization block*, in any language. A hand-made OB carries the header the CPU defines, such as `OB1_PREV_CYCLE`, and nothing imported can overwrite your own code.

| OB | Stage | Purpose |
|---|---|---|
| OB1 | 1 | exists already: it gets one call in step 7 |
| OB100 | 2 | start-up: keeps the previous boot's counters, stamps the new boot |
| OB80 | 2 | time error: count, then STOP |
| OB82 | 2 | diagnostic interrupt: count, then STOP |
| OB86 | 2 | rack or station failure: count, then STOP |

**Stage 1 adds no OB except the call in OB1.** On an S7-300 a missing OB80, OB82 or OB86 normally means STOP on that event, so an empty one would silently remove that reaction. Add them only with the stage 2 code that keeps the reaction.

**If your program already has one of these OBs,** keep it and add only the stage 2 counter network. Your own reaction to the fault stays as it is.

## 4. Import the code

1. *External source files → Add new external file →* `plc/read_probe.scl`.
2. Right-click it, *Generate blocks from source.*
3. Read the result in the *Info* tab. Any error: stop here.

## 5. Confirm what was created

| Where in the tree | Block | Number, set in step 6 |
|---|---|---|
| *PLC data types* | `typProbeStripe` | `UDT889` |
| *Program blocks* | `DB_ReadProbe` | `DB889` |
| *Program blocks* | `FC_ReadProbe` | `FC889` |

Open `DB_ReadProbe` after the compile in step 8 and compare the *Offset* column. **A read addresses bytes, so these offsets must match exactly:**

| Tag | Offset |
|---|---|
| `Magic` | 0.0 |
| `Scan` | 12.0 |
| `LifeMPI`, `EchoMPI` | 24.0, 25.0 |
| `LifePN`, `EchoPN` | 26.0, 27.0 |
| `InitDone` | 36.0 |
| `InitNext` | 38.0 |
| `Stripe[0]` | 40.0 |
| `WinStart` | 8232.0 |
| `Spare` | 8244.0 |

## 6. Block numbers and access

**Numbers.** On each block, *Properties → General → Numbering → Manual.* The `880` range is used because even crowded programs rarely reach it. Check it is free first.

- **The DB number matters:** the broker addresses `DB889` by number. If you pick another, use it in the route too.
- The FC and UDT numbers only have to be free.

**Reading from outside.** On an S7-300 there is less to set than on newer CPUs:

| Setting on an S7-1200/1500 | On an S7-300 |
|---|---|
| *Permit access with PUT/GET* | does not exist: the access is always on, subject to the protection level (step 2) |
| *Optimized block access* off | does not exist: every DB has absolute offsets |

Two things to check, in `DB_ReadProbe`'s *Properties → Attributes*:

- *Only store in load memory* is **off**: such a DB cannot be read at run time.
- *Data block write-protected in the device* is **off**: the test writes the `Echo` bytes.

## 7. Call it

**OB1, first network:** call `FC_ReadProbe` and wire `PrevCycle_ms` to `#OB1_PREV_CYCLE`.

## 8. Compile and download

1. *Compile → Hardware and software (rebuild all).* Check the offsets in step 5 now.
2. *Download to device,* over whichever path you reach the CPU on today. Read the list of actions before accepting it: look for blocks about to be deleted.
3. Start the CPU. The PN address is live from this download on: check it answers a ping.

## 9. Confirm it runs

A watch table on `DB_ReadProbe`:

| Tag | Expect |
|---|---|
| `Scan` | counting fast |
| `InitNext`, `InitDone` | 64 and TRUE within a second |
| `CycMin_ms`, `CycMax_ms`, `Cycles` | filled, updated each second |
| `LifeMPI`, `LifePN` | 1 and still, until a reader confirms them |

Compare the cycle times with step 2. The probe rewrites 64 stripes every scan on purpose. To see what that costs, set `StripesOff` and watch `CycMin_ms`.

## 10. The first read

Close any online monitoring first: on MPI it shares the bus and changes the timing.

```lot
DEFINE ROUTE S7ReadTest WITH TYPE SIEMENS_S7
    ADD S7_CONFIG
        WITH IP "192.0.2.131"
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
        WITH QUERY "{operation: READ, address: DB889.DBD0, data_type: DWORD, count: 2058}"
```

Publish anything to `s7test/cmd/read`. `s7test/res/read` answers with `{"success":true,…,"count":2058,"data":{"value_0":1347571522,…}}`: that first value is `16#50524F42`, the letters `PROB`, and it proves the addressing.

**Over MPI, through an Ethernet gateway,** use the gateway's IP. With an ACCON-NetLink in addressed mode, `SLOT` is the CPU's MPI address, not its real slot, and `CONNECTION_TYPE "OP"` is required.

| You see | It means |
|---|---|
| `Received error from PLC: Address out of range.` | wrong DB number, or a DB shorter than the read |
| `Siemens S7 PLC is not connected` | the route has no connection: check the address and port 102 |
| Route says added, but stays `Disconnected` | read the broker log; a tier limit is one cause, and each `ADD EVENT` counts as an action |

## 11. Stage 2: the metrics blocks

The same steps, with one more source file in step 4, and the OBs of step 3 added. The blocks and their numbers:

| Block | Purpose |
|---|---|
| `DB880` `DB_PerfMon` | header and ring of cycle records |
| `DB881` `DB_PerfDiag` | last fault, previous boot, diagnostics. Retentive |
| `DB882` `DB_PerfHealth` | health loop, one counter per path |
| `DB883` | the aggregator's instance DB |
| `UDT880`, `FC880`–`FC882`, `FB880` | the record type and the code |

Set the CPU's clock to UTC. A local clock has daylight-saving ambiguity.

**Removing the test,** when it is no longer needed: delete the OB1 call, `FC_ReadProbe`, `DB_ReadProbe` and `typProbeStripe`, then download.

## 12. The project archive

*Project → Archive*, with restorable data discarded, gives a `.zap` file in `tia/`. To use it, *Project → Retrieve*, then redo steps 2 and 6 for your CPU. It opens in the TIA version it was saved with or a newer one, as long as that version still supports the S7-300.
