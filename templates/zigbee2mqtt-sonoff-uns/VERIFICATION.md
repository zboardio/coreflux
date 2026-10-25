# Verification

Run 2026-10-25 22:55 UTC on a fresh `coreflux/coreflux-mqtt-broker:2.14.3` broker
(`sha256:687ce646041a…`, durability on, default accounts) in local Docker,
by the template's maintainers. The run deploys every code cell in notebook order (Rules last),
runs the simulator, then checks what arrives on the wire with an MQTT 5 observer.

**Cells deployed: 21/21 accepted. Checks: 23/23 passed. Runtime errors in the broker log: 0.**

## Deploy verdicts

| notebook | entity | verdict |
|---|---|---|
| `zigbee2mqtt-sonoff-uns.lotnb.md` | `MODEL UnsNumber` | accepted |
| `zigbee2mqtt-sonoff-uns.lotnb.md` | `MODEL UnsBoolean` | accepted |
| `zigbee2mqtt-sonoff-uns.lotnb.md` | `MODEL UnsText` | accepted |
| `zigbee2mqtt-sonoff-uns.lotnb.md` | `ACTION ZigbeeDeviceMap` | accepted |
| `zigbee2mqtt-sonoff-uns.lotnb.md` | `ACTION ZigbeeToUns` | accepted |
| `zigbee2mqtt-sonoff-uns.lotnb.md` | `ACTION ZigbeeAvailabilityToUns` | accepted |
| `zigbee2mqtt-sonoff-uns.lotnb.md` | `ACTION ZigbeeBridgeState` | accepted |
| `zigbee2mqtt-sonoff-uns.lotnb.md` | `ACTION ZigbeeSessionUp` | accepted |
| `zigbee2mqtt-sonoff-uns.lotnb.md` | `ACTION ZigbeeSessionDown` | accepted |
| `zigbee2mqtt-sonoff-uns.lotnb.md` | `ACTION ZigbeePermitJoin` | accepted |
| `zigbee2mqtt-sonoff-uns-simulator.lotnb.md` | `ACTION SimZigbeeBridgeOnline` | accepted |
| `zigbee2mqtt-sonoff-uns-simulator.lotnb.md` | `ACTION SimLivingRoomSnzb02` | accepted |
| `zigbee2mqtt-sonoff-uns-simulator.lotnb.md` | `ACTION SimBedroomSnzb02` | accepted |
| `zigbee2mqtt-sonoff-uns-simulator.lotnb.md` | `ACTION SimCorridorSnzb03` | accepted |
| `zigbee2mqtt-sonoff-uns-simulator.lotnb.md` | `ACTION SimEntranceSnzb04` | accepted |
| `zigbee2mqtt-sonoff-uns-simulator.lotnb.md` | `ACTION SimUnmappedDevice` | accepted |
| `zigbee2mqtt-sonoff-uns.lotnb.md` | `RULE Zigbee2mqttRawPublish` | accepted |
| `zigbee2mqtt-sonoff-uns.lotnb.md` | `RULE Zigbee2mqttRawSubscribe` | accepted |
| `zigbee2mqtt-sonoff-uns.lotnb.md` | `RULE Zigbee2mqttConfinePublish` | accepted |
| `zigbee2mqtt-sonoff-uns.lotnb.md` | `RULE Zigbee2mqttConfineSubscribe` | accepted |
| `zigbee2mqtt-sonoff-uns.lotnb.md` | `RULE ZigbeePermitJoinOperators` | accepted |

## Checks

| # | what is checked | result | evidence |
|---|---|---|---|
| Z1 | Temperature leaf is the five-key envelope with °C and an ISO-8601 Z timestamp | PASS | acme/site01/LivingRoom/Ambient01/Temperature {"value":21.308985667764826,"timestamp":"2026-10-25T22:54:02.003Z","datatype":"number","status":"Good","units":"\u00B0C"} |
| Z2 | Voltage is converted mV → V (2900 → 2.9) and labelled V | PASS | acme/site01/LivingRoom/Ambient01/Voltage {"value":2.9,"timestamp":"2026-10-25T22:54:02.003Z","datatype":"number","status":"Good","units":"V"} |
| Z3 | the leaf timestamp is the device's last_seen, not the publish time | PASS | leaf 2026-10-25T22:54:02.003Z / raw last_seen 2026-10-25T22:54:02.003Z |
| Z4 | Occupancy arrives as a JSON boolean and toggles | PASS | 4 messages, values ['False', 'True'] |
| Z5 | Contact maps to a boolean leaf | PASS | acme/site01/Entrance/Door01/Contact {"value":true,"timestamp":"2026-10-25T22:54:06.873Z","datatype":"boolean","status":"Good"} |
| Z6 | an attribute the device did not report publishes NO leaf (motion sensor: no Temperature) | PASS | 0 unexpected leaves |
| Z7 | an unmapped device is surfaced on ingest/zigbee2mqtt/unmapped/<friendly>, not dropped | PASS | ingest/zigbee2mqtt/unmapped/0x00158d0001a2b3c4 {"battery":100,"humidity":50.0,"linkquality":150,"temperature":22.0,"voltage":3100,"last_seen":"2026-10-25T22:54:42.863Z"} |
| Z8 | availability → DeviceStatus envelope | PASS | acme/site01/LivingRoom/Ambient01/DeviceStatus {"value":"online","timestamp":"2026-10-25T22:53:42.129Z","datatype":"string","status":"Good"} |
| Z9 | bridge/state → BridgeState | PASS | ingest/zigbee2mqtt/BridgeState {"value":"online","timestamp":"2026-10-25T22:53:42.125Z","datatype":"string","status":"Good"} |
| Z10 | a plain-string availability (pre-2.0 form) is accepted | PASS | acme/site01/Bedroom/Ambient01/DeviceStatus {"value":"offline","timestamp":"2026-10-25T22:54:47.038Z","datatype":"string","status":"Good"} |
| Z11 | a message carrying only temperature publishes only Temperature (cache_state: false contract) | PASS | leaves published: ['Temperature'] |
| Z12 | the broker's own view of the Z2M session: connected, then disconnected | PASS | Session values: ['connected', 'disconnected'] |
| Z13 | permit_join request reaches Z2M as {"time": 120} | PASS | zigbee2mqtt/bridge/request/permit_join {"time": 120} |
| R1 | an application account cannot subscribe to the raw plane zigbee2mqtt/# | PASS | SUBACK |
| R2 | an application account can subscribe to the UNS | PASS | SUBACK |
| R3 | the Z2M account can subscribe to its own namespace | PASS | SUBACK |
| R4 | the Z2M account cannot subscribe elsewhere | PASS | SUBACK |
| R5 | the Z2M account can publish its raw plane | PASS | root observer |
| R6 | the Z2M account cannot publish into the UNS | PASS | root observer |
| R7 | an application cannot forge raw device data | PASS | root observer |
| R8 | an application cannot open the network for pairing | PASS | root observer |
| R9 | the simulator and the mapper (LoT) still flow under the Rules | PASS | new Temperature after Rules |
| R10 | root's pairing request still reaches Z2M under the Rules | PASS | zigbee2mqtt/bridge/request/permit_join {"time": 60} |

## Runtime errors (broker log)

None.
