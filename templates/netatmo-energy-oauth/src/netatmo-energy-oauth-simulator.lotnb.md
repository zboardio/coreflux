# Netatmo Energy over REST, OAuth 2 on the broker — simulator

A hardware-free, account-free stand-in for the Netatmo cloud. It plays the part of the solution's
**Route**: it listens on the same request topics and answers on the same answer topics, with the
same JSON Netatmo returns. The solution's ticks, fan-out, room map, UNS leaves and setpoint commands
then run unchanged. One home, three rooms: two with a radiator valve each, and an office that is
deliberately **not** in the example room map, so you can see the unmapped path.

**Deploy the solution without its Route cell**, then this notebook. With the Route deployed, both
would answer every request. No secrets are needed: the token chain is the one part this simulator
does not exercise. Remove these actions, deploy the Route and enter the secrets once you have a
Netatmo app.

| Request topic (from the solution) | Simulated answer |
|---|---|
| `netatmo/_api/homesdata/request` | the home structure: rooms, valves, the relay |
| `netatmo/_api/homestatus/request` | live room values; temperatures wander, `heating_power_request` follows the setpoint |
| `netatmo/_api/setroomthermpoint/request` | `{"status":"ok"}`, and the room switches to `manual` at the requested temperature |

The setpoints live in broker-internal state (`KEEP TOPIC "sim/netatmo/setpoints"`), so a command is
visible on the next simulated poll, as it would be with the real API.

## Python

```python
# Script Name: NetatmoSim
import json
import random
import time

HOME = "65f0c0ffee0000000000c0de"
RELAY = "70:ee:50:aa:00:01"
ROOMS = [("1001", "Living room", "livingroom", "09:00:00:aa:00:01", 21.2),
         ("1002", "Bedroom", "bedroom", "09:00:00:aa:00:02", 19.4),
         ("1003", "Office", "office", None, 20.1)]


def _state(text):
    try:
        return json.loads(text) if text else {}
    except ValueError:
        return {}


def homesdata(_request=None):
    rooms = [{"id": rid, "name": name, "type": kind, "module_ids": [valve] if valve else []}
             for rid, name, kind, valve, _t in ROOMS]
    modules = [{"id": RELAY, "type": "NAPlug", "name": "Relay",
                "modules_bridged": [v for *_r, v, _t in ROOMS if v]}]
    modules += [{"id": valve, "type": "NRV", "name": "Valve " + name, "room_id": rid, "bridge": RELAY}
                for rid, name, _k, valve, _t in ROOMS if valve]
    return json.dumps({"body": {"homes": [{"id": HOME, "name": "Example home", "timezone": "Europe/Berlin",
                                           "therm_setpoint_default_duration": 180, "therm_mode": "schedule",
                                           "rooms": rooms, "modules": modules}]},
                       "status": "ok", "time_exec": 0.02, "time_server": int(time.time())})


def homestatus(state):
    sp = _state(state)
    rooms, modules = [], [{"id": RELAY, "type": "NAPlug", "firmware_revision": 254, "rf_strength": 107,
                           "wifi_strength": 52}]
    for n, (rid, _name, _kind, valve, base) in enumerate(ROOMS):
        cur = sp.get(rid, {"sp": 19.0, "mode": "schedule"})
        measured = round(base + random.uniform(-0.3, 0.3), 1)
        rooms.append({"id": rid, "reachable": True, "anticipating": False, "open_window": False,
                      "heating_power_request": 100 if measured < cur["sp"] - 0.2 else 0,
                      "therm_measured_temperature": measured,
                      "therm_setpoint_temperature": cur["sp"], "therm_setpoint_mode": cur["mode"],
                      "therm_setpoint_start_time": int(time.time()) - 600,
                      "therm_setpoint_end_time": int(time.time()) + 10800})
        if valve:
            modules.append({"id": valve, "type": "NRV", "reachable": True, "bridge": RELAY,
                            "battery_state": "high", "battery_level": 2950 - 40 * n,
                            "firmware_revision": 79, "rf_strength": 62 + 5 * n})
    return json.dumps({"status": "ok", "time_server": int(time.time()),
                       "body": {"home": {"id": HOME, "rooms": rooms, "modules": modules}}})


def setpoint(state, request):
    sp = _state(state)
    req = _state(request)
    sp[str(req.get("room_id"))] = {"sp": float(req.get("temp", 19.0)), "mode": "manual"}
    return json.dumps(sp)


def ok(_request=None):
    return json.dumps({"status": "ok", "time_exec": 0.02, "time_server": int(time.time())})
```

## Actions

### The cloud's answers

```lot
DEFINE ACTION SimNetatmoHomesData
ON TOPIC "netatmo/_api/homesdata/request" DO
    CALL PYTHON "NetatmoSim.homesdata"
        WITH (PAYLOAD)
        RETURN AS {answer}
    PUBLISH TOPIC "netatmo/_api/homesdata" WITH {answer}
```

```lot
DEFINE ACTION SimNetatmoHomeStatus
ON TOPIC "netatmo/_api/homestatus/request" DO
    CALL PYTHON "NetatmoSim.homestatus"
        WITH (GET TOPIC "sim/netatmo/setpoints")
        RETURN AS {answer}
    PUBLISH TOPIC "netatmo/_api/homestatus" WITH {answer}
```

```lot
DEFINE ACTION SimNetatmoSetpoint
ON TOPIC "netatmo/_api/setroomthermpoint/request" DO
    CALL PYTHON "NetatmoSim.setpoint"
        WITH (GET TOPIC "sim/netatmo/setpoints", PAYLOAD)
        RETURN AS {state}
    KEEP TOPIC "sim/netatmo/setpoints" WITH {state}
    CALL PYTHON "NetatmoSim.ok"
        WITH (PAYLOAD)
        RETURN AS {answer}
    PUBLISH TOPIC "netatmo/_api/setroomthermpoint" WITH {answer}
```

### A first poll right away

The solution polls every 5 minutes. This asks for the home structure and one status at deploy time,
so the demo shows data at once.

```lot
DEFINE ACTION SimNetatmoKickoff
ON START DO
    PUBLISH TOPIC "netatmo/_api/homesdata/request" WITH "{}"
    PUBLISH TOPIC "netatmo/_api/homestatus/request" WITH "{}"
```
