# Add the kit to an S7-1500 project

**Written for:** CPU 1511-1 PN, `6ES7 511-1AK02-0AB0`, firmware V2.6, in TIA Portal V15.1, added to a project that already runs a program. The source generates without errors in TIA V15.1 and runs on the CPU; `FC_PerfFaultClassic`, added since for error OBs with classic start information (step 7), has not been compiled yet. **Needs:** STEP 7 Professional or Basic for your CPU's firmware, and no licence: the kit uses only PUT/GET and standard instructions.

The kit is built to go into **a program that already exists** without touching its code:

- **It brings its own program-cycle OB and its own startup OB.** An S7-1500 runs every program-cycle OB each cycle, in number order: OB1, then the others. The kit's OB880 runs after your program and measures from one call to the next, which is one full cycle. Your OB1 and OB100 stay as they are.
- **Each error OB your project has gets one call at its end** that counts the call and records its start information. Your own code and your OB's reaction stay as they are.
- **The kit writes only its own DBs.** The only value written from outside is one byte per reading path, the health loop's echo.

The addresses below are examples: use your own.

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
| 885 | `FC_PerfFault` | `plc/perf_kit.scl` | **OB80, OB82, OB83, OB86, OB121, OB122** with S7-1500 start information, the ones your project has |
| 887 | `FC_PerfFaultClassic` | `plc/perf_kit.scl` | the same OBs where they have **classic** (S7-300/400 style) start information, step 7 |

**The source file holds the work, the OBs only start it.** `plc/perf_kit.scl` generates the three types, the three DBs and the seven FCs. No OB is in it: `OB_PerfMon` and `OB_PerfBoot` are two one-line blocks you create in TIA, where an OB gets its kind (program cycle, startup), and each only calls the FC of the same name and number. So `OB_PerfBoot` (OB884) is the CPU's entry at startup, and `FC_PerfBoot` (FC884) is the code it runs.

**A DB has the same number as the FC that writes it, and an OB the number of the FC it calls.** The `880` range is used because even crowded programs rarely reach it. 886 is kept free for a later block.

- `FC_PerfMon` measures the cycle with `RUNTIME` and closes one record per second into `DB_PerfMon`, the header and the ring of cycle records, with the communication load from `RT_INFO`. It runs the two below it.
- `FC_PerfDiag` reads the CPU's LEDs and `RT_INFO`'s cycle figures every 2 seconds into `DB_PerfDiag`. The CPU's identity is not read by the program: `Get_IM_Data` is not available in TIA V15.1 for this firmware, so the reader takes it from its configuration. That DB also holds one slot per error OB and the previous boot's counters.
- `FC_PerfHealth` runs the health loop in `DB_PerfHealth`, one counter per reading path.
- `FC_PerfStamp` gives the CPU's clock, UTC, as two DINTs. `FC_PerfBoot` keeps the previous boot's counters and stamps the new boot. `FC_PerfFault` counts and records one error-OB call; `FC_PerfFaultClassic` does the same for an OB with classic start information, into the same slot, marked as such.
- *PLC data types* holds `typPerfRecord`, `typPerfHealthSlot` and `typPerfFaultSlot`, which have no number.

## 1. Start from the right project

**A download replaces what is in the CPU.** Blocks that are in the CPU but not in the project are deleted.

- **Work in the project the CPU runs.** If you do not have it, use *Online → Upload device as new station* first, and keep a copy.
- Check *Online & diagnostics → General* shows the firmware the project's CPU has. TIA must support that firmware.
- **Archive the project before you start** (*Project → Archive*). It is your way back.

**A hardware download stops the CPU.** Steps 2 and 3 change the hardware configuration, so choose the moment.

## 2. Allow the reads

*Device view → the CPU → Properties.*

| Setting | Where | Value |
|---|---|---|
| PN address | *PROFINET interface [X1] → Ethernet addresses* | the CPU's address, e.g. `192.168.1.20` / `255.255.255.0` |
| PUT/GET | *Protection & Security → Connection mechanisms* | **Permit access with PUT/GET communication from remote partner**: on |
| Access level | *Protection & Security → Access level* | one that allows HMI access: *Full access* or *Read access*; with a password for full access, the reader still works |
| Connection resources | *Online & diagnostics → Connection information* | one free connection per reading path, on top of what is in use |

> **Important: PUT/GET is part of the hardware configuration.** A download of the program alone, as done while the CPU runs, does not load it: download *Hardware configuration* too, which stops the CPU. Until then every read is refused, and the reader reports an error ending in `81 04`.

PUT/GET has no authentication: whoever reaches port 102 can read and write. Keep the reader on the machine network, never on an office or public one.

Note the *Cycle → Maximum cycle time*, and the cycle times now in *Online & diagnostics → Cycle time*. You compare against them in step 9.

## 3. Set the clock

The kit stamps every record with the CPU's system time, which is UTC. **A CPU that was never set counts from 2012.**

- Once: *Online & diagnostics → Functions → Set time*, *Take from PG/PC*.
- To keep it right: *Properties → Time of day → Time synchronization*, NTP, with a server the CPU can reach.

## 4. Import the code

1. *External source files → Add new external file →* `plc/perf_kit.scl`.
2. Right-click it, *Generate blocks from source.* The file has Windows line endings (CRLF), and must keep them: an older TIA, V15.1 for one, reads the code of a file saved with Unix line endings (LF) as STL and fails on its first statement, while the DBs still compile. If you edit the file, use an editor that keeps CRLF.
3. Read the result in the *Info* tab. Any error: stop here, and **read the first error, at the top of the list.** The rest usually follow from it.

The source names no block numbers, so nothing it generates can overwrite a block of yours. A block of the same **name** would be replaced: check *Program blocks* has none starting with `FC_Perf`, `DB_Perf`, `OB_Perf` or `typPerf` first.

**Updating a CPU that already runs the kit:** generate the source again; the kit's own blocks are replaced, keep their numbers (step 5, a new FC gets the next free number). The DBs and types in the source keep their layout, so the reader needs nothing new. Whether TIA still wants to *reinitialize* a regenerated DB has not been seen yet: read the download's list of actions (step 8). Reinitializing the kit's DBs loses only the kit's own history and counters.

## 5. Confirm the blocks and set their numbers

Check every FC, DB and type in *The blocks at a glance* was created. TIA gives each generated block the next free number, so set them by hand from that table: on each block, *Properties → General → Numbering → Manual.* Check the `880` range is free first.

**The DB numbers matter:** the broker addresses them by number. If you pick others, use them in the route too.

Then each DB's *Properties → Attributes*:

| Attribute | `DB_PerfMon` | `DB_PerfDiag` | `DB_PerfHealth` | Why |
|---|---|---|---|---|
| *Optimized block access* | **off** | **off** | **off** | a read addresses bytes; the source already sets it, check it held |
| *Only store in load memory* | off | off | off | such a DB cannot be read at run time |
| *Data block write-protected in the device* | off | off | off | `DB_PerfHealth` takes the echo bytes, and the CPU writes all three |
| *Retain* (in the DB editor, for the whole block) | **on** | **on** | off | the ring, the previous boot and the fault counters must survive a restart and a power loss |

Retentive memory: the two retained DBs take about 8.7 KB. Check *Program info → Resources → Retentive memory* still has room after the compile.

## 6. Create the kit's two OBs

> **Important: the two OBs are of different types. `OB_PerfMon` is a *Program cycle* OB, `OB_PerfBoot` is a *Startup* OB.** The type is chosen in the *Add new block* dialog and cannot be changed afterwards: a wrong one is deleted and created again. If `OB_PerfBoot` is created as *Program cycle*, the kit still compiles and runs, but it starts a new boot every cycle: `DB_PerfMon.RestartCount` runs up to 32767, `Seq` never climbs and the ring keeps no history. After correcting it, set `DB_PerfMon.RestartCount` back to 0 in a watch table.

*Program blocks → Add new block → Organization block*, language **SCL**, number *manual*. Each holds one line:

| Type | Name | Number | The line |
|---|---|---|---|
| *Program cycle* | `OB_PerfMon` | **880** | `"FC_PerfMon"(CpuHwId := "Local~Common");` |
| *Startup* | `OB_PerfBoot` | **884** | `"FC_PerfBoot"();` |

Put a comment above each line saying why it is there, for whoever opens the OB later: `// Performance Monitor: the kit's cycle measurement, records, health loop and diagnostics` and `// Performance Boot Log: keeps the previous boot's counters, stamps this boot`.

**The CPU's hardware identifier:** *PLC tags → Show all tags → System constants*, the constant of the CPU itself, of type `Hw_SubModule` or `Hw_Io`, usually named `Local~Common`. The same number is under *Device view → the CPU → Properties → System constants*. If yours has another name, use it in the OB880 line.

If the project already has a program-cycle OB numbered above 880, the kit then runs before that one, not last. Nothing breaks: the cycle is still measured from call to call.

## 7. One call in each error OB

**The CPU runs these OBs itself, on their event. Never call one.** Each error OB **your project already has** gets the kit's call **at its end**. Your own code and the OB's reaction stay as they are.

### 7.1 Review the OBs first

> **Important: look at every error OB before adding anything.** How an error OB was made is its author's decision, and it can differ from OB to OB in one project. Two things decide which call fits, and a call of the wrong form does not compile.

Open OB80, OB82, OB83, OB86, OB121 and OB122, as far as the project has them, and note for each:

| Look at | What you find | Meaning |
|---|---|---|
| The block interface | an **Input** section with `Fault_ID`, `LADDR`, `Event_Class`, `BlockNr`… | **S7-1500 start information**: an OB created in TIA for an S7-1500 |
|  | a **Temp** section with `OB82_EV_CLASS`, `OB82_FLT_ID`, `OB82_MDL_ADDR`… | **classic start information**: an OB that came from an S7-300/400 project, usually by migration |
| The language, in the block's *Properties → General* | LAD, FBD, SCL or STL | which form of the call the OB accepts |

Then take the call from this table:

| Start information | Language of the OB | The function | The call |
|---|---|---|---|
| S7-1500 | SCL | `FC_PerfFault` | paste the OB's SCL call from 7.2 at the end |
| S7-1500 | LAD or FBD | `FC_PerfFault` | add a network at the end, *Insert SCL network*, and paste the same SCL call. Or, as a box: drag `FC_PerfFault` in and fill all eleven inputs from the table in 7.5 |
| classic | STL | `FC_PerfFaultClassic` | add a network at the end and paste the OB's STL call from 7.3. An STL OB accepts neither a LAD nor an SCL network |
| classic | LAD, FBD or SCL | `FC_PerfFaultClassic` | an SCL network at the end with the OB's SCL call from 7.4 |

**One project can need both.** On the bench, a project migrated from an S7-300, OB80, OB83 and OB121 had S7-1500 start information and OB82, OB86 and OB122 the classic one. Both functions write the same slot of `DB_PerfDiag`, each in its own form, and the reader tells them apart by itself. Use one call per OB: two calls in one OB count every event twice.

**Starting a new project, or adding an error OB the project lacks:** create it in TIA for the S7-1500, in **SCL** (or LAD with an SCL network), and paste the call from 7.2. Do not convert a classic OB: leave the author's OB as it is and use the classic call.

**Every input must be given a value, in every language, or the call does not compile.** An FC keeps no values of its own, so TIA accepts no open input. The calls below are complete: copy them whole. A literal `0` or `16#0` is accepted on every input, in LAD, SCL and STL alike.

### What each form records

Both forms keep the calls since the boot and the UTC stamp of the newest call. The OB number is the slot's, so neither keeps it; nor the priority, nor the OB's own `DATE_TIME`.

| OB | S7-1500 start information (`FC_PerfFault`) | Classic start information (`FC_PerfFaultClassic`) | Classic, not kept (no room) |
|---|---|---|---|
| OB80 | `Fault_ID`, `Csg_OBnr`, `Csg_Prio` | `FLT_ID`; `ERROR_INFO` (with `16#01`, the cycle time in ms); the start event that caused it (`ERR_EV_CLASS`, `ERR_EV_NUM`); the OB and its priority (`OB_NUM`, `OB_PRIORITY`) | – |
| OB82 | `IO_state`, `LADDR`, `Channel` | `EV_CLASS` (incoming or outgoing), `FLT_ID`; the module address and whether it is an input or an output module (`MDL_ADDR`, `IO_FLAG`); every fault bit of bytes 8, 10 and 11 and the module class of byte 9 | – |
| OB83 | `Event_Class`, `Fault_ID`, `LADDR` | `EV_CLASS`, `FLT_ID`; the module address, input or output (`MDL_ADDR`, `MDL_TD`); `RACK_NUM` (rack, DP or PROFINET station); `MDL_TYPE` | `OB83_RESERVED_1` (module or submodule) |
| OB86 | `Event_Class`, `Fault_ID`, `LADDR` | `EV_CLASS`, `FLT_ID`; `MDL_ADDR` (the IM, DP master or IO controller); `RACKS_FLTD` (which rack, or which DP or PROFINET station) | – |
| OB121 | `Fault_ID`, `BlockNr`, `BlockType`, `Area` | `SW_FLT`; the block (`BLK_TYPE`, `BLK_NUM`); the memory area and access type (`RESERVED_1`); `FLT_REG` (the wrong address, number or register) | `PRG_ADDR` |
| OB122 | `Fault_ID`, `BlockNr`, `BlockType`, `Area` | `SW_FLT` (reading or writing); the block (`BLK_TYPE`, `BLK_NUM`); the memory area and access type (`MEM_AREA`); **the failing address (`MEM_ADDR`)** | `PRG_ADDR` |

**Measured and from documentation.** The classic interfaces of OB82, OB86 and OB122 are as a migrated project on a CPU 1511 with firmware V2.6 declares them. Classic OB80, OB83 and OB121 were not in that project: their tags are taken from Siemens' S7-300/400 manual (*System Software for S7-300/400, System and Standard Functions*, Volume 1/2, chapter 1). The meaning of each classic code is from that manual too; what values an S7-1500 actually puts in a classic OB's start information is still to be seen on a CPU.

### 7.2 S7-1500 start information: the SCL calls

```
// OB80, time error. Performance Diagnostic: count this call and keep its start information
"FC_PerfFault"(OB_Nr := 80, EvClass := 0, FaultId := #Fault_ID, Laddr := 0, IoState := 0, Channel := 0,
               CsgOB := #Csg_OBnr, CsgPrio := #Csg_Prio, BlockNr := 0, BlockType := 0, Area := 0);

// OB82, diagnostic error. Performance Diagnostic: count this call and keep its start information
"FC_PerfFault"(OB_Nr := 82, EvClass := 0, FaultId := 0, Laddr := #LADDR, IoState := #IO_state, Channel := #Channel,
               CsgOB := 0, CsgPrio := 0, BlockNr := 0, BlockType := 0, Area := 0);

// OB83, pull or plug. Performance Diagnostic: count this call and keep its start information
"FC_PerfFault"(OB_Nr := 83, EvClass := #Event_Class, FaultId := #Fault_ID, Laddr := #LADDR, IoState := 0, Channel := 0,
               CsgOB := 0, CsgPrio := 0, BlockNr := 0, BlockType := 0, Area := 0);

// OB86, rack or station failure. Performance Diagnostic: count this call and keep its start information
"FC_PerfFault"(OB_Nr := 86, EvClass := #Event_Class, FaultId := #Fault_ID, Laddr := #LADDR, IoState := 0, Channel := 0,
               CsgOB := 0, CsgPrio := 0, BlockNr := 0, BlockType := 0, Area := 0);

// OB121, programming error. Performance Diagnostic: count this call and keep its start information
"FC_PerfFault"(OB_Nr := 121, EvClass := 0, FaultId := #Fault_ID, Laddr := 0, IoState := 0, Channel := 0,
               CsgOB := 0, CsgPrio := 0, BlockNr := #BlockNr, BlockType := #BlockType, Area := #Area);

// OB122, I/O access error. Performance Diagnostic: count this call and keep its start information
"FC_PerfFault"(OB_Nr := 122, EvClass := 0, FaultId := #Fault_ID, Laddr := 0, IoState := 0, Channel := 0,
               CsgOB := 0, CsgPrio := 0, BlockNr := #BlockNr, BlockType := #BlockType, Area := #Area);
```

### 7.3 Classic start information, STL: the calls

`FC_PerfFaultClassic` takes the classic start information **as it lies in the OB's Temp section**: each input is named after its byte and has the type of the tag found there, so the call needs no conversion and no tag of your own. `ModAddr` is the module address where the OB declares it as an `Int` (as a migration does), `Word6` where it is a `Word`; give the other one `0`. An OB that names a tag differently in your version: wire the tag at that byte.

```
// OB80, time error. Performance Diagnostic: count this call and keep its start information
      CALL "FC_PerfFaultClassic"
         OB_Nr      := 80
         EvClass    := #OB80_EV_CLASS
         FaultId    := #OB80_FLT_ID
         Byte4      := 16#0
         Byte5      := 16#0
         ModAddr    := 0
         Word6      := #OB80_ERROR_INFO
         Word8      := %LW8
         Word10     := %LW10

// OB82, diagnostic interrupt. Performance Diagnostic: count this call and keep its start information
      CALL "FC_PerfFaultClassic"
         OB_Nr      := 82
         EvClass    := #OB82_EV_CLASS
         FaultId    := #OB82_FLT_ID
         Byte4      := 16#0
         Byte5      := #OB82_IO_FLAG
         ModAddr    := #OB82_MDL_ADDR
         Word6      := 16#0
         Word8      := %LW8
         Word10     := %LW10

// OB83, insert or remove. Performance Diagnostic: count this call and keep its start information
      CALL "FC_PerfFaultClassic"
         OB_Nr      := 83
         EvClass    := #OB83_EV_CLASS
         FaultId    := #OB83_FLT_ID
         Byte4      := 16#0
         Byte5      := #OB83_MDL_TD
         ModAddr    := 0
         Word6      := #OB83_MDL_ADDR
         Word8      := #OB83_RACK_NUM
         Word10     := #OB83_MDL_TYPE

// OB86, rack or station failure. Performance Diagnostic: count this call and keep its start information
      CALL "FC_PerfFaultClassic"
         OB_Nr      := 86
         EvClass    := #OB86_EV_CLASS
         FaultId    := #OB86_FLT_ID
         Byte4      := 16#0
         Byte5      := 16#0
         ModAddr    := #OB86_MDL_ADDR
         Word6      := 16#0
         Word8      := %LW8
         Word10     := %LW10

// OB121, programming error. Performance Diagnostic: count this call and keep its start information
      CALL "FC_PerfFaultClassic"
         OB_Nr      := 121
         EvClass    := #OB121_EV_CLASS
         FaultId    := #OB121_SW_FLT
         Byte4      := #OB121_BLK_TYPE
         Byte5      := #OB121_RESERVED_1
         ModAddr    := 0
         Word6      := #OB121_FLT_REG
         Word8      := #OB121_BLK_NUM
         Word10     := 16#0

// OB122, I/O access error. Performance Diagnostic: count this call and keep its start information
      CALL "FC_PerfFaultClassic"
         OB_Nr      := 122
         EvClass    := #OB122_EV_CLASS
         FaultId    := #OB122_SW_FLT
         Byte4      := #OB122_BLK_TYPE
         Byte5      := #OB122_MEM_AREA
         ModAddr    := 0
         Word6      := #OB122_MEM_ADDR
         Word8      := #OB122_BLK_NUM
         Word10     := 16#0
```

> **Important: `%LW8` and `%LW10` are the bytes 8 to 11 of the OB's own Temp section, addressed directly.** In OB82 those bytes are 24 single `Bool` tags plus the module type, in OB86 an `Array[0..31] of Bool`, and in OB80 four `Byte` tags: none of them is one `Word` tag, so the call names the bytes by address. An OB with classic start information has standard access, where TIA allows such an address. **This has not been compiled yet.** If TIA refuses `%LW8`, put `16#0` on `Word8` and `Word10`: the OB is still counted, with its event class, fault code and module address, and only those bytes are lost (OB82's fault bits, OB86's station, OB80's start event and OB). **TIA compiles these calls with a warning per address, "The address is not occupied by a tag": that is expected, the block is compiled** (measured in TIA V15.1 on OB82 and OB86).

`Word10` gets `16#0` in OB121 and OB122: their `PRG_ADDR` (the position in the block's code) has no room in the slot. OB122 is the OB a program with unwired I/O calls thousands of times a second, and its call passes only tags, so it costs no more than the S7-1500 call.

### 7.4 Classic start information in a LAD, FBD or SCL OB: the SCL calls

An SCL network at the end of the OB, with the same inputs. An SCL network cannot name the bytes 8 to 11 of OB80, OB82 and OB86 as one tag, so those calls give `16#0` on `Word8` and `Word10`, and record what the STL call does without the bytes the note above lists.

```
// OB80, time error. Performance Diagnostic: count this call and keep its start information
"FC_PerfFaultClassic"(OB_Nr := 80, EvClass := #OB80_EV_CLASS, FaultId := #OB80_FLT_ID, Byte4 := 16#0, Byte5 := 16#0,
                      ModAddr := 0, Word6 := #OB80_ERROR_INFO, Word8 := 16#0, Word10 := 16#0);

// OB82, diagnostic interrupt. Performance Diagnostic: count this call and keep its start information
"FC_PerfFaultClassic"(OB_Nr := 82, EvClass := #OB82_EV_CLASS, FaultId := #OB82_FLT_ID, Byte4 := 16#0, Byte5 := #OB82_IO_FLAG,
                      ModAddr := #OB82_MDL_ADDR, Word6 := 16#0, Word8 := 16#0, Word10 := 16#0);

// OB83, insert or remove. Performance Diagnostic: count this call and keep its start information
"FC_PerfFaultClassic"(OB_Nr := 83, EvClass := #OB83_EV_CLASS, FaultId := #OB83_FLT_ID, Byte4 := 16#0, Byte5 := #OB83_MDL_TD,
                      ModAddr := 0, Word6 := #OB83_MDL_ADDR, Word8 := #OB83_RACK_NUM, Word10 := #OB83_MDL_TYPE);

// OB86, rack or station failure. Performance Diagnostic: count this call and keep its start information
"FC_PerfFaultClassic"(OB_Nr := 86, EvClass := #OB86_EV_CLASS, FaultId := #OB86_FLT_ID, Byte4 := 16#0, Byte5 := 16#0,
                      ModAddr := #OB86_MDL_ADDR, Word6 := 16#0, Word8 := 16#0, Word10 := 16#0);

// OB121, programming error. Performance Diagnostic: count this call and keep its start information
"FC_PerfFaultClassic"(OB_Nr := 121, EvClass := #OB121_EV_CLASS, FaultId := #OB121_SW_FLT, Byte4 := #OB121_BLK_TYPE,
                      Byte5 := #OB121_RESERVED_1, ModAddr := 0, Word6 := #OB121_FLT_REG, Word8 := #OB121_BLK_NUM, Word10 := 16#0);

// OB122, I/O access error. Performance Diagnostic: count this call and keep its start information
"FC_PerfFaultClassic"(OB_Nr := 122, EvClass := #OB122_EV_CLASS, FaultId := #OB122_SW_FLT, Byte4 := #OB122_BLK_TYPE,
                      Byte5 := #OB122_MEM_AREA, ModAddr := 0, Word6 := #OB122_MEM_ADDR, Word8 := #OB122_BLK_NUM, Word10 := 16#0);
```

### 7.5 The inputs, for a LAD or FBD box

S7-1500 start information, `FC_PerfFault`; bold is the OB's own tag, everything else the constant `0`:

| Input | OB80 | OB82 | OB83 | OB86 | OB121 | OB122 |
|---|---|---|---|---|---|---|
| `OB_Nr` | `80` | `82` | `83` | `86` | `121` | `122` |
| `EvClass` | `0` | `0` | **`#Event_Class`** | **`#Event_Class`** | `0` | `0` |
| `FaultId` | **`#Fault_ID`** | `0` | **`#Fault_ID`** | **`#Fault_ID`** | **`#Fault_ID`** | **`#Fault_ID`** |
| `Laddr` | `0` | **`#LADDR`** | **`#LADDR`** | **`#LADDR`** | `0` | `0` |
| `IoState` | `0` | **`#IO_state`** | `0` | `0` | `0` | `0` |
| `Channel` | `0` | **`#Channel`** | `0` | `0` | `0` | `0` |
| `CsgOB` | **`#Csg_OBnr`** | `0` | `0` | `0` | `0` | `0` |
| `CsgPrio` | **`#Csg_Prio`** | `0` | `0` | `0` | `0` | `0` |
| `BlockNr` | `0` | `0` | `0` | `0` | **`#BlockNr`** | **`#BlockNr`** |
| `BlockType` | `0` | `0` | `0` | `0` | **`#BlockType`** | **`#BlockType`** |
| `Area` | `0` | `0` | `0` | `0` | **`#Area`** | **`#Area`** |

`Laddr` is `HW_ANY`, so it accepts the `HW_IO`, `HW_ANY` and `HW_Device` the OBs hand over, and no conversion box is needed. If TIA names a start-information tag differently in your version, wire the tag of that meaning.

Classic start information, `FC_PerfFaultClassic`; the byte of the Temp section each input takes:

| Input | Type | Byte | OB80 | OB82 | OB83 | OB86 | OB121 | OB122 |
|---|---|---|---|---|---|---|---|---|
| `OB_Nr` | `Int` | – | `80` | `82` | `83` | `86` | `121` | `122` |
| `EvClass` | `Byte` | 0 | **`EV_CLASS`** | **`EV_CLASS`** | **`EV_CLASS`** | **`EV_CLASS`** | **`EV_CLASS`** | **`EV_CLASS`** |
| `FaultId` | `Byte` | 1 | **`FLT_ID`** | **`FLT_ID`** | **`FLT_ID`** | **`FLT_ID`** | **`SW_FLT`** | **`SW_FLT`** |
| `Byte4` | `Byte` | 4 | `16#0` | `16#0` | `16#0` | `16#0` | **`BLK_TYPE`** | **`BLK_TYPE`** |
| `Byte5` | `Byte` | 5 | `16#0` | **`IO_FLAG`** | **`MDL_TD`** | `16#0` | **`RESERVED_1`** | **`MEM_AREA`** |
| `ModAddr` | `Int` | 6 | `0` | **`MDL_ADDR`** | `0` | **`MDL_ADDR`** | `0` | `0` |
| `Word6` | `Word` | 6 | **`ERROR_INFO`** | `16#0` | **`MDL_ADDR`** | `16#0` | **`FLT_REG`** | **`MEM_ADDR`** |
| `Word8` | `Word` | 8 | `%LW8` | `%LW8` | **`RACK_NUM`** | `%LW8` | **`BLK_NUM`** | **`BLK_NUM`** |
| `Word10` | `Word` | 10 | `%LW10` | `%LW10` | **`MDL_TYPE`** | `%LW10` | `16#0` | `16#0` |

Each tag is the OB's own, `#OBxx_` followed by the name in the table. An `MDL_ADDR` the OB declares as a `Word` goes on `Word6`, with `0` on `ModAddr`.

**An error OB your project does not have:** the kit works without it, but that OB's events are then not counted. To count them, create the OB (*Add new block → Organization block*, SCL) with its call from 7.2, and **keep the reaction the CPU has without it**, because adding an OB changes that reaction:

| OB | Without the OB, the S7-1500… | So a new OB gets |
|---|---|---|
| OB80, time error | goes to **STOP when the cycle time is exceeded** (`Fault_ID` `16#01`); ignores the other time errors | after the call: `// Stop on cycle time exceeded, as with no OB80` and `IF #Fault_ID = 16#01 THEN STP(); END_IF;` |
| OB121, programming error | goes to **STOP** | after the call: `// Stop, as with no OB121` and `STP();` |
| OB82, OB83, OB86, OB122 | carries on (OB122: writes the buffer entry and stays in RUN) | nothing more |

A second cycle-time overrun in the same cycle stops the CPU whatever OB80 does. Agree any change of reaction with whoever owns the machine's safety concept.

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
   | `DB_PerfHealth` | `Reserve.Life` | 8.0 |
   | `DB_PerfHealth` | `PN.Life` | 26.0 |
   | `DB_PerfHealth` | `PN.Echo` | 27.0 |

3. *Download to device.* An S7-1500 loads new blocks and new OBs in RUN; the hardware changes of step 2 need a STOP. Read the list of actions before accepting it: look for blocks about to be deleted, and for *reinitialize*, which resets your DBs' actual values.
4. Start the CPU.

## 9. Confirm it runs

A watch table:

| Tag | Expect |
|---|---|
| `DB_PerfMon.Seq`, `WriteIdx` | `Seq` up by 1 each second, `WriteIdx` following, 0 to 119 |
| `DB_PerfMon.BootDate`, `BootTime`, `RestartCount` | today, UTC, and 1 or more after a STOP to RUN. **Still 0 means OB884 has no call:** step 6 |
| `DB_PerfMon.Ring[0].CycMax_ms`, `Cycles`, `CommLoad_pct` | filled; `CommLoad_pct` -1 means `RT_INFO` refused it, see `DB_PerfDiag.RtRet` |
| `DB_PerfDiag.Step` | 1 within a second of a start |
| `DB_PerfDiag.Led[0..2]` | RUN/STOP, ERROR, MAINT: 1 off, 2 or 3 on, 4 or 5 flashing |
| `DB_PerfDiag.RtRet[0..3]` | 0 each. `16#8452` (shown as -31662) means `RT_INFO` wanted another INFO type: report it |
| `DB_PerfDiag.Fault[i].Count` | rising for each error OB that is being called. A project with I/O not wired shows OB122 here |
| `DB_PerfDiag.Fault[i].EvClass` | `16#80` or more for an OB called through `FC_PerfFaultClassic`: the classic event class plus `16#80`, the mark of that form. Below `16#80` for `FC_PerfFault` |
| `DB_PerfHealth.PN.Life` | 1 and still, until a reader confirms it |

Compare the cycle times with step 2.

**Set the histogram once, before comparing anything:** `DB_PerfMon.Edges_ms` holds the buckets' upper edges. The default is `2 | 5 | 10 | 20 | 40 | 60 | 100` ms, to separate an idle CPU from one running a real program.

## 10. The first read

```lot
DEFINE ROUTE S7ReadTest WITH TYPE SIEMENS_S7
    ADD S7_CONFIG
        WITH IP "192.168.1.20"
        WITH CPU_TYPE "S71500"
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

Publish anything to `s7test/cmd/read`. `s7test/res/read` answers with `{"success":true,…,"count":2058,"data":{"value_0":131140,…}}`: that first value is `16#00020044`, `LayoutVersion` 2 and `RecordSize` 68, and it proves the addressing. `DB881.DBD0` with `count: 81` reads `DB_PerfDiag`; its first value is `16#00020144`, layout 2 and 324 bytes. Remove the route afterwards.

| You see | It means |
|---|---|
| `Received error from PLC: Address out of range.` | wrong DB number, a DB shorter than the read, or optimized access still on |
| An error about access or protection | PUT/GET is off, or the access level does not allow it: step 2 |
| `Siemens S7 PLC is not connected` | the route has no connection: check the address, port 102, and `SLOT 1` |
| Route says added, but stays `Disconnected` | read the broker log; a tier limit is one cause, and each `ADD EVENT` counts as an action |

## 11. To remove the kit

Delete the `FC_PerfFault` or `FC_PerfFaultClassic` network from each error OB, then OB880, OB884, every `FC_Perf`, `DB_Perf` and `typPerf` block, and download. Undo step 2's PUT/GET if nothing else uses it.
