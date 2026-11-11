#!/usr/bin/env python3
"""kit_mock.py — a python-snap7 server holding the kit's DBs, running the algorithm of plc/perf_kit.scl, started as
after a warm restart: the ring still holds a previous boot's slots. It proves the broker side, never the CPU.

The health loop is FC_PerfHealth's: Life moves on only when Echo confirms it, a value that is neither the current nor the
previous one counts BadEcho, and Age_s past LossLimit_s clears Healthy and counts a loss. A file STOP_FILE puts the mock
"into STOP": OB1 no longer runs, so Seq, Life and Age_s freeze while the DBs still answer reads. Create it
with `docker exec <mock> touch /tmp/kit-stop` and remove it to go back to RUN."""
from __future__ import annotations

import argparse
import os
import struct
import time
from datetime import datetime, timezone

import snap7
from snap7.type import SrvArea

from kit_layout import DIAG1500_SIZE, DIAG_SIZE, HEALTH_SIZE, HEALTH_SLOTS, MON_SIZE, RECORD_SIZE, RING_SIZE, build_diag, build_diag_1500
from kit_layout import build_health, build_mon, pack_record, stamp


STOP_FILE = "/tmp/kit-stop"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=102)
    ap.add_argument("--family", choices=("s7-300", "s7-1500"), default="s7-300",
                    help="s7-1500: DB_PerfDiag layout 2, and OB122 called about 2,000 times a second, as on the bench")
    a = ap.parse_args()
    now = datetime.now(timezone.utc)
    boot_date, boot_time = stamp(now)
    big = a.family == "s7-1500"
    mon, health = bytearray(build_mon(boot_date, boot_time)), bytearray(build_health())
    diag = bytearray(build_diag_1500(now) if big else build_diag(now))
    assert (len(mon), len(health)) == (MON_SIZE, HEALTH_SIZE) and len(diag) == (DIAG1500_SIZE if big else DIAG_SIZE)
    srv = snap7.server.Server(log=False)
    srv.register_area(SrvArea.DB, 880, mon)
    srv.register_area(SrvArea.DB, 881, diag)
    srv.register_area(SrvArea.DB, 882, health)
    srv.start(tcp_port=a.port)
    print(f"mock PLC: DB880, DB881, DB882 ({a.family})", flush=True)
    seq, next_close, next_second = 0, time.time() + 1, time.time() + 1
    while True:
        time.sleep(0.01)
        t = time.time()
        if os.path.exists(STOP_FILE):
            next_close, next_second = t + 1, t + 1
            continue
        tick = t >= next_second
        if tick:
            next_second += 1
        limit = struct.unpack_from(">h", health, 4)[0]
        for at in HEALTH_SLOTS.values():
            health_slot(health, at, limit, tick, datetime.now(timezone.utc))
        if big:   # FC_PerfFault from OB122: the slot's Count and newest stamp, the newest fault and DiagSeq
            n = struct.unpack_from(">i", diag, 160)[0] + 20
            called = stamp(datetime.now(timezone.utc))
            struct.pack_into(">iii", diag, 160, n, *called)
            struct.pack_into(">i", diag, 8, struct.unpack_from(">i", diag, 8)[0] + 20)
            struct.pack_into(">hhii", diag, 12, 122, min(32767, struct.unpack_from(">h", diag, 14)[0] + 20), *called)
        if t >= next_close:
            next_close += 1
            seq += 1
            slot = (seq - 1) % RING_SIZE
            mon[72 + slot * RECORD_SIZE:72 + (slot + 1) * RECORD_SIZE] = pack_record(seq, datetime.now(timezone.utc), comm=3.0 if big else -1.0)
            struct.pack_into(">i", mon, 8, seq)
            struct.pack_into(">h", mon, 6, slot)


def health_slot(db: bytearray, at: int, limit: int, tick: bool, now: datetime) -> None:
    """FC_PerfHealth on one slot: Life +0, Echo +1, BadEcho +2, Age_s +4, Losses +6, LastLoss +8/+12, bits +16, PrevEcho +17."""
    life, echo, prev = db[at], db[at + 1], db[at + 17]
    if life == 0:
        db[at] = 1
    elif echo == life:
        db[at] = 1 if life >= 255 else life + 1
        struct.pack_into(">h", db, at + 4, 0)
        db[at + 16] |= 3                     # Healthy, Seen
    elif echo != prev and echo != 0:
        struct.pack_into(">h", db, at + 2, struct.unpack_from(">h", db, at + 2)[0] + 1)
    db[at + 17] = echo
    if tick:
        age = struct.unpack_from(">h", db, at + 4)[0]
        if age < 32767:
            age += 1
            struct.pack_into(">h", db, at + 4, age)
        if db[at + 16] & 1 and age > limit:
            db[at + 16] &= ~1 & 0xFF
            struct.pack_into(">h", db, at + 6, struct.unpack_from(">h", db, at + 6)[0] + 1)
            struct.pack_into(">ii", db, at + 8, *stamp(now))

if __name__ == "__main__":
    main()
