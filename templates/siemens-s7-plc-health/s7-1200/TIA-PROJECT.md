# Add the kit to an S7-1200 project

**Written for:** an S7-1200 of the first generation, firmware V4.x (CPU 1211C to 1217C), in TIA Portal V20 or newer, added to a project that already runs a program. **Status: derived from the S7-1500 kit; the source compiles in TIA Portal V20 and V21. It runs on a simulated S7-1200 G2** (CPU 1214C AC/DC/Rly G2, firmware V4.1, in S7-PLCSIM Advanced V8.0 Upd1 with TIA Portal V21 Upd3), read whole every 10 seconds by a Coreflux 2.22 broker into the historian for hours, with no read error and no record missing; a STOP to RUN gave a new boot whose stamp equals the CPU's diagnostic buffer to the millisecond, the restart count one higher and the previous boot kept. **Not run yet on a first-generation CPU** (the one this guide is written for): the statements about it below are from Siemens' documentation until a bench confirms them, and the places most likely to need a correction are marked *to confirm*. The G2 has more memory and may name tags differently; what this guide says about retentive memory is for the first generation. **Needs:** STEP 7 Basic or Professional for your CPU's firmware, and no licence: the kit uses only PUT/GET and standard instructions.

The kit is built to go into **a program that already exists** without touching its code:

- **It brings its own program-cycle OB and its own startup OB.** An S7-1200 runs every program-cycle OB each cycle, in number order: OB1, then the others. The kit's OB880 runs after your program and measures from one call to the next, which is one full cycle. Your OB1 and OB100 stay as they are.
- **Each error OB your project has gets one call at its end** that counts the call and records its start information. Your own code and your OB's reaction stay as they are.
- **The kit writes only its own DBs.** The only value written from outside is one byte per reading path, the health loop's echo.

The addresses below are examples: use your own.

## What differs from the S7-1500 kit

The reader's side is the same: the three DBs have the same numbers, and every byte a read returns lies where the S7-1500 kit puts it. `DB_PerfDiag.CpuFamily` says `1200`.

| S7-1200 | The kit |
|---|---|
| No `RT_INFO`, so no communication load | `CommLoad_pct` is `-1` in every record and in `DB_PerfDiag`. The longest, shortest and last cycle in `DB_PerfDiag` come from the kit's own `RUNTIME` measurement |
| Error OBs: OB80, OB82, OB83, OB86 only. No OB121, no OB122 | `FC_PerfFault` takes those four; the slots of OB121 and OB122 in `DB_PerfDiag.Fault` stay empty |
| No STL and no classic (S7-300/400 style) start information | there is no `FC_PerfFaultClassic`; number 887 stays free |
| Little retentive memory, about 10 KB in all on most CPUs | `DB_PerfMon` (8.3 KB) may be left not retained: step 5 |

## The blocks at a glance

| Number | Block | Where it comes from | Called from |
|---|---|---|---|
| **OB880** | `OB_PerfMon`, program cycle | **you create it**, step 6 | the CPU, every cycle, after OB1 |
| **OB884** | `OB_PerfBoot`, startup | **you create it**, step 6 | the CPU, at each STOP to RUN |
| **880** | `FC_PerfMon` and `DB_PerfMon` | `plc/perf_kit.scl` | `OB_PerfMon` (OB880) |
| 881 | `FC_PerfDiag` and `DB_PerfDiag` | `plc/perf_kit.scl` | `FC_PerfMon` |
| 882 | `FC_PerfHealth` and `DB_PerfHealth` | `plc/perf_kit.scl` | `FC_PerfMon` |
| 883 | `FC_PerfStamp` | `plc/perf_kit.scl` | the other FCs |
| 884 | `FC_PerfBoot` | `plc/perf_kit.scl` | `OB_PerfBoot` (OB884) |
| 885 | `FC_PerfFault` | `plc/perf_kit.scl` | **OB80, OB82, OB83, OB86**, the ones your project has |

**The source file holds the work, the OBs only start it.** `plc/perf_kit.scl` generates the three types, the three DBs and the six FCs. No OB is in it: `OB_PerfMon` and `OB_PerfBoot` are two one-line blocks you create in TIA, where an OB gets its kind (program cycle, startup), and each only calls the FC of the same name and number.

**A DB has the same number as the FC that writes it, and an OB the number of the FC it calls.** The `880` range is used because even crowded programs rarely reach it, and it is the range of the S7-1500 kit, so one reader configuration serves both families. 886 and 887 are kept free.

- `FC_PerfMon` measures the cycle with `RUNTIME` and closes one record per second into `DB_PerfMon`, the header and the ring of cycle records. It runs the two below it.
- `FC_PerfDiag` reads the CPU's LEDs every 2 seconds into `DB_PerfDiag`, with the cycle figures. That DB also holds one slot per error OB, the previous boot's counters, and a copy of `DB_PerfMon`'s boot facts.
- `FC_PerfHealth` runs the health loop in `DB_PerfHealth`, one counter per reading path.
- `FC_PerfStamp` gives the CPU's clock, UTC, as two DINTs. `FC_PerfBoot` keeps the previous boot's counters and stamps the new boot. `FC_PerfFault` counts and records one error-OB call.
- *PLC data types* holds `typPerfRecord`, `typPerfHealthSlot` and `typPerfFaultSlot`, which have no number.

## 1. Start from the right project

**A download replaces what is in the CPU.** Blocks that are in the CPU but not in the project are deleted.

- **Work in the project the CPU runs.** If you do not have it, use *Online → Upload device as new station* first, and keep a copy.
- Check *Online & diagnostics → General* shows the firmware the project's CPU has. TIA must support that firmware.
- **Archive the project before you start** (*Project → Archive*). It is your way back.
- **Check the memory first.** *Online & diagnostics → Memory* shows what is free. The kit needs about 9 KB of work memory for its DBs, plus its code; a CPU 1211C has 50 KB in all (30 KB on older firmware). The retentive memory is the tighter one: step 5.

**A hardware download stops the CPU.** Steps 2 and 3 change the hardware configuration, so choose the moment.

## 2. Allow the reads

*Device view → the CPU → Properties.*

| Setting | Where | Value |
|---|---|---|
| PN address | *PROFINET interface [X1] → Ethernet addresses* | the CPU's address, e.g. `192.168.1.30` / `255.255.255.0` |
| PUT/GET | *Protection & Security → Connection mechanisms* | **Permit access with PUT/GET communication from remote partner**: on |
| Access level | *Protection & Security → Access level* | one that allows HMI access: *Full access* or *Read access*; with a password for full access, the reader still works |
| Connection resources | *Online & diagnostics → Connection information* | one free connection per reading path, on top of what is in use |

> **Important: PUT/GET is part of the hardware configuration.** A download of the program alone does not load it: download *Hardware configuration* too, which stops the CPU. Until then every read is refused, and the reader reports an error ending in `81 04`.

PUT/GET has no authentication: whoever reaches port 102 can read and write. Keep the reader on the machine network, never on an office or public one.

Note the *Cycle → Cycle monitoring time*, and the cycle times now in *Online & diagnostics → Cycle time*. You compare against them in step 9.

## 3. Set the clock

The kit stamps every record with the CPU's system time, which is UTC. **A CPU that was never set, or that lost power for longer than its buffer holds (about 20 days), stamps a date years in the past.**

- Once: *Online & diagnostics → Functions → Set time*, *Take from PG/PC*.
- To keep it right: *Properties → PROFINET interface [X1] → Time synchronization*, NTP, with a server the CPU can reach.

**Good engineering practice: synchronise every CPU from NTP, not only this one.**
- **A clock set by hand is right only at that moment.** A CPU's clock drifts, and a simulated CPU's clock stands still while its host sleeps.
- **With NTP, the stamps line up:** the kit's records, the diagnostic buffer, the broker and the historian, across every CPU of the plant. That is what lets you put an event in the buffer next to a record or an alert.
- **Use a time server on the machine network** that the CPU reaches: the plant's own, or an edge or gateway that serves NTP. Enter as many as you have. The addresses are your plant's: this guide gives none.
- **The CPU's time zone does not matter to the kit,** which stamps UTC.

Tried on the S7-1500 kit, set up the same way on a CPU 1511-1 PN and on a simulated CPU 1516-3 PN/DP in S7-PLCSIM Advanced V8.0 Upd1. The simulated CPU's clock, set by hand, was 27 s behind after an hour and a half. Once it was synchronised, records reached the broker 0.5 to 0.6 s after their stamp. **Not tried on an S7-1200 yet.**

## 4. Import the code

1. *External source files → Add new external file →* `plc/perf_kit.scl`.
2. Right-click it, *Generate blocks from source.* The file has Windows line endings (CRLF), and must keep them: an older TIA, V15.1 for one, reads the code of a file saved with Unix line endings (LF) as STL and fails on its first statement, while the DBs still compile. If you edit the file, use an editor that keeps CRLF.
3. Read the result in the *Info* tab. Any error: stop here, and **read the first error, at the top of the list.** The rest usually follow from it.

The source names no block numbers, so nothing it generates can overwrite a block of yours. A block of the same **name** would be replaced: check *Program blocks* has none starting with `FC_Perf`, `DB_Perf`, `OB_Perf` or `typPerf` first.

The source uses `LReal`, `DTL`, `HW_ANY`, `OB_ANY`, `RUNTIME`, `RD_SYS_T` and `LED`, all documented for the S7-1200 from firmware V4.0. An error naming one of them points to an older firmware.

## 5. Confirm the blocks and set their numbers

Check every FC, DB and type in *The blocks at a glance* was created. TIA gives each generated block the next free number, so set them by hand from that table: on each block, *Properties → General → Numbering → Manual.* Check the `880` range is free first.

**The DB numbers matter:** the broker addresses them by number. If you pick others, use them in the route too.

Then each DB's *Properties → Attributes*:

| Attribute | `DB_PerfMon` | `DB_PerfDiag` | `DB_PerfHealth` | Why |
|---|---|---|---|---|
| *Optimized block access* | **off** | **off** | **off** | a read addresses bytes; the source already sets it, check it held |
| *Only store in load memory* | off | off | off | such a DB cannot be read at run time |
| *Data block write-protected in the device* | off | off | off | `DB_PerfHealth` takes the echo bytes, and the CPU writes all three |
| *Retain* (in the DB editor, for the whole block) | **on if there is room, else off** | **on** | on | the source creates all three retained (it has no `NON_RETAIN`); `DB_PerfMon`: see below |

### Retentive memory decides `DB_PerfMon`

A DB without optimized access is retained as a whole or not at all. `DB_PerfDiag` takes 362 bytes and is always retained: it holds the fault counters, the previous boot, and a copy of `DB_PerfMon`'s boot stamp, restart count and last record number. `DB_PerfMon` takes 8,322 bytes.

**Read the CPU's figure in *Program info → Resources → Retentive memory*** (about 10 KB in all on an S7-1200 with firmware V4.x; newer firmware and the newer S7-1200 generation have more), subtract what your program retains, and choose:

| `DB_PerfMon` | Costs | After a STOP to RUN or a power loss |
|---|---|---|
| **Retain on** | 8.3 KB of retentive memory | everything survives: the ring still holds the last two minutes before the stop, for the reader to collect |
| **Retain off** | nothing | the ring starts empty, so the records between the reader's last read and the stop are lost. The boot stamp, the restart count, the previous boot and all fault counters survive: `FC_PerfBoot` takes them from `DB_PerfDiag` |

With *Retain off*, values you set in `DB_PerfMon` at run time (the histogram edges, step 9) are lost at the next start as well: set them as **start values**.

## 6. Create the kit's two OBs

> **Important: the two OBs are of different types. `OB_PerfMon` is a *Program cycle* OB, `OB_PerfBoot` is a *Startup* OB.** The type is chosen in the *Add new block* dialog and cannot be changed afterwards: a wrong one is deleted and created again. If `OB_PerfBoot` is created as *Program cycle*, the kit still compiles and runs, but it starts a new boot every cycle: `DB_PerfMon.RestartCount` runs up to 32767, `Seq` never climbs and the ring keeps no history. After correcting it, set `DB_PerfMon.RestartCount` and `DB_PerfDiag.KeepRestartCount` back to 0 in a watch table.

*Program blocks → Add new block → Organization block*, language **SCL**, number *manual*. Each holds one line:

| Type | Name | Number | The line |
|---|---|---|---|
| *Program cycle* | `OB_PerfMon` | **880** | `"FC_PerfMon"(CpuHwId := "Local~Common");` |
| *Startup* | `OB_PerfBoot` | **884** | `"FC_PerfBoot"();` |

Put a comment above each line saying why it is there, for whoever opens the OB later: `// Performance Monitor: the kit's cycle measurement, records, health loop and diagnostics` and `// Performance Boot Log: keeps the previous boot's counters, stamps this boot`.

**The CPU's hardware identifier:** *PLC tags → Show all tags → System constants*, the constant of the CPU itself, of type `Hw_SubModule`, usually named `Local~Common`. The same number is under *Device view → the CPU → Properties → System constants*. If yours has another name, use it in the OB880 line. *To confirm:* that `LED` accepts this identifier on an S7-1200; a wrong one shows as a negative value in `DB_PerfDiag.Led` (step 9), and nothing else in the kit depends on it.

If the project already has a program-cycle OB numbered above 880, the kit then runs before that one, not last. Nothing breaks: the cycle is still measured from call to call.

## 7. One call in each error OB

**The CPU runs these OBs itself, on their event. Never call one.** Each error OB **your project already has** gets the kit's call **at its end**. Your own code and the OB's reaction stay as they are. An S7-1200 has four: OB80 (time error), OB82 (diagnostic error), OB83 (pull or plug) and OB86 (rack or station failure).

| Language of the OB | The call |
|---|---|
| SCL | paste the OB's call from 7.1 at the end |
| LAD or FBD | add a network at the end, *Insert SCL network*, and paste the same call (firmware V4.2 or newer). Or, as a box: drag `FC_PerfFault` in and fill all eight inputs from the table in 7.2 |

**Every input must be given a value, in every language, or the call does not compile.** An FC keeps no values of its own, so TIA accepts no open input. The calls below are complete: copy them whole. Use one call per OB: two calls in one OB count every event twice.

Each call keeps the calls since the boot, the UTC stamp of the newest call, and:

| OB | Kept |
|---|---|
| OB80 | `Fault_ID`, `Csg_OBnr`, `Csg_Prio` |
| OB82 | `IO_State`, `LADDR`, `Channel` |
| OB83 | `Event_Class`, `Fault_ID`, `LADDR` |
| OB86 | `Event_Class`, `Fault_ID`, `LADDR` |

### 7.1 The SCL calls

```
// OB80, time error. Performance Diagnostic: count this call and keep its start information
"FC_PerfFault"(OB_Nr := 80, EvClass := 0, FaultId := #Fault_ID, Laddr := 0, IoState := 0, Channel := 0,
               CsgOB := #Csg_OBnr, CsgPrio := #Csg_Prio);

// OB82, diagnostic error. Performance Diagnostic: count this call and keep its start information
"FC_PerfFault"(OB_Nr := 82, EvClass := 0, FaultId := 0, Laddr := #LADDR, IoState := #IO_State, Channel := #Channel,
               CsgOB := 0, CsgPrio := 0);

// OB83, pull or plug. Performance Diagnostic: count this call and keep its start information
"FC_PerfFault"(OB_Nr := 83, EvClass := #Event_Class, FaultId := #Fault_ID, Laddr := #LADDR, IoState := 0, Channel := 0,
               CsgOB := 0, CsgPrio := 0);

// OB86, rack or station failure. Performance Diagnostic: count this call and keep its start information
"FC_PerfFault"(OB_Nr := 86, EvClass := #Event_Class, FaultId := #Fault_ID, Laddr := #LADDR, IoState := 0, Channel := 0,
               CsgOB := 0, CsgPrio := 0);
```

*To confirm:* the names of the start-information tags. Open the OB's interface, section *Input*: if TIA V20 names a tag differently for your firmware, wire the tag of that meaning. TIA does not tell upper from lower case in a name.

### 7.2 The inputs, for a LAD or FBD box

Bold is the OB's own tag, everything else the constant `0`:

| Input | OB80 | OB82 | OB83 | OB86 |
|---|---|---|---|---|
| `OB_Nr` | `80` | `82` | `83` | `86` |
| `EvClass` | `0` | `0` | **`#Event_Class`** | **`#Event_Class`** |
| `FaultId` | **`#Fault_ID`** | `0` | **`#Fault_ID`** | **`#Fault_ID`** |
| `Laddr` | `0` | **`#LADDR`** | **`#LADDR`** | **`#LADDR`** |
| `IoState` | `0` | **`#IO_State`** | `0` | `0` |
| `Channel` | `0` | **`#Channel`** | `0` | `0` |
| `CsgOB` | **`#Csg_OBnr`** | `0` | `0` | `0` |
| `CsgPrio` | **`#Csg_Prio`** | `0` | `0` | `0` |

`Laddr` is `HW_ANY`, so it accepts the hardware type each OB hands over, and no conversion box is needed.

### 7.3 An error OB your project does not have

The kit works without it, but that OB's events are then not counted. To count them, create the OB (*Add new block → Organization block*, SCL) with its call from 7.1.

| OB | Without the OB, the S7-1200… | A new OB |
|---|---|---|
| OB82, OB83, OB86 | stays in RUN. Pulling a module of the central rack stops the CPU with or without OB83 | changes nothing: the call only |
| OB80, time error | **not settled**: Siemens' system manual says in one place that the CPU goes to STOP when the cycle monitoring time is exceeded and no OB80 exists, and in another that the first overrun is ignored | **do not add an OB80 for the kit alone** until this is measured on your firmware: an OB80 that exists keeps the CPU in RUN at the first overrun, which may change what the machine does today |

Exceeding twice the cycle monitoring time stops the CPU whatever OB80 does. Agree any change of reaction with whoever owns the machine's safety concept.

A programming error and an I/O access error call no OB on an S7-1200: the CPU writes a diagnostic-buffer entry and stays in RUN, and the kit cannot count them.

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
   | `DB_PerfDiag` | `CpuFamily` | 4.0 |
   | `DB_PerfDiag` | `DiagSeq` | 8.0 |
   | `DB_PerfDiag` | `PrevBootDate` | 24.0 |
   | `DB_PerfDiag` | `Fault` | 60.0 |
   | `DB_PerfDiag` | `Led` | 180.0 |
   | `DB_PerfDiag` | `CommLoad_pct` | 208.0 |
   | `DB_PerfDiag` | `IM0` | 260.0 |
   | `DB_PerfDiag` | `Step` | 324.0 |
   | `DB_PerfDiag` | `KeepBootDate` | 348.0 |
   | `DB_PerfHealth` | `Reserve.Life` | 8.0 |
   | `DB_PerfHealth` | `PN.Life` | 26.0 |
   | `DB_PerfHealth` | `PN.Echo` | 27.0 |

3. *Download to device.* **Plan it with the CPU in STOP:** an S7-1200 loads only some changes in RUN, and the hardware changes of step 2 need a STOP in any case. Read the list of actions before accepting it: look for blocks about to be deleted, and for *reinitialize*, which resets your DBs' actual values.
4. Start the CPU.

## 9. Confirm it runs

A watch table:

| Tag | Expect |
|---|---|
| `DB_PerfMon.Seq`, `WriteIdx` | `Seq` up by 1 each second, `WriteIdx` following, 0 to 119 |
| `DB_PerfMon.BootDate`, `BootTime`, `RestartCount` | today, UTC, and 1 or more after a STOP to RUN. **Still 0 means OB884 has no call:** step 6 |
| `DB_PerfMon.Ring[0].CycMax_ms`, `Cycles` | filled |
| `DB_PerfMon.Ring[0].CommLoad_pct` | `-1`: an S7-1200 does not measure it |
| `DB_PerfDiag.CpuFamily` | 1200 |
| `DB_PerfDiag.Step` | 1 within a second of a start |
| `DB_PerfDiag.Led[0..2]` | RUN/STOP, ERROR, MAINT: 1 off, 2 or 3 on, 4 or 5 flashing. Negative: `LED` refused the hardware identifier, step 6 |
| `DB_PerfDiag.CycLongest_ms`, `CycShortest_ms`, `CycLast_ms` | filled after the first second |
| `DB_PerfDiag.KeepSeq`, `KeepRestartCount` | the same as `DB_PerfMon.Seq` and `RestartCount` |
| `DB_PerfDiag.Fault[i].Count` | rising for each error OB that is being called |
| `DB_PerfHealth.PN.Life` | 1 and still, until a reader confirms it |

Then a STOP to RUN: `RestartCount` is one higher, `DB_PerfDiag.PrevBootDate` and `PrevBootTime` hold the boot before, `PrevLastSeq` its last record number. **With `DB_PerfMon` not retained this is the test that the copy in `DB_PerfDiag` works:** `RestartCount` must not fall back to 1.

Compare the cycle times with step 2.

**In STOP the kit's DBs keep their last values.** The program writes them, and the program does not run in STOP: `Seq` stands still, and `DB_PerfDiag.Led` still says RUN. A reader must take the CPU's state from `Seq` (no new record while the reads still answer means the CPU is not scanning) and never from the stored LEDs. The DBs stay readable in STOP.

**Set the histogram once, before comparing anything:** `DB_PerfMon.Edges_ms` holds the buckets' upper edges. The default is `2 | 5 | 10 | 20 | 40 | 60 | 100` ms, to separate an idle CPU from one running a real program. With `DB_PerfMon` not retained, set them as start values (step 5).

## 10. The first read

```lot
DEFINE ROUTE S7ReadTest WITH TYPE SIEMENS_S7
    ADD S7_CONFIG
        WITH IP "192.168.1.30"
        WITH CPU_TYPE "S71200"
        WITH RACK 0
        WITH SLOT 1
        WITH PORT 102
        WITH CONNECTION_TYPE "OP"
        WITH READ_TIMEOUT 30000
        WITH WRITE_TIMEOUT 30000
    ADD EVENT ReadAll
        WITH SOURCE_TOPIC "s7test/cmd/read"
        WITH DESTINATION_TOPIC "s7test/res/read"
        WITH QUERY "{operation: READ, address: DB880.DBD0, data_type: DWORD, count: 2058}"
```

Publish anything to `s7test/cmd/read`. `s7test/res/read` answers with `{"success":true,…,"count":2058,"data":{"value_0":131140,…}}`: that first value is `16#00020044`, `LayoutVersion` 2 and `RecordSize` 68, and it proves the addressing. `DB881.DBD0` with `count: 81` reads `DB_PerfDiag`; its first value is `16#00020144`, layout 2 and 324 bytes, and its second `78643200`, which is `16#04B00000`: family 1200. Remove the route afterwards.

| You see | It means |
|---|---|
| `Received error from PLC: Address out of range.` | wrong DB number, a DB shorter than the read, or optimized access still on |
| An error about access or protection | PUT/GET is off, or the access level does not allow it: step 2 |
| `Siemens S7 PLC is not connected` | the route has no connection: check the address, port 102, and `SLOT 1` |
| Route says added, but stays `Disconnected` | read the broker log; a tier limit is one cause, and each `ADD EVENT` counts as an action |

**The reader's decoder must know the family.** A decoder written for the S7-1500 kit checks `CpuFamily` and refuses `1200` until it is told that this family has the same layout. What it must treat differently: `CommLoad_pct` is `-1` (not available), and the slots of OB121 and OB122 are always empty.

## 11. To remove the kit

Delete the `FC_PerfFault` network from each error OB, then OB880, OB884, every `FC_Perf`, `DB_Perf` and `typPerf` block, and download. Undo step 2's PUT/GET if nothing else uses it.
