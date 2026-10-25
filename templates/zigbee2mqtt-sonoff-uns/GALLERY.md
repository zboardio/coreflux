# Gallery submission: templates.coreflux.org

This template's entry on templates.coreflux.org: the submission form field by field, in the form's
order, then the page text under `## Content`. The gallery hands out only the notebooks and this page,
so the Content is self-contained about the template; the rest of this folder is the fuller record.

| Field | Limit | Value |
|---|---|---|
| Title * | ≤ 75 | Zigbee2MQTT + Sonoff USB dongle to a clean UNS |
| Short description * | ≤ 100 | Zigbee2MQTT sensors from a Sonoff USB dongle into a position-based UNS, with liveness and rules. |
| Content | Markdown | the `## Content` section below |
| Category | one | IoT & Connected Devices |
| Broker version * | one | 2.14.3 |
| Difficulty * | one | intermediate |
| GitHub repository | optional | https://github.com/zboardio/coreflux/tree/main/templates/zigbee2mqtt-sonoff-uns |
| Tags | ≤ 8 | `Zigbee2MQTT` · `zigbee` · `Sonoff` · `uns` · `sensors` · `home automation` · `rules` · `data model` |
| .lotnb files | ≤ 5, ≤ 5 MB each | `zigbee2mqtt-sonoff-uns.lotnb` · `zigbee2mqtt-sonoff-uns-simulator.lotnb` |

## Content

## Summary

Battery-powered Zigbee sensors (temperature, humidity, motion, door contact, water leak) go into a **Unified Namespace** on your Coreflux broker, with no vendor cloud and no hub appliance. A Sonoff USB coordinator and Zigbee2MQTT own the radio. This template turns Z2M's device-shaped feed into position-shaped UNS leaves: one topic per measurement under `acme/site01/<Area>/<Position>/<Leaf>`, each the same five-key envelope, addressed by where it is measured, not by which device happens to sit there.
It is the pattern we run on a small edge gateway, generalised. It carries the decisions that are expensive to change later (network key, channel, base topic), the Z2M settings that make a UNS honest, and a liveness chain that still tells the truth when Z2M itself dies.
LoT only: no Python, no Routes. Z2M connects to the broker as an ordinary MQTT client with its own account.

## Key features

- **Position-based UNS:** leaves are addressed by where they measure; one map action is the only place that knows which device sits where, so replacing a sensor keeps every consumer's subscription and history.
- **Honest timestamps:** every leaf carries the device's own `last_seen`, stamped only onto the attributes that message contains.
- **Units owned by the leaf:** Z2M's millivolts become volts; booleans stay JSON booleans.
- **Nothing is dropped:** a freshly paired device that is not mapped yet appears on `ingest/zigbee2mqtt/unmapped/<friendly>`.
- **A liveness chain:** per-device `DeviceStatus`, Z2M's own `BridgeState`, and the broker's view of the Z2M session, which still tell the truth when Z2M itself dies.
- **Pairing from the broker:** open the network for N seconds with one publish.
- **Rules:** the Z2M account is confined to its namespace both ways; applications read the UNS, never the raw plane, and cannot open the network.
- **The Z2M configuration, explained:** every setting the UNS depends on, with its reason, is on this page.

## Who is this for?

Building-automation, facility and OT teams who want Zigbee sensors in the same namespace as their PLC and meter data, and anyone replacing a vendor hub with a broker they control.

## What you will see

- `acme/site01/LivingRoom/Ambient01/Temperature` → `{"value":21.4,"timestamp":"2026-10-06T10:00:00.000Z","datatype":"number","status":"Good","units":"°C"}`.
- `Voltage` in volts, although Z2M reports millivolts.
- `Occupancy` and `Contact` as JSON booleans, and `DeviceStatus` per position.
- A freshly paired, not yet mapped device on `ingest/zigbee2mqtt/unmapped/<friendly>`, not lost.
- `ingest/zigbee2mqtt/BridgeState`, Z2M's own view of itself, and `ingest/zigbee2mqtt/Session`, the broker's view of Z2M's MQTT session.
- Rules: the Z2M account confined to `zigbee2mqtt/#`, the raw plane hidden from applications, pairing an operator act.

## Architecture

Three chains, each a few actions:

**Data chain**
- The Sonoff coordinator → Zigbee2MQTT → `zigbee2mqtt/<friendly>`: one retained JSON object per device, in Z2M's vocabulary.
- `ZigbeeDeviceMap` holds one line per device: friendly name → UNS position.
- `ZigbeeToUns` reads every raw device message, looks up its position and publishes one envelope per reported key to `acme/site01/<Area>/<Position>/<Leaf>`, or the raw payload to `ingest/zigbee2mqtt/unmapped/<friendly>`.

**Liveness chain**
- Z2M's `zigbee2mqtt/<friendly>/availability` → `ZigbeeAvailabilityToUns` → `<position>/DeviceStatus`.
- Z2M's last will on `zigbee2mqtt/bridge/state` → `ZigbeeBridgeState` → `ingest/zigbee2mqtt/BridgeState`.
- The broker's own `ON CONNECT` and `ON DISCONNECT` for the account `zigbee2mqtt` → `ZigbeeSessionUp` and `ZigbeeSessionDown` → `ingest/zigbee2mqtt/Session`.

**Pairing chain**
- An operator publishes seconds to `ingest/zigbee2mqtt/permit_join` → `ZigbeePermitJoin` → `zigbee2mqtt/bridge/request/permit_join` as `{"time": 120}`.
- Z2M answers on `zigbee2mqtt/bridge/response/permit_join`, and the new device's first message appears on the unmapped topic.

## Included notebooks

- `zigbee2mqtt-sonoff-uns.lotnb`, for every deployment: three Models, the device map, the mapper, the liveness chain, pairing, and five Rules.
- `zigbee2mqtt-sonoff-uns-simulator.lotnb`, for running without hardware: two SNZB-02 temperature and humidity sensors, an SNZB-03 motion sensor, an SNZB-04 door contact and one paired but unnamed device, with Z2M's exact payloads on Z2M's topics. Never run it next to a real Z2M that uses the same friendly names.

**Verified on 2.14.3**
Every cell of both notebooks deployed on a fresh broker (21 cells), 23 checks passed, no runtime error in the broker log. The checks cover the envelope and its ISO timestamp, mV → V, the device's `last_seen` as the leaf time, booleans, no leaf for an attribute the device did not report, the unmapped topic, availability in both the 2.x and the pre-2.0 form, the broker's session view, the pairing request, and the Rules with real accounts: applications cannot read or forge the raw plane or open the network, Z2M cannot write into the UNS, and the mapper still flows under the Rules.

## Prerequisites

- Coreflux broker **2.14.2 or newer**, and the Hub. The template uses the `ON CONNECT` and `ON DISCONNECT` triggers and the banded Rule priorities of 2.14.2.
- **Anonymous login off**, and the default `root` password changed before anything else.
- A broker account `zigbee2mqtt` with its own password, for Z2M. Never root.
- Zigbee2MQTT 2.x and a Sonoff Zigbee USB coordinator: ZBDongle-P, ZBDongle-E, Dongle Plus MG24, Dongle Max or Dongle Lite. Or nothing at all for the simulator.
- Z2M configured with the settings under *Zigbee2MQTT settings this template depends on*, before anything is paired.

## Topic and data dictionary

**Raw plane, written by Z2M**
- `zigbee2mqtt/<friendly>`: one JSON object per device, retained, e.g. `{"temperature":21.4,"humidity":48,"battery":97,"voltage":2900,"linkquality":120,"last_seen":"…"}`.
- `zigbee2mqtt/<friendly>/availability`: `{"state":"online"}` or `{"state":"offline"}`, retained.
- `zigbee2mqtt/bridge/state`: Z2M's own state, `offline` from its MQTT last will, retained.

**UNS leaves**
All are published by `ZigbeeToUns` under `acme/site01/<Area>/<Position>/`, each as the five-key envelope of `value`, `timestamp`, `datatype`, `status` and `units`:
- `Temperature`: °C, e.g. 21.4.
- `Humidity`: %.
- `Pressure`: hPa.
- `Battery`: %.
- `Voltage`: V, converted from Z2M's mV, e.g. 2.9.
- `LinkQuality`: 0–255, units `1`. Radio transport quality, never a data-quality judgement.
- `Occupancy`, `WaterLeak` and `BatteryLow`: true or false.
- `Contact`: true or false; true means closed.
- `DeviceStatus`: `online` or `offline`, from `ZigbeeAvailabilityToUns`.

**Bridge, session and pairing**
- `ingest/zigbee2mqtt/BridgeState`: envelope, Z2M's view of itself, from `ZigbeeBridgeState`.
- `ingest/zigbee2mqtt/Session`: envelope, `connected` or `disconnected`, the broker's view, from `ZigbeeSessionUp` and `ZigbeeSessionDown`.
- `ingest/zigbee2mqtt/unmapped/<friendly>`: the raw payload of a device that has no position yet.
- `ingest/zigbee2mqtt/permit_join`: seconds to open the network, `0` closes it; root only.
- `ingest/zigbee2mqtt/map/<friendly>`: the device map, broker-internal `KEEP TOPIC` state, never on the wire.

**The envelope**
- `value`: its JSON type matches `datatype`.
- `timestamp`: ISO-8601 UTC, the device's `last_seen`. It is the observation time, never the publish time.
- `datatype`: `number`, `boolean` or `string`.
- `status`: `Good`. Z2M publishes only successful reads, so degraded data shows up as a stale `timestamp` or as `DeviceStatus`, never as a `Bad` sample.
- `units`: on numeric leaves only.

## Quick start

**A] Without hardware (2 mins)**
1. Open the Hub on your broker.
2. In `zigbee2mqtt-sonoff-uns.lotnb` run **Models** and **Actions**.
3. Run `zigbee2mqtt-sonoff-uns-simulator.lotnb` top to bottom.
4. Subscribe to `acme/site01/#` and `ingest/zigbee2mqtt/#`. Leaves arrive within 30 s, and one device waits on the unmapped topic.
5. Run the **Rules** last.

**B] With a Sonoff dongle**
1. In the Hub, create the user `zigbee2mqtt` with its own password.
2. Give the dongle a stable device name, never `/dev/ttyUSB0`: in a container, map `/dev/serial/by-id/<your dongle>` to `/dev/zigbee`; on a host, use the udev rule under *Production readiness*.
3. Write Z2M's `configuration.yaml` with the settings below, and put the broker password in Z2M's `secret.yaml` as `mqtt_password`. **Decide the channel now**, before anything is paired.
4. In `zigbee2mqtt-sonoff-uns.lotnb` run **Models** and **Actions**, but not the simulator.
5. Start Z2M. `ingest/zigbee2mqtt/BridgeState` reads `online` and `ingest/zigbee2mqtt/Session` reads `connected`.
6. Pair a sensor: publish `120` to `ingest/zigbee2mqtt/permit_join` and press the sensor's pairing button. Its first message appears on `ingest/zigbee2mqtt/unmapped/0x…`.
7. Rename it in the Z2M frontend, e.g. `LivingRoom-SNZB02-01`, add its line to `ZigbeeDeviceMap`, and redeploy that action.
8. Create your application accounts, then run the **Rules**.

## How it works

**Two planes**
Z2M owns `zigbee2mqtt/#`: device-shaped, retained, its own vocabulary. The UNS under `acme/site01/` is position-shaped and vendor-neutral. Nothing but the mapper reads the raw plane: an application that reads a raw topic is a missing UNS leaf, not a shortcut, and Rule 2 enforces that.

**The device map**
`ZigbeeDeviceMap` runs on start, so on every deploy and every broker start, and keeps one line per device: friendly name → UNS position. Replacing a sensor means pairing the new one under the old friendly name, and every consumer keeps its subscription and its history. Moving a sensor is one edited line.
Friendly names must not contain `/`: Z2M allows it, but the mapper's `zigbee2mqtt/+` trigger would then miss the device. The naming that has worked well is `<Area>-<Model>-<nn>`, e.g. `LivingRoom-SNZB02-01`.

**The mapper**
`ZigbeeToUns` tests every key before publishing it. An attribute exists only once the device has reported it: a motion sensor sends `occupancy` only after its first motion, `battery_low` only when it changes. An absent key publishes nothing, never a null. On the broker a missing JSON path reads as the string `"null"`, which is what the tests compare against.
It stamps `last_seen` only onto what the message carries, which is honest because Z2M runs with `cache_state: false`. Units are converted once, here: `voltage` is multiplied by 0.001, because dividing by an integer would truncate on the broker.

**Liveness is a chain**
Z2M computes device availability, but only while Z2M runs: if the Z2M process dies at 02:00, every device still reads `online` at 09:00, with values dated 02:00. So three signals are published, and a consumer trusts a leaf only when all three agree:
- the position's `DeviceStatus` is `online`, which catches one device gone: a dead battery, out of range, unplugged;
- `BridgeState` is `online`, which catches Z2M stopped or crashed, or the dongle lost;
- the leaf's `timestamp` is younger than the device's reporting interval allows, which catches the rest, including a hung Z2M.

`Session` adds the broker's own, independent view of the Z2M connection. The broker evaluates lifecycle triggers only when an action defines one, so the two session actions cost nothing otherwise.

**Retention**
The raw plane is retained by Z2M. The clean leaves are published by LoT as live events. A consumer that needs a value the instant it connects reads the raw topic once, or waits for the next report: a battery sensor reports roughly every 30–60 minutes, a mains device more often.

**Pairing**
Z2M 2.x expects `{"time": <seconds>}`, caps it at 254, and `0` closes the network; permanent joining was removed in 2.0, deliberately. `ZigbeePermitJoin` builds that request as a string and sends it with `PUBLISH TOPIC`, not `PUBLISH MODEL`: an action's `PUBLISH TOPIC` is not subject to user publish Rules, its `PUBLISH MODEL` is, and Rule 1 admits only Z2M and root under `zigbee2mqtt/`.

**The Rules**
- Rule 1, priority 200: only `zigbee2mqtt` and root publish under `zigbee2mqtt/#`.
- Rule 2, priority 200: only `zigbee2mqtt` and root subscribe to `zigbee2mqtt/#`; root keeps the Hub's Data Viewer.
- Rules 3 and 4, priority 999000: the `zigbee2mqtt` account publishes and subscribes nowhere else.
- Rule 5, priority 200: only root publishes to `ingest/zigbee2mqtt/permit_join`.

The lower number is the stronger band, and inside a band a DENY wins. The confinement rules sit in the weakest user band, just above the broker's allow-all seeds at 1000000, so they never override an access design you already run. Rules 3 and 4 have no ELSE: on 2.14.2 and newer a rule without one decides the opposite for everyone else, which here is the same ALLOW the seeds give them.

## Zigbee2MQTT settings this template depends on

Z2M's defaults suit a Home Assistant install, not a UNS. Every non-default value below is a decision, and each comes with its reason. Three are marked **decide before pairing**: changing them later re-pairs every device. Z2M rewrites its `configuration.yaml` itself and drops the comments, so keep this list as the explanation.

**MQTT**
- `mqtt.server`: your broker, e.g. `mqtt://127.0.0.1:1883` for a broker on the same host.
- `mqtt.base_topic: zigbee2mqtt`, decide before pairing. Z2M's own default, and deliberately outside the UNS: this is the raw plane the notebook maps.
- `mqtt.user: zigbee2mqtt` with `mqtt.password: '!secret.yaml mqtt_password'`: its own account, confined by the Rules, and the password kept in `secret.yaml`, out of `configuration.yaml`.
- `mqtt.client_id: zigbee2mqtt`: a stable, non-empty client id, so a reconnect replaces the old session instead of looking like a second client, and the broker's session view stays readable.

**Serial**
- `serial.port: /dev/zigbee`: a stable name from a container device mapping or the udev rule, never `/dev/ttyUSB0` or `/dev/ttyACM0`, which follow enumeration order.
- `serial.adapter`: since 2.0 there is no default. `zstack` for the ZBDongle-P and the Dongle-PP10; `ember` for the ZBDongle-E, Dongle Plus MG24, Dongle Max and Dongle Lite. `ezsp` is deprecated; never set `rtscts: true` on these.
- Do not tell the P from the E by USB id: the E also ships with the same CP210x bridge, 10c4:ea60. Read the label, or the by-id name: `…_V2_…` is an E.
- `serial.baudrate: 115200` and `serial.rtscts: false`.

**Device options and availability**
- `device_options.retain: true`: Z2M's default is false, and a device's state then exists on the broker only in the instant it is published. Retained, the raw plane always holds the last reading.
- `availability.enabled: true`: off by default. It publishes the availability topics the notebook maps to `DeviceStatus`.
- `availability.active.timeout: 10` minutes for mains devices, which are pinged, and `availability.passive.timeout: 1500` minutes, 25 h, for battery devices, which sleep. That is why a sensor with a dead battery reads `online` for a day.

**Advanced**
- `advanced.cache_state: false`: Z2M's default true is wrong for a UNS. With it on, every message repeats every attribute ever reported under one `last_seen`, and a battery reading from 09:00 re-sent with the 14:00 temperature looks five hours fresher than it is. Home Assistant's integration needs it on; this template does not use Home Assistant.
- `advanced.last_seen: ISO_8601`: the observation time of every message, used as the leaf timestamp. The default is off, and then a retained reading from three hours ago looks like a live one.
- `advanced.output: json`: one JSON object per device, the shape the mapper parses.
- `advanced.channel: 25`, decide before pairing. 25 sits above WiFi channel 11, while Z2M's default 11 overlaps WiFi channel 1. A few very old devices reject 26. Use 11, 15, 20 or 25.
- `advanced.network_key`, `advanced.pan_id` and `advanced.ext_pan_id` set to `GENERATE`, decide before pairing, and not optional. Z2M's defaults are published constants: omit them and your network is encrypted with a key everyone knows, on the same PAN id as every other default install in radio range. `GENERATE` mints real values on the first start, and from then on the file holds the network key.
- `advanced.enable_external_js: false`: the default true loads user-supplied JavaScript converters and runs them in-process. This template needs none, and on a gateway that is code execution for nothing.

**Frontend, OTA and Home Assistant**
- `frontend.enabled: true` on port 8080. It has no authentication until you set `frontend.auth_token`, as a `secret.yaml` reference; keep it on localhost or behind your access layer.
- `ota.disable_automatic_update_check: true`: by default a device can make Z2M fetch firmware from the internet. On an OT gateway that is unplanned outbound traffic and an unplanned firmware update on a field device. Update deliberately, from the frontend.
- `homeassistant.enabled: false`.
- `permit_join` is no longer a setting since 2.0: pair from the frontend, or from the broker with `ingest/zigbee2mqtt/permit_join`.

## Production readiness

**Remove the simulator**
Do not run `zigbee2mqtt-sonoff-uns-simulator.lotnb` next to a real Z2M: both would write the same raw topics. Nothing else changes.

**Rules first, accounts per role**
Create `zigbee2mqtt` and one account per application, deploy the Rules, then connect Z2M. The notebook keeps the Rules last only so that a demo never locks the deploying session out halfway.

**Run Z2M as a host service on an unattended gateway**
A container's device mapping is resolved once, when the container is created. If the dongle re-enumerates (another USB port, a replug, a powered hub coming up in a different order, a kernel update), the container keeps pointing at a device that is no longer the coordinator until it is recreated. Mapping `/dev/serial/by-id/…` does not help, because the symlink is resolved at the same moment. The robust form is a udev rule and a systemd unit:
- The udev rule, as `/etc/udev/rules.d/60-zigbee.rules`: `SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", ATTRS{serial}=="<your dongle serial>", SYMLINK+="zigbee", ENV{ID_MM_DEVICE_IGNORE}="1", TAG+="systemd", ENV{SYSTEMD_WANTS}="zigbee2mqtt.service"`, then `sudo udevadm control --reload && sudo udevadm trigger`.
- Read your dongle's values with `udevadm info -a -n /dev/ttyUSB0`; a Dongle Plus MG24, Max or Lite may enumerate as `/dev/ttyACM0`, and a ZBDongle-E with the CH9102 bridge is 1a86 / 55d4.
- `ATTRS{serial}` pins the rule to this dongle, so a second adapter with the same USB bridge cannot race for the name. Replacing the dongle means editing this one value.
- `ID_MM_DEVICE_IGNORE` keeps ModemManager off the port. ModemManager probes new serial devices with AT commands, which shows up as an intermittent failure to start, not as a clean error.
- `TAG+="systemd"` publishes `dev-zigbee.device`, and the unit binds to it with `BindsTo=dev-zigbee.device`: unplugging stops Z2M cleanly, replugging into any port starts it again. This is what a container's device mapping cannot do.
- The unit runs Z2M as a dedicated unprivileged account in the `dialout` group, with `Type=notify`, `WatchdogSec=30s`, `Restart=always` and `StartLimitIntervalSec=0`: an unattended gateway that has given up looks exactly like one that is fine.
- `RequiresMountsFor=` on the data directory: without it Z2M would create an empty data folder and come up as a brand-new network with every device unpaired.
- Sandbox it with `ProtectSystem=strict`, write access to the data and install folders only, and `MemoryMax=1G`, because the process holds the network key. Do not set `PrivateDevices`: it would hide `/dev/zigbee`.
- Build Z2M once by hand before the first start, with `libsystemd-dev` installed for the sd-notify binding. Otherwise Z2M recompiles itself on start and exceeds the start timeout on a small CPU, or never reports ready and is killed while it runs fine.

**Back up the data folder, and know what a rebuild means**
Z2M's data folder holds the network key and the device database: losing it means re-pairing every device by hand. Back it up as a whole. The Zigbee network lives in four places, and only one of them is `configuration.yaml`:
- `configuration.yaml`: the parameters Z2M will ask for;
- `coordinator_backup.json`: the network Z2M formed;
- the dongle's own memory: the network itself;
- `database.db`: the devices paired to it.

Rewriting `configuration.yaml` with new keys while the other three still hold the old network makes Z2M refuse to start with `configuration-adapter mismatch`. That refusal is deliberate, and it protects you. To really start a new network, stop Z2M, move `coordinator_backup.json`, `database.db` and `state.json` aside and keep them, since they are the only record of the old network, then start Z2M with the new configuration. Re-pairing every device is the price.

**Credentials and network exposure**
- Z2M's broker password lives in `secret.yaml`, never in `configuration.yaml` or in git.
- After the first start, `configuration.yaml` holds the generated network key: treat the whole data folder as a secret.
- Bind the broker's MQTT port to the network your devices use, deliberately.

## How to customize

1. **UNS root and positions:** edit the right-hand side of each `ZigbeeDeviceMap` line. The mapper writes wherever the map points; nothing else changes.
2. **Another sensor type:** copy one key block in `ZigbeeToUns`, raw key → leaf and unit. Check the device's page on zigbee2mqtt.io for the exact key and unit, and convert to the unit the leaf should own.
3. **A second Z2M instance** for another radio or building: give it its own `base_topic` and account, and copy the mapper with that topic and its own map prefix.
4. **Actuators** such as plugs and valves: map a UNS `…/set` topic back to `zigbee2mqtt/<friendly>/set` in an action with `PUBLISH TOPIC`, because an action's `PUBLISH MODEL` is subject to the raw-plane Rule.

## Security notes

- Z2M's account is confined to `zigbee2mqtt/#` both ways by Rules 1 to 4; it cannot write into the UNS.
- Applications cannot read or forge the raw plane, and cannot open the network for pairing, by Rule 5.
- The network key is generated per install with `GENERATE`; Z2M's built-in defaults are public constants.
- External JavaScript converters are off, and so are automatic OTA checks: updating firmware is a deliberate act.
- Anonymous login stays off, and the default `root` password is changed before anything else.

## Field notes

- **Cached state fabricates freshness:** with Z2M's default `cache_state: true`, every message re-sends every attribute ever reported under one `last_seen`. A battery leaf then never looks stale, and a historian stores copies of old values with new timestamps.
- **A dead battery reads online for a day:** the passive availability timeout is 25 h, because pinging a sleeping device drains it. Leaf freshness is the earlier signal.
- **The first motion creates the key:** a motion sensor has no `occupancy` key until its first motion. Mappers must treat "absent" as "not reported", never as false or zero.
- **Decide the channel and keys before pairing:** channel 25 avoids the common WiFi channels; a few very old devices reject 26.
- **ModemManager grabs serial ports:** on a desktop or general-purpose image it takes CP210x ports intermittently. The udev rule's `ID_MM_DEVICE_IGNORE` settles it.

&nbsp;
