# Siemens S7 PLC health — simulator

A hardware-free stand-in for the two example PLCs of this template: **PLC01, an S7-300**, and **PLC02, an S7-1500
running a program with unwired I/O**. It plays the part of the family notebooks' **Route** cells: it answers on the same
read topics with the same JSON the `SIEMENS_S7` connector returns, built byte for byte in the kit's DB layouts, and it
publishes the record counter `Seq` and the health loop's `Life` the way the route polls them. Everything after the route
then runs unchanged: the decoder, the actions, the UNS leaves, the health loop and the historian.

**Deploy a family notebook without its Route cell** (or both notebooks, without either Route cell), then this one. With a
Route deployed, both would answer every read. Remove these actions and deploy the Route once a PLC is there.

What it simulates, per PLC, from the moment it first runs:

| | PLC01, S7-300 | PLC02, S7-1500 |
|---|---|---|
| Cycle | about 0.48 ms, 2,000 cycles a second, no communication-load figure | about 20 ms, 50 cycles a second, communication load about 6 % |
| Error OBs | none called | OB122 called about 3 times a second (S7-1500 start information: an FC reading an input that is not wired), and one classic OB82 call |
| `DB_PerfDiag` | layout 1: identity, firmware V2.6.7, the diagnostic buffer with the STOP and restart entries | layout 2: the six error-OB slots, the LEDs, `RT_INFO` |
| Health loop | `Life` moves on when the broker's echo confirms it; a loss after 5 s without one, a wrong value counted as `BadEcho` | the same |

**STOP and RUN from the broker.** Publish `STOP` (retained) to `siemens/site01/_sim/PLC01/mode` (or `PLC02`): the
record counter stands still, the reads still answer, and the solution reports `CpuScanning` false within about 10 s,
`Health` `unknown`, `DeviceStatus` still `online`. Publish `RUN`: the PLC restarts as a real one does, with a new boot, the
previous boot's counters kept, and on PLC01 the STOP and restart entries in its diagnostic buffer.

The simulated state lives in broker-internal topics (`KEEP TOPIC "siemens/site01/_sim/<PLC>/state"`), so a broker
restart starts the PLCs again, as a power cycle would.

## Python

**Reads:** nothing (called by the actions). **Writes:** nothing.

```python
# Script Name: S7KitSim
# A simulated S7-300 (PLC01) and S7-1500 (PLC02) running the health kit: the kit's three DBs as bytes, answered in the
# JSON the SIEMENS_S7 connector returns for a whole-DB DWORD read. State comes back from the broker as an argument.
import json
import math
import struct
import time

FAMILY = {"PLC01": "s7-300", "PLC02": "s7-1500"}
RECORD, RING, LOSS_LIMIT = 68, 120, 5
EDGES = (2.0, 5.0, 10.0, 20.0, 40.0, 60.0, 100.0)
COUNT = {"PerfMon": 2058, "PerfDiag": {"s7-300": 161, "s7-1500": 81}, "PerfHealth": 11}
ADDRESS = {"PerfMon": "DB880.DBD0", "PerfDiag": "DB881.DBD0", "PerfHealth": "DB882.DBD0"}
# Diagnostic-buffer entries, bytes 2-11 (priority, OB, DatID, info 1, info 2) as a CPU 315-2 PN/DP writes them: STOP to
# STARTUP carries the STOP's cause (0x4304, STOP by the programming device) in info 1.
HEAD = {0x4302: "FF68C700000008147714", 0x4301: "FF46C772430408147714", 0x4304: "FF840000000000000000"}


def _load(text):
    try:
        doc = json.loads(text)
        return doc if isinstance(doc, dict) else {}
    except (TypeError, ValueError):
        return {}


def _stamp(t):
    g = time.gmtime(t)
    ms = int((t - int(t)) * 1000)
    return (g.tm_year * 10000 + g.tm_mon * 100 + g.tm_mday,
            g.tm_hour * 10000000 + g.tm_min * 100000 + g.tm_sec * 1000 + ms)


def _bcd(v):
    return (int(v / 10) << 4) | (v % 10)


def _entry(event_id, t):
    g = time.gmtime(t)
    ms = int((t - int(t)) * 1000)
    weekday = (g.tm_wday + 1) % 7 + 1
    clock = bytes(_bcd(v) for v in (g.tm_year % 100, g.tm_mon, g.tm_mday, g.tm_hour, g.tm_min, g.tm_sec, int(ms / 10)))
    return struct.pack(">H", event_id) + bytes.fromhex(HEAD[event_id]) + clock + bytes([(ms % 10) << 4 | weekday])


def _seq(s, now):
    if s.get("stopped") is not None:
        return s.get("seq_stop", 0)
    return max(0, int(now - s["boot"]))


def _boot(s, now, first):
    if not first:
        s["prev"] = list(_stamp(s["boot"])) + [_seq(s, now)]
        s["events"] = [[0x4302, now + 0.2], [0x4301, now]] + s["events"][:8]
    else:
        s["prev"] = list(_stamp(now - 86400)) + [86400]
        s["events"] = [[0x4302, now - 0.8], [0x4301, now - 1.0]]
    s.update({"boot": now, "restarts": s.get("restarts", 0) + 1, "stopped": None, "life": 1, "prev_echo": 0, "age": 0,
              "bits": 0})


def tick(plc, state, echo, mode):
    """One second of the simulated PLC: its health loop (FC_PerfHealth's rule), STOP and RUN from the mode topic, and
    what the route would publish: Life every second, Seq every 5 s. Returns the new state, life and (when due) seq."""
    now = time.time()
    s = _load(state)
    if "boot" not in s:
        s.update({"bad": 0, "losses": 0, "loss": [0, 0]})
        _boot(s, now, True)
    stop = str(mode or "").strip().upper() == "STOP"
    if stop and s.get("stopped") is None:
        s["seq_stop"], s["stopped"] = _seq(s, now), now
        s["events"] = [[0x4304, now]] + s["events"][:9]
    elif not stop and s.get("stopped") is not None:
        _boot(s, now, False)
    if s.get("stopped") is None:
        try:
            e = int(float(echo))
        except (TypeError, ValueError):
            e = 0
        life = s["life"]
        if life == 0:
            s["life"] = 1
        elif e == life:
            s["life"] = 1 if life >= 255 else life + 1
            s["age"], s["bits"] = 0, s["bits"] | 3
        elif e != s["prev_echo"] and e != 0:
            s["bad"] += 1
        s["prev_echo"] = e
        s["age"] = min(s["age"] + 1, 32767)
        if s["bits"] & 1 and s["age"] > LOSS_LIMIT:
            s["bits"] &= 0xFE
            s["losses"] += 1
            s["loss"] = list(_stamp(now))
    out = {"life": s["life"], "state": json.dumps(s)}
    if int(now / 5) != int(s.get("t", 0) / 5):
        out["seq"] = _seq(s, now)
    s["t"] = now
    out["state"] = json.dumps(s)
    return json.dumps(out)


def _cycle(family, k):
    if family == "s7-300":
        avg = 0.48 + 0.04 * math.sin(k / 30.0)
        return avg, 0.41, 2.0 if k % 60 else 3.1, -1.0
    avg = 20.0 + 2.0 * math.sin(k / 40.0)
    return avg, 17.6, avg + 4.0 + (3.0 if k % 45 == 0 else 0.0), 6.0 + math.sin(k / 25.0)


def _perf_mon(s, family, now):
    raw = bytearray(72 + RING * RECORD)
    seq = _seq(s, now)
    b = _stamp(s["boot"])
    calls = _ob_calls(s, family, now)
    struct.pack_into(">hhhhihh7fffiiiii", raw, 0, 2, RECORD, RING, (seq - 1) % RING if seq else -1, seq, 1000,
                     s["restarts"], *EDGES, 1.0, 2.0, 0, calls.get(86, (0,))[0], calls.get(82, (0,))[0], b[0], b[1])
    for k in range(max(1, seq - RING + 1), seq + 1):
        avg, low, high, comm = _cycle(family, k)
        cycles = int(1000 / avg)
        hist = [0] * 8
        hist[sum(1 for e in EDGES if avg >= e)] = cycles
        d, t = _stamp(s["boot"] + k)
        struct.pack_into(">iiii4f8iHh", raw, 72 + ((k - 1) % RING) * RECORD, k, d, t, cycles, low, high, avg, comm, *hist,
                         1 if k == 1 else 0, 0)
    return bytes(raw)


def _perf_diag_300(s):
    raw = bytearray(644)
    struct.pack_into(">hhi", raw, 0, 1, 644, len(s["events"]))
    struct.pack_into(">6i", raw, 24, s["prev"][0], s["prev"][1], s["prev"][2], 0, 0, 0)
    struct.pack_into(">hhh", raw, 64, 2, 1, len(s["events"]))
    raw[74:94] = b"6ES7 315-2EH13-0AB0 "
    raw[100:102], raw[124:128] = b"\x00\x07", b"V\x02\x06\x07"
    raw[130:142] = b"SIMULATED-01"
    raw[164:178] = b"simulated PLC1"
    for i, (event_id, t) in enumerate(s["events"][:10]):
        raw[444 + i * 20:464 + i * 20] = _entry(event_id, t)
    return bytes(raw)


def _ob_calls(s, family, now):
    """The S7-1500's error-OB slots: OB -> (calls, stamp of the newest, EvClass, FaultId, Info1, Info2, Info3)."""
    if family != "s7-1500":
        return {}
    run = (s["stopped"] if s.get("stopped") is not None else now) - s["boot"]
    return {122: (int(run * 3), now if s.get("stopped") is None else s["stopped"], 0, 0x42, 72, 2, 0x01),
            82: (1, s["boot"] + 2.0, 0x39 | 0x80, 0x42, 256, 0x0D15, 0x0000)}


def _perf_diag_1500(s, now):
    raw = bytearray(324)
    calls = _ob_calls(s, "s7-1500", now)
    total = sum(c[0] for c in calls.values())
    struct.pack_into(">hhhh", raw, 0, 2, 324, 1500, 0)
    struct.pack_into(">i", raw, 8, total)
    struct.pack_into(">hhii", raw, 12, 122, min(32767, calls[122][0]), *_stamp(calls[122][1]))
    struct.pack_into(">iii", raw, 24, *s["prev"])
    for i, ob in enumerate((80, 82, 83, 86, 121, 122)):
        if ob in calls:
            n, t, ev, fid, i1, i2, i3 = calls[ob]
            struct.pack_into(">iiiBBHHH", raw, 60 + 20 * i, n, *_stamp(t), ev, fid, i1, i2, i3)
    struct.pack_into(">8h", raw, 180, 2, 1, 1, 0, 0, 0, 0, 0)
    struct.pack_into(">ffff", raw, 208, 6.0, 26.0, 17.6, 20.0)
    return bytes(raw)


def _perf_health(s):
    raw = bytearray(44)
    struct.pack_into(">hhh", raw, 0, 1, 44, LOSS_LIMIT)
    struct.pack_into(">BBhhhiiBB", raw, 26, s["life"], s["prev_echo"], s["bad"], s["age"], s["losses"], s["loss"][0],
                     s["loss"][1], s["bits"], s["prev_echo"])
    raw[8] = 1
    return bytes(raw)


def read(plc, kind, state):
    """A whole-DB read of the simulated PLC, as the connector answers it on …/raw."""
    now = time.time()
    s, family = _load(state), FAMILY.get(plc)
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now))
    if family is None or "boot" not in s or kind not in ADDRESS:
        return json.dumps({"success": False, "route_name": "S7KitSim", "error": "Siemens S7 PLC is not connected", "timestamp": stamp})
    if kind == "PerfMon":
        raw = _perf_mon(s, family, now)
    elif kind == "PerfDiag":
        raw = _perf_diag_300(s) if family == "s7-300" else _perf_diag_1500(s, now)
    else:
        raw = _perf_health(s)
    count = COUNT[kind] if kind != "PerfDiag" else COUNT[kind][family]
    values = struct.unpack(">%di" % count, raw[:count * 4])
    return json.dumps({"success": True, "route_name": "S7KitSim", "operation": "READ", "address": ADDRESS[kind], "count": count,
                       "data": dict(("value_%d" % i, v) for i, v in enumerate(values)), "timestamp": stamp},
                      separators=(",", ":"))
```

## Actions

**The PLCs' second.** Every second, each simulated PLC runs its health loop on what the broker echoed, and the action
publishes what the route would: `Life` every second, `Seq` every 5 s. A `STOP` on the mode topic freezes both.

**Reads:** the kept state, the kept echo, the retained `siemens/site01/_sim/<PLC>/mode`. **Writes:** the kept state,
`siemens/site01/<PLC>/PN/PerfHealth/Life`, `siemens/site01/<PLC>/PN/PerfMon/Seq`.

```lot
DEFINE ACTION S7SimTick
ON EVERY 1 SECOND DO
    SET "s1" WITH (GET TOPIC "siemens/site01/_sim/PLC01/state")
    SET "e1" WITH (GET TOPIC "siemens/site01/_sim/PLC01/echo")
    SET "m1" WITH (GET TOPIC "siemens/site01/_sim/PLC01/mode")
    CALL PYTHON "S7KitSim.tick"
        WITH ("PLC01", {s1}, {e1}, {m1})
        RETURN AS {t1}
    KEEP TOPIC "siemens/site01/_sim/PLC01/state" WITH (GET JSON "state" IN {t1} AS STRING)
    PUBLISH TOPIC "siemens/site01/PLC01/PN/PerfHealth/Life" WITH (GET JSON "life" IN {t1} AS STRING)
    IF (GET JSON "seq" IN {t1} AS STRING) != "null" THEN
        PUBLISH TOPIC "siemens/site01/PLC01/PN/PerfMon/Seq" WITH (GET JSON "seq" IN {t1} AS STRING)
    SET "s2" WITH (GET TOPIC "siemens/site01/_sim/PLC02/state")
    SET "e2" WITH (GET TOPIC "siemens/site01/_sim/PLC02/echo")
    SET "m2" WITH (GET TOPIC "siemens/site01/_sim/PLC02/mode")
    CALL PYTHON "S7KitSim.tick"
        WITH ("PLC02", {s2}, {e2}, {m2})
        RETURN AS {t2}
    KEEP TOPIC "siemens/site01/_sim/PLC02/state" WITH (GET JSON "state" IN {t2} AS STRING)
    PUBLISH TOPIC "siemens/site01/PLC02/PN/PerfHealth/Life" WITH (GET JSON "life" IN {t2} AS STRING)
    IF (GET JSON "seq" IN {t2} AS STRING) != "null" THEN
        PUBLISH TOPIC "siemens/site01/PLC02/PN/PerfMon/Seq" WITH (GET JSON "seq" IN {t2} AS STRING)
```

**The echo, as the route would write it into the PLC.** The solution's echo action publishes on `…/Echo/set`; the
simulated PLC sees it on its next second.

**Reads:** `siemens/site01/+/+/PerfHealth/Echo/set`. **Writes:** the kept `siemens/site01/_sim/<PLC>/echo`.

```lot
DEFINE ACTION S7SimEcho
ON TOPIC "siemens/site01/+/+/PerfHealth/Echo/set" DO
    SET "plc" WITH TOPIC POSITION 3
    KEEP TOPIC "siemens/site01/_sim/" + {plc} + "/echo" WITH PAYLOAD
```

**A whole-DB read**, answered on the same topic the route would answer on. A PLC the simulator does not know, or one that
has not run yet, answers as an unreachable PLC does.

**Reads:** `siemens/site01/+/+/+/read`, the kept state. **Writes:** `siemens/site01/<PLC>/<path>/<Kind>/raw`.

```lot
DEFINE ACTION S7SimRead
ON TOPIC "siemens/site01/+/+/+/read" DO
    SET "plc" WITH TOPIC POSITION 3
    SET "via" WITH TOPIC POSITION 4
    SET "kind" WITH TOPIC POSITION 5
    SET "state" WITH (GET TOPIC "siemens/site01/_sim/" + {plc} + "/state")
    CALL PYTHON "S7KitSim.read"
        WITH ({plc}, {kind}, {state})
        RETURN AS {raw}
    PUBLISH TOPIC "siemens/site01/" + {plc} + "/" + {via} + "/" + {kind} + "/raw" WITH {raw}
```

## What you will see

Within 30 s of deploying this notebook after a family notebook (without its Route):

- `acme/site01/Automation/PLC01/PN/CycleAvg` about 0.48 ms, `CommLoad` -1 with status `Bad`, `LastDiagEvent`
  `0x4302, Mode transition from STARTUP to RUN`, `Health` `ok`, `CpuScanning` true, `DeviceStatus` `online`.
- `acme/site01/Automation/PLC02/PN/CycleAvg` about 20 ms, `CommLoad` about 6 %, `OB122Events` counting, `LastFault`
  `OB122, fault id 0x42 I/O access error, reading, FC 72, area 0x01 Direct (peripheral) access to inputs, … calls since the boot`.
- With the historian connected: one row a second per PLC in `plc_cycle`, the reads in `plc_read`, PLC02's OB122 and its
  classic OB82 in words in `plc_ob_call_text`, PLC01's buffer entries with Siemens' texts in `plc_diag_event_text`.
- `STOP` on `siemens/site01/_sim/PLC01/mode`: `CpuScanning` false, `Health` `unknown`; `RUN`: a new `BootTime`, and
  `LastDiagEvent` `0x4302 …` again, the 0x4301 entry before it naming the STOP's cause.
- Disable `S7PLC01Echo` (the solution's echo action): `Health` turns `stalled` within about 15 s and the simulated PLC
  counts a loss; enable it again and `Health` returns to `ok`.
