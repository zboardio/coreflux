# Gallery submission: templates.coreflux.org

This template's entry on templates.coreflux.org: the submission form field by field, in the form's
order, then the page text under `## Content`. The gallery hands out only the notebooks and this page,
so the Content is self-contained about the template; the rest of this folder is the fuller record.

| Field | Limit | Value |
|---|---|---|
| Title * | ≤ 75 | Netatmo Energy over REST, OAuth 2 on the broker |
| Short description * | ≤ 100 | Poll Netatmo valves into a UNS and write setpoints back; OAuth 2 token rotation runs in the broker. |
| Content | Markdown | the `## Content` section below |
| Category | one | IoT & Connected Devices |
| Broker version * | one | 2.14.3 |
| Difficulty * | one | advanced |
| GitHub repository | optional | https://github.com/zboardio/coreflux/tree/main/templates/netatmo-energy-oauth |
| Tags | ≤ 8 | `Netatmo` · `OAuth` · `rest-api` · `uns` · `Python` · `Secrets` · `rules` · `home automation` |
| .lotnb files | ≤ 5, ≤ 5 MB each | `netatmo-energy-oauth.lotnb` · `netatmo-energy-oauth-simulator.lotnb` |

## Content

## Summary

Netatmo smart radiator valves (NRV), thermostats (NATherm1) and their relay report to the Netatmo cloud only: there is no local API. This template polls the Netatmo Energy API from the broker, publishes every room into a **Unified Namespace**, and lets an operator change a room's setpoint from the UNS.
The whole OAuth 2 refresh-token rotation runs **inside the Coreflux broker**: no container, no cron script, no token in a file. A REST Route posts the refresh, an action keeps the rotated pair in the broker's encrypted secret store, and the Route reads the tokens again per request. They never travel from a client and never sit in your git repository.
It is the pattern we run against a live Netatmo account, generalised and hardened by what operating it taught us. Two of its rules came from failures: the refresh must never land in the same second as a poll, and the token store must only ever write a real token pair.

## Key features

- **OAuth 2 rotation on the broker:** the refresh token is replaced on every refresh and stored encrypted; secrets are substituted into each request, with no route reload.
- **A self-healing chain:** an expired or rotated token on any call (401/403) triggers an immediate refresh; a refresh during a network outage overwrites nothing.
- **Collision-proof timing:** a refresh period of `300·n + 1` seconds never lands in the same second as the 5-minute poll, the cause of intermittent "Invalid access_token" errors.
- **A measured token lifetime:** 70 expiries on a live account, not the vendor's word (below).
- **No room ids in code:** the fan-out walks the home's rooms one message at a time; one map action places each room in your UNS, and a discovery topic prints the lines to paste.
- **Typed UNS leaves:** temperature, setpoint, mode, heating demand, open window, reachability, valve battery in volts, radio strength, all in one five-key envelope.
- **Setpoints from the UNS:** `…/Setpoint/set` with `{"value": 21}` reaches the room within seconds, confirmed by the next poll.
- **Rules:** the token hop is root-only, no client can drive the API, and only an operator account changes setpoints.

## Who is this for?

Facility, building-automation and energy teams who want Netatmo heating data next to the rest of their plant data, and anyone integrating a cloud API whose OAuth 2 refresh tokens rotate on every use.

## What you will see

- `acme/site01/LivingRoom/Radiator01/Temperature` → `{"value":20.5,"timestamp":"2026-10-06T17:20:19Z","datatype":"number","status":"Good","units":"°C"}`.
- `Setpoint`, `SetpointMode`, `HeatingPowerRequest` (%), `OpenWindow`, `Reachable`, valve `Voltage` (V), `BatteryState` and `RfStrength` per room.
- `netatmo/discovery`: your home's rooms and valves, plus the ready-to-paste room-map lines.
- A room you have not mapped yet on `netatmo/unmapped/<room_id>`.
- `{"value": 21}` on `…/Setpoint/set` → Netatmo answers `ok` → the confirming poll shows `Setpoint` 21, `SetpointMode` manual.
- `netatmo/_status/auth|poll|cmd`: one JSON event per token answer, poll and command, with `event`, `status` Good/Bad, ISO `timestamp` and the detail, ready for a historian or a state timeline, and never a secret.

## Architecture

Three chains, each a few actions and one Route:

**Token chain**
- `NetatmoTokenRefreshTick` fires every 9001 s and requests a refresh.
- The Route posts it to `/oauth2/token`.
- `NetatmoTokenStore` keeps the new access and refresh tokens with `KEEP SECRET`, in the encrypted secret store.
- Every later request reads the tokens from the secret store, so a new token takes effect without a reload.

**Poll chain**
- `NetatmoPollTick` fires every 5 minutes; the Route calls `GET /api/homestatus`.
- `NetatmoHomeStatusAnswer` checks the answer. On 401 or 403 it requests a refresh at once (the self-heal); on `ok` it starts the fan-out.
- `NetatmoFanoutStep` walks the home one room per message, and `NetatmoRoomToUns` publishes each room to `acme/site01/<Area>/Radiator01/<Leaf>`.

**Command chain**
- An operator publishes to `…/Setpoint/set`.
- `NetatmoSetpointCommand` looks the room up in the room map and the Route posts `/api/setroomthermpoint`.
- The next poll confirms the new setpoint.

## Included notebooks

- `netatmo-energy-oauth.lotnb`, for every deployment: the Models, the Python transform, the Route, the token chain, the room fan-out and map, setpoint commands, and the Rules.
- `netatmo-energy-oauth-simulator.lotnb`, for running without a Netatmo account: it plays the Netatmo cloud on the Route's own topics, with one home, three rooms and working setpoints. Deploy the solution **without its Route** when you use it.
**Verified on 2.14.3:**
every cell of both notebooks deployed on a fresh broker, 25 checks passed, no runtime error in the broker log. The token chain ran against a stand-in API that rotates tokens the way Netatmo does. The checks cover token expiry, a forced refresh/poll collision, a refresh during a network outage, setpoint round trips, the Rules with real accounts, and the simulator path.

## Prerequisites

- Coreflux broker **2.14.2 or newer**, and the Hub.
- **The secret-store key pinned:** `COREFLUX_SECRET_KEY` set on the broker before you enter any secret. It encrypts the secret store that holds the tokens; unpinned, the key is machine-derived, and a restore onto other hardware can no longer read them. The notebook's Prerequisites show how to generate one.
- **Anonymous login off.** The Route publishes under an empty user name, which is also what an anonymous client presents, so Rule 2 is only sound with anonymous login off.
- Outbound HTTPS from the broker to `api.netatmo.com`.
- A Netatmo account with Energy devices, or nothing at all for the simulator.

## Topic and data dictionary

**UNS leaves**
All are published by `NetatmoRoomToUns` under `acme/site01/<Area>/Radiator01/`, each as the five-key envelope of `value`, `timestamp`, `datatype`, `status` and `units`:
- `Temperature`: °C, e.g. 20.5.
- `Setpoint`: °C, e.g. 19. This is what Netatmo **reports**.
- `SetpointMode`: `schedule`, `manual`, `max`, `away`, `hg` or `off`.
- `HeatingPowerRequest`: %, 0–100.
- `OpenWindow` and `Reachable`: true or false.
- `Voltage`: the valve battery in V, converted from mV, e.g. 2.7.
- `BatteryState`: `full` … `very_low`.
- `RfStrength`: about 60 (full) to 90 (low).
**Command**
- `…/Setpoint/set`: `{"value": 21}` in °C, not retained; published by `hvac_operator` or root.
**Raw plane and discovery**
- `netatmo/raw/<room_id>`: the joined room object, with Netatmo's own keys.
- `netatmo/unmapped/<room_id>`: the same, for a room not in the map yet.
- `netatmo/discovery`: homes, rooms, valves, `default_manual_minutes` and the ready-to-paste `map_lines` (from `NetatmoHomesDataAnswer`).
**Status and internal**
- `netatmo/_status/auth`, `netatmo/_status/poll` and `netatmo/_status/cmd`: one JSON event each, e.g. `{"event":"tokenRefresh","status":"Good","timestamp":"…","expiresIn":10800}`. The schema is in the notebook, under *Status events*.
- `netatmo/_auth/refresh/response`: **the tokens in clear**, for the instant before `KEEP SECRET`. The Route publishes it, and only root may read it (Rule 1).

## Quick start

**A] Without a Netatmo account (2 mins)**

1. Open the Hub on your broker.
2. In `netatmo-energy-oauth.lotnb` run **Models**, **Python** and **Actions**, but skip the **Route**.
3. Run `netatmo-energy-oauth-simulator.lotnb`.
4. Subscribe to `acme/site01/#` and `netatmo/#`. Then publish `{"value": 22.5}` to `acme/site01/Bedroom/Radiator01/Setpoint/set` and watch `Setpoint` follow.

**B] With your Netatmo home**

1. Check that `COREFLUX_SECRET_KEY` is pinned (Prerequisites). **Pin it before you enter any secret**: secrets entered under an unpinned key become unreadable the moment it is pinned.
2. At dev.netatmo.com create an app with **no redirect URI**. Use its *Token generator* with the scopes `read_thermostat` and `write_thermostat`.
3. Hub → **System Config → ENV & Secrets**: create `NETATMO_CLIENT_ID`, `NETATMO_CLIENT_SECRET`, `NETATMO_REFRESH_TOKEN` and `NETATMO_ACCESS_TOKEN` as secrets. `NETATMO_HOME_ID` is optional and is filled in from your first home.
4. Run Models, Python, **Route**, Actions.
5. Publish `{}` to `netatmo/_auth/refresh/request`. `netatmo/_status/auth` shows a `Good` `tokenRefresh` with `expiresIn` 10800, and the generator's seed pair is now replaced.
6. Publish `{}` to `netatmo/_api/homestatus/request`, or wait for the 5-minute poll. Copy the `map_lines` from `netatmo/discovery` into `NetatmoRoomMap`, give the areas your own names, and redeploy that action.
7. Create `hvac_operator`, then run the **Rules**.

## How it works

**The token chain**
Netatmo answers a refresh with a new access token and a new refresh token, and **invalidates the old pair immediately**. `NetatmoTokenStore` keeps both in the encrypted secret store the moment the answer arrives. The Route substitutes `{secret.NETATMO_ACCESS_TOKEN}` per request, so the next request uses the new token without a reload.

**The self-heal**
A 401 or 403 on any call requests a refresh at once. That covers an expired token (code 3) and a token rotated under the request (code 2). The refresh is serialised behind the failed answer, so it cannot collide again. A 400 is only logged and never rotates anything.

**Rooms, without room ids in code**
Netatmo splits a room across two answers: `/homestatus` has the live values, `/homesdata` knows which valve is in which room and what the room is called. The Python transform joins them. The fan-out walks the rooms one message per room, so a new room in your home needs no edit. The room map, `NetatmoRoomMap`, is the only place that knows where each room sits in your UNS.

**Commands**
`…/Setpoint/set` → the room map → `POST /api/setroomthermpoint` with `mode=manual`. There is no acknowledgement beyond `{"status":"ok"}`: the confirming poll *is* the confirmation. `Setpoint` and `SetpointMode` change within seconds; `HeatingPowerRequest` follows once the relay has reached the valve.

## Token timing: the refresh must never meet a poll

This is the operational lesson of this template, so here it is in full.

**What happens**
The refresh and the poll are two timers. When the refresh fires in the same second as a poll, Netatmo rotates the access token while the `/homestatus` request is in flight, and that request fails with **403, code 2, "Invalid access_token"**.

**Why a "round" period is the worst choice**
Any whole number of minutes is a multiple of the 5-minute poll. After a broker restart, a project load or a redeploy, both timers start together, and a 150-minute refresh then collides on **every** refresh. We saw exactly that: a 403 code 2 four times a day, each one precisely on the 150-minute grid.

**The rule**
Write the refresh period in **seconds**, as `300·n + 1`. The template uses **9001 s (150 min + 1 s)**:

- it stays at least five polls (1499 s) clear of the measured lifetime (below);
- it moves one second against the poll grid per cycle, so it meets the grid again only after 300 refreshes (about a month);
- that one collision heals itself: the failed poll requests a refresh, and the next poll is `ok`.
If you change either period, re-check the other.

**Why the self-heal must exist**
It makes the refresh tick a safety net rather than a single point of failure. Without it, any token that dies early stays dead until the next tick: hours of no data, while a careless status check still reports success.

**The access-token lifetime, measured**
Netatmo's token answer declares `expires_in: 10800` (3 hours). The documentation states no lifetime in prose, and a declared value is not a measured one, so we measured it. A live account ran the refresh tick at 12 h + 1 s on purpose, so the access token expired before the tick. The next 5-minute poll then got **403 code 3 "Access token expired"**, and the self-heal requested the refresh straight behind that answer. The time between two consecutive code-3 answers is the token lifetime, rounded up to the next poll.

- **70** expiries over 13 days, no `invalid_grant`, no code 2.
- **42** clean intervals of exactly **10800 s** (spread 10799.4 to 10800.5 s). Whenever the 12 h timer refresh fell inside a cycle, the interval was exactly twice that.
- The refresh is issued within a second of the failing poll, and the poll one step earlier (about 10500 s old) always succeeded. So the lifetime is **more than 10500 s and less than 10799.4 s**: Netatmo's real expiry sits a hair under the declared value.
- Back at 9001 s, the same account then ran 65 hours (26 refresh cycles) without a single expiry.
**In short:**
Netatmo declares 10800 s; the measured lifetime is more than 10500 s and less than 10799.4 s; this template refreshes every 9001 s, that is `300·30 + 1`, at least 1499 s below the measured minimum.

**Recommended practice**
1. **Use 10800 s as the ceiling, not the budget.** A token is never alive at exactly 3 h.
2. **Refresh well inside it.** The largest `300·n + 1` that leaves two polls of margin below 10500 s is 9601 s; this template uses the more conservative 9001 s, 2.4 more refreshes a day.
3. **Keep the self-heal.** A token that dies early (a manual rotation elsewhere, a vendor change) is recovered by the next poll.
4. **Keep logging the declared lifetime**, `expiresIn`, on every refresh, in the `tokenRefresh` status event. It shows a vendor change of the lifetime before it hurts.
5. **Repeat the measurement** if Netatmo changes the token answer or you see 403 code 3 outside the refresh cycle: set the tick above the lifetime, count the intervals between code-3 answers, then go back. A redeploy of the tick causes one code 3 at the old token's expiry; that one is expected.

## Production readiness
**Remove the simulator**
Do not run `netatmo-energy-oauth-simulator.lotnb` once the Route is deployed: both would answer every request.

**Rules first, accounts per role**
Create `hvac_operator` and one read-only account per application, then deploy the Rules before anyone connects. Rule 2 admits an **empty user name** beside root, because Routes and any `PUBLISH MODEL` publish under that empty name; without it the Route falls silent the moment the rule is deployed. That is why anonymous login must stay off.

**Pin, back up, never casually rotate the secret-store key**
Without the same `COREFLUX_SECRET_KEY` after a restore or a rebuild, the broker cannot read its own refresh token, and the chain is locked out. Back up the key (password manager) and the broker's data volume. Rotating the key means re-entering every secret.

**One Netatmo app per integration**
Netatmo has one valid pair per app at a time. If two integrations share an app, each refresh invalidates the other's tokens. Create a dedicated app for the broker.

**Limits**
Netatmo allows 50 requests per 10 s and 500 per hour per user; this template uses about 13 an hour. Valves report to the cloud every few minutes, so polling faster mostly re-reads the same sample.

**Monitoring**
`netatmo/_status/#` carries one JSON event per token answer, poll and command. It is not retained: store it with a historian route keyed on `event`, `status` and `timestamp`. Alert on `"status":"Bad"` on a `tokenRefresh` event, and on leaf `timestamp` age (a `Temperature` older than three polls).

**Lock-out runbook**
In full in the notebook's last section. `invalid_grant` means the stored refresh token is no longer the newest. Note `NETATMO_TOKEN_REFRESHED_AT`, generate a new pair, overwrite the two token secrets, and publish `{}` to `netatmo/_auth/refresh/request`. No redeploy and no restart.

## How to customize

1. **UNS root and positions:** the `NetatmoRoomMap` lines, the setpoint topic in `NetatmoSetpointCommand`, and Rule 3's topic.
2. **More leaves:** `room_at` already passes `anticipating` and `therm_setpoint_end_time` through; add a block in `NetatmoRoomToUns`.
3. **A setpoint with a duration:** add `endtime` (Unix seconds) to the Route's body and to the command payload. Without it, Netatmo applies the home's default manual duration.
4. **Several homes:** one notebook per home, with its own `NETATMO_HOME_ID` and topic prefixes.
5. **Another OAuth 2 vendor that rotates refresh tokens:** keep the Route, `NetatmoTokenStore`, the self-heal and the timing rule; change the endpoints and the answer parsing.

## Security notes

- The tokens live only in the encrypted secret store and in the request the Route sends. The status topics carry no secret (checked: no token on any status, discovery or UNS topic).
- `netatmo/_auth/refresh/response` carries the new pair in clear for an instant. Rule 1 keeps every account but root from subscribing to it.
- No client can force a refresh, call the API directly, or inject a forged token answer (Rule 2). Only `hvac_operator` and root may change a setpoint (Rule 3).
- Treat broker logs and backups as sensitive: they belong to a system that holds credentials.

## Field notes

- **Test "present", never "absent".** On the broker, a missing JSON field reads as the string `"null"`, not as an empty value. Our first token store guarded its `KEEP SECRET` with "the token is empty"; the guard never fired, and one refresh attempt during a network outage stored the text `null` as the refresh token. Every guard in this notebook tests for a positive value instead: `status == "ok"`, a token that is not `"null"`.
- **An offline gateway is harmless now.** A request that never reaches Netatmo rotates nothing, and the store ignores every answer that is not a token pair (verified with the network cut mid-refresh).
- **The confirmation of a command is the next poll.** The valve acts about half a minute after the cloud accepts the setpoint, and the app shows the change before the valve does.
- **"My setpoint undid itself."** That is usually the home's default manual duration expiring; `netatmo/discovery` shows it as `default_manual_minutes`.

&nbsp;
