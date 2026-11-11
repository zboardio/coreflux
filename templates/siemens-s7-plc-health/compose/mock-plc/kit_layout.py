"""kit_layout.py — the kit's DBs as bytes, the Python side of <family>/plc/perf_kit.scl, for the mock PLC."""
from __future__ import annotations

import struct
from datetime import datetime, timedelta

RECORD_SIZE, RING_SIZE = 68, 120
MON_SIZE, DIAG_SIZE, HEALTH_SIZE = 72 + RECORD_SIZE * RING_SIZE, 670, 44
STALE_BASE = 961   # Seq 961 + i lands in slot i, as it would have in a previous boot
HEALTH_SLOTS = {"MPI": 8, "PN": 26}   # DB_PerfHealth: one typPerfHealthSlot per path
# The spare fields: reserved in the layout, written by nothing in the kit. (offset, S7 type, DB)
SPARE = {"DB_PerfHealth.Spare6": (6, "INT", 882)}


def stamp(t: datetime) -> tuple[int, int]:
    return (t.year * 10000 + t.month * 100 + t.day,
            t.hour * 10000000 + t.minute * 100000 + t.second * 1000 + int(t.microsecond / 1000))


def pack_record(seq: int, t: datetime, flags: int = 0, comm: float = -1.0) -> bytes:
    """comm: CommLoad_pct, -1 on an S7-300 (none), RT_INFO's value on an S7-1500."""
    d, tm = stamp(t)
    return struct.pack(">iiii4f8iHh", seq, d, tm, 950, 1.0, 2.0, 1.05, comm, 900, 50, 0, 0, 0, 0, 0, 0, flags, 0)


def build_mon(boot_date: int, boot_time: int, seq: int = 0, write_idx: int = -1, stale: bool = True) -> bytes:
    b = bytearray(MON_SIZE)
    struct.pack_into(">hhhhihh7fffiiiii", b, 0, 2, RECORD_SIZE, RING_SIZE, write_idx, seq, 1000, 3, 2.0, 5.0, 10.0, 20.0, 40.0, 60.0, 100.0,
                     1.0, 2.0, 0, 0, 0, boot_date, boot_time)
    if stale:
        old = datetime(2026, 11, 1, 8, 0, 0)
        for i in range(RING_SIZE):
            b[72 + i * RECORD_SIZE:72 + (i + 1) * RECORD_SIZE] = pack_record(STALE_BASE + i, old)
    return bytes(b)


def _bcd(v: int) -> int:
    return (int(v / 10) << 4) | (v % 10)


# Bytes 2-11 (priority, OB, DatID, info 1, info 2) as a real CPU 315-2 PN/DP wrote them, from a TIA export of its
# diagnostic buffer. A mode transition has no priority (0xFF)
# and its byte 3 holds the previous/requested mode; any other ID gets priority 1, OB100.
REAL_HEAD = {0x4302: "FF68C700000008147714", 0x4301: "FF46C772430408147714", 0x4304: "FF840000000000000000",
             0x1381: "1B64C772430408147714"}


def diag_entry(event_id: int, t: datetime) -> bytes:
    ms = int(t.microsecond / 1000)
    weekday = (t.weekday() + 1) % 7 + 1   # S7 DATE_AND_TIME: 1 = Sunday
    clock = bytes(_bcd(v) for v in (t.year % 100, t.month, t.day, t.hour, t.minute, t.second, int(ms / 10))) + bytes([(ms % 10) << 4 | weekday])
    head = bytes.fromhex(REAL_HEAD[event_id]) if event_id in REAL_HEAD else struct.pack(">BBHHI", 1, 100, 0, 0, 0)
    return struct.pack(">H", event_id) + head + clock


def build_diag(now: datetime) -> bytes:
    b = bytearray(DIAG_SIZE)
    struct.pack_into(">hhi", b, 0, 1, 644, 3)
    struct.pack_into(">hhiiBB", b, 8, 80, 1, 20261102, 233000123, 0x39, 0x01)
    struct.pack_into(">6i", b, 24, 20261101, 80000000, 1080, 1, 0, 0)
    struct.pack_into(">hhh", b, 64, 2, 1, 2)
    b[74:94] = b"6ES7 315-2EH13-0AB0 "
    b[100:102], b[124:128] = b"\x00\x07", b"V\x02\x06\x07"   # SZL 0x0111 index 7: Ausbg 'V' + 2, Ausbe 6, 7 = this CPU's V2.6.7
    b[130:137] = b"S C-TST"
    b[164:176] = b"mock station"
    b[444:464] = diag_entry(0x4302, now)
    b[464:484] = diag_entry(0x4301, datetime(2026, 11, 2, 23, 30, 0, 123000))
    return bytes(b)


def build_health() -> bytes:
    b = bytearray(HEALTH_SIZE)
    struct.pack_into(">hhh", b, 0, 1, 44, 5)
    b[8] = b[26] = 1
    return bytes(b)


# ── The S7-1500 (s7-1500/plc/perf_kit.scl): DB_PerfMon's read part and DB_PerfHealth as above; DB_PerfDiag is layout 2,
# family 1500.
DIAG1500_READ, DIAG1500_SIZE = 324, 348
FAULT_OBS = (80, 82, 83, 86, 121, 122)   # the order of DB_PerfDiag.Fault[0..5]
HEALTH_SLOTS_1500 = {"Reserve": 8, "PN": 26}


# The classic form of a slot (FC_PerfFaultClassic, an OB migrated with the S7-300/400 TEMP): EvClass + 0x80, then the packing
# of the comment above typPerfFaultSlot in perf_kit.scl. As the bench's project has them: OB82 and OB86 classic.
CLASSIC = 0x80
# OB82, incoming: input module 256, byte 8 = defective + external fault + channel fault (0x0D), byte 9 = analog module with
# channel information (0x15), bytes 10-11 clear.
CLASSIC_OB82 = (0x39 | CLASSIC, 0x42, 256, 0x0D15, 0x0000)
# OB86, PROFINET IO station failure (16#CB): IO controller at 2042; RACKS_FLTD = station address 2040 (bits 16-30), bit 15
# (PROFINET), IO system ID 0, device 3.
CLASSIC_OB86 = (0x39 | CLASSIC, 0xCB, 2042, 0x07F8, 0x8003)
# OB122 as the bench's classic OB122 would record the FC 72 read: SW_FLT 16#42, BLK_NUM 72, BLK_TYPE 16#8C (FC), MEM_AREA
# 16#20 (word access, I/O area), MEM_ADDR 256.
CLASSIC_OB122 = (0x29 | CLASSIC, 0x42, 72, 0x8C20, 256)


def build_diag_1500(now: datetime, classic: bool = True, ob122: tuple | None = None) -> bytes:
    """classic: OB82 and OB86 hold a classic call each, an hour and two hours before now (the newest stays OB122's).
    ob122: the newest call's (EvClass, FaultId, Info1..3); default the S7-1500 form of the bench's FC 72 read."""
    b = bytearray(DIAG1500_SIZE)
    struct.pack_into(">hhhh", b, 0, 2, DIAG1500_READ, 1500, 0)
    struct.pack_into(">i", b, 8, 1)
    struct.pack_into(">hhii", b, 12, 122, 1, *stamp(now))
    struct.pack_into(">iii", b, 24, 20261101, 80000000, 1080)
    # OB122 once, as the bench's FC 72 reading an input: Fault_ID 16#42, BlockNr 72, BlockType 2 (FC), Area 16#01 (direct)
    struct.pack_into(">iiiBBHHH", b, 60 + 5 * 20, 1, *stamp(now), *(ob122 or (0, 0x42, 72, 2, 0x01)))
    if classic:
        struct.pack_into(">iiiBBHHH", b, 60 + 1 * 20, 1, *stamp(now - timedelta(hours=1)), *CLASSIC_OB82)
        struct.pack_into(">iiiBBHHH", b, 60 + 3 * 20, 2, *stamp(now - timedelta(hours=2)), *CLASSIC_OB86)
    struct.pack_into(">8h", b, 180, 2, 1, 1, 0, 0, 0, 0, 0)          # RUN on, ERROR off, MAINT off
    struct.pack_into(">ffff", b, 208, 3.0, 4.2, 0.4, 0.5)
    # IM0 (260..323) stays zero: the kit reads no identity on TIA V15.1 / FW V2.6 (no Get_IM_Data)
    return bytes(b)


def decode_diag_1500(raw: bytes) -> dict:
    """DB_PerfDiag layout 2, family 1500: what the bench needs to see, before the broker's decoder learns it."""
    if len(raw) < DIAG1500_READ:
        return {"error": f"{len(raw)} bytes, want {DIAG1500_READ}"}
    layout, size, family = struct.unpack_from(">hhh", raw, 0)
    if (layout, size, family) != (2, DIAG1500_READ, 1500):
        return {"error": f"not DB_PerfDiag layout 2 / family 1500: layout {layout}, size {size}, family {family}"}
    faults = {}
    for i, ob in enumerate(FAULT_OBS):
        count, d, t, ev, fid, i1, i2, i3 = struct.unpack_from(">iiiBBHHH", raw, 60 + 20 * i)
        faults[f"OB{ob}"] = {"count": count, "last": f"{d}/{t}", "ev_class": f"0x{ev:02X}", "fault_id": f"0x{fid:02X}",
                             "info": [f"0x{i1:04X}", f"0x{i2:04X}", f"0x{i3:04X}"]}
    im0 = raw[260:324]
    order = next((im0[i:i + 20].decode("ascii", "replace").strip() for i in range(0, 44) if im0[i:i + 4] == b"6ES7"), "")
    return {
        "diag_seq": struct.unpack_from(">i", raw, 8)[0],
        "fault": {"ob": struct.unpack_from(">h", raw, 12)[0], "count": struct.unpack_from(">h", raw, 14)[0],
                  "at": "%d/%d" % struct.unpack_from(">ii", raw, 16)},
        "prev_boot": "%d/%d, last Seq %d" % struct.unpack_from(">iii", raw, 24),
        "prev_count": dict(zip((f"OB{o}" for o in FAULT_OBS), struct.unpack_from(">6i", raw, 36))),
        "faults": faults,
        "led": list(struct.unpack_from(">8h", raw, 180)),
        "im_status": f"0x{struct.unpack_from('>H', raw, 196)[0]:04X}",
        "rt_ret": list(struct.unpack_from(">4h", raw, 198)),
        "comm_load_pct": round(struct.unpack_from(">f", raw, 208)[0], 2),
        "cycle_longest_shortest_last_ms": [round(v, 3) for v in struct.unpack_from(">fff", raw, 212)],
        "order_no": order,
        "im0_hex": im0.hex(),
    }
