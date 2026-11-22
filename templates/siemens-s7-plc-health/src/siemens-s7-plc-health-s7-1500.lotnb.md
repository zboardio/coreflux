# Siemens S7 PLC health — S7-1500, over PN

Cycle-time metrics, error-OB calls and a health loop from a Siemens **S7-1500** (from firmware V2.x, no licence, no Web
API), read with the broker's native `SIEMENS_S7` connector over PUT/GET. A small set of blocks in the PLC measures every
cycle, counts every call of each error OB with its start information, and closes one record a second in a ring. The
broker reads the whole ring, so nothing is lost between two reads. The PLC also shows a counter that the broker echoes
back: if the echo stops, or comes back wrong, you know the data path is broken although the reads look fine.

```text
S7PLC02ReadTick (10 s) ─► …/<Kind>/read ─► Route S7PLC02PN reads DB880 | DB881 | DB882 whole ─► …/<Kind>/raw
…/raw ─► S7PLC02Decode ─► S7PerfDecode.decode ─► …/<Kind>/decoded ─┬─► Route S7Store ─► plc_ingest() in TimescaleDB
                                                                     └─► S7PLC02Uns ─► acme/site01/Automation/PLC02/PN/<Leaf>
Route: Seq every 5 s ─► S7PLC02Scan ─► CpuScanning (STOP seen from outside)
Route: Life every 1 s ─► S7PLC02Echo ─► Echo/set ─► Route writes it back into the PLC (the health loop)
S7PLC02Liveness (10 s) ─► DeviceStatus online | stale | offline, and _asset
```

**Run order:** the Prerequisites → Python → Route → Storage → Actions; the Rule only with a Growth or Enterprise licence. The hardware-free path skips the
Route cell and runs `siemens-s7-plc-health-simulator.lotnb` instead.

**Requires:** Coreflux broker **2.22 or newer**: the actions publish retained leaves with `PUBLISH … RETAIN` and read
`GET JSON` from a Python return value, which 2.14 cannot. Verified on 2.22.0: every cell of the three notebooks deployed
on a fresh broker and run against a mock PLC that speaks S7 (python-snap7) and a real TimescaleDB, with the checks
listed under "How to verify" passing and no runtime error in the broker log.

**Licence: this notebook alone fits the Community tier.** Measured on 2.22.0 Community: 2 connectors of 3 (the S7
route and the store route) and 12 actions of 24 (6 actions, 3 read events + 1 writable tag on the S7 route, 1 event on
the store route, 1 Python script). Both family notebooks on one broker: 3 connectors, 22 actions, which still fits. A
second PLC of either family costs one more connector, which Community does not have.

## Prerequisites

### 1. The kit's blocks in the CPU

The broker reads three DBs that the kit's blocks write: **DB880 `DB_PerfMon`** (the ring of one-second records,
8,232 bytes), **DB881 `DB_PerfDiag`** (layout 2 on an S7-1500: one slot per error OB, the LEDs, `RT_INFO`; 324 bytes
read) and **DB882 `DB_PerfHealth`** (the health loop, 44 bytes). They come with this template as a TIA Portal external
source for the S7-1500, `perf_kit.scl`, with its own guide; the template's GitHub folder holds both. The DB numbers
matter: the route addresses them by number.

On the CPU: **"Permit access with PUT/GET communication from remote partner"** on (it is hardware configuration: the
reads are refused with `0x8104` until the hardware is downloaded), **optimized block access off** on the three DBs, and a
CPU clock in UTC is assumed (the kit stamps records with `RD_SYS_T`, which is UTC).

### 2. The historian

A TimescaleDB (2.11 or newer, on PostgreSQL 16 or newer) with the template's SQL applied in this order:
`schema.sql`, `plc_fleet.sql`, `s7_1500_ob_fault.sql`, `s7_event_text.sql`, `role.sql`. `role.sql` creates the two
roles: **`uns_writer`**, which the store route uses and which can only INSERT, and **`grafana_reader`**, which can only
read. Without a historian the UNS leaves still work; the store route then only logs that it cannot connect.

### 3. Environment and secrets on the broker

Enter these in the Hub (**System Config → ENV & Secrets**) or with `-setEnv NAME=value` / `-setSecret NAME=value` on
`$SYS/Coreflux/Command`, before you deploy the Storage cell:

| Name | Type | Value |
|---|---|---|
| `TIMESCALE_HOST` | ENV | the database host, as the broker reaches it |
| `TIMESCALE_DB` | ENV | the historian's database |
| `TIMESCALE_USER` | ENV | `uns_writer` |
| `TIMESCALE_PASSWORD` | SECRET | its password |

Pin the secret store's key first: the broker encrypts its secret store with `COREFLUX_SECRET_KEY` (base64 of 32 random
bytes, passed to the broker container). Unpinned, the key is derived from the machine, and a restore onto other
hardware cannot read the password again.

## Topic contract

| Topic | Writer | Payload |
|---|---|---|
| `siemens/site01/PLC02/PN/<Kind>/read` | `S7PLC02ReadTick` | `go`: one read of the whole DB, `<Kind>` = `PerfMon`, `PerfDiag` or `PerfHealth` |
| `siemens/site01/PLC02/PN/<Kind>/raw` | the route | the connector's answer: `{"success":true,"count":N,"data":{"value_0":…}}` or `{"success":false,"error":…}` |
| `siemens/site01/PLC02/PN/<Kind>/decoded` | `S7PLC02Decode` | one JSON message per read, for the historian |
| `siemens/site01/PLC02/PN/Transition/decoded` | the scan, liveness and UNS actions | one message per change of a verdict, for the historian |
| `siemens/site01/PLC02/PN/PerfMon/Seq` | the route, every 5 s | the record counter |
| `siemens/site01/PLC02/PN/PerfHealth/Life` · `Echo` · `Echo/set` | the route · `S7PLC02Echo` | the health loop |
| `acme/site01/Automation/PLC02/PN/<Leaf>` | the actions | retained five-key envelope |
| `acme/site01/Automation/PLC02/PN/_asset` | `S7PLC02Liveness` | retained: model, order number, route, endpoint, every leaf |

**The leaves**, each the envelope `value`, `timestamp` (the PLC's stamp of the newest record for what the PLC measures,
the broker's time for what the broker derives), `datatype`, `status`, `units` on numbers:

| Leaf | Units | What |
|---|---|---|
| `CycleMin`, `CycleAvg`, `CycleMax` | ms | the newest one-second record |
| `CommLoad` | % | communication load, from `RT_INFO` |
| `OB80Events`, `OB82Events`, `OB86Events`, `OB83Events`, `OB121Events`, `OB122Events` | 1 | calls of each error OB since the boot |
| `LastFault` | | the newest error-OB call in words: OB, Siemens' meaning of its codes, block and address, calls since the boot |
| `BootTime` | | when the CPU last went to RUN |
| `ReadDuration` | ms | the last whole read of `DB_PerfMon` |
| `ClockSkew` | s | the broker's time minus the newest record's stamp |
| `CpuScanning` | | false once the record counter has not moved for 10 s: the CPU is in STOP |
| `Health` | | `ok`, `stalled` (the echo stopped), `corrupt` (a wrong echo came back, held 300 s), `unknown` (not scanning) |
| `DeviceStatus` | | `online` (a read or heartbeat within 20 s), `stale` (up to 90 s), `offline` |

## Python

**The decoder**, the one place that knows the DB layouts and the read contract. A read is not atomic: it spans many
CPU cycles while the ring moves on. A record is accepted only when its number is not newer than the header's, sits in
the slot its number belongs to, is not about to be overwritten during the read, and carries a valid stamp; everything
else is counted by reason and refused. Every read offers everything valid and the database keeps each record once, so a
broker restart loses nothing. The texts at the end are Siemens' meanings of the error-OB codes (both forms of start
information) and of the S7-300's diagnostic-buffer events, generated from the template's CSV tables.

**`PLCS`** at the top is the only per-PLC setting: the `plc_id` the historian stores, the family, the route and endpoint
of each path. This cell is the same in both family notebooks (it lists one example PLC of each family), so the two
notebooks can run on one broker; if you edit it, deploy the same text from both.

**Reads:** nothing (called by the actions). **Writes:** nothing.

```python
# Script Name: S7PerfDecode
# The broker-hosted decoder of the Siemens S7 PLC health kit, for every PLC this broker reads: one raw read in, one JSON
# message out, for plc_ingest() in the historian. Layouts: <family>/plc/perf_kit.scl of the template (s7-300, s7-1500).
# Stateless, so a broker restart is safe: every read offers everything valid and the database dedupes. The UNS functions
# get their state back as arguments, from the broker. Which PLC: the trailing plc argument (a key of PLCS).
# This cell is the same in both family notebooks, PLCS included, so both can run on one broker: keep the two equal.
import calendar
import hashlib
import json
import struct
import time

# The PLCs this broker reads: the only per-PLC configuration of the decoder, one example PLC per family (the S7-300
# notebook reads PLC01, the S7-1500 notebook PLC02). paths: path -> (route, endpoint, hardware), the order the reads take
# turns in; health_slots: DB_PerfHealth's slots this PLC uses, (path, offset), in the order the UNS action hands their
# kept state over; read_s: the read tick of its LoT. An S7-300's second path (MPI through a gateway): add
# "MPI": ("S7PLC01MPI", "<gateway>:102", "<gateway>, MPI address 2") to paths and ("MPI", 8) to health_slots.
PLCS = {
    "PLC01": {"plc_id": "acme-site01-plc01", "family": "s7-300", "read_s": 10,
              "paths": {"PN": ("S7PLC01PN", "192.168.1.10:102", "the CPU's own PN port")},
              "health_slots": (("PN", 26),),
              "model": "CPU 315-2 PN/DP", "order_no": "6ES7 315-2EH13-0AB0", "installed": "2026-11-01T00:00:00Z",
              "area": "site01", "firmware": None, "description": "CPU 315-2 PN/DP, read over PN"},
    "PLC02": {"plc_id": "acme-site01-plc02", "family": "s7-1500", "read_s": 10,
              "paths": {"PN": ("S7PLC02PN", "192.168.1.20:102", "the CPU's own PN port")},
              "health_slots": (("PN", 26),),
              "model": "CPU 1511-1 PN", "order_no": "6ES7 511-1AK02-0AB0", "installed": "2026-11-01T00:00:00Z",
              "area": "site01", "firmware": "V2.6", "description": "CPU 1511-1 PN, FW V2.6, PN only (PUT/GET)"},
}
KINDS = ("PerfMon", "PerfDiag", "PerfHealth")
READ_SECONDS = 5
# What a whole read of each DB returns, per (kind, family). DB_PerfMon and DB_PerfHealth are byte-identical across
# families; DB_PerfDiag is layout 1 on the S7-300 (SZL copies, the diagnostic buffer) and layout 2 on the S7-1500.
# The S7-1200 reads exactly as the S7-1500 (layout 2, family 1200 at byte 4); only four of its six slots are written.
SIZE = {("PerfMon", "s7-300"): 8232, ("PerfDiag", "s7-300"): 644, ("PerfHealth", "s7-300"): 44,
        ("PerfMon", "s7-1500"): 8232, ("PerfDiag", "s7-1500"): 324, ("PerfHealth", "s7-1500"): 44,
        ("PerfMon", "s7-1200"): 8232, ("PerfDiag", "s7-1200"): 324, ("PerfHealth", "s7-1200"): 44}
LAYOUT = {("PerfMon", "s7-300"): 2, ("PerfDiag", "s7-300"): 1, ("PerfHealth", "s7-300"): 1,
          ("PerfMon", "s7-1500"): 2, ("PerfDiag", "s7-1500"): 2, ("PerfHealth", "s7-1500"): 1,
          ("PerfMon", "s7-1200"): 2, ("PerfDiag", "s7-1200"): 2, ("PerfHealth", "s7-1200"): 1}
CPU_FAMILY = {"s7-1500": 1500, "s7-1200": 1200}   # DB_PerfDiag layout 2 names its family at byte 4
# The error OBs a layout-2 family has beyond OB80/82/86 (which DB_PerfMon counts too): an S7-1200 has no OB121/OB122.
EXTRA_OBS = {"s7-1500": (83, 121, 122), "s7-1200": (83,)}
FAULT_OBS = (80, 82, 83, 86, 121, 122)   # DB_PerfDiag layout 2: Fault[0..5], PrevCount[0..5]
CLASSIC = 0x80   # EvClass bit 7: the slot holds classic start information (FC_PerfFaultClassic); FC_PerfFault clears it
RECORD_SIZE = 68
RING_MARGIN = 5


def _plc(plc):
    return PLCS[plc or "PLC01"]


def _plc_of(plc_id):
    for key, cfg in PLCS.items():
        if cfg["plc_id"] == plc_id:
            return key, cfg
    return None, None


def reads(plc="PLC01"):
    return [path + "/" + kind for path in _plc(plc)["paths"] for kind in KINDS]


READS = reads("PLC01")   # PLC01's turn order, as the tests that predate PLCS read it


def next_read(_tick, plc="PLC01"):
    cfg = _plc(plc)
    every = reads(plc)
    return every[int(time.time() / cfg["read_s"]) % len(every)]


def now_ms(_tick):
    return str(int(time.time() * 1000))


def _raw_bytes(doc):
    data = doc["data"]
    # A DWORD with its high bit set arrives as a negative number: the mask gives the bytes back.
    return b"".join(struct.pack(">I", data["value_%d" % i] & 0xFFFFFFFF) for i in range(int(doc["count"])))


def _text(raw):
    return raw.split(b"\x00")[0].decode("ascii", "replace").strip().replace("'", "")


def _valid_stamp(stamp_date, stamp_time):
    month, day = int(stamp_date / 100) % 100, stamp_date % 100
    hour, minute = int(stamp_time / 10000000), int(stamp_time / 100000) % 100
    second = int(stamp_time / 1000) % 100
    return 19900101 <= stamp_date <= 20891231 and 1 <= month <= 12 and 1 <= day <= 31 and hour < 24 and minute < 60 and second < 60


def _perf_mon(raw, out):
    record_size, ring_size, write_idx, seq = struct.unpack_from(">hhhi", raw, 2)
    out["header"] = {
        "ring_size": ring_size, "write_idx": write_idx, "seq": seq,
        "window_ms": struct.unpack_from(">h", raw, 12)[0], "restart_count": struct.unpack_from(">h", raw, 14)[0],
        "edges_ms": [round(v, 3) for v in struct.unpack_from(">7f", raw, 16)],
        "life_min_ms": struct.unpack_from(">f", raw, 44)[0], "life_max_ms": struct.unpack_from(">f", raw, 48)[0],
        "ob80_total": struct.unpack_from(">i", raw, 52)[0], "ob86_events": struct.unpack_from(">i", raw, 56)[0],
        "ob82_events": struct.unpack_from(">i", raw, 60)[0],
        "boot_date": struct.unpack_from(">i", raw, 64)[0], "boot_time": struct.unpack_from(">i", raw, 68)[0],
    }
    rejected = {"empty": 0, "future": 0, "slot": 0, "old": 0, "stamp": 0}
    records, earlier = [], []
    if record_size != RECORD_SIZE or ring_size <= RING_MARGIN or 72 + ring_size * RECORD_SIZE != len(raw):
        out["error"] = "ring layout: record %d, ring %d, %d bytes" % (record_size, ring_size, len(raw))
        out["rejected"], out["records"] = rejected, records
        return
    boot_s = _stamp_s(out["header"]["boot_date"], out["header"]["boot_time"])
    for slot in range(ring_size):
        at = 72 + slot * RECORD_SIZE
        rec_seq = struct.unpack_from(">i", raw, at)[0]
        if rec_seq <= 0:
            rejected["empty"] += 1
        elif rec_seq > seq:
            # Newer than the header: being written during the read, or a slot of an EARLIER boot that this one has
            # not overwritten yet. The previous boot's tail is offered when its slot is consistent, its stamp is before
            # this boot and the next slots to be written are clear of it; plc_ingest() decides which boot it belongs to.
            stamp_s = _stamp_s(*struct.unpack_from(">ii", raw, at + 4))
            if ((rec_seq - 1) % ring_size == slot and boot_s is not None and stamp_s is not None and stamp_s < boot_s
                    and (slot - seq) % ring_size >= RING_MARGIN):
                earlier.append(_record(raw, at, rec_seq))
            else:
                rejected["future"] += 1
        elif (rec_seq - 1) % ring_size != slot:
            rejected["slot"] += 1
        elif rec_seq <= seq - (ring_size - RING_MARGIN):
            rejected["old"] += 1
        else:
            stamp_date, stamp_time = struct.unpack_from(">ii", raw, at + 4)
            if not _valid_stamp(stamp_date, stamp_time):
                rejected["stamp"] += 1
                continue
            records.append(_record(raw, at, rec_seq))
    out["rejected"], out["records"] = rejected, records
    if earlier:
        out["earlier"] = earlier


def _record(raw, at, rec_seq):
    stamp_date, stamp_time, cycles = struct.unpack_from(">iii", raw, at + 4)
    cyc_min, cyc_max, cyc_avg, comm = struct.unpack_from(">4f", raw, at + 16)
    return {
        "seq": rec_seq, "stamp_date": stamp_date, "stamp_time": stamp_time, "cycles": cycles,
        "cyc_min_ms": cyc_min, "cyc_max_ms": cyc_max, "cyc_avg_ms": cyc_avg, "comm_load_pct": comm,
        "hist": list(struct.unpack_from(">8i", raw, at + 32)),
        "flags": struct.unpack_from(">H", raw, at + 64)[0], "ob80_cnt": struct.unpack_from(">h", raw, at + 66)[0],
        "hash": hashlib.md5(raw[at:at + RECORD_SIZE]).hexdigest(),
    }


def _bcd(byte):
    return (byte >> 4) * 10 + (byte & 15)


# Entries whose info 1 (bytes 6-7) is the event ID of the STOP before them (OB100/101/102 start information, A5E02790053-01
# §13.2): STOP to STARTUP and the class-1 restart requests. Proven on the TIA export: 0x4301 and 0x1381 carry 0x4304.
CAUSE_IDS = frozenset([0x4301] + list(range(0x1381, 0x1389)) + list(range(0x138A, 0x138E)))


def diag_entry(entry):
    """One 20-byte SZL 0x00A0 entry, or None when its stamp is not a date. Laid out like the start information of an OB:
    bytes 0-1 event ID, 2 priority class, 3 OB, 4-5 DatID, 6-7 info 1, 8-11 info 2, 12-19 DATE_AND_TIME in BCD (the low
    nibble of byte 19 is the weekday, not the time). Byte 2 = 0xFF means no priority class (mode transitions, class 4):
    byte 3 is then no OB but the previous (high nibble) and requested (low nibble) operating mode, so both are None. On
    the CAUSE_IDS entries info 1 is the STOP cause's event ID (cause_id, else None) and info 2 the startup information.
    The cause's text is not carried here: the message goes into a quoted SQL literal and the historian has the lookup.
    Proven on the TIA export."""
    year, month, day, hour, minute, second = [_bcd(b) for b in entry[12:18]]
    millis = _bcd(entry[18]) * 10 + (entry[19] >> 4)
    stamp_date = (1900 if year >= 90 else 2000) * 10000 + year * 10000 + month * 100 + day
    stamp_time = hour * 10000000 + minute * 100000 + second * 1000 + millis
    if not _valid_stamp(stamp_date, stamp_time):
        return None
    event_id, info1, info2 = struct.unpack_from(">H", entry, 0)[0], struct.unpack_from(">H", entry, 6)[0], struct.unpack_from(">I", entry, 8)[0]
    no_priority = entry[2] == 0xFF
    return {"event_id": event_id, "priority": None if no_priority else entry[2], "ob_nr": None if no_priority else entry[3],
            "info1": info1, "info2": info2, "cause_id": info1 if event_id in CAUSE_IDS and info1 else None,
            "stamp_date": stamp_date, "stamp_time": stamp_time, "entry_hex": entry.hex()}


def _diag_entries(raw, count):
    entries, skipped = [], 0
    for i in range(min(max(count, 0), 10)):
        parsed = diag_entry(raw[444 + i * 20:444 + (i + 1) * 20])
        if parsed is None:
            skipped += 1
        else:
            entries.append(parsed)
    return entries, skipped


def _perf_diag(raw, out):
    fault_ob, fault_count, fault_date, fault_time, ev_class, flt_id = struct.unpack_from(">hhiiBB", raw, 8)
    ret = list(struct.unpack_from(">8h", raw, 48)) + [struct.unpack_from(">h", raw, 70)[0]]
    led_count, mod_count, diag_count = struct.unpack_from(">hhh", raw, 64)
    entries, skipped = _diag_entries(raw, diag_count)
    out.update({
        "diag_seq": struct.unpack_from(">i", raw, 4)[0], "ret": ret, "led_count": led_count, "mod_count": mod_count,
        "fault": {"ob": fault_ob, "count": fault_count, "date": fault_date, "time": fault_time, "ev_class": ev_class, "flt_id": flt_id},
        "boot_end": dict(zip(("date", "time", "last_seq", "ob80", "ob86", "ob82"), struct.unpack_from(">6i", raw, 24))),
        "order_no": _text(raw[74:94]), "firmware_hex": raw[100:128].hex(), "serial": _text(raw[130:162]), "station": _text(raw[164:196]),
        "led_hex": raw[196:236].hex(), "mod_hex": raw[236:364].hex(), "protection_hex": raw[364:404].hex(), "connections_hex": raw[404:444].hex(),
        "entries": entries, "entries_skipped": skipped,
    })


def _perf_diag_l2(raw, out):
    """DB_PerfDiag layout 2, the S7-1500 (s7-1500/plc/perf_kit.scl): the program cannot read the diagnostic buffer on this
    family, so no SZL and no entries. Instead one 20-byte slot per error OB (FAULT_OBS): calls since the boot, the newest
    call's UTC stamp, Event_Class, Fault_ID and three start-information words. The newest call of any OB is "newest",
    not "fault": plc_fault holds what stopped an S7-300; an S7-1500's OB122 can be called 2,000 times a second.
    A slot whose EvClass has bit 7 set holds CLASSIC start information (FC_PerfFaultClassic, an OB migrated with the
    S7-300/400 TEMP): it gets "form": "classic", ev_class stays the raw byte (the historian derives the form from it)."""
    slots = []
    for i, ob in enumerate(FAULT_OBS):
        calls, date, tod, ev_class, fault_id, info1, info2, info3 = struct.unpack_from(">iiiBBHHH", raw, 60 + 20 * i)
        if not _valid_stamp(date, tod):   # a stamp that is no date must not fail the whole ingest: 0 = none
            date, tod = 0, 0
        slot = {"ob": ob, "calls": calls, "last_date": date, "last_time": tod, "ev_class": ev_class, "fault_id": fault_id,
                "info1": info1, "info2": info2, "info3": info3}
        if ev_class & CLASSIC:   # only then: an S7-1500-form slot decodes exactly as before the classic form
            slot["form"] = "classic"
        slots.append(slot)
    newest = struct.unpack_from(">hhii", raw, 12)
    prev_date, prev_time, prev_seq = struct.unpack_from(">iii", raw, 24)
    prev = struct.unpack_from(">6i", raw, 36)
    longest, shortest, last = struct.unpack_from(">fff", raw, 212)
    out.update({
        "layout": 2, "diag_seq": struct.unpack_from(">i", raw, 8)[0],
        "newest": dict(zip(("ob", "count", "date", "time"), newest)),
        "boot_end": {"date": prev_date, "time": prev_time, "last_seq": prev_seq, "ob80": prev[0], "ob86": prev[3], "ob82": prev[1]},
        "prev_count": [{"ob": ob, "calls": n} for ob, n in zip(FAULT_OBS, prev)],
        "ob_slots": slots,   # schema.sql: plc_ob_call, one row per newest call the reads see
        "led": list(struct.unpack_from(">3h", raw, 180)), "im_status": struct.unpack_from(">H", raw, 196)[0],
        "rt_ret": list(struct.unpack_from(">4h", raw, 198)), "comm_load_pct": struct.unpack_from(">f", raw, 208)[0],
        "cyc_longest_ms": longest, "cyc_shortest_ms": shortest, "cyc_last_ms": last,
        "mod_ret": struct.unpack_from(">h", raw, 256)[0], "mod_configured_hex": raw[224:240].hex(), "mod_problem_hex": raw[240:256].hex(),
        "im0_hex": raw[260:324].hex(), "entries": [],
    })


def _slot(raw, at):
    life, echo, bad_echo, age_s, losses, loss_date, loss_time, bits = struct.unpack_from(">BBhhhiiB", raw, at)
    return {"life": life, "echo": echo, "bad_echo": bad_echo, "age_s": age_s, "losses": losses,
            "last_loss_date": loss_date, "last_loss_time": loss_time, "healthy": bool(bits & 1), "seen": bool(bits & 2)}


def _perf_health(raw, out, slots):
    out["loss_limit_s"] = struct.unpack_from(">h", raw, 4)[0]
    out["slots"] = dict((name, _slot(raw, at)) for name, at in slots)


def decode(payload, via, kind, asked, plc="PLC01"):
    t0 = time.time()
    cfg = _plc(plc)
    family = cfg["family"]
    out = {"plc_id": cfg["plc_id"], "via": via, "kind": kind, "bytes": 0, "read_ms": None, "records": [], "rejected": {}}
    try:
        out["read_ms"] = int(t0 * 1000) - int(asked)
    except (TypeError, ValueError):
        pass
    try:
        doc = json.loads(payload)
        if not doc.get("success"):
            out["error"] = str(doc.get("error", "no success flag"))[:200].replace("'", "")
            return json.dumps(out, separators=(",", ":"))
        raw = _raw_bytes(doc)
        out["bytes"] = len(raw)
        layout = struct.unpack_from(">h", raw, 0)[0]
        if len(raw) != SIZE[(kind, family)] or layout != LAYOUT[(kind, family)]:
            out["error"] = "layout: version %d, %d bytes" % (layout, len(raw))
        elif kind == "PerfMon":
            _perf_mon(raw, out)
        elif kind == "PerfDiag" and layout == 2:
            cpu_family = struct.unpack_from(">h", raw, 4)[0]
            if cpu_family != CPU_FAMILY.get(family):
                out["error"] = "layout: version 2, family %d" % cpu_family
            else:
                _perf_diag_l2(raw, out)
        elif kind == "PerfDiag":
            _perf_diag(raw, out)
        else:
            _perf_health(raw, out, cfg["health_slots"])
    except Exception as exc:
        out["error"] = ("%s: %s" % (type(exc).__name__, exc))[:200].replace("'", "")
    out["decode_ms"] = round((time.time() - t0) * 1000, 2)
    return json.dumps(out, separators=(",", ":"))


# The UNS plane: acme/site01/Automation/<PLC>/<path>/<Leaf>. Each function returns one JSON object whose
# values are finished payloads (a five-key envelope, or _asset) and kept state, so an action only routes them. State
# lives in the broker (KEEP TOPIC, or the retained leaf itself) and comes back as an argument: nothing is held here.
# After a broker restart the first reading of each kind only re-baselines. The PLC's clock is taken as UTC (measured on
# the S7-300; RD_SYS_T is UTC on an S7-1500).
FROZEN_S = 10          # CpuScanning false: Seq unchanged this long, 10 windows of 1 s, two heartbeats of 5 s
ONLINE_S = 20          # DeviceStatus online: a good read or heartbeat on that path at most this old (the reads leave 20 s gaps)
OFFLINE_S = 90         # DeviceStatus offline beyond this; stale in between
CORRUPT_HOLD_S = 300   # Health stays corrupt this long after BadEcho rose, so a one-off wrong value is seen
ASSET_EVERY = 6        # _asset re-asserted on every 6th liveness visit of a path, once a minute
LEAVES = {
    "CycleMin": ("ms", "number", 30, "PerfMon", "records[newest].cyc_min_ms"),
    "CycleAvg": ("ms", "number", 30, "PerfMon", "records[newest].cyc_avg_ms"),
    "CycleMax": ("ms", "number", 30, "PerfMon", "records[newest].cyc_max_ms"),
    "CommLoad": ("%", "number", 30, "PerfMon", "records[newest].comm_load_pct, -1 = not available (S7-300)"),
    "OB80Events": ("1", "number", 30, "PerfMon", "header.ob80_total"),
    "OB82Events": ("1", "number", 30, "PerfMon", "header.ob82_events"),
    "OB86Events": ("1", "number", 30, "PerfMon", "header.ob86_events"),
    "BootTime": (None, "string", 30, "PerfMon", "header.boot_date, header.boot_time"),
    "ReadDuration": ("ms", "number", 30, "PerfMon", "read_ms of the whole DB_PerfMon read"),
    "ClockSkew": ("s", "number", 30, "PerfMon", "read time - newest record stamp"),
    "LastFault": (None, "string", 30, "PerfDiag", "fault"),
    "LastDiagEvent": (None, "string", 30, "PerfDiag", "entries[newest]"),
    "CpuScanning": (None, "boolean", 5, "PerfMon/Seq", "Seq moved within %d s" % FROZEN_S),
    "Health": (None, "string", 15, "PerfHealth", "slots.<path>: healthy, age_s, bad_echo; unknown while CpuScanning is false"),
    "DeviceStatus": (None, "string", 10, "lastOk", "age of the last good read or heartbeat on this path"),
}
# The S7-1500's DB_PerfDiag (layout 2) has no diagnostic buffer, so no LastDiagEvent, and counts three more error OBs.
LEAVES_1500 = {
    "OB83Events": ("1", "number", 30, "PerfDiag", "ob_slots[OB83].count"),
    "OB121Events": ("1", "number", 30, "PerfDiag", "ob_slots[OB121].count"),
    "OB122Events": ("1", "number", 30, "PerfDiag", "ob_slots[OB122].count"),
    "LastFault": (None, "string", 30, "PerfDiag", "newest, ob_slots[newest.ob]: the codes with their meaning"),
}
ALL_LEAVES = dict(LEAVES, **LEAVES_1500)
# The three verdicts above are also written to the historian as they change (plc_state_change, one row per change, by the
# broker's clock): the store route takes the message like a decoded read, kind "Transition", on
# siemens/site01/<PLC>/<path>/Transition/decoded. The Overview's tiles then show the broker's own answer, the same as the
# Hub, instead of deriving one from the stored reads with a 90 s margin (the first acceptance run, 2026-11-04).
STATE_SIGNALS = ("CpuScanning", "DeviceStatus", "Health")


def leaves_of(family):
    """The leaves a PLC of this family publishes, in order: what its _asset lists. A layout-2 family (S7-1500, S7-1200)
    has no LastDiagEvent and one OB<n>Events leaf per error OB of EXTRA_OBS."""
    if family not in EXTRA_OBS:
        return LEAVES
    out = {}
    for leaf, spec in LEAVES.items():
        if leaf == "LastDiagEvent":
            continue
        out[leaf] = LEAVES_1500.get(leaf, spec)
        if leaf == "OB86Events":
            for ob in EXTRA_OBS[family]:
                out["OB%dEvents" % ob] = LEAVES_1500["OB%dEvents" % ob]
    return out


def event_text(event_id):
    """The text TIA shows for an event ID, or None: an exact ID first, then the masked module forms, the most specific
    mask first. The same data and rule as the historian's plc_event_text(); the dicts at the end are generated."""
    text = EVENT_TEXT.get(event_id)
    if text is None:
        for mask in sorted(EVENT_TEXT_MASKED, reverse=True):
            text = EVENT_TEXT_MASKED[mask].get(event_id & mask)
            if text is not None:
                break
    return text


def ob_fault_text(ob, slot):
    """The newest call of an S7-1500 error OB in words: its start information with Siemens' meaning of each code (the
    generated OB_FAULT_TEXT at the end; the historian's view plc_ob_call_text reads the same CSV)."""
    ev, fid, info1, info2, info3 = slot["ev_class"], slot["fault_id"], slot["info1"], slot["info2"], slot["info3"]
    if ev & CLASSIC:
        return _classic_text(ob, slot)

    def named(field, code, label):
        text = OB_FAULT_TEXT.get((ob, field, code))
        return label + (" " + text if text else "")

    parts = ["OB%d" % ob]
    if ob in (80, 121, 122):
        parts.append(named("Fault_ID", fid, "fault id 0x%02X" % fid))
    elif ob in (83, 86):
        parts.append(named("Event_Class/Fault_ID", ev * 256 + fid, "event class 0x%02X fault id 0x%02X" % (ev, fid)))
    if ob == 80:
        parts.append("caused by OB%d at priority %d" % (info1, info2))
    elif ob == 82:
        bits = [OB_FAULT_TEXT.get((82, "IO_state bit", b)) or "bit %d" % b for b in range(16) if info1 >> b & 1]
        parts += ["IO_state 0x%04X" % info1 + (" (" + ", ".join(bits) + ")" if bits else ""), "LADDR %d" % info2, "channel %d" % info3]
    elif ob in (83, 86):
        parts.append("LADDR %d" % info1)
    else:
        parts.append((OB_FAULT_TEXT.get((ob, "BlockType", info2)) or "block type %d" % info2) + " %d" % info1)
        parts.append(named("Area", info3, "area 0x%02X" % info3))
    parts.append("%d calls since the boot" % slot["calls"])
    return ", ".join(parts)


def _classic_text(ob, slot):
    """A slot with CLASSIC start information (EvClass bit 7, FC_PerfFaultClassic), in words: Siemens' S7-300/400 meanings
    (the "Classic ..." rows of the CSV) and the packing of the comment above typPerfFaultSlot in perf_kit.scl. The
    historian's plc_ob_call_text.details says the same."""
    ev, fid, info1, info2, info3 = slot["ev_class"] & 0x7F, slot["fault_id"], slot["info1"], slot["info2"], slot["info3"]
    z = info2 << 16 | info3   # bytes 8 to 11 of the OB's TEMP, as one DWORD (OB82's bits, OB86's RACKS_FLTD)

    def named(field, code, label):
        text = OB_FAULT_TEXT.get((ob, field, code))
        return label + (" " + text if text else "")

    def hex4(value):
        return "16#%04X" % value

    parts = ["OB%d classic" % ob]
    if ob in (82, 83, 86):
        parts.append(named("Classic EV_CLASS/FLT_ID", ev * 256 + fid, "event class 0x%02X fault id 0x%02X" % (ev, fid)))
    else:
        parts.append(named("Classic FLT_ID", fid, "fault id 0x%02X" % fid))
    if ob == 80:
        if fid in (1, 10):
            parts.append(("cycle %d ms" if fid == 1 else "CiR synchronization %d ms") % info1)
        else:
            parts.append(("time-of-day interrupts " if fid in (5, 6) else "error info ") + hex4(info1))
        if info2:
            parts.append("start event " + hex4(info2))
        if info3:
            parts.append("caused by OB%d at priority %d" % (info3 & 255, info3 >> 8))
    elif ob == 82:
        parts.append("%s module %d" % ("output" if info1 & 0x8000 else "input", info1 & 0x7FFF))
        parts += [OB_FAULT_TEXT[(82, "Classic fault bit", code)] for code in range(64, 96)
                  if (82, "Classic fault bit", code) in OB_FAULT_TEXT and z >> ((11 - int(code / 8)) * 8 + code % 8) & 1]
        parts.append("module class " + (OB_FAULT_TEXT.get((82, "Classic module class", info2 & 15)) or "class 16#%X" % (info2 & 15)))
    elif ob == 83:
        parts.append("%s address %d" % ("output" if info1 & 0x8000 else "input", info1 & 0x7FFF))
        if info2 & 0x8000:
            parts.append("PROFINET IO system ID %d, device %d" % (info2 >> 11 & 15, info2 & 2047))
        else:
            parts.append("rack or DP station " + hex4(info2))
        parts.append("module type " + hex4(info3))
    elif ob == 86:
        addr = info1 - 65536 if info1 > 32767 else info1
        if fid in (0xC1, 0xC2, 0xC6):
            racks = " ".join(str(n) for n in range(1, 22) if z >> n & 1) or "none"
            parts += ["IM address %d" % addr, "expansion racks " + racks + (" and the S5 area" if z >> 30 & 1 else "")]
        elif fid == 0xC3:
            parts += ["DP master address %d" % addr, "DP master system %d" % (z >> 8 & 255)]
        elif 0xC4 <= fid <= 0xC9:
            parts += ["DP master address %d" % addr, "DP master system %d, station %d, slave address %d" % (z >> 8 & 255, z & 255, z >> 16 & 32767)]
        elif fid == 0xCA:
            parts += ["IO controller address %d" % addr, "PROFINET IO system ID %d" % (z >> 11 & 15)]
        elif 0xCB <= fid <= 0xCF:
            parts += ["IO controller address %d" % addr,
                      "PROFINET IO system ID %d, device %d, station address %d" % (z >> 11 & 15, z & 2047, z >> 16 & 32767)]
        else:
            parts += ["MDL_ADDR %d" % addr, "RACKS_FLTD 16#%08X" % z]
    else:
        block_type = info2 >> 8
        parts.append((OB_FAULT_TEXT.get((ob, "Classic BLK_TYPE", block_type)) or "block type 16#%02X" % block_type) + " %d" % info1)
        if ob == 122 or fid in (0x22, 0x23, 0x28, 0x29):   # OB121: RESERVED_1 holds area and access type for these only
            area, access = info2 & 15, info2 >> 4 & 15
            parts.append((OB_FAULT_TEXT.get((ob, "Classic memory area", area)) or "area %d" % area) + ", "
                         + (OB_FAULT_TEXT.get((ob, "Classic access type", access)) or "access type %d" % access))
        parts.append("address %d" % info3 if ob == 122 else "FLT_REG " + hex4(info3))
    parts.append("%d calls since the boot" % slot["calls"])
    return ", ".join(parts)


def _iso(seconds):
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(seconds)) + ".%03dZ" % (int(seconds * 1000) % 1000)


def _stamp_s(stamp_date, stamp_time):
    if not _valid_stamp(stamp_date, stamp_time):
        return None
    year, month, day = int(stamp_date / 10000), int(stamp_date / 100) % 100, stamp_date % 100
    hour, minute = int(stamp_time / 10000000), int(stamp_time / 100000) % 100
    second, millis = int(stamp_time / 1000) % 100, stamp_time % 1000
    return calendar.timegm((year, month, day, hour, minute, second, 0, 0, 0)) + millis / 1000.0


def _envelope(leaf, value, at, status="Good"):
    units, datatype = ALL_LEAVES[leaf][0], ALL_LEAVES[leaf][1]
    env = {"value": value, "timestamp": _iso(at), "datatype": datatype, "status": status}
    if units is not None:
        env["units"] = units
    return json.dumps(env, separators=(",", ":"))


def _load(text):
    try:
        doc = json.loads(text)
        return doc if isinstance(doc, dict) else {}
    except (TypeError, ValueError):
        return {}


def _verdict(value):
    """A verdict as the historian stores it: booleans as true/false, strings as they are, None for no previous one."""
    if isinstance(value, bool):
        return "true" if value else "false"
    return None if value is None else str(value)


def transition(via, signal, value, prev, now, plc_id=None):
    """One change of a verdict, for the store route (plc_ingest kind Transition → plc_state_change)."""
    return json.dumps({"plc_id": plc_id or PLCS["PLC01"]["plc_id"], "via": via, "kind": "Transition", "signal": signal,
                       "value": _verdict(value), "prev": _verdict(prev), "at": _iso(now)}, separators=(",", ":"))


def _health(slot, state, now, scan):
    """ok, stalled (Life stopped: the PLC's Healthy is off), corrupt (BadEcho rose) or unknown (the CPU is not
    scanning: the loop runs in the program cycle, so Life, Age_s and Healthy are frozen and prove nothing), and the
    state to keep."""
    bad, rose = slot["bad_echo"], state.get("rose")
    if "bad" in state and bad > state["bad"]:
        rose = now
    if scan is False:
        value = "unknown"
    elif rose is not None and now - rose < CORRUPT_HOLD_S:
        value = "corrupt"
    elif not slot["healthy"]:
        value = "stalled"
    else:
        value = "ok"
    return value, json.dumps({"bad": bad, "rose": rose, "value": value})


def _diag_leaves_l2(msg, out, now, family="s7-1500"):
    """DB_PerfDiag layout 2 (S7-1500, S7-1200): LastFault from the newest call of any error OB, with its meaning; the call
    counts of the OBs DB_PerfMon does not count (EXTRA_OBS of the family), stamped with each one's newest call."""
    slots = dict((s["ob"], s) for s in msg.get("ob_slots", []))
    newest = msg.get("newest", {})
    slot = slots.get(newest.get("ob"))
    at = _stamp_s(newest.get("date", 0), newest.get("time", 0))
    if newest.get("count", 0) > 0 and slot and at is not None:
        out["LastFault"] = _envelope("LastFault", ob_fault_text(newest["ob"], slot), at)
    else:
        out["LastFault"] = _envelope("LastFault", "none", now)
    for ob in EXTRA_OBS.get(family, (83, 121, 122)):
        s = slots.get(ob)
        if s:
            when = _stamp_s(s["last_date"], s["last_time"]) if s["calls"] > 0 else None
            out["OB%dEvents" % ob] = _envelope("OB%dEvents" % ob, s["calls"], now if when is None else when)


def uns_leaves(decoded, scanning, health_1, health_2, now=None):
    """One decoded read becomes the leaves it carries. scanning is the path's retained CpuScanning envelope (for
    ClockSkew's status and the health loop's unknown), health_1/health_2 the kept health state of the PLC's health slots
    in PLCS order (PLC01: MPI, PN; PLC02: PN, and the second is unused). The PLC is the message's own plc_id. A failed
    read carries no leaf, and so does a Transition message: it travels on the same decoded topics."""
    now = time.time() if now is None else float(now)
    msg, out = _load(decoded), {}
    if not msg or "error" in msg or msg.get("kind") not in KINDS:
        return json.dumps(out)
    cfg = _plc_of(msg.get("plc_id"))[1] or PLCS["PLC01"]   # a message without a known plc_id is read as before PLC02
    out["lastOk"] = str(int(now * 1000))
    kind = msg.get("kind")
    if kind == "PerfMon":
        hdr, records = msg.get("header", {}), msg.get("records", [])
        if records:
            last = max(records, key=lambda r: r["seq"])
            at = _stamp_s(last["stamp_date"], last["stamp_time"])
            out["CycleMin"] = _envelope("CycleMin", round(last["cyc_min_ms"], 3), at)
            out["CycleAvg"] = _envelope("CycleAvg", round(last["cyc_avg_ms"], 3), at)
            out["CycleMax"] = _envelope("CycleMax", round(last["cyc_max_ms"], 3), at)
            comm = round(last["comm_load_pct"], 2)
            out["CommLoad"] = _envelope("CommLoad", comm, at, "Good" if comm >= 0 else "Bad")
            for leaf, key in (("OB80Events", "ob80_total"), ("OB82Events", "ob82_events"), ("OB86Events", "ob86_events")):
                out[leaf] = _envelope(leaf, hdr.get(key), at)
            boot = _stamp_s(hdr.get("boot_date", 0), hdr.get("boot_time", 0))
            out["BootTime"] = _envelope("BootTime", _iso(boot) if boot is not None else "unknown", at, "Good" if boot is not None else "Bad")
            scan = _load(scanning).get("value")
            out["ClockSkew"] = _envelope("ClockSkew", round(now - at, 3), now, "Uncertain" if scan is False else "Good")
        if msg.get("read_ms") is not None:
            out["ReadDuration"] = _envelope("ReadDuration", msg["read_ms"], now)
    elif kind == "PerfDiag" and msg.get("layout") == 2:
        _diag_leaves_l2(msg, out, now, cfg["family"])
    elif kind == "PerfDiag":
        fault = msg.get("fault", {})
        at = _stamp_s(fault.get("date", 0), fault.get("time", 0))
        if fault.get("count", 0) > 0 and at is not None:
            text = "OB%d, event class 0x%02X, fault id 0x%02X" % (fault["ob"], fault["ev_class"], fault["flt_id"])
            out["LastFault"] = _envelope("LastFault", text, at)
        else:
            out["LastFault"] = _envelope("LastFault", "none", now)
        entries = msg.get("entries", [])
        if entries:
            newest = max(entries, key=lambda e: (e["stamp_date"], e["stamp_time"]))
            known = event_text(newest["event_id"])
            parts = ["0x%04X" % newest["event_id"]] + ([known] if known else [])
            if newest["priority"] is not None:
                parts += ["priority %d" % newest["priority"], "OB%d" % newest["ob_nr"]]
            cause = newest.get("cause_id")
            if cause is not None:
                cause_text = event_text(cause)
                parts.append("STOP cause: 0x%04X" % cause + (" " + cause_text if cause_text else ""))
            text = ", ".join(parts)
            out["LastDiagEvent"] = _envelope("LastDiagEvent", text, _stamp_s(newest["stamp_date"], newest["stamp_time"]))
    elif kind == "PerfHealth":
        scan = _load(scanning).get("value")
        names = [name for name, _at in cfg["health_slots"]]
        for slot_name, kept in zip(names, (health_1, health_2)):
            slot = msg.get("slots", {}).get(slot_name)
            if slot:
                before = _load(kept)
                value, state = _health(slot, before, now, scan)
                out["Health" + slot_name] = _envelope("Health", value, now)
                out["stateHealth" + slot_name] = state
                if before.get("value") != value:
                    out["transitionHealth" + slot_name] = transition(slot_name, "Health", value, before.get("value"), now, cfg["plc_id"])
    return json.dumps(out)


def scanning(seq, state, via=None, now=None, plc="PLC01"):
    """The path's Seq heartbeat: CpuScanning is false once Seq has not moved for FROZEN_S. The first reading only
    baselines. A heartbeat is also proof the path answers, so it refreshes lastOk. A change of the verdict (and the
    first one after a broker start) is also a transition for the historian."""
    now = time.time() if now is None else float(now)
    try:
        value = int(float(seq))
    except (TypeError, ValueError):
        return json.dumps({})
    kept, out = _load(state), {"lastOk": str(int(now * 1000))}
    moved = now if kept.get("seq") != value else kept.get("moved", now)
    state_out = {"seq": value, "moved": moved}
    if "seq" in kept:
        verdict = now - moved < FROZEN_S
        out["CpuScanning"] = _envelope("CpuScanning", verdict, now)
        state_out["value"] = verdict
        if "value" not in kept or kept["value"] != verdict:
            out["transition"] = transition(via or "", "CpuScanning", verdict, kept.get("value"), now, _plc(plc)["plc_id"])
    out["state"] = json.dumps(state_out)
    return json.dumps(out)


def scanning_for(seq, state, via, plc):
    """scanning() for the named PLC, as a LoT action calls it (the trailing plc, no clock argument)."""
    return scanning(seq, state, via, None, plc)


def live_path(_tick, plc="PLC01"):
    cfg = _plc(plc)
    paths = list(cfg["paths"])
    return paths[int(time.time() / cfg["read_s"]) % len(paths)]


def _asset(via, plc="PLC01"):
    cfg = _plc(plc)
    route, endpoint, hardware = cfg["paths"][via]
    leaves = {}
    for leaf, (units, datatype, cadence, source, raw) in leaves_of(cfg["family"]).items():
        entry = {"derivation": "measured" if source in ("PerfMon", "PerfDiag") and leaf not in ("ClockSkew", "ReadDuration") else "derived",
                 "class": "health", "datatype": datatype, "cadence": cadence, "raw": source + ": " + raw}
        if units is not None:
            entry["units"] = units
        leaves[leaf] = entry
    doc = {"schemaVersion": 1, "deviceTag": cfg["plc_id"], "vendor": "Siemens", "model": cfg["model"], "type": "plc",
           "specificAssetIds": [{"name": "orderNumber", "value": cfg["order_no"]}],
           "installedAt": cfg["installed"],
           "source": {"kind": "native-route", "route": route, "endpoint": endpoint, "via": hardware,
                      "raw": "siemens/site01/" + (plc or "PLC01") + "/" + via + "/"},
           "leaves": leaves}
    return json.dumps(doc, separators=(",", ":"))


def registration(_tick, plc="PLC01", now=None):
    """The PLC as the historian's registry holds it, for plc_ingest() (kind "Register"), once a minute with _asset's
    cadence: {"reg": <message as JSON text>} when due, else {"reg": null}, so the LoT action publishes only then. The row is
    added when missing and never overwritten (the writer can only INSERT): a later change is an UPDATE by hand or by
    schema.sql. Its model goes into plc_model the same way, interfaces unknown until plc_fleet.sql lists the model."""
    now = time.time() if now is None else float(now)
    if int(now / (2 * READ_SECONDS)) % ASSET_EVERY != 0:
        return json.dumps({"reg": None})
    cfg = _plc(plc)
    msg = {"plc_id": cfg["plc_id"], "via": list(cfg["paths"])[0], "kind": "Register", "family": cfg["family"],
           "model": cfg["model"], "order_no": cfg["order_no"], "paths": list(cfg["paths"]), "area": cfg.get("area"),
           "firmware": cfg.get("firmware"), "description": cfg.get("description"), "clock_zone": "UTC"}
    return json.dumps({"reg": json.dumps(msg, separators=(",", ":"))})


def liveness(via, last_ok, status, now=None, plc="PLC01"):
    """DeviceStatus of one path from the age of its last good read or heartbeat. Its timestamp is the transition
    time, so it is kept from the retained envelope while the value holds. _asset rides along once a minute."""
    now = time.time() if now is None else float(now)
    try:
        age = now - int(last_ok) / 1000.0
    except (TypeError, ValueError):
        age = None
    value = "offline" if age is None or age > OFFLINE_S else "online" if age <= ONLINE_S else "stale"
    before = _load(status)
    if before.get("value") == value and before.get("timestamp"):
        out = {"DeviceStatus": json.dumps(before, separators=(",", ":"))}
    else:
        out = {"DeviceStatus": _envelope("DeviceStatus", value, now),
               "transition": transition(via, "DeviceStatus", value, before.get("value"), now, _plc(plc)["plc_id"])}
    if int(now / (2 * READ_SECONDS)) % ASSET_EVERY == 0:
        out["asset"] = _asset(via, plc)
    return json.dumps(out)


def liveness_for(via, last_ok, status, plc):
    """liveness() for the named PLC, as a LoT action calls it (the trailing plc, no clock argument)."""
    return liveness(via, last_ok, status, None, plc)


# ---- BEGIN GENERATED from sql/s7_event_text.csv: never edit by hand ----
# Siemens' published event texts (A5E02790053-01 chapter 35), a lookup for diagnostics: see s7_event_text.sql's header.
EVENT_TEXT = {
    0x1381: "Request for manual warm restart",
    0x1382: "Request for automatic warm restart",
    0x1383: "Request for manual hot restart",
    0x1384: "Request for automatic hot restart",
    0x1385: "Request for manual cold restart",
    0x1386: "Request for automatic cold restart",
    0x1387: "Master CPU: request for manual cold restart",
    0x1388: "Master CPU: request for automatic cold restart",
    0x138A: "Master CPU: request for manual warm restart",
    0x138B: "Master CPU: request for automatic warm restart",
    0x138C: "Standby CPU: request for manual hot restart",
    0x138D: "Standby CPU: request for automatic hot restart",
    0x2521: "BCD conversion error",
    0x2522: "Area length error when reading",
    0x2523: "Area length error when writing",
    0x2524: "Area error when reading",
    0x2525: "Area error when writing",
    0x2526: "Timer number error",
    0x2527: "Counter number error",
    0x2528: "Alignment error when reading",
    0x2529: "Alignment error when writing",
    0x2530: "Write error when accessing the DB",
    0x2531: "Write error when accessing the DI",
    0x2532: "Block number error when opening a DB",
    0x2533: "Block number error when opening a DI",
    0x2534: "Block number error when calling an FC",
    0x2535: "Block number error when calling an FB",
    0x253A: "DB not loaded",
    0x253C: "FC not loaded",
    0x253D: "SFC not loaded",
    0x253E: "FB not loaded",
    0x253F: "SFB not loaded",
    0x2942: "I/O access error, reading",
    0x2943: "I/O access error, writing",
    0x3501: "Cycle time exceeded.",
    0x3502: "User interface (OB or FRB) request error",
    0x3505: "Time-of-day interrupt(s) skipped due to new clock setting",
    0x3506: "Time-of-day interrupt(s) skipped when changing to RUN after HOLD",
    0x3507: "Multiple OB request errors caused internal buffer overflow",
    0x3508: "Synchronous cycle interrupt-timing error",
    0x3509: "Interrupt loss due to excess interrupt load",
    0x350A: "Resume RUN mode after CiR",
    0x350B: "Technology synchronization interrupt - timing error",
    0x3921: "BATTF: failure on at least one backup battery of the central rack/ problem eliminated",
    0x3821: "BATTF: failure on at least one backup battery of the central rack/ problem eliminated",
    0x3922: "BAF: failure of backup voltage on central rack/ problem eliminated",
    0x3822: "BAF: failure of backup voltage on central rack/ problem eliminated",
    0x3923: "24 volt supply failure on central rack / problem eliminated",
    0x3823: "24 volt supply failure on central rack / problem eliminated",
    0x3925: "BATTF: failure on at least one backup battery of the redundant central rack/ problem eliminated",
    0x3825: "BATTF: failure on at least one backup battery of the redundant central rack/ problem eliminated",
    0x3926: "BAF: failure of backup voltage on redundant central rack/ problem eliminated",
    0x3826: "BAF: failure of backup voltage on redundant central rack/ problem eliminated",
    0x3917: "24 volt supply failure on redundant central rack / problem eliminated",
    0x3827: "24 volt supply failure on redundant central rack / problem eliminated",
    0x3931: "BATTF: failure of at least one backup battery of the expansion rack/ problem eliminated",
    0x3831: "BATTF: failure of at least one backup battery of the expansion rack/ problem eliminated",
    0x3932: "BAF: failure of backup voltage on expansion rack/ problem eliminated",
    0x3832: "BAF: failure of backup voltage on expansion rack/ problem eliminated",
    0x3933: "24 volt supply failure on at least one expansion rack/ problem eliminated",
    0x3833: "24 volt supply failure on at least one expansion rack/ problem eliminated",
    0x3942: "Diagnostic interrupt (module/submodule fault or maintenance required or both)",
    0x3842: "Diagnostic interrupt (module/submodule OK)",
    0x3951: "PROFINET IO submodule removed",
    0x3954: "PROFINET IO interface submodule/submodule removed",
    0x3854: "PROFINET IO interface submodule/submodule and matches the configured interface submodule/submodule",
    0x3855: "PROFINET IO interface submodule/submodule inserted, but does not match the configured interface submodule/submodule",
    0x3856: "PROFINET IO interface submodule/submodule inserted, but error in module parameter assignment",
    0x3858: "PROFINET IO interface submodule access error corrected",
    0x3861: "Module/interface module inserted, module type OK",
    0x3961: "Module/interface module removed, cannot be addressed",
    0x3863: "Module/interface module plugged in, but wrong module type",
    0x3864: "Module/interface module plugged in, but causing problem (type ID unreadable)",
    0x3865: "Module plugged in, but error in module parameter assignment",
    0x3866: "Module can be addressed again, load voltage error removed",
    0x3966: "Module cannot be addressed, load voltage error",
    0x3367: "Start of module reconfiguration",
    0x3267: "End of module reconfiguration",
    0x3968: "Module reconfiguration has ended with error",
    0x3571: "Nesting depth too high in nesting levels",
    0x3572: "Nesting depth for Master Control Relays too high",
    0x3573: "Nesting depth too high after synchronous errors",
    0x3574: "Nesting depth for block calls (U stack) too high",
    0x3575: "Nesting depth for block calls (B stack) too high",
    0x3576: "Local data allocation error",
    0x3578: "Unknown instruction",
    0x357A: "Jump instruction to target outside of the block",
    0x3981: "Interface error entering state",
    0x3881: "Interface error leaving state",
    0x3582: "Memory error detected and corrected by operating system",
    0x3583: "Accumulation of detected and corrected memo errors",
    0x3585: "Error in the PC operating system (only with Win AC controllers)",
    0x3986: "Performance of an H-Sync link negatively affected",
    0x3587: "Multi-bit memory error detected and corrected",
    0x35A1: "User interface (OB or FRB) not found",
    0x35A2: "OB not loaded (started by SFC or operating system due to configuration)",
    0x35A3: "Error when operating system accesses a block",
    0x35A4: "PROFINET Interface DB cannot be addressed",
    0x34A4: "PROFINET Interface DB can be addressed again",
    0x39B1: "I/O access error when updating the process image input table",
    0x39B2: "I/O access error when transferring the process image to the output modules",
    0x39B3: "I/O access error when updating the process image input table",
    0x38B3: "I/O access error when updating the process image input table",
    0x39B4: "I/O access error when transferring the process image to the output modules",
    0x38B4: "I/O access error when transferring the process image to the output modules",
    0x38C1: "Expansion rack operational again (1 to 21), leaving state",
    0x39C1: "Expansion rack failure (1 to 21), entering state",
    0x38C2: "Expansion rack operational again but mismatch between setpoint and actual configuration",
    0x39C3: "Distributed I/Os: master system failure entering state",
    0x39C4: "Distributed I/Os: station failure, entering state",
    0x38C4: "Distributed I/Os: station failure, leaving state",
    0x38C5: "Distributed I/Os: station return with problem",
    0x38C6: "Expansion rack operational again, but error(s) in module parameter assignment",
    0x38C7: "DP: station operational again, but error(s) in module parameter assignment",
    0x38C8: "DP: station operational again, but mismatch between setpoint and actual configuration",
    0x39CA: "PROFINET IO system failure",
    0x39CB: "PROFINET IO station failure",
    0x38CB: "PROFINET IO station operational again",
    0x38CC: "PROFINET IO station return with problem",
    0x39CD: "PROFINET IO station operational again, but expected configuration does not match actual configuration",
    0x39CE: "PROFINET IO station operational again, but error(s) in module parameter assignment",
    0x35D2: "Diagnostic entries cannot be sent at present",
    0x35D3: "Synchronization frames cannot be sent",
    0x35D4: "Illegal time jump resulting from synchronization",
    0x35D5: "Error adopting the synchronization time",
    0x35E1: "Incorrect frame ID in GD",
    0x35E2: "GD packet status cannot be entered in DB",
    0x35E3: "Frame length error in GD",
    0x35E4: "Illegal GD packet number received",
    0x35E5: "Error accessing DB in communication SFBs for configured S7 connections",
    0x35E6: "GD total status cannot be entered in DB",
    0x4300: "Backed-up power on",
    0x4301: "Mode transition from STOP to STARTUP",
    0x4302: "Mode transition from STARTUP to RUN",
    0x4303: "STOP caused by stop switch being activated",
    0x4304: "STOP caused by PG STOP operation or by SFB 20 \"STOP\"",
    0x4305: "HOLD: breakpoint reached",
    0x4306: "HOLD: breakpoint exited",
    0x4307: "Memory reset started by PG operation",
    0x4308: "Memory reset started by switch setting",
    0x4309: "Memory reset started automatically (power on not backed up)",
    0x430A: "HOLD exited, transition to STOP",
    0x430D: "STOP caused by other CPU in multicomputing",
    0x430E: "Memory reset executed",
    0x430F: "STOP on the module due to STOP on a CPU",
    0x4510: "STOP violation of the CPU's data range",
    0x4318: "Start of CiR",
    0x4319: "CiR completed",
    0x4520: "DEFECTIVE: STOP not possible",
    0x4521: "DEFECTIVE: failure of instruction processing processor",
    0x4522: "DEFECTIVE: failure of clock chip",
    0x4523: "DEFECTIVE: failure of clock pulse generator",
    0x4524: "DEFECTIVE: failure of timer update function",
    0x4525: "DEFECTIVE: failure of multicomputing synchronization",
    0x4926: "DEFECTIVE: failure of the watchdog for I/O access",
    0x4527: "DEFECTIVE: failure of I/O access monitoring",
    0x4528: "DEFECTIVE: failure of scan time monitoring",
    0x4530: "DEFECTIVE: memory test error in internal memory",
    0x4931: "STOP or DEFECTIVE: memory test error in memory submodule",
    0x4532: "DEFECTIVE: failure of core resources",
    0x4933: "Checksum error",
    0x4934: "DEFECTIVE: memory not available",
    0x4935: "DEFECTIVE: cancelled by watchdog/processor exceptions",
    0x4536: "DEFECTIVE: switch defective",
    0x4540: "STOP: Memory expansion of the internal work memory has gaps. First memory expansion too small or missing.",
    0x4541: "STOP caused by priority class system",
    0x4542: "STOP caused by object management system",
    0x4543: "STOP caused by test functions",
    0x4544: "STOP caused by diagnostic system",
    0x4545: "STOP caused by communication system",
    0x4546: "STOP caused by CPU memory management",
    0x4547: "STOP caused by process image management",
    0x4548: "STOP caused by I/O management",
    0x4949: "STOP caused by continuous hardware interrupt",
    0x454A: "STOP caused by configuration: an OB deselected with STEP 7 was being loaded into the CPU during STARTUP",
    0x494D: "STOP caused by I/O error",
    0x494E: "STOP caused by power failure",
    0x494F: "STOP caused by configuration error",
    0x4550: "DEFECTIVE: internal system error",
    0x4555: "No restart possible, monitoring time elapsed",
    0x4556: "STOP: memory reset request from communication system / due to data inconsistency",
    0x4357: "Module watchdog started",
    0x4358: "All modules are ready for operation",
    0x4959: "One or more modules not ready for operation",
    0x4562: "STOP caused by programming error (OB not loaded or not possible",
    0x4563: "STOP caused by I/O access error (OB not loaded or not possible",
    0x4567: "STOP caused by H event",
    0x4568: "STOP caused by time error (OB not loaded or not possible)",
    0x456A: "STOP caused by diagnostic interrupt (OB not loaded or not possible)",
    0x456B: "STOP caused by removing/inserting module (OB not loaded or not possible)",
    0x456C: "STOP caused by CPU hardware error (OB not loaded or not possible, or no FRB)STOP",
    0x456D: "STOP caused by program sequence error (OB not loaded or not possible)",
    0x456E: "STOP caused by communication error (OB not loaded or not possible)",
    0x456F: "STOP caused by rack failure OB (OB not loaded or not possible)",
    0x4570: "STOP caused by process interrupt (OB not loaded or not possible)",
    0x4571: "STOP caused by nesting stack error",
    0x4572: "STOP caused by master control relay stack error",
    0x4573: "STOP caused by exceeding the nesting depth for synchronous errors",
    0x4574: "STOP caused by exceeding interrupt stack nesting depth in the priority class stack",
    0x4575: "STOP caused by exceeding block stack nesting depth in the priority class stack",
    0x4576: "STOP caused by error when allocating the local data",
    0x4578: "STOP caused by unknown opcode",
    0x457A: "STOP caused by code length error",
    0x457B: "STOP caused by DB not being loaded on on-board I/Os",
    0x497C: "STOP caused by integrated technology",
    0x457D: "Reset/clear request because the version of the internal interface to the integrated technology was changed.",
    0x457F: "STOP caused by STOP command",
    0x4580: "STOP: back-up buffer contents inconsistent (no transition to RUN)",
    0x4590: "STOP caused by overloading the internal functions",
    0x49A0: "STOP caused by parameter assignment error or non-permissible variation of setpoint and actual extension: Start-up blocked.",
    0x49A1: "STOP caused by parameter assignment error: memory reset request",
    0x49A2: "STOP caused by error in parameter modification: startup disabled",
    0x49A3: "STOP caused by error in parameter modification: memory reset request",
    0x49A4: "STOP: inconsistency in configuration data",
    0x49A5: "STOP: distributed I/Os: inconsistency in the loaded configuration information",
    0x49A6: "STOP: distributed I/Os: invalid configuration information",
    0x49A7: "STOP: distributed I/Os: no configuration information",
    0x49A8: "STOP: error indicated by the interface module for the distributed I/Os",
    0x43B0: "Firmware update / backup was successful",
    0x49B1: "Firmware update data incorrect",
    0x49B2: "Firmware update: hardware version does not match firmware",
    0x49B3: "Firmware update: module type does not match firmware",
    0x43B4: "Error in firmware fuse",
    0x43B6: "Firmware updates canceled by redundant modules",
    0x49D0: "LINK-UP aborted due to violation of coordination rules",
    0x49D1: "LINK-UP/UPDATE sequence aborted",
    0x49D2: "Standby CPU changed to STOP due to STOP on the master CPU during link-up",
    0x43D3: "STOP on standby CPU",
    0x49D4: "STOP on a master, since partner CPU is also a master (link-up error)",
    0x45D5: "LINK-UP rejected due to mismatched CPU memory configuration of the sub-PLC",
    0x45D6: "LINK-UP rejected due to mismatched system program of the sub-PLC",
    0x49D7: "LINK-UP rejected due to change in user program or in configuration",
    0x45D8: "DEFECTIVE: hardware fault detected due to other error",
    0x45D9: "STOP due to SYNC module error",
    0x45DA: "STOP due to synchronization error between H CPUs",
    0x43DC: "Abort during link-up with switchover",
    0x45DD: "LINK-UP rejected due to running test or other online functions",
    0x43DE: "Updating aborted due to monitoring time being exceeded during the n-th attempt, new update attempt initiated",
    0x43DF: "Updating aborted for final time due to monitoring time being exceeded after completing the maximum amount of attempts. User intervention required.",
    0x43E0: "Change from solo mode after link-up",
    0x43E1: "Change from link-up after updating",
    0x43E2: "Change from updating to redundant mode",
    0x43E3: "Master CPU: change from redundant mode to solo mode",
    0x43E4: "Standby CPU: change from redundant mode after error-search mode",
    0x43E5: "Standby CPU: change from error-search mode after link-up or STOP",
    0x43E6: "Link-up aborted on the standby CPU",
    0x43E7: "Updating aborted on the standby CPU",
    0x43E8: "Standby CPU: change from link-up after startup",
    0x43E9: "Standby CPU: change from startup after updating",
    0x43F1: "Reserve-master switchover",
    0x43F2: "Coupling of incompatible H-CPUs blocked by system program",
    0x42F3: "Checksum error detected and corrected by the operating system",
    0x42F4: "Standby CPU: connection/update via SFC90 is locked in the master CPU",
    0x530D: "New startup information in the STOP mode",
    0x510F: "A problem as occurred with WinLC. This problem has caused the CPU to go into STOP mode or has caused a fault in the CPU.",
    0x5311: "Startup despite Not Ready message from module(s)",
    0x5545: "Start of System reconfiguration in RUN mode",
    0x5445: "Start of System reconfiguration in RUN mode",
    0x5380: "Diagnostic buffer entries of interrupt and asynchronous errors disabled",
    0x5395: "Distributed I/Os: reset of a DP master",
    0x5481: "All licenses for runtime software are complete again.",
    0x5498: "No more inconsistency with DP master systems due to CiR",
    0x5581: "One or several licenses for runtime software are missing.",
    0x558A: "Difference between the MLFB of the configured and inserted CPU",
    0x558B: "Difference in the firmware version of the configured and inserted CPU",
    0x5598: "Start of possible inconsistency with DP master systems due to CiR",
    0x5960: "Parameter assignment error when switching",
    0x5961: "Parameter assignment error",
    0x5962: "Parameter assignment error preventing startup",
    0x5963: "Parameter assignment error with memory reset request",
    0x5966: "Parameter assignment error when switching",
    0x5967: "Parameter assignment error: unknown configuration data",
    0x5968: "Emergency address of an Ethernet interface enabled/disabled",
    0x5858: "Emergency address of an Ethernet interface enabled/disabled",
    0x5969: "Parameter assignment error with startup blocked",
    0x596A: "PROFINET IO: IP address of an IO device already present",
    0x596B: "IP address of an Ethernet interface already exists",
    0x596C: "Name of an Ethernet interface already exists",
    0x596D: "The existing network configuration does not mach the system requirements or configuration.",
    0x5371: "Distributed I/Os: end of the synchronization with a DP master",
    0x5979: "Diagnostic message from DP interface: EXTF LED on/off",
    0x5879: "Diagnostic message from DP interface: EXTF LED on/off",
    0x597C: "DP Global Control command failed or moved",
    0x59A0: "The interrupt can not be associated in the CPU",
    0x59A1: "Configuration error in the integrated technology",
    0x53A2: "Download of technology firmware successful",
    0x59A3: "Error when downloading the integrated technology",
    0x53A4: "Download of technology DB not successful",
    0x55A5: "Version conflict: internal interface with integrated technology",
    0x55A6: "The maximum number of technology objects has been exceeded.",
    0x55A7: "A technology DB of this type is already present.",
    0x53FF: "Reset to factory setting",
    0x6316: "Interface error when starting programmable controller",
    0x6390: "Formatting of Micro Memory Card complete",
    0x6500: "Connection ID exists twice on module",
    0x6501: "Connection resources inadequate",
    0x6502: "Error in the connection description",
    0x6510: "CFB structure error detected in instance DB when evaluating EPROM",
    0x6514: "GD packet number exists twice on the module",
    0x6515: "Inconsistent length specifications in GD configuration information",
    0x6521: "No memory submodule and no internal memory available",
    0x6522: "Illegal memory submodule: replace submodule and reset memory",
    0x6523: "Memory reset request due to error accessing submodule",
    0x6524: "Memory reset request due to error in block header",
    0x6526: "Memory reset request due to memory replacement",
    0x6527: "Memory replaced, therefore restart not possible",
    0x6528: "Object handling function in the STOP/HOLD mode, no restart possible",
    0x6529: "No startup possible during the \"load user program\" function",
    0x652A: "No startup because block exists twice in user memory",
    0x652B: "No startup because block is too long for submodule - replace submodule",
    0x652C: "No startup due to illegal OB on submodule",
    0x6532: "No startup because illegal configuration information on submodule",
    0x6533: "Memory reset request because of invalid submodule content",
    0x6534: "No startup: block exists more than once on submodule",
    0x6535: "No startup: not enough memory to transfer block from submodule",
    0x6536: "No startup: submodule contains an illegal block number",
    0x6537: "No startup: submodule contains a block with an illegal length",
    0x6538: "Local data or write-protection ID (for DB) of a block illegal for CPU",
    0x6539: "Illegal command in block (detected by compiler)",
    0x653A: "Memory reset request because local OB data on submodule too short",
    0x6543: "No startup: illegal block type",
    0x6544: "No startup: attribute \"relevant for processing\" illegal",
    0x6545: "Source language illegal",
    0x6546: "Maximum number of blocks of one block type reached",
    0x6547: "Parameter assignment error assigning parameters to modules (not on P bus, cancel download)",
    0x6548: "Plausibility error during block check",
    0x6549: "Structure error in block",
    0x6550: "A block has an error in the CRC",
    0x6551: "A block has no CRC",
    0x6353: "Firmware update: Start of firmware download over the network",
    0x6253: "Firmware update: End of firmware download over the network",
    0x6560: "SCAN overflow",
    0x6881: "Interface error leaving state",
    0x6905: "Resource problem on configured connections/eliminated",
    0x6805: "Resource problem on configured connections/eliminated",
    0x6981: "Interface error entering state",
    0x72A2: "Failure of a DP master or a DP master system",
    0x72A3: "Redundancy restored on the DP slave",
    0x7301: "Loss of redundancy (1 of 2) due to failure of a CPU",
    0x7302: "Loss of redundancy (1 of 2) due to STOP on the standby triggered by user",
    0x7303: "H system (1 of 2) changed to redundant mode",
    0x7323: "Discrepancy found in operating system data",
    0x7331: "Standby-master switchover due to master failure",
    0x7333: "Standby-master switchover due to system modification during runtime",
    0x7334: "Standby-master switchover due to communication error at the synchronization module",
    0x7340: "Synchronization error in user program due to elapsed wait time",
    0x7341: "Synchronization error in user program due to waiting at different synchronization points",
    0x7342: "Synchronization error in operating system due to waiting at different synchronization points",
    0x7343: "Synchronization error in operating system due to elapsed wait time",
    0x7344: "Synchronization error in operating system due to incorrect data",
    0x734A: "The \"Re-enable\" job triggered by SFC 90 \"H_CTRL\" was executed.",
    0x73A3: "Loss of redundancy on the DP slave",
    0x73D8: "Safety mode disabled",
    0x73E0: "Loss of redundancy in communication/ problem eliminated",
    0x72E0: "Loss of redundancy in communication/ problem eliminated",
    0x7520: "Error in RAM comparison",
    0x7521: "Error in comparison of process image output value",
    0x7522: "Error in comparison of memory bits, timers, or counters",
    0x73C1: "Update process canceled",
    0x73C2: "Updating aborted due to monitoring time being exceeded during the n-th attempt (1 \u2264 n \u2264 max. possible number of update attempts after abort due to excessive monitoring time)",
    0x75D1: "Safety program: Internal CPU error",
    0x75D2: "Safety program error: Cycle time time-out",
    0x75D6: "Data corrupted in safety program prior to the output to F I/O",
    0x75D7: "Data corrupted in safety program prior to the output to partner F CPU",
    0x75D9: "Invalid REAL number in a DB",
    0x75DA: "Safety program: Error in safety data format",
    0x73DB: "Safety program: safety mode enabled/disabled",
    0x72DB: "Safety program: safety mode enabled/disabled",
    0x75DC: "Runtime group, internal protocol error",
    0x75DD: "Safety program: Shutdown of a fail-save runtime group enabled/disabled",
    0x74DD: "Safety program: Shutdown of a fail-save runtime group enabled/disabled",
    0x75DE: "Safety program: Shutdown of the F program enabled/disabled",
    0x74DE: "Safety program: Shutdown of the F program enabled/disabled",
    0x75DF: "Start / end of F program initialization",
    0x74DF: "Start / end of F program initialization",
    0x75E1: "Safety program: Error in FB \"F_PLK\" or \"F_PLK_O\" or F_CYC_CO\" or \"F_TEST\" or \"F_TESTC\"",
    0x7934: "Standby-master switchover due to connection problem at the SYNC module",
    0x7950: "Synchronization module missing",
    0x7951: "Change at the SYNC module without Power On",
    0x7952: "SYNC module removed/inserted",
    0x7852: "SYNC module removed/inserted",
    0x7953: "Change at the SYNC-module without reset",
    0x7954: "SYNC module: rack number assigned twice",
    0x7955: "SYNC module error/eliminated",
    0x7855: "SYNC module error/eliminated",
    0x7956: "Illegal rack number set on SYNC module",
    0x7960: "Redundant I/O: Time-out of discrepancy time at digital input, error is not yet localized",
    0x7961: "Redundant I/O, digital input error: Signal change after expiration of the discrepancy time",
    0x7962: "Redundant I/O: Digital input error",
    0x7963: "Redundant I/O: Digital input channel error",
    0x7964: "Redundant I/O: Digital input error: Signal change after discrepancy time elapsed",
    0x796F: "Redundant I/O: The I/O was globally depassivated",
    0x7970: "Redundant I/O: Digital output error",
    0x7971: "Redundant I/O: Digital output channel error",
    0x7980: "Redundant I/O: Time-out of discrepancy time at analog input",
    0x7981: "Redundant I/O: Analog input error",
    0x7982: "Redundant I/O: Analog input channel error",
    0x7983: "Redundant I/O: Discrepancy time for analog input channel elapsed",
    0x7984: "Redundant I/O: Analog input channel error",
    0x7990: "Redundant I/O: Analog output error",
    0x7991: "Redundant I/O: Analog output channel error",
    0x73A2: "Failure of a DP master or a DP master system",
    0x79D3: "Communication error between PROFIsafe and F I/O",
    0x78D3: "Communication error between PROFIsafe and F I/O",
    0x79D4: "Error in safety relevant communication between F CPUs",
    0x78D4: "Error in safety relevant communication between F CPUs",
    0x79D5: "Error in safety relevant communication between F CPUs",
    0x78D5: "Error in safety relevant communication between F CPUs",
    0x75E2: "Safety program: Area length error",
    0x79E3: "F-I/O device input channel passivated",
    0x78E3: "F-I/O device input channel depassivated",
    0x79E4: "F-I/O device output channel passivated",
    0x78E4: "F-I/O device output channel depassivated",
    0x79E5: "F-I/O device passivated",
    0x78E5: "F-I/O device depassivated",
    0x79E6: "Inconsistent safety program",
    0x79E7: "Simulation block (F system block) loaded",
    0x73E8: "Consistency of the safety program verified by testing",
    0x73E9: "Consistency of the safety program cannot be checked",
    0x9001: "Automatic mode",
    0x9101: "Manual mode",
    0x9190: "User parameter assignment error entering/leaving",
    0x9090: "User parameter assignment error entering/leaving",
    0x91F0: "Overflow",
    0x91F1: "Underflow",
    0x91F2: "Division by 0",
    0x91F3: "Illegal calculation operation",
}
EVENT_TEXT_MASKED = {
    0xF0FF: {
        0x8000: "Module fault/OK",
        0x8001: "Internal error",
        0x8002: "External error",
        0x8003: "Channel error",
        0x8004: "No external auxiliary voltage",
        0x8005: "No front connector",
        0x8006: "No parameter assignment",
        0x8007: "Incorrect parameters in module",
        0x8030: "User submodule incorrect/not found",
        0x8031: "Communication problem",
        0x8032: "Operating mode: RUN/STOP (STOP: entering state, RUN: leaving state)",
        0x8033: "Time monitoring responded (watchdog)",
        0x8034: "Internal module power failure",
        0x8035: "BATTF: battery exhausted",
        0x8036: "Total backup failed",
        0x8040: "Expansion rack failed",
        0x8041: "Processor failure",
        0x8042: "EPROM error",
        0x8043: "RAM error",
        0x8044: "ADC/DAC error",
        0x8045: "Fuse blown",
        0x8046: "Hardware interrupt lost",
        0x8050: "Configuration/parameter assignment error",
        0x8051: "Common mode error",
        0x8052: "Short circuit to phase",
        0x8053: "Short circuit to ground",
        0x8054: "Wire break",
        0x8055: "Reference channel error",
        0x8056: "Below measuring range",
        0x8057: "Above measuring range",
        0x8060: "Configuration/parameter assignment error",
        0x8061: "Common mode error",
        0x8062: "Short circuit to phase",
        0x8063: "Short circuit to ground",
        0x8064: "Wire break",
        0x8066: "No load voltage",
        0x8070: "Configuration/parameter assignment error",
        0x8071: "Chassis ground fault",
        0x8072: "Short circuit to phase (sensor)",
        0x8073: "Short circuit to ground (sensor)",
        0x8074: "Wire break",
        0x8075: "No sensor power supply",
        0x8080: "Configuration/parameter assignment error",
        0x8081: "Chassis ground fault",
        0x8082: "Short circuit to phase",
        0x8083: "Short circuit to ground",
        0x8084: "Wire break",
        0x8085: "Fuse tripped",
        0x8086: "No load voltage",
        0x8087: "Excess temperature",
        0x80B0: "Counter module, signal A faulty",
        0x80B1: "Counter module, signal B faulty",
        0x80B2: "Counter module, signal N faulty",
        0x80B3: "Counter module, incorrect value passed between the channels",
        0x80B4: "Counter module, 5.2 V sensor supply faulty",
        0x80B5: "Counter module, 24 V sensor supply faulty",
        0x9002: "OPEN/CLOSED, ON/OFF",
        0x9003: "Manual command enable",
        0x9004: "Unit protective command (OPEN/CLOSED)",
        0x9005: "Process enable",
        0x9006: "System protection command",
        0x9007: "Process value monitoring responded",
        0x9008: "Manipulated variable monitoring responded",
        0x9009: "System deviation greater than permitted",
        0x900A: "Limit position error",
        0x900B: "Runtime error",
        0x900C: "Command execution error (sequencer)",
        0x900D: "Operating status running > OPEN",
        0x900E: "Operating status running > CLOSED",
        0x900F: "Command blocking",
        0x9011: "Process status OPEN/ON",
        0x9012: "Process status CLOSED/OFF",
        0x9013: "Process status intermediate position",
        0x9014: "Process status ON via AUTO",
        0x9015: "Process status ON via manual",
        0x9016: "Process status ON via protective command",
        0x9017: "Process status OFF via AUTO",
        0x9018: "Process status OFF via manual",
        0x9019: "Process status OFF via protective command",
        0x9021: "Function error on approach",
        0x9022: "Function error on leaving",
        0x9031: "Actuator (DE/WE) limit position OPEN",
        0x9032: "Actuator (DE/WE) limit position not OPEN",
        0x9033: "Actuator (DE/WE) limit position CLOSED",
        0x9034: "Actuator (DE/WE) limit position not CLOSED",
        0x9041: "Illegal status, tolerance time elapsed",
        0x9042: "Illegal status, tolerance time not elapsed",
        0x9043: "Interlock error, tolerance time = 0",
        0x9044: "Interlock error, tolerance time > 0",
        0x9045: "No reaction",
        0x9046: "Final status exited illegally, tolerance time = 0",
        0x9047: "Final status exited illegally, tolerance time > 0",
        0x9050: "Upper limit of signal range USR",
        0x9051: "Upper limit of measuring range UMR",
        0x9052: "Lower limit of signal range LSR",
        0x9053: "Lower limit of measuring range LMR",
        0x9054: "Upper alarm limit UAL",
        0x9055: "Upper warning limit UWL",
        0x9056: "Upper tolerance limit UTL",
        0x9057: "Lower tolerance limit LTL",
        0x9058: "Lower warning limit LWL",
        0x9059: "Lower alarm limit LAL",
        0x9060: "GRAPH7 step entering/leaving",
        0x9061: "GRAPH7 interlock error",
        0x9062: "GRAPH7 execution error",
        0x9063: "GRAPH7 error noted",
        0x9064: "GRAPH7 error acknowledged",
        0x9070: "Trend exceeded in positive direction",
        0x9071: "Trend exceeded in negative direction",
        0x9072: "No reaction",
        0x9073: "Final state exited illegally",
        0x9080: "Limit value exceeded, tolerance time = 0",
        0x9081: "Limit value exceeded, tolerance time > 0",
        0x9082: "Below limit value, tolerance time = 0",
        0x9083: "Below limit value, tolerance time > 0",
        0x9084: "Gradient exceeded, tolerance time = 0",
        0x9085: "Gradient exceeded, tolerance time > 0",
        0x9086: "Below gradient, tolerance time = 0",
        0x9087: "Below gradient, tolerance time > 0",
    },
    0xF000: {
        0xA000: "Events available for user",
        0xB000: "Events available for user",
    },
}
# ---- END GENERATED ----

# ---- BEGIN GENERATED from sql/s7_1500_ob_fault.csv: never edit by hand ----
# Siemens' meaning of each S7-1500 error-OB code (sql/s7_1500_ob_fault.csv cites the page of each).
OB_FAULT_TEXT = {
    (80, "Fault_ID", 0x0001): "Cycle time exceeded",
    (80, "Fault_ID", 0x0002): "The requested OB is still being processed",
    (80, "Fault_ID", 0x0005): "Expired time interrupt due to time jump",
    (80, "Fault_ID", 0x0006): "Expired time interrupt upon re-entry into RUN after HOLD",
    (80, "Fault_ID", 0x0007): "Overflow of the OB request buffer for the current priority class",
    (80, "Fault_ID", 0x0008): "Isochronous mode interrupt: time error",
    (80, "Fault_ID", 0x0009): "Interrupt loss due to high interrupt load",
    (80, "Fault_ID", 0x000B): "Technology synchronization interrupt: time error",
    (80, "Fault_ID", 0x000C): "Cycle time exceeded for the second time (S7-1500 R/H only)",
    (82, "IO_state bit", 0x0000): "Good",
    (82, "IO_state bit", 0x0001): "Deactivated",
    (82, "IO_state bit", 0x0002): "Maintenance required",
    (82, "IO_state bit", 0x0003): "Maintenance demanded",
    (82, "IO_state bit", 0x0004): "Error",
    (82, "IO_state bit", 0x0005): "Not available",
    (82, "IO_state bit", 0x0006): "Qualified",
    (82, "IO_state bit", 0x0007): "Not available",
    (82, "IO_state bit", 0x000F): "With bit 4 or 5: 0 network error, 1 hardware error",
    (83, "Event_Class/Fault_ID", 0x3951): "IO module removed",
    (83, "Event_Class/Fault_ID", 0x3954): "IO submodule removed",
    (83, "Event_Class/Fault_ID", 0x3854): "IO submodule inserted, matches the configuration",
    (83, "Event_Class/Fault_ID", 0x3855): "Inserted, does not match the configured submodule",
    (83, "Event_Class/Fault_ID", 0x3856): "Inserted, error in module parameter assignment",
    (83, "Event_Class/Fault_ID", 0x3857): "Inserted, with fault or maintenance",
    (83, "Event_Class/Fault_ID", 0x3858): "IO submodule, access error corrected",
    (83, "Event_Class/Fault_ID", 0x3961): "Module removed or not responding",
    (83, "Event_Class/Fault_ID", 0x3861): "Module inserted",
    (83, "Event_Class/Fault_ID", 0x3367): "R/H CiR reparameterization started",
    (83, "Event_Class/Fault_ID", 0x3267): "R/H CiR reparameterization finished",
    (83, "Event_Class/Fault_ID", 0x3268): "R/H CiR reparameterization rejected",
    (83, "Event_Class/Fault_ID", 0x3971): "R/H central module removed",
    (83, "Event_Class/Fault_ID", 0x3872): "R/H central module inserted",
    (83, "Event_Class/Fault_ID", 0x3873): "R/H central module inserted with a fault",
    (86, "Event_Class/Fault_ID", 0x39C3): "DP master system failure",
    (86, "Event_Class/Fault_ID", 0x39C4): "DP slave failure",
    (86, "Event_Class/Fault_ID", 0x38C4): "DP slave return",
    (86, "Event_Class/Fault_ID", 0x39CA): "PROFINET IO system failure",
    (86, "Event_Class/Fault_ID", 0x39CB): "PROFINET IO device failure",
    (86, "Event_Class/Fault_ID", 0x38CB): "PROFINET IO device return",
    (86, "Event_Class/Fault_ID", 0x38CC): "PN IO device returned with fault or maintenance",
    (86, "Event_Class/Fault_ID", 0x38CD): "PN IO device returned with a preset/actual configuration difference",
    (86, "Event_Class/Fault_ID", 0x38CE): "PN IO device returned with an error in module configuration",
    (86, "Event_Class/Fault_ID", 0x39F8): "Some submodules of a PN I-device failed",
    (86, "Event_Class/Fault_ID", 0x38F8): "Some submodules of a PN I-device returned",
    (86, "Event_Class/Fault_ID", 0x38F9): "Some submodules of a PN I-device returned with a configuration difference",
    (121, "Fault_ID", 0x0000): "Maximum nesting depth of block calls exceeded",
    (121, "Fault_ID", 0x0003): "NULL pointer used to address an operand",
    (121, "Fault_ID", 0x0004): "Unknown instruction",
    (121, "Fault_ID", 0x0005): "Stop instruction",
    (121, "Fault_ID", 0x0020): "Addressed string has incorrect length information",
    (121, "Fault_ID", 0x0021): "BCD conversion error",
    (121, "Fault_ID", 0x0022): "Area length error when reading",
    (121, "Fault_ID", 0x0023): "Area length error when writing",
    (121, "Fault_ID", 0x0024): "Area error when reading",
    (121, "Fault_ID", 0x0025): "Area error when writing",
    (121, "Fault_ID", 0x0026): "Error in timer number",
    (121, "Fault_ID", 0x0027): "Error in counter number",
    (121, "Fault_ID", 0x0028): "Read access to byte/word/dword with a pointer whose bit address is not zero",
    (121, "Fault_ID", 0x0029): "Access to byte/word/dword with a pointer whose bit address is not zero (printed twice by Siemens; presumably the write case)",
    (121, "Fault_ID", 0x002C): "NULL pointer",
    (121, "Fault_ID", 0x0030): "Write access to a write-protected global DB",
    (121, "Fault_ID", 0x0031): "Write access to a write-protected instance DB",
    (121, "Fault_ID", 0x0032): "DB number error, global DB",
    (121, "Fault_ID", 0x0033): "DB number error, instance DB",
    (121, "Fault_ID", 0x0034): "Number error during FC call",
    (121, "Fault_ID", 0x0035): "Number error during FB call",
    (121, "Fault_ID", 0x0038): "Type-safe DB not loaded",
    (121, "Fault_ID", 0x0039): "DB not defined as type-safe",
    (121, "Fault_ID", 0x003A): "Access to a DB that is not loaded",
    (121, "Fault_ID", 0x003B): "DB does not exist",
    (121, "Fault_ID", 0x003C): "FC not loaded",
    (121, "Fault_ID", 0x003D): "SFC not loaded",
    (121, "Fault_ID", 0x003E): "FB not loaded",
    (121, "Fault_ID", 0x003F): "SFB not available",
    (121, "Fault_ID", 0x0050): "Type-safe DB not loaded",
    (121, "Fault_ID", 0x0051): "DB not type-safe",
    (121, "Fault_ID", 0x0075): "Maximum nesting depth exceeded",
    (121, "Fault_ID", 0x0076): "Maximum available local data exceeded",
    (121, "Fault_ID", 0x0077): "Block call with unsuitable parameter interface",
    (121, "Fault_ID", 0x00A1): "Write access to a write-protected tag",
    (121, "Fault_ID", 0x00A2): "Access to a tag with an invalid numerical value",
    (121, "BlockType", 0x0001): "OB",
    (121, "BlockType", 0x0002): "FC",
    (121, "BlockType", 0x0003): "FB",
    (121, "BlockType", 0x0004): "SFC",
    (121, "BlockType", 0x0005): "SFB",
    (121, "BlockType", 0x0006): "DB",
    (122, "BlockType", 0x0001): "OB",
    (122, "BlockType", 0x0002): "FC",
    (122, "BlockType", 0x0003): "FB",
    (122, "BlockType", 0x0004): "SFC",
    (122, "BlockType", 0x0005): "SFB",
    (122, "BlockType", 0x0006): "DB",
    (122, "Fault_ID", 0x0042): "I/O access error, reading",
    (122, "Fault_ID", 0x0043): "I/O access error, writing",
    (122, "Area", 0x0001): "Direct (peripheral) access to inputs",
    (122, "Area", 0x0002): "Direct (peripheral) access to outputs",
    (122, "Area", 0x0081): "Access to the process image of the inputs",
    (122, "Area", 0x0082): "Access to the process image of the outputs",
    (122, "Reaction", 0x0000): "Ignore",
    (122, "Reaction", 0x0001): "Replace the incorrect value",
    (122, "Reaction", 0x0002): "Skip the command",
    (121, "Reaction", 0x0000): "Ignore",
    (121, "Reaction", 0x0001): "Replace the incorrect value",
    (121, "Reaction", 0x0002): "Skip the command",
    (121, "Reaction", 0x0003): "Programmed error handling",
    (80, "Classic FLT_ID", 0x0001): "Cycle time exceeded",
    (80, "Classic FLT_ID", 0x0002): "The called OB is still being executed",
    (80, "Classic FLT_ID", 0x0005): "Elapsed time-of-day interrupt due to moving the clock forward",
    (80, "Classic FLT_ID", 0x0006): "Elapsed time-of-day interrupt on return to RUN after HOLD",
    (80, "Classic FLT_ID", 0x0007): "Overflow of OB request buffer for the current priority class",
    (80, "Classic FLT_ID", 0x0008): "Synchronous-cycle interrupt time error",
    (80, "Classic FLT_ID", 0x0009): "Interrupt loss due to high interrupt load",
    (80, "Classic FLT_ID", 0x000A): "Resume RUN after CiR",
    (80, "Classic FLT_ID", 0x000B): "Technology synchronization interrupt",
    (82, "Classic EV_CLASS/FLT_ID", 0x3942): "Diagnostic interrupt, incoming event: a problem, or a component requires maintenance",
    (82, "Classic EV_CLASS/FLT_ID", 0x3842): "Diagnostic interrupt, outgoing event: no problem and no maintenance left",
    (82, "Classic fault bit", 0x0040): "Module is defective",
    (82, "Classic fault bit", 0x0041): "Internal fault",
    (82, "Classic fault bit", 0x0042): "External fault",
    (82, "Classic fault bit", 0x0043): "Channel fault",
    (82, "Classic fault bit", 0x0044): "External voltage failed",
    (82, "Classic fault bit", 0x0045): "Front panel connector not plugged in",
    (82, "Classic fault bit", 0x0046): "Module is not configured",
    (82, "Classic fault bit", 0x0047): "Incorrect parameters on module",
    (82, "Classic fault bit", 0x004C): "Channel information exists",
    (82, "Classic fault bit", 0x004D): "User information exists",
    (82, "Classic fault bit", 0x004E): "Diagnostic interrupt from substitute",
    (82, "Classic fault bit", 0x004F): "Maintenance required",
    (82, "Classic fault bit", 0x0050): "Submodule is missing or has an error",
    (82, "Classic fault bit", 0x0051): "Communication problem",
    (82, "Classic fault bit", 0x0052): "Module in STOP",
    (82, "Classic fault bit", 0x0053): "Watchdog timer responded",
    (82, "Classic fault bit", 0x0054): "Internal power supply failed",
    (82, "Classic fault bit", 0x0055): "Battery exhausted",
    (82, "Classic fault bit", 0x0056): "Entire backup failed",
    (82, "Classic fault bit", 0x0057): "Maintenance demanded",
    (82, "Classic fault bit", 0x0058): "Expansion rack failure",
    (82, "Classic fault bit", 0x0059): "Processor failure",
    (82, "Classic fault bit", 0x005A): "EPROM fault",
    (82, "Classic fault bit", 0x005B): "RAM fault",
    (82, "Classic fault bit", 0x005C): "ADC/DAC error",
    (82, "Classic fault bit", 0x005D): "Fuse tripped",
    (82, "Classic fault bit", 0x005E): "Hardware interrupt lost",
    (82, "Classic module class", 0x0000): "CPU",
    (82, "Classic module class", 0x0003): "DP standard slave",
    (82, "Classic module class", 0x0004): "IM",
    (82, "Classic module class", 0x0005): "Analog module",
    (82, "Classic module class", 0x0008): "Function module",
    (82, "Classic module class", 0x000B): "I slave",
    (82, "Classic module class", 0x000C): "CP",
    (82, "Classic module class", 0x000F): "Digital module",
    (83, "Classic EV_CLASS/FLT_ID", 0x3951): "PROFINET IO module removed",
    (83, "Classic EV_CLASS/FLT_ID", 0x3954): "PROFINET IO submodule removed",
    (83, "Classic EV_CLASS/FLT_ID", 0x3854): "PROFINET IO submodule inserted and matches configured submodule",
    (83, "Classic EV_CLASS/FLT_ID", 0x3855): "PROFINET IO submodule inserted, but does not match configured submodule",
    (83, "Classic EV_CLASS/FLT_ID", 0x3856): "PROFINET IO submodule inserted, but error with module parameters",
    (83, "Classic EV_CLASS/FLT_ID", 0x3858): "PROFINET IO submodule, access error corrected",
    (83, "Classic EV_CLASS/FLT_ID", 0x3961): "Module removed or not responding",
    (83, "Classic EV_CLASS/FLT_ID", 0x3861): "Module inserted. Module type OK",
    (83, "Classic EV_CLASS/FLT_ID", 0x3863): "Module inserted but incorrect module type",
    (83, "Classic EV_CLASS/FLT_ID", 0x3864): "Module inserted but problem (module ID cannot be read)",
    (83, "Classic EV_CLASS/FLT_ID", 0x3865): "Module inserted but error in module parameter assignment",
    (83, "Classic EV_CLASS/FLT_ID", 0x3966): "Module not responding, load voltage error",
    (83, "Classic EV_CLASS/FLT_ID", 0x3866): "Module responds again, load voltage error corrected",
    (83, "Classic EV_CLASS/FLT_ID", 0x3367): "Start of module reconfiguration",
    (83, "Classic EV_CLASS/FLT_ID", 0x3267): "End of module reconfiguration",
    (83, "Classic EV_CLASS/FLT_ID", 0x3968): "Module reconfiguration terminated with error",
    (86, "Classic EV_CLASS/FLT_ID", 0x39C1): "Expansion rack failure",
    (86, "Classic EV_CLASS/FLT_ID", 0x38C1): "Expansion rack operational again",
    (86, "Classic EV_CLASS/FLT_ID", 0x38C2): "Expansion rack operational again, with a discrepancy between expected and actual configuration",
    (86, "Classic EV_CLASS/FLT_ID", 0x39C3): "Distributed I/O: failure of a DP master system",
    (86, "Classic EV_CLASS/FLT_ID", 0x39C4): "Failure of a DP station",
    (86, "Classic EV_CLASS/FLT_ID", 0x38C4): "Return of a DP station",
    (86, "Classic EV_CLASS/FLT_ID", 0x39C5): "Return of the station, but station faulty",
    (86, "Classic EV_CLASS/FLT_ID", 0x38C5): "Return of the station, but station faulty",
    (86, "Classic EV_CLASS/FLT_ID", 0x38C6): "Expansion rack operational again, but still an error with module parameters",
    (86, "Classic EV_CLASS/FLT_ID", 0x38C7): "Return of a DP station, but error in module parameter assignment",
    (86, "Classic EV_CLASS/FLT_ID", 0x38C8): "Return of a DP station, however discrepancy in configured and actual configuration",
    (86, "Classic EV_CLASS/FLT_ID", 0x32C9): "Enabling a DP slave with SFC 12 D_ACT_DP, MODE=3",
    (86, "Classic EV_CLASS/FLT_ID", 0x33C9): "Disabling a DP slave with SFC 12 D_ACT_DP, MODE=4",
    (86, "Classic EV_CLASS/FLT_ID", 0x39CA): "PROFINET IO system failure",
    (86, "Classic EV_CLASS/FLT_ID", 0x39CB): "PROFINET IO station failure",
    (86, "Classic EV_CLASS/FLT_ID", 0x38CB): "PROFINET IO station return",
    (86, "Classic EV_CLASS/FLT_ID", 0x39CC): "PROFINET IO station return with problem",
    (86, "Classic EV_CLASS/FLT_ID", 0x38CC): "PROFINET IO station return with problem",
    (86, "Classic EV_CLASS/FLT_ID", 0x38CD): "PROFINET IO station return, expected and actual configuration differ",
    (86, "Classic EV_CLASS/FLT_ID", 0x38CE): "PROFINET IO station return, error in module configuration parameters",
    (86, "Classic EV_CLASS/FLT_ID", 0x32CF): "Enabling a PROFINET IO device with SFC 12 D_ACT_DP, MODE=3",
    (86, "Classic EV_CLASS/FLT_ID", 0x33CF): "Disabling a PROFINET IO device with SFC 12 D_ACT_DP, MODE=4",
    (121, "Classic FLT_ID", 0x0021): "BCD conversion error",
    (121, "Classic FLT_ID", 0x0022): "Area length error when reading",
    (121, "Classic FLT_ID", 0x0023): "Area length error when writing",
    (121, "Classic FLT_ID", 0x0024): "Range error when reading",
    (121, "Classic FLT_ID", 0x0025): "Range error when writing",
    (121, "Classic FLT_ID", 0x0026): "Error for timer number",
    (121, "Classic FLT_ID", 0x0027): "Error for counter number",
    (121, "Classic FLT_ID", 0x0028): "Read access to a byte, word or double word with a pointer whose bit address is not 0",
    (121, "Classic FLT_ID", 0x0029): "Write access to a byte, word or double word with a pointer whose bit address is not 0",
    (121, "Classic FLT_ID", 0x0030): "Write access to a write-protected global DB",
    (121, "Classic FLT_ID", 0x0031): "Write access to a write-protected instance DB",
    (121, "Classic FLT_ID", 0x0032): "DB number error accessing a global DB",
    (121, "Classic FLT_ID", 0x0033): "DB number error accessing an instance DB",
    (121, "Classic FLT_ID", 0x0034): "FC number error in FC call",
    (121, "Classic FLT_ID", 0x0035): "FB number error in FB call",
    (121, "Classic FLT_ID", 0x003A): "Access to a DB that has not been loaded",
    (121, "Classic FLT_ID", 0x003C): "Access to an FC that has not been loaded",
    (121, "Classic FLT_ID", 0x003D): "Access to an SFC that is not available",
    (121, "Classic FLT_ID", 0x003E): "Access to an FB that has not been loaded",
    (121, "Classic FLT_ID", 0x003F): "Access to an SFB that is not available",
    (121, "Classic BLK_TYPE", 0x0088): "OB",
    (121, "Classic BLK_TYPE", 0x008A): "DB",
    (121, "Classic BLK_TYPE", 0x008C): "FC",
    (121, "Classic BLK_TYPE", 0x008E): "FB",
    (122, "Classic BLK_TYPE", 0x0088): "OB",
    (122, "Classic BLK_TYPE", 0x008C): "FC",
    (122, "Classic BLK_TYPE", 0x008E): "FB",
    (121, "Classic memory area", 0x0000): "I/O area",
    (121, "Classic memory area", 0x0001): "process-image input table",
    (121, "Classic memory area", 0x0002): "process-image output table",
    (121, "Classic memory area", 0x0003): "bit memory",
    (121, "Classic memory area", 0x0004): "global DB",
    (121, "Classic memory area", 0x0005): "instance DB",
    (121, "Classic memory area", 0x0006): "own local data",
    (121, "Classic memory area", 0x0007): "local data of caller",
    (122, "Classic memory area", 0x0000): "I/O area",
    (122, "Classic memory area", 0x0001): "process image of the inputs",
    (122, "Classic memory area", 0x0002): "process image of the outputs",
    (121, "Classic access type", 0x0000): "bit access",
    (121, "Classic access type", 0x0001): "byte access",
    (121, "Classic access type", 0x0002): "word access",
    (121, "Classic access type", 0x0003): "double word access",
    (122, "Classic access type", 0x0000): "bit access",
    (122, "Classic access type", 0x0001): "byte access",
    (122, "Classic access type", 0x0002): "word access",
    (122, "Classic access type", 0x0003): "double word access",
    (122, "Classic FLT_ID", 0x0042): "I/O access error, reading",
    (122, "Classic FLT_ID", 0x0043): "I/O access error, writing",
}
# ---- END GENERATED (s7_ob_fault) ----
```

## Route

**The CPU over its PN interface.** `RACK 0`, `SLOT 1` is an S7-1500 CPU. The route reads each DB **whole** when its
read topic gets a message: `DB_PerfMon` as 2,058 DWORDs, `DB_PerfDiag` as 81, `DB_PerfHealth` as 11. A whole
`DB_PerfMon` read took about 0.02 s on a CPU 1511-1 PN with a 480-byte PDU. It also polls the record counter `Seq`
every 5 s, and the health loop's `Life` every second; `Echo` is writable, through `…/Echo/set`.

Replace the address with your CPU's. If you chose other DB numbers in TIA, change them here too. Each `ADD EVENT` and the
writable tag count as actions on the licence.

**Reads:** `siemens/site01/PLC02/PN/<Kind>/read`, `…/PerfHealth/Echo/set`. **Writes:** `…/<Kind>/raw`,
`…/PerfMon/Seq`, `…/PerfHealth/Life`, `…/PerfHealth/Echo`.

```lot
DEFINE ROUTE S7PLC02PN WITH TYPE SIEMENS_S7
    ADD S7_CONFIG
        WITH IP "192.168.1.20"
        WITH CPU_TYPE "S71500"
        WITH RACK 0
        WITH SLOT 1
        WITH PORT 102
        WITH CONNECTION_TYPE "OP"
        WITH READ_TIMEOUT 30000
        WITH WRITE_TIMEOUT 30000
    ADD MAPPING Heartbeat
        WITH EVERY 5 SECONDS
        ADD TAG Seq
            WITH ADDRESS "DB880.DBD8"
            WITH ADDRESS_TYPE "DATABLOCK"
            WITH DATA_TYPE "DINT"
            WITH SOURCE_TOPIC "siemens/site01/PLC02/PN/PerfMon/Seq"
    ADD MAPPING HealthLoop
        WITH EVERY 1 SECOND
        ADD TAG Life
            WITH ADDRESS "DB882.DBB26"
            WITH ADDRESS_TYPE "DATABLOCK"
            WITH DATA_TYPE "BYTE"
            WITH SOURCE_TOPIC "siemens/site01/PLC02/PN/PerfHealth/Life"
        ADD TAG Echo
            WITH ADDRESS "DB882.DBB27"
            WITH ADDRESS_TYPE "DATABLOCK"
            WITH DATA_TYPE "BYTE"
            WITH SOURCE_TOPIC "siemens/site01/PLC02/PN/PerfHealth/Echo"
            WITH WRITABLE "true"
            WITH DESTINATION_TOPIC "siemens/site01/PLC02/PN/PerfHealth/Echo/set"
    ADD EVENT ReadPerfMon
        WITH SOURCE_TOPIC "siemens/site01/PLC02/PN/PerfMon/read"
        WITH DESTINATION_TOPIC "siemens/site01/PLC02/PN/PerfMon/raw"
        WITH QUERY "{operation: READ, address: DB880.DBD0, data_type: DWORD, count: 2058}"
    ADD EVENT ReadPerfDiag
        WITH SOURCE_TOPIC "siemens/site01/PLC02/PN/PerfDiag/read"
        WITH DESTINATION_TOPIC "siemens/site01/PLC02/PN/PerfDiag/raw"
        WITH QUERY "{operation: READ, address: DB881.DBD0, data_type: DWORD, count: 81}"
    ADD EVENT ReadPerfHealth
        WITH SOURCE_TOPIC "siemens/site01/PLC02/PN/PerfHealth/read"
        WITH DESTINATION_TOPIC "siemens/site01/PLC02/PN/PerfHealth/raw"
        WITH QUERY "{operation: READ, address: DB882.DBD0, data_type: DWORD, count: 11}"
```

## Storage

**One store route for every PLC of the broker**: each decoded read becomes one statement, `plc_ingest()`, which
unpacks it, stores every fact once and the evidence of which path delivered it. A store route per PLC would spend a
connector each. The same cell is in both family notebooks.

**Reads:** `siemens/site01/+/+/+/decoded`. **Writes:** the historian.

```lot
DEFINE ROUTE S7Store WITH TYPE POSTGRESQL
    ADD SQL_CONFIG
        WITH SERVER GET ENV "TIMESCALE_HOST"
        WITH PORT 5432
        WITH DATABASE GET ENV "TIMESCALE_DB"
        WITH USERNAME GET ENV "TIMESCALE_USER"
        WITH PASSWORD GET SECRET "TIMESCALE_PASSWORD"
    ADD EVENT IngestRead
        WITH SOURCE_TOPIC "siemens/site01/+/+/+/decoded"
        WITH QUERY "SELECT plc_ingest('{value.json}'::jsonb)"
```

## Actions

### The reads

**One read every 10 s**, in turn over the three DBs, so each DB is read every 30 s and no two reads overlap. The ring
holds 120 one-second records, so a 30 s read of it leaves room for an outage of 90 s. The time of asking is kept, so
the decoder can report how long the read took.

**Reads:** nothing. **Writes:** `siemens/site01/PLC02/PN/<Kind>/read`, the kept `…/<Kind>/asked`.

```lot
DEFINE ACTION S7PLC02ReadTick
ON EVERY 10 SECONDS DO
    CALL PYTHON "S7PerfDecode.next_read"
        WITH ("tick", "PLC02")
        RETURN AS {target}
    CALL PYTHON "S7PerfDecode.now_ms"
        WITH ("tick")
        RETURN AS {askedMs}
    KEEP TOPIC "siemens/site01/PLC02/" + {target} + "/asked" WITH {askedMs}
    PUBLISH TOPIC "siemens/site01/PLC02/" + {target} + "/read" WITH "go"
```

**Each raw read becomes one decoded message**, for the store route and the UNS action.

**Reads:** `siemens/site01/PLC02/+/+/raw`. **Writes:** `siemens/site01/PLC02/<path>/<Kind>/decoded`.

```lot
DEFINE ACTION S7PLC02Decode
ON TOPIC "siemens/site01/PLC02/+/+/raw" DO
    SET "via" WITH TOPIC POSITION 4
    SET "kind" WITH TOPIC POSITION 5
    SET "asked" WITH (GET TOPIC "siemens/site01/PLC02/" + {via} + "/" + {kind} + "/asked")
    CALL PYTHON "S7PerfDecode.decode"
        WITH (PAYLOAD, {via}, {kind}, {asked}, "PLC02")
        RETURN AS {decoded}
    PUBLISH TOPIC "siemens/site01/PLC02/" + {via} + "/" + {kind} + "/decoded" WITH {decoded}
```

### The health loop

**What the PLC shows as `Life` goes straight back as `Echo`**, on the same path. The PLC moves `Life` on only when it
sees its value come back, so the counter's speed is the speed of the whole circle: PLC → broker → PLC. The PLC counts a
loss when no confirmation came for 5 s, and a wrong value as `BadEcho`.

**Reads:** `siemens/site01/PLC02/+/PerfHealth/Life`. **Writes:** `…/PerfHealth/Echo/set`, which the route writes into the PLC.

```lot
DEFINE ACTION S7PLC02Echo
ON TOPIC "siemens/site01/PLC02/+/PerfHealth/Life" DO
    SET "via" WITH TOPIC POSITION 4
    PUBLISH TOPIC "siemens/site01/PLC02/" + {via} + "/PerfHealth/Echo/set" WITH PAYLOAD
```

### The verdicts

**`CpuScanning`, from the record counter.** The kit closes one record a second, in the program cycle. When `Seq` has not
moved for 10 s while the route still reads it, the CPU is not scanning: STOP. The DBs stay readable in STOP, so the
path itself stays online: this is how a CPU in STOP is told apart from a broken path. Each change of the verdict also
goes to the historian.

**Reads:** `siemens/site01/PLC02/+/PerfMon/Seq`, the kept scan state. **Writes:** `acme/site01/Automation/PLC02/<path>/CpuScanning`
(retained), the kept `…/PerfMon/scanState` and `…/lastOk`, `…/Transition/decoded`.

```lot
DEFINE ACTION S7PLC02Scan
ON TOPIC "siemens/site01/PLC02/+/PerfMon/Seq" DO
    SET "via" WITH TOPIC POSITION 4
    SET "kept" WITH (GET TOPIC "siemens/site01/PLC02/" + {via} + "/PerfMon/scanState")
    CALL PYTHON "S7PerfDecode.scanning_for"
        WITH (PAYLOAD, {kept}, {via}, "PLC02")
        RETURN AS {scan}
    IF (GET JSON "state" IN {scan} AS STRING) != "null" THEN
        KEEP TOPIC "siemens/site01/PLC02/" + {via} + "/PerfMon/scanState" WITH (GET JSON "state" IN {scan} AS STRING)
        KEEP TOPIC "siemens/site01/PLC02/" + {via} + "/lastOk" WITH (GET JSON "lastOk" IN {scan} AS STRING)
    IF (GET JSON "CpuScanning" IN {scan} AS STRING) != "null" THEN
        PUBLISH TOPIC "acme/site01/Automation/PLC02/" + {via} + "/CpuScanning" WITH (GET JSON "CpuScanning" IN {scan} AS STRING) RETAIN QOS1
    IF (GET JSON "transition" IN {scan} AS STRING) != "null" THEN
        PUBLISH TOPIC "siemens/site01/PLC02/" + {via} + "/Transition/decoded" WITH (GET JSON "transition" IN {scan} AS STRING)
```

**`DeviceStatus` per path**, by the age of the last good read or `Seq` heartbeat on it: `online` up to 20 s, `stale`
up to 90 s, `offline` beyond. Its timestamp is the time of the change. The retained `_asset` (model, order number,
route, endpoint and every leaf) is re-asserted once a minute.

Once a minute it also **registers the PLC** in the historian: `S7PerfDecode.registration` returns the PLC as the
decoder's `PLCS` declares it (family, model, order number, paths, area, firmware), and the store route hands it to
`plc_ingest()`, which adds the `plc_registry` row (and the model) only when missing. A new PLC of a known family is its
LoT and its `PLCS` entry: nothing to change in the database.

**Reads:** the kept `…/lastOk`, the retained `DeviceStatus`. **Writes:** `acme/site01/Automation/PLC02/<path>/DeviceStatus`
and `_asset` (retained), `…/Transition/decoded`, `…/Register/decoded`.

```lot
DEFINE ACTION S7PLC02Liveness
ON EVERY 10 SECONDS DO
    CALL PYTHON "S7PerfDecode.live_path"
        WITH ("tick", "PLC02")
        RETURN AS {via}
    SET "lastOk" WITH (GET TOPIC "siemens/site01/PLC02/" + {via} + "/lastOk")
    SET "before" WITH (GET TOPIC "acme/site01/Automation/PLC02/" + {via} + "/DeviceStatus")
    CALL PYTHON "S7PerfDecode.liveness_for"
        WITH ({via}, {lastOk}, {before}, "PLC02")
        RETURN AS {live}
    PUBLISH TOPIC "acme/site01/Automation/PLC02/" + {via} + "/DeviceStatus" WITH (GET JSON "DeviceStatus" IN {live} AS STRING) RETAIN QOS1
    IF (GET JSON "transition" IN {live} AS STRING) != "null" THEN
        PUBLISH TOPIC "siemens/site01/PLC02/" + {via} + "/Transition/decoded" WITH (GET JSON "transition" IN {live} AS STRING)
    IF (GET JSON "asset" IN {live} AS STRING) != "null" THEN
        PUBLISH TOPIC "acme/site01/Automation/PLC02/" + {via} + "/_asset" WITH (GET JSON "asset" IN {live} AS STRING) RETAIN QOS1
    CALL PYTHON "S7PerfDecode.registration"
        WITH ("tick", "PLC02")
        RETURN AS {reg}
    IF (GET JSON "reg" IN {reg} AS STRING) != "null" THEN
        PUBLISH TOPIC "siemens/site01/PLC02/" + {via} + "/Register/decoded" WITH (GET JSON "reg" IN {reg} AS STRING)
```

### The UNS

**Each decoded read becomes the leaves it carries**, each a retained envelope. Only the newest value goes to the UNS:
the older records of a read are in the historian, and so is the cycle-time histogram. The decoder builds every payload;
this action only routes them. `Health` of the PN slot comes from the read of `DB_PerfHealth`: `unknown` while
`CpuScanning` is false (the loop runs in the program cycle, so nothing it shows is current in STOP), `corrupt` for
300 s after `BadEcho` rose, `stalled` while the PLC reports no confirmation, else `ok`. A change of `Health` also goes
to the historian. An S7-1500 has no diagnostic buffer the program can read, so there is no `LastDiagEvent`; it counts
OB83, OB121 and OB122 as well, and `LastFault` is the newest call of any error OB, in Siemens' words.

**Reads:** `siemens/site01/PLC02/+/+/decoded`, the retained `CpuScanning`, the kept health state. **Writes:** the leaves
under `acme/site01/Automation/PLC02/<path>/`, the kept `…/lastOk` and `…/PerfHealth/unsState`, `…/Transition/decoded`.

```lot
DEFINE ACTION S7PLC02Uns
ON TOPIC "siemens/site01/PLC02/+/+/decoded" DO
    SET "via" WITH TOPIC POSITION 4
    SET "base" WITH "acme/site01/Automation/PLC02/" + {via}
    SET "scan" WITH (GET TOPIC "acme/site01/Automation/PLC02/" + {via} + "/CpuScanning")
    SET "hp" WITH (GET TOPIC "siemens/site01/PLC02/PN/PerfHealth/unsState")
    CALL PYTHON "S7PerfDecode.uns_leaves"
        WITH (PAYLOAD, {scan}, {hp}, "none")
        RETURN AS {leaves}
    IF (GET JSON "lastOk" IN {leaves} AS STRING) != "null" THEN
        KEEP TOPIC "siemens/site01/PLC02/" + {via} + "/lastOk" WITH (GET JSON "lastOk" IN {leaves} AS STRING)
    IF (GET JSON "CycleMin" IN {leaves} AS STRING) != "null" THEN
        PUBLISH TOPIC {base} + "/CycleMin" WITH (GET JSON "CycleMin" IN {leaves} AS STRING) RETAIN QOS1
        PUBLISH TOPIC {base} + "/CycleAvg" WITH (GET JSON "CycleAvg" IN {leaves} AS STRING) RETAIN QOS1
        PUBLISH TOPIC {base} + "/CycleMax" WITH (GET JSON "CycleMax" IN {leaves} AS STRING) RETAIN QOS1
        PUBLISH TOPIC {base} + "/CommLoad" WITH (GET JSON "CommLoad" IN {leaves} AS STRING) RETAIN QOS1
        PUBLISH TOPIC {base} + "/OB80Events" WITH (GET JSON "OB80Events" IN {leaves} AS STRING) RETAIN QOS1
        PUBLISH TOPIC {base} + "/OB82Events" WITH (GET JSON "OB82Events" IN {leaves} AS STRING) RETAIN QOS1
        PUBLISH TOPIC {base} + "/OB86Events" WITH (GET JSON "OB86Events" IN {leaves} AS STRING) RETAIN QOS1
        PUBLISH TOPIC {base} + "/BootTime" WITH (GET JSON "BootTime" IN {leaves} AS STRING) RETAIN QOS1
        PUBLISH TOPIC {base} + "/ClockSkew" WITH (GET JSON "ClockSkew" IN {leaves} AS STRING) RETAIN QOS1
    IF (GET JSON "ReadDuration" IN {leaves} AS STRING) != "null" THEN
        PUBLISH TOPIC {base} + "/ReadDuration" WITH (GET JSON "ReadDuration" IN {leaves} AS STRING) RETAIN QOS1
    IF (GET JSON "LastFault" IN {leaves} AS STRING) != "null" THEN
        PUBLISH TOPIC {base} + "/LastFault" WITH (GET JSON "LastFault" IN {leaves} AS STRING) RETAIN QOS1
        PUBLISH TOPIC {base} + "/OB83Events" WITH (GET JSON "OB83Events" IN {leaves} AS STRING) RETAIN QOS1
        PUBLISH TOPIC {base} + "/OB121Events" WITH (GET JSON "OB121Events" IN {leaves} AS STRING) RETAIN QOS1
        PUBLISH TOPIC {base} + "/OB122Events" WITH (GET JSON "OB122Events" IN {leaves} AS STRING) RETAIN QOS1
    IF (GET JSON "HealthPN" IN {leaves} AS STRING) != "null" THEN
        KEEP TOPIC "siemens/site01/PLC02/PN/PerfHealth/unsState" WITH (GET JSON "stateHealthPN" IN {leaves} AS STRING)
        PUBLISH TOPIC "acme/site01/Automation/PLC02/PN/Health" WITH (GET JSON "HealthPN" IN {leaves} AS STRING) RETAIN QOS1
    IF (GET JSON "transitionHealthPN" IN {leaves} AS STRING) != "null" THEN
        PUBLISH TOPIC "siemens/site01/PLC02/PN/Transition/decoded" WITH (GET JSON "transitionHealthPN" IN {leaves} AS STRING)
```

## Rules (Growth or Enterprise)

**Not a cell of this notebook, because Community refuses it:** on broker 2.22.0 Community, `-addRule` answers "RBAC /
Topic Access Control rules require a Growth or Enterprise license" (measured). With such a licence, deploy it last, after
the accounts exist, in a new cell.

Publishing on the raw plane writes into the PLC (`…/Echo/set` goes straight into `DB_PerfHealth`) or makes the route
read, so only the broker's own logic should do it. The route publishes under the broker's own identity, an **empty user
name**, and an action's `PUBLISH TOPIC` is not subject to publish Rules; the rule admits `""` beside root, which is only
sound with **anonymous login off**. Applications read the UNS under `acme/site01/Automation/…`. Priority 200 sits in the
user band (100–999999; 0–99 are reserved). It has not been verified by the template's harness, which runs on Community.

```text
DEFINE RULE S7RawPlanePublish WITH PRIORITY 200 FOR Publish TO TOPIC "siemens/#"
    IF USER IS "root" OR USER IS "" THEN
        ALLOW
    ELSE
        DENY
```

**On Community there is no topic fence:** any account that can log in can publish on `siemens/#`. What a forged message
can do there is bounded by the route: it writes only the one `Echo` byte of `DB_PerfHealth` (the health loop then shows
`corrupt`), and a read request only makes the route read. Give applications no broker account they do not need, keep
anonymous login off, and keep the broker on the OT network.

## How to verify

1. Within 30 s, `siemens/site01/PLC02/PN/PerfMon/raw` shows `{"success":true,…,"count":2058,…}` and `…/decoded` a
   message with `"records":[…]` and no `"error"`. A layout error names the version and size it found: wrong DB number,
   optimized access still on, or an older kit.
2. `acme/site01/Automation/PLC02/PN/` fills: `CpuScanning` true, `Health` `ok`, `DeviceStatus` `online`, `CycleAvg` your
   CPU's cycle, `CommLoad` its communication load.
3. `LastFault` reads `none` on a CPU whose error OBs are not called, or the newest call in words, e.g.
   `OB122, fault id 0x42 I/O access error, reading, FC 72, area 0x01 Direct (peripheral) access to inputs, 420 calls since the boot`.
4. Put the CPU into STOP: `CpuScanning` turns false within about 10 s, `DeviceStatus` stays `online` (the DBs still answer),
   `Health` turns `unknown`. Back to RUN: `BootTime` is the new boot.
5. In the historian: `SELECT * FROM plc_latest;` gives one row per PLC, and `plc_ob_call_text` names every error-OB call.

The template's maintainers verify every cell on a fresh 2.22.0 broker against a mock S7-1500 that plays these cases (the
echo stopped, a wrong echo, STOP and RUN, the PLC gone), with an S7-1500-form OB122 flood and classic OB82 and OB86
calls, and against a real TimescaleDB; and they check the broker log for runtime errors, because an action is compiled
when it first runs.
