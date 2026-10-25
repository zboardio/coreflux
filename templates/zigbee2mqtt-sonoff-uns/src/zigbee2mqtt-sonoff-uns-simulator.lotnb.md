# Zigbee2MQTT + Sonoff USB dongle → a clean UNS — simulator

A hardware-free stand-in for Zigbee2MQTT. It publishes **exactly the payloads Z2M 2.x publishes**
for four SONOFF sensors, on the same raw topics, so the solution notebook runs end to end with no
dongle and no Z2M process. It shares nothing with the solution but topic names.

**Run it after** the solution's Models and Actions, on the same broker. **Never run it next to a real
Z2M** that uses the same friendly names: both would write the same raw topics. Remove the actions (or
skip this notebook) once a real coordinator is connected.

| Simulated device | Model | Raw topic | Cadence |
|---|---|---|---|
| `LivingRoom-SNZB02-01` | SNZB-02 temperature/humidity | `zigbee2mqtt/LivingRoom-SNZB02-01` | 20 s |
| `Bedroom-SNZB02-01` | SNZB-02 temperature/humidity | `zigbee2mqtt/Bedroom-SNZB02-01` | 30 s |
| `Corridor-SNZB03-01` | SNZB-03 motion | `zigbee2mqtt/Corridor-SNZB03-01` | 15 s, occupancy toggles |
| `Entrance-SNZB04-01` | SNZB-04 door contact | `zigbee2mqtt/Entrance-SNZB04-01` | 25 s, opens and closes |
| `0x00158d0001a2b3c4` | a freshly paired SNZB-02 nobody has named or mapped yet | `zigbee2mqtt/0x00158d0001a2b3c4` | 60 s |

Real sensors report far less often (a SNZB-02 every few minutes when values move, a heartbeat
roughly hourly); the cadences here are short so a demo shows movement within a minute.

**Why plain JSON strings and not Models.** Z2M publishes plain JSON, and so does this simulator: the
payloads are built with `PUBLISH TOPIC` and string concatenation, field names and units exactly as
Z2M sends them (`voltage` in millivolts, `linkquality` 0–255, `last_seen` ISO-8601 with
`advanced.last_seen: ISO_8601`). It also keeps the simulator running after the solution's Rules: an
action's `PUBLISH TOPIC` is not subject to user publish Rules, an action's `PUBLISH MODEL` is, and
Rule 1 admits only Z2M and root to `zigbee2mqtt/`.

One escaping detail, measured on 2.14.3: inside a `+` concatenation, a string literal that **ends**
with an escaped quote (`"…\":\""`) is accepted on deploy but fails when the action first runs.
The quote around the timestamp is therefore written `\u0022`, which works in every position.

Simulator state (the previous values of each random walk) is kept with `KEEP TOPIC` under `sim/…`:
broker-internal, never on the wire.

## Actions

### Bridge and device availability

Z2M announces itself with a retained `bridge/state` and one `availability` topic per device. Runs
on deploy and on every broker start.

```lot
DEFINE ACTION SimZigbeeBridgeOnline
ON START DO
    PUBLISH TOPIC "zigbee2mqtt/bridge/state" WITH "{\"state\":\"online\"}"
    PUBLISH TOPIC "zigbee2mqtt/LivingRoom-SNZB02-01/availability" WITH "{\"state\":\"online\"}"
    PUBLISH TOPIC "zigbee2mqtt/Bedroom-SNZB02-01/availability" WITH "{\"state\":\"online\"}"
    PUBLISH TOPIC "zigbee2mqtt/Corridor-SNZB03-01/availability" WITH "{\"state\":\"online\"}"
    PUBLISH TOPIC "zigbee2mqtt/Entrance-SNZB04-01/availability" WITH "{\"state\":\"online\"}"
```

### Living room SNZB-02: a bounded temperature and humidity walk

```lot
DEFINE ACTION SimLivingRoomSnzb02
ON EVERY 20 SECONDS DO
    SET "t" WITH (GET TOPIC "sim/zigbee/livingroom/t" AS DOUBLE)
    IF {t} == 0 THEN
        SET "t" WITH 21.5
    SET "t" WITH ({t} + (RANDOM DOUBLE BETWEEN -0.3 AND 0.3))
    IF {t} < 18.0 THEN
        SET "t" WITH 18.0
    IF {t} > 26.0 THEN
        SET "t" WITH 26.0
    KEEP TOPIC "sim/zigbee/livingroom/t" WITH {t}
    SET "h" WITH (RANDOM DOUBLE BETWEEN 44.0 AND 52.0)
    PUBLISH TOPIC "zigbee2mqtt/LivingRoom-SNZB02-01" WITH ("{\"battery\":97,\"humidity\":" + {h} + ",\"linkquality\":120,\"temperature\":" + {t} + ",\"voltage\":2900,\"last_seen\":\u0022" + TIMESTAMP "ISO" + "\u0022}")
```

### Bedroom SNZB-02: cooler, weaker radio, older battery

```lot
DEFINE ACTION SimBedroomSnzb02
ON EVERY 30 SECONDS DO
    SET "t" WITH (GET TOPIC "sim/zigbee/bedroom/t" AS DOUBLE)
    IF {t} == 0 THEN
        SET "t" WITH 19.0
    SET "t" WITH ({t} + (RANDOM DOUBLE BETWEEN -0.2 AND 0.2))
    IF {t} < 16.0 THEN
        SET "t" WITH 16.0
    IF {t} > 23.0 THEN
        SET "t" WITH 23.0
    KEEP TOPIC "sim/zigbee/bedroom/t" WITH {t}
    SET "h" WITH (RANDOM DOUBLE BETWEEN 50.0 AND 58.0)
    PUBLISH TOPIC "zigbee2mqtt/Bedroom-SNZB02-01" WITH ("{\"battery\":64,\"humidity\":" + {h} + ",\"linkquality\":72,\"temperature\":" + {t} + ",\"voltage\":2700,\"last_seen\":\u0022" + TIMESTAMP "ISO" + "\u0022}")
```

### Corridor SNZB-03: occupancy toggles every report

```lot
DEFINE ACTION SimCorridorSnzb03
ON EVERY 15 SECONDS DO
    SET "occ" WITH (GET TOPIC "sim/zigbee/corridor/occ" AS STRING)
    IF {occ} == "true" THEN
        SET "occ" WITH "false"
    ELSE
        SET "occ" WITH "true"
    KEEP TOPIC "sim/zigbee/corridor/occ" WITH {occ}
    PUBLISH TOPIC "zigbee2mqtt/Corridor-SNZB03-01" WITH ("{\"battery\":88,\"battery_low\":false,\"linkquality\":96,\"occupancy\":" + {occ} + ",\"voltage\":3000,\"last_seen\":\u0022" + TIMESTAMP "ISO" + "\u0022}")
```

### Entrance SNZB-04: the door opens and closes

`contact: true` means the magnet is next to the sensor, i.e. the door is **closed**.

```lot
DEFINE ACTION SimEntranceSnzb04
ON EVERY 25 SECONDS DO
    SET "closed" WITH (GET TOPIC "sim/zigbee/entrance/closed" AS STRING)
    IF {closed} == "true" THEN
        SET "closed" WITH "false"
    ELSE
        SET "closed" WITH "true"
    KEEP TOPIC "sim/zigbee/entrance/closed" WITH {closed}
    PUBLISH TOPIC "zigbee2mqtt/Entrance-SNZB04-01" WITH ("{\"battery\":100,\"battery_low\":false,\"contact\":" + {closed} + ",\"linkquality\":140,\"voltage\":3100,\"last_seen\":\u0022" + TIMESTAMP "ISO" + "\u0022}")
```

### A device that is paired but not mapped yet

Z2M names a new device after its IEEE address until you give it a friendly name. The solution
does not drop it: it shows up on `ingest/zigbee2mqtt/unmapped/0x00158d0001a2b3c4`.

```lot
DEFINE ACTION SimUnmappedDevice
ON EVERY 60 SECONDS DO
    PUBLISH TOPIC "zigbee2mqtt/0x00158d0001a2b3c4" WITH ("{\"battery\":100,\"humidity\":50.0,\"linkquality\":150,\"temperature\":22.0,\"voltage\":3100,\"last_seen\":\u0022" + TIMESTAMP "ISO" + "\u0022}")
```
