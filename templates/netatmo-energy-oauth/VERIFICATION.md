# Verification

Run 2026-10-25 22:57 UTC on a fresh `coreflux/coreflux-mqtt-broker:2.14.3` broker
(`sha256:687ce646041a…`, durability on, default accounts) in local Docker,
by the template's maintainers. The run deploys every code cell in notebook order (Rules last),
runs the simulator, then checks what arrives on the wire with an MQTT 5 observer.

**Cells deployed: 39/39 accepted. Checks: 25/25 passed. Runtime errors in the broker log: 0.**

## Deploy verdicts

| notebook | entity | verdict |
|---|---|---|
| `netatmo-energy-oauth.lotnb.md` | `MODEL UnsNumber` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `MODEL UnsBoolean` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `MODEL UnsText` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `PYTHON NetatmoEnergy` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ROUTE NetatmoEnergyApi` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoTokenRefreshTick` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoTokenStore` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoPollTick` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoHomesDataTick` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoHomesDataAnswer` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoHomeStatusAnswer` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoFanoutStep` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoRoomMap` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoRoomToUns` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoSetpointCommand` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoCommandAnswer` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `RULE NetatmoAuthSubscribe` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `RULE NetatmoInternalPublish` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `RULE NetatmoSetpointWriters` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `MODEL UnsNumber` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `MODEL UnsBoolean` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `MODEL UnsText` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `PYTHON NetatmoEnergy` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoTokenRefreshTick` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoTokenStore` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoPollTick` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoHomesDataTick` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoHomesDataAnswer` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoHomeStatusAnswer` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoFanoutStep` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoRoomMap` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoRoomToUns` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoSetpointCommand` | accepted |
| `netatmo-energy-oauth.lotnb.md` | `ACTION NetatmoCommandAnswer` | accepted |
| `netatmo-energy-oauth-simulator.lotnb.md` | `PYTHON NetatmoSim` | accepted |
| `netatmo-energy-oauth-simulator.lotnb.md` | `ACTION SimNetatmoHomesData` | accepted |
| `netatmo-energy-oauth-simulator.lotnb.md` | `ACTION SimNetatmoHomeStatus` | accepted |
| `netatmo-energy-oauth-simulator.lotnb.md` | `ACTION SimNetatmoSetpoint` | accepted |
| `netatmo-energy-oauth-simulator.lotnb.md` | `ACTION SimNetatmoKickoff` | accepted |

## Checks

| # | what is checked | result | evidence |
|---|---|---|---|
| N1 | with NETATMO_HOME_ID unset, the first poll fails harmlessly, /homesdata fills it in, the home is read | PASS | acme/site01/LivingRoom/Radiator01/Temperature {"value":20.3,"timestamp":"2026-10-25T22:55:51Z","datatype":"number","status":"Good","units":"\u00B0C"}; mock {'refresh_ok': 0, 'invalid_grant': 0, 'code2 |
| N2 | netatmo/discovery lists the rooms and the ready-to-paste map lines | PASS | 3 rooms, 6 map lines |
| N3 | Temperature is the five-key envelope, °C, timestamp = Netatmo's time_server in ISO-8601 Z | PASS | acme/site01/LivingRoom/Radiator01/Temperature {"value":20.3,"timestamp":"2026-10-25T22:55:51Z","datatype":"number","status":"Good","units":"\u00B0C"} |
| N4 | every mapped leaf arrives with its type: Voltage in V, SetpointMode text, OpenWindow boolean | PASS | leaves ['BatteryState', 'HeatingPowerRequest', 'OpenWindow', 'Reachable', 'RfStrength', 'Setpoint', 'SetpointMode', 'Temperature', 'Voltage']; Voltage 2.7 |
| N5 | raw plane joins /homestatus and /homesdata: room name and its valve | PASS | netatmo/raw/1001 {"room_id":"1001","room_name":"Living room","therm_measured_temperature":20.3,"therm_setpoint_temperature":19.0,"therm_setpoint_mode":"schedule","therm_setpoint_end_time":179297075 |
| N6 | a room missing from the map appears on netatmo/unmapped/<room_id> | PASS | netatmo/unmapped/1003 {"room_id":"1003","room_name":"Office","therm_measured_temperature":22.4,"therm_setpoint_temperature":19.0,"therm_setpoint_mode":"schedule","therm_setpoint_end_time":1792970751," |
| N7 | a refresh rotates both tokens into the secret store; the Good event carries the declared lifetime | PASS | [{'event': 'tokenRefresh', 'status': 'Good', 'timestamp': '2026-10-25T22:55:59.769Z', 'expiresIn': 10800}]; mock refresh_ok 1 |
| N8 | the next poll uses the rotated access token (no route reload) | PASS | [{'event': 'homeStatus', 'status': 'Good', 'timestamp': '2026-10-25T22:56:03.678Z', 'observedAt': '2026-10-25T22:56:03Z', 'rooms': 3}] |
| N9 | expired token (403 code 3) heals itself: a Bad event says so and that a refresh runs; next poll Good | PASS | poll events [('Bad', 3), ('Good', None)] |
| N10 | refresh/poll collision (403 code 2) heals itself: the next poll is Good | PASS | poll events [('Bad', 2), ('Good', None)] |
| N11 | a refresh during a network outage leaves the stored tokens intact: the next refresh succeeds | PASS | during: [{'event': 'tokenRefresh', 'status': 'Bad', 'timestamp': '2026-10-25T22:56:28.068Z', 'httpStatus': 0, 'error': 'HttpRequestException', 'message': 'Name or service not known (netatmo-mock:8080) |
| N12 | Setpoint/set → Netatmo → a Good setpoint event for that area, and the confirming poll shows 23, manual | PASS | cmd [{'event': 'setpoint', 'status': 'Good', 'timestamp': '2026-10-25T22:56:35.379Z', 'observedAt': '2026-10-25T22:56:35Z', 'area': 'LivingRoom', 'value': 23.0}]; Setpoint [23] |
| N13 | a command for an area the map does not know is refused with a Bad event naming the area | PASS | [{'event': 'setpoint', 'status': 'Bad', 'timestamp': '2026-10-25T22:56:40.186Z', 'error': 'area not in the room map', 'subject': 'Garage'}] |
| N14 | no token ever appears on a status, discovery or UNS topic | PASS | 0 leaks |
| N15 | every status event is JSON with event, status Good/Bad and an ISO-8601 Z timestamp | PASS | 17 events, 0 malformed [] |
| R0 | anonymous login is refused (the Route's empty user name is admitted by Rule 2) | PASS | CONNACK |
| R1 | an application cannot subscribe to the token hop netatmo/_auth/# | PASS | SUBACK |
| R2 | an application can subscribe to the UNS | PASS | SUBACK |
| R3 | an application cannot force a refresh or call the API | PASS | mock {'refresh_ok': 5, 'invalid_grant': 0, 'code2': 1, 'code3': 1, 'homestatus_ok': 5, 'homesdata_ok': 1, 'setpoint_ok': 1, 'bad_home': 1} |
| R4 | an application cannot change a setpoint | PASS | setpoint_ok 1 |
| R5 | hvac_operator can change a setpoint | PASS | mock {'refresh_ok': 5, 'invalid_grant': 0, 'code2': 1, 'code3': 1, 'homestatus_ok': 6, 'homesdata_ok': 1, 'setpoint_ok': 2, 'bad_home': 1} |
| R6 | the LoT chain (poll, fan-out, UNS) still runs under the Rules | PASS | new Temperature after Rules |
| S1 | the simulator alone fills the UNS for both mapped rooms | PASS | 36 UNS messages |
| S2 | the unmapped office shows on netatmo/unmapped/1003 | PASS |  |
| S3 | a setpoint command round-trips through the simulated cloud | PASS | Setpoint [22.5] |

## Runtime errors (broker log)

None.
