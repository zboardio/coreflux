# Zigbee2MQTT + Sonoff USB dongle → a clean UNS — solution

Zigbee2MQTT (Z2M) owns the radio: a Sonoff USB coordinator, the Zigbee network and its devices.
It publishes one JSON object per device under `zigbee2mqtt/<friendly_name>`. This notebook turns
that **device-shaped raw feed** into a **position-shaped Unified Namespace**: one topic per
measurement, each carrying the same five-key envelope, addressed by *where the sensor is and what
it measures*, not by which device happens to be installed there.

```text
Sonoff dongle ─ Z2M ─► zigbee2mqtt/LivingRoom-SNZB02-01            raw plane (Z2M's own, retained)
                         {"temperature":21.4,"humidity":48,"battery":97,"voltage":2900,
                          "linkquality":120,"last_seen":"2026-10-06T10:00:00.000Z"}
                │
                ▼  ZigbeeDeviceMap (one line per device) + ZigbeeToUns
acme/site01/LivingRoom/Ambient01/Temperature   {"value":21.4,"timestamp":"2026-10-06T10:00:00.000Z",
acme/site01/LivingRoom/Ambient01/Humidity        "datatype":"number","status":"Good","units":"°C"}
acme/site01/LivingRoom/Ambient01/Voltage       2.9 V — the leaf owns the unit, Z2M reports mV
acme/site01/LivingRoom/Ambient01/DeviceStatus  online | offline
```

**Run order:** Models → Actions → Rules (last). The hardware-free path runs
`zigbee2mqtt-sonoff-uns-simulator.lotnb` after the Actions. With a real dongle, configure Z2M **before pairing anything**: channel, network key and PAN ids
cannot be changed later without re-pairing every device. The Z2M `configuration.yaml` settings this
notebook relies on: `mqtt.base_topic: zigbee2mqtt`, `mqtt.user: zigbee2mqtt`,
`device_options.retain: true`, `advanced.cache_state: false`, `advanced.last_seen: ISO_8601`,
`advanced.output: json`, a fixed `advanced.channel`, and `network_key`, `pan_id`, `ext_pan_id` set to
`GENERATE`.

**Requires:** Coreflux broker 2.14.2 or newer (`ON CONNECT`/`ON DISCONNECT` triggers, banded Rule
priorities); verified on 2.14.3: every cell of both notebooks deployed on a fresh broker and 23 checks passed, with no runtime
error in the broker log. No Python, no Routes. Z2M 2.x connects to this broker as an
ordinary MQTT client with its own account `zigbee2mqtt`.

## Topic contract

| Topic | Who writes it | Retained | Payload |
|---|---|---|---|
| `zigbee2mqtt/<friendly>` | Z2M | yes (`device_options.retain: true`) | device JSON, `last_seen` ISO-8601 |
| `zigbee2mqtt/<friendly>/availability` | Z2M | yes | `{"state":"online"}` / `{"state":"offline"}` |
| `zigbee2mqtt/bridge/state` | Z2M (its LWT on disconnect) | yes | `{"state":"online"}` / `{"state":"offline"}` |
| `acme/site01/<Area>/<Position>/<Leaf>` | `ZigbeeToUns` | no — a live event, see below | five-key envelope |
| `acme/site01/<Area>/<Position>/DeviceStatus` | `ZigbeeAvailabilityToUns` | no | envelope, `value` online/offline |
| `ingest/zigbee2mqtt/BridgeState` | `ZigbeeBridgeState` | no | envelope: Z2M's own view of itself |
| `ingest/zigbee2mqtt/Session` | `ZigbeeSessionWatch` | no | envelope: the broker's view of Z2M's MQTT session |
| `ingest/zigbee2mqtt/unmapped/<friendly>` | `ZigbeeToUns` | no | the raw payload of a device that has no position yet |
| `ingest/zigbee2mqtt/permit_join` | you (root) | no | seconds to open the network for pairing, `0` closes it |

**Retention, by design.** The raw plane is retained by Z2M itself, so a late subscriber always has
the last device state. The clean leaves are published by LoT as **live events**. A consumer that needs a
last-known value right after it connects reads the raw topic once, or waits for the next report. A
battery sensor reports roughly every 30–60 minutes, a mains device more often. Every envelope carries
the **observation** time (`timestamp` = Z2M's `last_seen`), never the publish time, so a consumer
can always tell a fresh value from an old one.

## Models

One envelope shape per JSON type. The `datatype` key lets a consumer or historian pick a typed column
without a schema lookup; `units` appears on numeric leaves only and is a property of the leaf (a
replacement sensor that reports in other units is converted by the mapper, never passed through).

```lot
DEFINE MODEL UnsNumber COLLAPSED
    ADD DOUBLE "value"
    ADD STRING "timestamp"
    ADD STRING "datatype"
    ADD STRING "status"
    ADD STRING "units"
```

```lot
DEFINE MODEL UnsBoolean COLLAPSED
    ADD BOOL "value"
    ADD STRING "timestamp"
    ADD STRING "datatype"
    ADD STRING "status"
```

```lot
DEFINE MODEL UnsText COLLAPSED
    ADD STRING "value"
    ADD STRING "timestamp"
    ADD STRING "datatype"
    ADD STRING "status"
```

## Actions

### The device map — the one place that knows which device sits where

**Reads:** nothing. **Writes:** broker-internal state `ingest/zigbee2mqtt/map/<friendly>` (KEEP).

One line per device: Z2M friendly name → UNS position. The position is the stable address; the
device is an occupant that can be replaced. **Replacing a sensor** = pair the new one, give it the old
friendly name (or edit its line here), and every consumer keeps its subscription and its history.
**Moving a sensor** to another room = edit its line here. A device that is not listed is not dropped:
its raw payload appears on `ingest/zigbee2mqtt/unmapped/<friendly>`, which is how a freshly paired
device announces itself.

Friendly names must not contain `/` (Z2M allows it; the `zigbee2mqtt/+` trigger below would then
miss the device). The naming that has worked well: `<Area>-<Model>-<nn>`, e.g. `LivingRoom-SNZB02-01`.

`ON START` runs on deploy and on every broker start, so editing a line and re-deploying this action
is the whole change.

```lot
DEFINE ACTION ZigbeeDeviceMap
ON START DO
    KEEP TOPIC "ingest/zigbee2mqtt/map/LivingRoom-SNZB02-01" WITH "acme/site01/LivingRoom/Ambient01"
    KEEP TOPIC "ingest/zigbee2mqtt/map/Bedroom-SNZB02-01" WITH "acme/site01/Bedroom/Ambient01"
    KEEP TOPIC "ingest/zigbee2mqtt/map/Corridor-SNZB03-01" WITH "acme/site01/Corridor/Motion01"
    KEEP TOPIC "ingest/zigbee2mqtt/map/Entrance-SNZB04-01" WITH "acme/site01/Entrance/Door01"
```

### Raw device object → UNS leaves

**Reads:** `zigbee2mqtt/+` (trigger), the device map. **Writes:** `<position>/<Leaf>` envelopes, or
`ingest/zigbee2mqtt/unmapped/<friendly>`.

Three rules make this mapper trustworthy, and each one comes from running it against real sensors:

1. **An attribute appears only when the device reported it.** A sensor sends `occupancy` only after
   its first motion, `battery_low` only when it changes. Every key is therefore tested before it is
   published, and an absent key publishes nothing, never a null. A JSON path that is not in the
   payload reads as the string `"null"`, which is what the tests compare against.
2. **One timestamp per message, stamped only onto what the message contains.** With Z2M's
   `cache_state: true` (its default), every message repeats *every* attribute the device ever
   reported. Stamping `last_seen` onto all of them makes a three-hour-old battery reading look fresh.
   Set `advanced.cache_state: false` in Z2M (Run order, above), so a message carries what was just
   measured, and the stamp is true for every leaf in it.
3. **The leaf owns its unit.** Z2M reports `voltage` in millivolts; the leaf `Voltage` is in volts.
   The multiplication happens here, once (`* 0.001`: an integer divisor would truncate).

Mapped keys: `temperature` °C, `humidity` %, `pressure` hPa, `battery` %, `voltage` mV → V,
`linkquality` (0–255, dimensionless `"1"`: radio transport quality, never a data-quality judgement),
`occupancy`, `contact` (`true` = closed), `water_leak`, `battery_low`. Add a key by copying a block.

`status` is `Good` by construction: Z2M publishes a value only when the device reported it, so every
published sample is a successful read. Degraded quality shows up as a stale `timestamp`, a gap or
`DeviceStatus`, never as a `Bad` sample.

```lot
DEFINE ACTION ZigbeeToUns
ON TOPIC "zigbee2mqtt/+" DO
    SET "dev" WITH TOPIC POSITION 2
    IF {dev} != "bridge" THEN
        SET "pos" WITH (GET TOPIC "ingest/zigbee2mqtt/map/" + {dev})
        IF {pos} == EMPTY THEN
            PUBLISH TOPIC "ingest/zigbee2mqtt/unmapped/" + {dev} WITH PAYLOAD
        ELSE
            SET "ts" WITH (GET JSON "last_seen" IN PAYLOAD AS STRING)
            IF {ts} == "null" THEN
                SET "ts" WITH TIMESTAMP "ISO"
            SET "k_temp" WITH (GET JSON "temperature" IN PAYLOAD AS STRING)
            IF {k_temp} != "null" THEN
                PUBLISH MODEL UnsNumber TO {pos} + "/Temperature" WITH
                    value = (GET JSON "temperature" IN PAYLOAD AS DOUBLE)
                    timestamp = {ts}
                    datatype = "number"
                    status = "Good"
                    units = "°C"
            SET "k_hum" WITH (GET JSON "humidity" IN PAYLOAD AS STRING)
            IF {k_hum} != "null" THEN
                PUBLISH MODEL UnsNumber TO {pos} + "/Humidity" WITH
                    value = (GET JSON "humidity" IN PAYLOAD AS DOUBLE)
                    timestamp = {ts}
                    datatype = "number"
                    status = "Good"
                    units = "%"
            SET "k_press" WITH (GET JSON "pressure" IN PAYLOAD AS STRING)
            IF {k_press} != "null" THEN
                PUBLISH MODEL UnsNumber TO {pos} + "/Pressure" WITH
                    value = (GET JSON "pressure" IN PAYLOAD AS DOUBLE)
                    timestamp = {ts}
                    datatype = "number"
                    status = "Good"
                    units = "hPa"
            SET "k_bat" WITH (GET JSON "battery" IN PAYLOAD AS STRING)
            IF {k_bat} != "null" THEN
                PUBLISH MODEL UnsNumber TO {pos} + "/Battery" WITH
                    value = (GET JSON "battery" IN PAYLOAD AS DOUBLE)
                    timestamp = {ts}
                    datatype = "number"
                    status = "Good"
                    units = "%"
            SET "k_volt" WITH (GET JSON "voltage" IN PAYLOAD AS STRING)
            IF {k_volt} != "null" THEN
                PUBLISH MODEL UnsNumber TO {pos} + "/Voltage" WITH
                    value = ((GET JSON "voltage" IN PAYLOAD AS DOUBLE) * 0.001)
                    timestamp = {ts}
                    datatype = "number"
                    status = "Good"
                    units = "V"
            SET "k_lqi" WITH (GET JSON "linkquality" IN PAYLOAD AS STRING)
            IF {k_lqi} != "null" THEN
                PUBLISH MODEL UnsNumber TO {pos} + "/LinkQuality" WITH
                    value = (GET JSON "linkquality" IN PAYLOAD AS DOUBLE)
                    timestamp = {ts}
                    datatype = "number"
                    status = "Good"
                    units = "1"
            SET "k_occ" WITH (GET JSON "occupancy" IN PAYLOAD AS STRING)
            IF {k_occ} != "null" THEN
                PUBLISH MODEL UnsBoolean TO {pos} + "/Occupancy" WITH
                    value = (GET JSON "occupancy" IN PAYLOAD AS BOOL)
                    timestamp = {ts}
                    datatype = "boolean"
                    status = "Good"
            SET "k_contact" WITH (GET JSON "contact" IN PAYLOAD AS STRING)
            IF {k_contact} != "null" THEN
                PUBLISH MODEL UnsBoolean TO {pos} + "/Contact" WITH
                    value = (GET JSON "contact" IN PAYLOAD AS BOOL)
                    timestamp = {ts}
                    datatype = "boolean"
                    status = "Good"
            SET "k_leak" WITH (GET JSON "water_leak" IN PAYLOAD AS STRING)
            IF {k_leak} != "null" THEN
                PUBLISH MODEL UnsBoolean TO {pos} + "/WaterLeak" WITH
                    value = (GET JSON "water_leak" IN PAYLOAD AS BOOL)
                    timestamp = {ts}
                    datatype = "boolean"
                    status = "Good"
            SET "k_batlow" WITH (GET JSON "battery_low" IN PAYLOAD AS STRING)
            IF {k_batlow} != "null" THEN
                PUBLISH MODEL UnsBoolean TO {pos} + "/BatteryLow" WITH
                    value = (GET JSON "battery_low" IN PAYLOAD AS BOOL)
                    timestamp = {ts}
                    datatype = "boolean"
                    status = "Good"
```

### Liveness is a chain, and Z2M is only one link of it

Z2M computes device availability, but only **while Z2M is running**. If the Z2M process dies at
02:00, every device still reads `online` at 09:00, with values dated 02:00. The thing that computes
availability is the thing that died. Three independent signals, combined by the consumer:

| Signal | Source | Catches |
|---|---|---|
| `<position>/DeviceStatus` | Z2M per-device availability (active ping for mains devices, passive timeout for battery devices) | one device gone: dead battery, out of range, unplugged |
| `ingest/zigbee2mqtt/BridgeState` | Z2M's own state, `offline` from its MQTT last will | Z2M stopped or crashed, the dongle lost |
| `ingest/zigbee2mqtt/Session` | the **broker** sees Z2M's MQTT session connect and drop | Z2M hung with the session still open is *not* caught here: that is what leaf freshness is for |

A consumer treats a leaf as live only when its `DeviceStatus` is `online`, `BridgeState` is
`online`, and its `timestamp` is younger than the device's reporting interval allows.

**Reads:** `zigbee2mqtt/+/availability`. **Writes:** `<position>/DeviceStatus`. Z2M 2.x always sends
JSON; a plain `online`/`offline` (the pre-2.0 form) is accepted as well.

```lot
DEFINE ACTION ZigbeeAvailabilityToUns
ON TOPIC "zigbee2mqtt/+/availability" DO
    SET "dev" WITH TOPIC POSITION 2
    SET "pos" WITH (GET TOPIC "ingest/zigbee2mqtt/map/" + {dev})
    IF {pos} != EMPTY THEN
        SET "state" WITH (GET JSON "state" IN PAYLOAD AS STRING)
        IF {state} == "null" THEN
            SET "state" WITH (PAYLOAD AS STRING)
        PUBLISH MODEL UnsText TO {pos} + "/DeviceStatus" WITH
            value = {state}
            timestamp = TIMESTAMP "ISO"
            datatype = "string"
            status = "Good"
```

**Reads:** `zigbee2mqtt/bridge/state`. **Writes:** `ingest/zigbee2mqtt/BridgeState`.

```lot
DEFINE ACTION ZigbeeBridgeState
ON TOPIC "zigbee2mqtt/bridge/state" DO
    SET "state" WITH (GET JSON "state" IN PAYLOAD AS STRING)
    IF {state} == "null" THEN
        SET "state" WITH (PAYLOAD AS STRING)
    PUBLISH MODEL UnsText TO "ingest/zigbee2mqtt/BridgeState" WITH
        value = {state}
        timestamp = TIMESTAMP "ISO"
        datatype = "string"
        status = "Good"
```

**Reads:** MQTT client lifecycle of the account `zigbee2mqtt`. **Writes:** `ingest/zigbee2mqtt/Session`.
The broker evaluates lifecycle triggers only when an action defines one, so these two cost nothing
otherwise.

```lot
DEFINE ACTION ZigbeeSessionUp
ON CONNECT DO
    IF USER IS "zigbee2mqtt" THEN
        PUBLISH MODEL UnsText TO "ingest/zigbee2mqtt/Session" WITH
            value = "connected"
            timestamp = TIMESTAMP "ISO"
            datatype = "string"
            status = "Good"
```

```lot
DEFINE ACTION ZigbeeSessionDown
ON DISCONNECT DO
    IF USER IS "zigbee2mqtt" THEN
        PUBLISH MODEL UnsText TO "ingest/zigbee2mqtt/Session" WITH
            value = "disconnected"
            timestamp = TIMESTAMP "ISO"
            datatype = "string"
            status = "Good"
```

### Pairing from the broker

**Reads:** `ingest/zigbee2mqtt/permit_join` (seconds). **Writes:** `zigbee2mqtt/bridge/request/permit_join`.

Opens the network for the given number of seconds: Z2M 2.x expects `{"time": <seconds>}`, caps it
at 254, and `0` closes the network (permanent joining was removed in 2.0, deliberately). Publish `120`, power the new sensor on or hold its pairing button,
then watch `ingest/zigbee2mqtt/unmapped/#` for its first message, give it a friendly name in the Z2M
frontend, and add its line to `ZigbeeDeviceMap`. Z2M answers on `zigbee2mqtt/bridge/response/permit_join`.

The request is built as a string and sent with `PUBLISH TOPIC`, not `PUBLISH MODEL`, on purpose: an
action's `PUBLISH TOPIC` is not subject to user publish Rules, but its `PUBLISH MODEL` is, and Rule 1
below allows only Z2M and root to write under `zigbee2mqtt/`.

```lot
DEFINE ACTION ZigbeePermitJoin
ON TOPIC "ingest/zigbee2mqtt/permit_join" DO
    PUBLISH TOPIC "zigbee2mqtt/bridge/request/permit_join" WITH ("{\"time\": " + (PAYLOAD AS INT) + "}")
```

## Rules

**Run these last.** They confine the Z2M account to its own namespace and keep the raw plane away
from applications, which read the UNS instead. An application reading a raw topic is a missing UNS
leaf, not a shortcut.

Create the account first, with its own password (never the shared `root`):
`-addUser zigbee2mqtt <password>` on `$SYS/Coreflux/Command`, or in the Hub's user management.

Priorities sit in the 2.14 user band. The lower number is the stronger band, and inside a band a DENY
wins. The two confinement rules are deliberately the *weakest* user band (`999000`), just above the
broker's own allow-all seeds at `1000000`, so they never override an access design you already run;
the two raw-plane rules at `200` decide the `zigbee2mqtt/#` subtree.

### Rule 1 — only Z2M (and root) write the raw plane (priority 200)

An action's `PUBLISH TOPIC` is not subject to user publish Rules (2.14.2+), so `ZigbeePermitJoin`
still reaches Z2M. An action's `PUBLISH MODEL` **is**: that is why nothing in this notebook writes a
Model into `zigbee2mqtt/`.

```lot
DEFINE RULE Zigbee2mqttRawPublish WITH PRIORITY 200 FOR Publish TO TOPIC "zigbee2mqtt/#"
    IF USER IS "zigbee2mqtt" OR USER IS "root" THEN
        ALLOW
    ELSE
        DENY
```

### Rule 2 — only Z2M (and root) read the raw plane (priority 200)

Z2M subscribes to its own `…/set` and `bridge/request/#` topics; root keeps the Hub's Data Viewer.

```lot
DEFINE RULE Zigbee2mqttRawSubscribe WITH PRIORITY 200 FOR Subscribe TO TOPIC "zigbee2mqtt/#"
    IF USER IS "zigbee2mqtt" OR USER IS "root" THEN
        ALLOW
    ELSE
        DENY
```

### Rule 3 — Z2M publishes nowhere else (priority 999000)

No `ELSE`: on 2.14.2+ a rule without one decides the opposite for everyone else, which here is the
same ALLOW the broker's seed gives them.

```lot
DEFINE RULE Zigbee2mqttConfinePublish WITH PRIORITY 999000 FOR Publish TO TOPIC "#"
    IF USER IS "zigbee2mqtt" THEN
        DENY
```

### Rule 4 — Z2M subscribes nowhere else (priority 999000)

```lot
DEFINE RULE Zigbee2mqttConfineSubscribe WITH PRIORITY 999000 FOR Subscribe TO TOPIC "#"
    IF USER IS "zigbee2mqtt" THEN
        DENY
```

### Rule 5 — opening the network is an operator act (priority 200)

```lot
DEFINE RULE ZigbeePermitJoinOperators WITH PRIORITY 200 FOR Publish TO TOPIC "ingest/zigbee2mqtt/permit_join"
    IF USER IS "root" THEN
        ALLOW
    ELSE
        DENY
```

## How to verify

1. Broker version 2.14.2 or newer: `$SYS/Coreflux/Version`.
2. Run Models, Actions; then the simulator notebook (or start Z2M against the broker).
3. In the Hub's Data Viewer subscribe to `acme/site01/#` and `ingest/zigbee2mqtt/#`.
4. Expect envelopes under `acme/site01/LivingRoom/Ambient01/…`, `Voltage` in volts, `Occupancy` and
   `Contact` as JSON booleans, one device under `ingest/zigbee2mqtt/unmapped/` until you map it.
5. Run the Rules, then as a non-root user subscribe to `zigbee2mqtt/#`: denied. As `zigbee2mqtt`,
   publish to `acme/site01/x`: dropped.
