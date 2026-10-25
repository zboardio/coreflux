# Netatmo Energy over REST, OAuth 2 on the broker — solution

Smart radiator valves (Netatmo NRV), thermostats (NATherm1) and their relay (NAPlug) report to the
Netatmo cloud only: there is no local API. This notebook polls the Netatmo Energy API from the
broker and publishes every room into a Unified Namespace, and it writes room setpoints back from a
UNS command topic. **No container, no external script**: the broker itself runs the OAuth 2
refresh-token rotation, keeps the tokens in its encrypted secret store, and serves them to the
REST route per request. The tokens never reach your notebook or your git repository.

```text
NetatmoTokenRefreshTick  ─► RefreshToken  POST /oauth2/token  (form body from {secret.*})
                              └► NetatmoTokenStore  KEEP SECRET ×2  (only on a real token answer)
NetatmoPollTick (5 min)  ─► HomeStatus    GET /api/homestatus  (Bearer {secret.NETATMO_ACCESS_TOKEN})
                              └► NetatmoHomeStatusAnswer ── ok ─► cache + fan-out, one room per step
                                                         └ 401/403 ─► refresh now (self-heal)
NetatmoFanoutStep ─► NetatmoRoomToUns ─► netatmo/raw/<room_id>  +  acme/site01/<Area>/Radiator01/<Leaf>
acme/site01/<Area>/Radiator01/Setpoint/set {"value":21} ─► SetRoomThermpoint POST /api/setroomthermpoint
```

**Run order:** set the secrets (Prerequisites) → Models → Python → Route → Actions → Rules (last).
The hardware-free path skips the Route and runs `netatmo-energy-oauth-simulator.lotnb` instead.

**Requires:** Coreflux broker 2.14.2 or newer with the secret store's key pinned (below); verified on
2.14.3: every cell of both notebooks deployed on a fresh broker and 25 checks passed against a mock Netatmo API that
rotates tokens the way Netatmo does, with no runtime error in the broker log. Internet egress to `api.netatmo.com:443`.

## Prerequisites

### 1. A Netatmo app and a first token pair

1. Sign in at [dev.netatmo.com](https://dev.netatmo.com) with the account that owns the home, and
   create an app under **My apps**. Leave its **redirect URI empty**: the portal's *Token generator*
   is disabled for an app that has one.
2. Copy the app's **client ID** and **client secret**.
3. In the app's **Token generator**, choose the scopes **`read_thermostat` and `write_thermostat`**
   (the second one is needed for setpoint commands) and generate. Copy the **access token** and the
   **refresh token**. This pair is only the *seed*: the broker replaces it within hours.

### 2. Secrets and environment on the broker

Enter these in the Hub (**System Config → ENV & Secrets**) or with `-setSecret NAME=value` /
`-setEnv NAME=value` on `$SYS/Coreflux/Command`. Docs:
[Secrets and environment variables](https://docs.coreflux.org/mqtt-broker/secrets-and-env).

| Name | Type | Value | Who changes it later |
|---|---|---|---|
| `NETATMO_CLIENT_ID` | SECRET | the app's client ID | you, if you recreate the app |
| `NETATMO_CLIENT_SECRET` | SECRET | the app's client secret | you |
| `NETATMO_REFRESH_TOKEN` | SECRET | the seed refresh token | **the broker**, on every refresh |
| `NETATMO_ACCESS_TOKEN` | SECRET | the seed access token | **the broker**, on every refresh |
| `NETATMO_HOME_ID` | ENV | optional: filled in automatically from your first home | you, if you have several homes |
| `NETATMO_TOKEN_REFRESHED_AT` | ENV | do not set | the broker: time of the last good rotation |

### 3. Pin the secret store's key before you enter any secret

The broker encrypts its secret store with the key in `COREFLUX_SECRET_KEY` (base64 of 32 random
bytes). Without it the key is derived from the machine: a restore onto other hardware, or a rebuilt
VM, cannot decrypt a single secret, and the next refresh fails with a token the broker can no longer
read. Pass it to the broker container as the environment variable `COREFLUX_SECRET_KEY`. Generate it once, keep it in your password
manager, never rotate it casually (rotating = re-entering every secret):

```text
python3 -c "import base64,secrets; print(base64.b64encode(secrets.token_bytes(32)).decode())"
```

### 4. Limits worth knowing

Netatmo allows **50 requests per 10 seconds and 500 per hour per user**. This notebook makes 12 status
polls an hour, a few refreshes a day and one home-structure read every 3 hours. The valves report to the
cloud every few minutes, so polling more often than every 5 minutes mostly re-reads the same
sample.

## Topic contract

| Topic | Writer | Payload |
|---|---|---|
| `netatmo/_auth/refresh/request` | the refresh tick, the self-heal | `{}` |
| `netatmo/_auth/refresh/response` | the Route | **the new tokens in clear**: root-only by Rule 1 |
| `netatmo/_api/<call>/request` → `netatmo/_api/<call>` | actions → the Route | request / Netatmo's answer, or the Route's error envelope |
| `netatmo/raw/<room_id>` | `NetatmoRoomToUns` | one flat object per room per poll: room + first valve + `last_seen` |
| `netatmo/unmapped/<room_id>` | `NetatmoRoomToUns` | a room the map does not place yet |
| `netatmo/discovery` | `NetatmoHomesDataAnswer` | homes, rooms, valves and the ready-to-paste map lines |
| `netatmo/_status/auth` · `poll` · `cmd` | actions | one JSON status event per event (below); **no secret is ever in it** |
| `acme/site01/<Area>/Radiator01/<Leaf>` | `NetatmoRoomToUns` | five-key envelope (live events, not retained) |
| `acme/site01/<Area>/Radiator01/Setpoint/set` | an operator | `{"value": 21}`, not retained |

## Status events

Every token answer, poll answer and command produces **one JSON object** on `netatmo/_status/…`. It
uses the same `status` vocabulary as a UNS leaf, so a historian can store it as a state change and a
dashboard can draw it as a state timeline:

| Field | Always | Meaning |
|---|---|---|
| `event` | yes | `tokenRefresh` · `homeStatus` · `homesData` · `setpoint` |
| `status` | yes | `Good` or `Bad` |
| `timestamp` | yes | when the broker handled it, ISO-8601 UTC |
| `observedAt` | Good poll/command | Netatmo's own server time for the answer |
| `expiresIn` | Good `tokenRefresh` | the lifetime Netatmo declares for the new access token, in seconds |
| `rooms` | Good poll | rooms in the answer |
| `area`, `value` | `setpoint` | the command it belongs to |
| `httpStatus` | Bad | the HTTP status; `0` = Netatmo was not reached at all |
| `netatmoCode`, `message` | Bad API call | Netatmo's error code and text (3 = token expired, 2 = token replaced, 21 = invalid argument …) |
| `error` | Bad | the OAuth error (`invalid_grant`), the transport error (`HttpRequestException`), or why a command was refused |
| `next` | Bad poll | `refreshRequested` (401/403: the self-heal runs) or `none` |

```text
{"event":"tokenRefresh","status":"Good","timestamp":"2026-10-06T20:25:47.312Z","expiresIn":10800}
{"event":"homeStatus","status":"Bad","timestamp":"2026-10-06T20:25:46.120Z","httpStatus":403,"netatmoCode":3,"message":"Access token expired","next":"refreshRequested"}
{"event":"tokenRefresh","status":"Bad","timestamp":"…","httpStatus":0,"error":"HttpRequestException","message":"Name or service not known (api.netatmo.com:443)"}
{"event":"setpoint","status":"Good","timestamp":"…","observedAt":"…","area":"LivingRoom","value":23}
```

An alert is a field test: `status` is `Bad` on `tokenRefresh`, or no `Good` `homeStatus` for three polls.

**Why the poll and the command are separate leaves.** A setpoint command does not change the
`Setpoint` leaf. The leaf changes when Netatmo *reports* the new setpoint, on the poll that the
command triggers. A UNS state leaf only ever says what the device reports, never what someone asked for.

## Models

The same three envelope shapes as every UNS leaf in this kit: `datatype` lets a consumer pick a typed
column without a schema lookup; `units` is on numeric leaves only and belongs to the leaf.

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

## Python

`NetatmoEnergy` is a pure transform: standard library only, no I/O, well under 100 ms. The HTTP hop
is the Route, never Python.

Netatmo splits a room across two answers. `/homestatus` carries the live values: per room the measured
and set-point temperatures, per module the battery and radio. Only `/homesdata` knows which valve sits
in which room, and what the rooms are called. `room_at` joins the two by the room's `module_ids`;
the notebook caches the last `/homesdata` answer for exactly this purpose.

Every function returns a JSON **string**: a returned `dict` would reach LoT as a Python repr.

The second half builds the **status events** (see *Status events* below) from the Route's answer.
It copies only codes, counts and messages: a token can never reach a status topic, whatever the
answer holds.

```python
# Script Name: NetatmoEnergy
import json
from datetime import datetime, timezone

ROOM_KEYS = ("therm_measured_temperature", "therm_setpoint_temperature", "therm_setpoint_mode",
             "therm_setpoint_end_time", "heating_power_request", "open_window", "anticipating",
             "reachable")
VALVE_KEYS = ("battery_level", "battery_state", "rf_strength", "firmware_revision")
VALVE_TYPES = ("NRV", "NATherm1")


def _load(text):
    try:
        return json.loads(text) if isinstance(text, str) and text else (text or {})
    except ValueError:
        return {}


def _iso(epoch):
    try:
        return datetime.fromtimestamp(float(epoch), tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    except (TypeError, ValueError, OverflowError):
        return datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _home_meta(homesdata, home_id):
    homes = (_load(homesdata).get("body") or {}).get("homes") or []
    return next((h for h in homes if h.get("id") == home_id), {})


def room_at(homestatus, homesdata, index):
    """The index-th room of a /homestatus answer as one flat object, or "" past the last room."""
    status = _load(homestatus)
    home = (status.get("body") or {}).get("home") or {}
    rooms = home.get("rooms") or []
    i = int(index)
    if i < 0 or i >= len(rooms):
        return ""
    room = rooms[i]
    room_id = str(room.get("id"))
    meta = next((r for r in _home_meta(homesdata, home.get("id")).get("rooms") or []
                 if str(r.get("id")) == room_id), {})
    modules = {m.get("id"): m for m in home.get("modules") or []}
    valves = [modules[m] for m in meta.get("module_ids") or []
              if m in modules and modules[m].get("type") in VALVE_TYPES]
    out = {"room_id": room_id, "room_name": meta.get("name", "")}
    for key in ROOM_KEYS:
        if key in room:
            out[key] = room[key]
    if valves:
        valve = valves[0]
        out["valve_id"] = valve.get("id")
        out["valve_count"] = len(valves)
        out["valve_reachable"] = valve.get("reachable", True)
        for key in VALVE_KEYS:
            if key in valve:
                out[key] = valve[key]
    out["last_seen"] = _iso(status.get("time_server"))
    return json.dumps(out, separators=(",", ":"))


def discover(homesdata):
    """Ids and names of every home, room and valve, plus the NetatmoRoomMap lines to paste."""
    homes = (_load(homesdata).get("body") or {}).get("homes") or []
    out = []
    for h in homes:
        rooms = h.get("rooms") or []
        lines = []
        for r in rooms:
            area = "".join(w.capitalize() for w in str(r.get("name", r.get("id"))).split())
            lines.append('KEEP TOPIC "netatmo/_map/room/%s" WITH "acme/site01/%s/Radiator01"' % (r.get("id"), area))
            lines.append('KEEP TOPIC "netatmo/_map/area/%s" WITH "%s"' % (area, r.get("id")))
        out.append({"home_id": h.get("id"), "name": h.get("name"),
                    "default_manual_minutes": h.get("therm_setpoint_default_duration"),
                    "rooms": [{"id": r.get("id"), "name": r.get("name"), "module_ids": r.get("module_ids") or []}
                              for r in rooms],
                    "modules": [{"id": m.get("id"), "type": m.get("type"), "name": m.get("name"),
                                 "room_id": m.get("room_id")} for m in h.get("modules") or []],
                    "map_lines": lines})
    return json.dumps(out, separators=(",", ":"))


def _now():
    return datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def _event(event, status, **detail):
    out = {"event": event, "status": status, "timestamp": _now()}
    out.update({k: v for k, v in detail.items() if v is not None and v != ""})
    return json.dumps(out, separators=(",", ":"))


def _failure(answer):
    """What went wrong, from the Route's error envelope: Netatmo's API code and message, the token
    endpoint's OAuth error, or the transport error (statusCode 0 while the link is down)."""
    out = {"httpStatus": answer.get("statusCode", 0)}
    body = answer.get("error")
    inner = _load(body)
    err = inner.get("error") if isinstance(inner, dict) else None
    if isinstance(err, dict):
        out["netatmoCode"] = err.get("code")
        out["message"] = err.get("message")
    elif isinstance(err, str):
        out["error"] = err
        out["message"] = inner.get("error_description")
    else:
        out["error"] = answer.get("statusMessage") or "unknown"
        out["message"] = str(body)[:200] if body else None
    return out


def auth_status(answer):
    """The status event for one token answer: Good exactly when NetatmoTokenStore keeps the pair."""
    a = _load(answer)
    if a.get("refresh_token") and a.get("access_token"):
        return _event("tokenRefresh", "Good", expiresIn=a.get("expires_in"))
    if a.get("success") is False:
        return _event("tokenRefresh", "Bad", **_failure(a))
    return _event("tokenRefresh", "Bad", error="no token pair in the answer")


def poll_status(answer, event):
    """The status event for one /homestatus or /homesdata answer; `next` says what the chain does
    about a failure (a 401/403 requests a refresh, anything else waits for the next poll)."""
    a = _load(answer)
    if a.get("status") == "ok":
        body = a.get("body") or {}
        homes = [body["home"]] if body.get("home") else body.get("homes") or []
        observed = _iso(a["time_server"]) if a.get("time_server") else None
        return _event(event, "Good", observedAt=observed, rooms=sum(len(h.get("rooms") or []) for h in homes))
    out = _failure(a)
    out["next"] = "refreshRequested" if out["httpStatus"] in (401, 403) else "none"
    return _event(event, "Bad", **out)


def cmd_status(answer, request):
    """The status event for one /setroomthermpoint answer; `request` is "<area>|<value>"."""
    a = _load(answer)
    area, _, value = str(request or "").partition("|")
    try:
        value = float(value) if value else None
    except ValueError:
        value = None
    if a.get("status") == "ok":
        observed = _iso(a["time_server"]) if a.get("time_server") else None
        return _event("setpoint", "Good", observedAt=observed, area=area, value=value)
    return _event("setpoint", "Bad", area=area, value=value, **_failure(a))


def refused(event, reason, subject):
    """A command refused before it reached Netatmo."""
    return _event(event, "Bad", error=reason, subject=subject)
```

## Route

`NetatmoEnergyApi` is the only thing that talks to Netatmo. Every `{secret.NAME}` and `{env.NAME}`
placeholder is substituted **per request**, in the body and in the headers. A token rotated by
`NetatmoTokenStore` is therefore used from the very next request, with no route reload. The tokens
travel only from the secret store to the HTTP request.

A non-2xx answer arrives on the destination topic as the route's envelope,
`{"success":false,"statusCode":403,"statusMessage":"Forbidden","error":"<Netatmo's body>",…}`, and a
network failure as `statusCode` `0`. The actions below branch on exactly that shape.

Numbers in the configuration are double-quoted (`"30"`).

```lot
DEFINE ROUTE NetatmoEnergyApi WITH TYPE REST_API
    ADD REST_API_CONFIG
        WITH BASE_ADDRESS "https://api.netatmo.com"
        WITH ENABLE_CLIENT "true"
        WITH USE_SSL "true"
        WITH REQUEST_TIMEOUT "30"
    ADD EVENT RefreshToken
        WITH SOURCE_TOPIC "netatmo/_auth/refresh/request"
        WITH DESTINATION_TOPIC "netatmo/_auth/refresh/response"
        WITH METHOD "POST"
        WITH ENDPOINT "/oauth2/token"
        WITH HEADERS
            ADD "Content-Type" "application/x-www-form-urlencoded"
        WITH BODY "grant_type=refresh_token&refresh_token={secret.NETATMO_REFRESH_TOKEN}&client_id={secret.NETATMO_CLIENT_ID}&client_secret={secret.NETATMO_CLIENT_SECRET}"
    ADD EVENT HomesData
        WITH SOURCE_TOPIC "netatmo/_api/homesdata/request"
        WITH DESTINATION_TOPIC "netatmo/_api/homesdata"
        WITH METHOD "GET"
        WITH ENDPOINT "/api/homesdata"
        WITH HEADERS
            ADD "Authorization" "Bearer {secret.NETATMO_ACCESS_TOKEN}"
    ADD EVENT HomeStatus
        WITH SOURCE_TOPIC "netatmo/_api/homestatus/request"
        WITH DESTINATION_TOPIC "netatmo/_api/homestatus"
        WITH METHOD "GET"
        WITH ENDPOINT "/api/homestatus?home_id={env.NETATMO_HOME_ID}"
        WITH HEADERS
            ADD "Authorization" "Bearer {secret.NETATMO_ACCESS_TOKEN}"
    ADD EVENT SetRoomThermpoint
        WITH SOURCE_TOPIC "netatmo/_api/setroomthermpoint/request"
        WITH DESTINATION_TOPIC "netatmo/_api/setroomthermpoint"
        WITH METHOD "POST"
        WITH ENDPOINT "/api/setroomthermpoint"
        WITH HEADERS
            ADD "Authorization" "Bearer {secret.NETATMO_ACCESS_TOKEN}"
            ADD "Content-Type" "application/x-www-form-urlencoded"
        WITH BODY "home_id={env.NETATMO_HOME_ID}&room_id={value.json.room_id}&mode=manual&temp={value.json.temp}"
```

## Actions

### The token chain

**The refresh period, and why it ends in `1`.** Netatmo declares `expires_in` 10800 s (3 h) in every
token answer. The refresh must run well inside that lifetime and must never fire in the same second
as a poll.

When it does, Netatmo rotates the token *under* the in-flight `/homestatus` request. That request
then fails with **403 code 2 "Invalid access_token"**. A refresh period of a whole number of minutes
is a multiple of the 5-minute poll, so after a broker restart, when both timers start together, it
collides on every single refresh.

**9001 s = 150 min + 1 s** keeps at least 1499 s (five polls) of margin below the measured lifetime (at
least 10500 s, below) and drifts one second against the poll
grid per cycle. It meets the grid again only after 300 refreshes (about a month), and that one collision
heals itself (see `NetatmoHomeStatusAnswer`). If you change either period, keep this one in
**seconds** and of the form `300·n + 1`.

**The lifetime was measured, not assumed.** On a live account the access token lives the declared
**10800 s (3 h)**: 70 expiries over 13 days put it between 10500 s and 10799 s, so it dies a hair
before the declared value. Treat 10800 s as the ceiling, never as the budget. The method: with the refresh timer set to 12 h,
every token expired before it was refreshed, the next poll got 403 code 3 "Access token expired" and
the self-heal refreshed right behind it. The interval between consecutive code-3 answers in the
broker log is the lifetime, rounded up to the 5-minute poll; the poll one step earlier always
succeeded.

**Reads:** nothing. **Writes:** `netatmo/_auth/refresh/request`.

```lot
DEFINE ACTION NetatmoTokenRefreshTick
ON EVERY 9001 SECONDS DO
    PUBLISH TOPIC "netatmo/_auth/refresh/request" WITH "{}"
```

**The rotation hop.** Netatmo answers a refresh with a **new access token and a new refresh token,
and invalidates the old pair immediately**. Both are kept in the encrypted secret store the moment the
answer lands.

The test that guards the `KEEP SECRET` is the most important line in this notebook. It runs only when
the answer really carries a refresh token. Any other answer leaves the stored pair untouched and is
logged instead: `invalid_grant`, a 5xx, or the route's `statusCode 0` envelope while the network is down.

Write that test as "the field is present". A JSON path that is absent reads as the string `"null"`, not
as an empty value. A test written as "the field is empty" never fires, and then one refresh attempt
during a network outage overwrites a good refresh token with the text `null`. The account is locked out
from the next refresh on.

`NETATMO_TOKEN_REFRESHED_AT` is written only here, on success: after an incident it is the time of
the last good rotation. The status event carries Netatmo's declared `expiresIn`, which is free to
log and shows at once if Netatmo ever changes it.

**Reads:** `netatmo/_auth/refresh/response`. **Writes:** the two token secrets, `NETATMO_TOKEN_REFRESHED_AT`,
`netatmo/_status/auth`.

```lot
DEFINE ACTION NetatmoTokenStore
ON TOPIC "netatmo/_auth/refresh/response" DO
    SET "rt" WITH (GET JSON "refresh_token" IN PAYLOAD AS STRING)
    SET "at" WITH (GET JSON "access_token" IN PAYLOAD AS STRING)
    CALL PYTHON "NetatmoEnergy.auth_status"
        WITH (PAYLOAD)
        RETURN AS {report}
    IF {rt} != "null" THEN
        IF {at} != "null" THEN
            KEEP SECRET "NETATMO_REFRESH_TOKEN" WITH {rt}
            KEEP SECRET "NETATMO_ACCESS_TOKEN" WITH {at}
            KEEP ENV "NETATMO_TOKEN_REFRESHED_AT" WITH TIMESTAMP "ISO"
    PUBLISH TOPIC "netatmo/_status/auth" WITH {report}
```

### Polling

**Reads:** nothing. **Writes:** `netatmo/_api/homestatus/request`. The home id comes from the
`{env.NETATMO_HOME_ID}` placeholder in the Route, so the payload is empty.

```lot
DEFINE ACTION NetatmoPollTick
ON EVERY 5 MINUTES DO
    PUBLISH TOPIC "netatmo/_api/homestatus/request" WITH "{}"
```

The home structure (room names, which valve is in which room) changes rarely. It is read on the first
successful poll, then every 3 hours.

```lot
DEFINE ACTION NetatmoHomesDataTick
ON EVERY 3 HOURS DO
    PUBLISH TOPIC "netatmo/_api/homesdata/request" WITH "{}"
```

### Answers

**The self-heal.** Only a 401 or a 403 requests a refresh. They mean an expired access token (code 3),
or one rotated under the request (code 2). The refresh happens right after that answer, serialised
behind it, so it cannot collide.

A 400 is only logged, for example `Invalid home_id` while `NETATMO_HOME_ID` is wrong. It must not
rotate the tokens every five minutes. A refresh that itself fails (`invalid_grant`) is not retried
in a tight loop: the next attempt is the next poll's 403.

Success is tested positively, as Netatmo's `"status":"ok"`, never as the absence of an error.

**Reads:** `netatmo/_api/homesdata`. **Writes:** the cache `netatmo/_cache/homesdata` (KEEP),
`NETATMO_HOME_ID` when it is not set yet, `netatmo/discovery`.

```lot
DEFINE ACTION NetatmoHomesDataAnswer
ON TOPIC "netatmo/_api/homesdata" DO
    CALL PYTHON "NetatmoEnergy.poll_status"
        WITH (PAYLOAD, "homesData")
        RETURN AS {report}
    IF (GET JSON "status" IN PAYLOAD AS STRING) == "ok" THEN
        KEEP TOPIC "netatmo/_cache/homesdata" WITH PAYLOAD
        IF GET ENV "NETATMO_HOME_ID" == EMPTY THEN
            KEEP ENV "NETATMO_HOME_ID" WITH (GET JSON "body.homes[0].id" IN PAYLOAD AS STRING)
            PUBLISH TOPIC "netatmo/_api/homestatus/request" WITH "{}"
        CALL PYTHON "NetatmoEnergy.discover"
            WITH (PAYLOAD)
            RETURN AS {summary}
        PUBLISH TOPIC "netatmo/discovery" WITH {summary}
    ELSE
        IF (GET JSON "statusCode" IN PAYLOAD AS STRING) == "401" THEN
            PUBLISH TOPIC "netatmo/_auth/refresh/request" WITH "{}"
        IF (GET JSON "statusCode" IN PAYLOAD AS STRING) == "403" THEN
            PUBLISH TOPIC "netatmo/_auth/refresh/request" WITH "{}"
    PUBLISH TOPIC "netatmo/_status/poll" WITH {report}
```

**Reads:** `netatmo/_api/homestatus`. **Writes:** the cache `netatmo/_cache/homestatus` (KEEP),
`netatmo/_fanout/step`, `netatmo/_status/poll`, and on 401/403 `netatmo/_auth/refresh/request`.

```lot
DEFINE ACTION NetatmoHomeStatusAnswer
ON TOPIC "netatmo/_api/homestatus" DO
    CALL PYTHON "NetatmoEnergy.poll_status"
        WITH (PAYLOAD, "homeStatus")
        RETURN AS {report}
    IF (GET JSON "status" IN PAYLOAD AS STRING) == "ok" THEN
        KEEP TOPIC "netatmo/_cache/homestatus" WITH PAYLOAD
        IF GET TOPIC "netatmo/_cache/homesdata" == EMPTY THEN
            PUBLISH TOPIC "netatmo/_api/homesdata/request" WITH "{}"
        PUBLISH TOPIC "netatmo/_fanout/step" WITH 0
    ELSE
        IF (GET JSON "statusCode" IN PAYLOAD AS STRING) == "401" THEN
            PUBLISH TOPIC "netatmo/_auth/refresh/request" WITH "{}"
        IF (GET JSON "statusCode" IN PAYLOAD AS STRING) == "403" THEN
            PUBLISH TOPIC "netatmo/_auth/refresh/request" WITH "{}"
        IF GET ENV "NETATMO_HOME_ID" == EMPTY THEN
            PUBLISH TOPIC "netatmo/_api/homesdata/request" WITH "{}"
    PUBLISH TOPIC "netatmo/_status/poll" WITH {report}
```

### One room per step

A home has any number of rooms, and LoT has no loop over a JSON array. The fan-out therefore walks
the rooms **one message at a time**. Each step asks Python for room *n* of the cached answer and hands
it on, then publishes step *n + 1*; an empty answer ends the walk (with a hard stop at 32 rooms).

Each step runs as its own short action execution, and adding a room to the home needs no change here.
The room goes to a topic of its own (`netatmo/_fanout/room`) before it is mapped, because a JSON field
can be read from `PAYLOAD` but not from a value returned by `CALL PYTHON`.

**Reads:** `netatmo/_fanout/step`, both caches. **Writes:** `netatmo/_fanout/room`, the next step.

```lot
DEFINE ACTION NetatmoFanoutStep
ON TOPIC "netatmo/_fanout/step" DO
    SET "idx" WITH (PAYLOAD AS INT)
    CALL PYTHON "NetatmoEnergy.room_at"
        WITH (GET TOPIC "netatmo/_cache/homestatus", GET TOPIC "netatmo/_cache/homesdata", {idx})
        RETURN AS {room}
    IF {room} != EMPTY THEN
        PUBLISH TOPIC "netatmo/_fanout/room" WITH {room}
        IF {idx} < 31 THEN
            PUBLISH TOPIC "netatmo/_fanout/step" WITH ({idx} + 1)
```

### The room map, the one place that knows where each room sits

Two lines per room. The Netatmo room id points to its UNS position, and the UNS area points back to
the room id for commands. `netatmo/discovery` prints these lines for every room of your home, so in
practice this cell is copied from there. A room that is not listed is not dropped: it shows up on
`netatmo/unmapped/<room_id>`.

Netatmo controls heating **per room**, not per valve. The position `Radiator01` is the room's heating
control point. With several valves in one room, the valve-health leaves report the first valve, and the
raw object says how many there are (`valve_count`).

```lot
DEFINE ACTION NetatmoRoomMap
ON START DO
    KEEP TOPIC "netatmo/_map/room/1001" WITH "acme/site01/LivingRoom/Radiator01"
    KEEP TOPIC "netatmo/_map/area/LivingRoom" WITH "1001"
    KEEP TOPIC "netatmo/_map/room/1002" WITH "acme/site01/Bedroom/Radiator01"
    KEEP TOPIC "netatmo/_map/area/Bedroom" WITH "1002"
```

### Room → raw plane + UNS leaves

The raw object is published as-is on `netatmo/raw/<room_id>`, for debugging and for consumers that
want Netatmo's own vocabulary. The UNS leaves translate it. All leaves of one poll carry the poll's
`time_server` as their observation time. `status` is `Good` by construction: a value is published only
when Netatmo reported it, and degraded data shows up as a stale `timestamp` or as `Reachable` false.

| Raw key | Leaf | Type | Units |
|---|---|---|---|
| `therm_measured_temperature` | `Temperature` | number | °C |
| `therm_setpoint_temperature` | `Setpoint` | number | °C |
| `therm_setpoint_mode` (`schedule`, `manual`, `max`, `away`, `hg`, `off`) | `SetpointMode` | string | |
| `heating_power_request` (0–100) | `HeatingPowerRequest` | number | % |
| `open_window` | `OpenWindow` | boolean | |
| `reachable` | `Reachable` | boolean | |
| `battery_level` (millivolts) | `Voltage` | number | V |
| `battery_state` (`full` … `very_low`) | `BatteryState` | string | |
| `rf_strength` (lower is better: about 60 full … 90 low) | `RfStrength` | number | 1 |

**Reads:** `netatmo/_fanout/room`, the room map. **Writes:** `netatmo/raw/<room_id>`, the leaves, or
`netatmo/unmapped/<room_id>`.

```lot
DEFINE ACTION NetatmoRoomToUns
ON TOPIC "netatmo/_fanout/room" DO
    SET "rid" WITH (GET JSON "room_id" IN PAYLOAD AS STRING)
    PUBLISH TOPIC "netatmo/raw/" + {rid} WITH PAYLOAD
    SET "pos" WITH (GET TOPIC "netatmo/_map/room/" + {rid})
    IF {pos} == EMPTY THEN
        PUBLISH TOPIC "netatmo/unmapped/" + {rid} WITH PAYLOAD
    ELSE
        SET "ts" WITH (GET JSON "last_seen" IN PAYLOAD AS STRING)
        SET "k_temp" WITH (GET JSON "therm_measured_temperature" IN PAYLOAD AS STRING)
        IF {k_temp} != "null" THEN
            PUBLISH MODEL UnsNumber TO {pos} + "/Temperature" WITH
                value = (GET JSON "therm_measured_temperature" IN PAYLOAD AS DOUBLE)
                timestamp = {ts}
                datatype = "number"
                status = "Good"
                units = "°C"
        SET "k_sp" WITH (GET JSON "therm_setpoint_temperature" IN PAYLOAD AS STRING)
        IF {k_sp} != "null" THEN
            PUBLISH MODEL UnsNumber TO {pos} + "/Setpoint" WITH
                value = (GET JSON "therm_setpoint_temperature" IN PAYLOAD AS DOUBLE)
                timestamp = {ts}
                datatype = "number"
                status = "Good"
                units = "°C"
        SET "k_mode" WITH (GET JSON "therm_setpoint_mode" IN PAYLOAD AS STRING)
        IF {k_mode} != "null" THEN
            PUBLISH MODEL UnsText TO {pos} + "/SetpointMode" WITH
                value = {k_mode}
                timestamp = {ts}
                datatype = "string"
                status = "Good"
        SET "k_hpr" WITH (GET JSON "heating_power_request" IN PAYLOAD AS STRING)
        IF {k_hpr} != "null" THEN
            PUBLISH MODEL UnsNumber TO {pos} + "/HeatingPowerRequest" WITH
                value = (GET JSON "heating_power_request" IN PAYLOAD AS DOUBLE)
                timestamp = {ts}
                datatype = "number"
                status = "Good"
                units = "%"
        SET "k_win" WITH (GET JSON "open_window" IN PAYLOAD AS STRING)
        IF {k_win} != "null" THEN
            PUBLISH MODEL UnsBoolean TO {pos} + "/OpenWindow" WITH
                value = (GET JSON "open_window" IN PAYLOAD AS BOOL)
                timestamp = {ts}
                datatype = "boolean"
                status = "Good"
        SET "k_reach" WITH (GET JSON "reachable" IN PAYLOAD AS STRING)
        IF {k_reach} != "null" THEN
            PUBLISH MODEL UnsBoolean TO {pos} + "/Reachable" WITH
                value = (GET JSON "reachable" IN PAYLOAD AS BOOL)
                timestamp = {ts}
                datatype = "boolean"
                status = "Good"
        SET "k_bat" WITH (GET JSON "battery_level" IN PAYLOAD AS STRING)
        IF {k_bat} != "null" THEN
            PUBLISH MODEL UnsNumber TO {pos} + "/Voltage" WITH
                value = ((GET JSON "battery_level" IN PAYLOAD AS DOUBLE) * 0.001)
                timestamp = {ts}
                datatype = "number"
                status = "Good"
                units = "V"
        SET "k_bstate" WITH (GET JSON "battery_state" IN PAYLOAD AS STRING)
        IF {k_bstate} != "null" THEN
            PUBLISH MODEL UnsText TO {pos} + "/BatteryState" WITH
                value = {k_bstate}
                timestamp = {ts}
                datatype = "string"
                status = "Good"
        SET "k_rf" WITH (GET JSON "rf_strength" IN PAYLOAD AS STRING)
        IF {k_rf} != "null" THEN
            PUBLISH MODEL UnsNumber TO {pos} + "/RfStrength" WITH
                value = (GET JSON "rf_strength" IN PAYLOAD AS DOUBLE)
                timestamp = {ts}
                datatype = "number"
                status = "Good"
                units = "1"
```

### The write path: a setpoint from the UNS

An operator publishes `{"value": 21}`, not retained, to `acme/site01/<Area>/Radiator01/Setpoint/set`.
The action looks the area up in the room map and asks the Route for `mode=manual` at that
temperature. Netatmo validates the range (7–30 °C) and answers.

The request is built as a string and sent with `PUBLISH TOPIC`. An action's `PUBLISH MODEL` is subject
to user publish Rules, and Rule 2 admits only root to `netatmo/`. Inside a concatenation, a quote that
ends a literal is written `\u0022`.

**How long it holds.** Without an `endtime`, Netatmo applies the home's *default manual duration*,
`default_manual_minutes` in `netatmo/discovery`, set in the Netatmo app. When it expires the room
returns to its schedule. A setpoint that seems to "undo itself" after 30 or 180 minutes is this, not a
fault.

**How it is confirmed.** There is no acknowledgement beyond Netatmo's `{"status":"ok"}`. The
confirmation *is* the next `/homestatus`, which `NetatmoCommandAnswer` requests at once:
`Setpoint` and `SetpointMode` show the change within seconds. `HeatingPowerRequest` follows after
the relay has reached the valve, typically about half a minute later, so the next regular poll
shows it.

**Reads:** `acme/site01/+/Radiator01/Setpoint/set`, the room map. **Writes:**
`netatmo/_api/setroomthermpoint/request` and the last command (KEEP, for the answer's status event),
or a `Bad` event on `netatmo/_status/cmd`.

```lot
DEFINE ACTION NetatmoSetpointCommand
ON TOPIC "acme/site01/+/Radiator01/Setpoint/set" DO
    SET "area" WITH TOPIC POSITION 3
    SET "rid" WITH (GET TOPIC "netatmo/_map/area/" + {area})
    SET "temp" WITH (GET JSON "value" IN PAYLOAD AS STRING)
    IF {rid} == EMPTY THEN
        CALL PYTHON "NetatmoEnergy.refused"
            WITH ("setpoint", "area not in the room map", {area})
            RETURN AS {unknown_area}
        PUBLISH TOPIC "netatmo/_status/cmd" WITH {unknown_area}
    ELSE
        IF {temp} == "null" THEN
            CALL PYTHON "NetatmoEnergy.refused"
                WITH ("setpoint", "no value in the command", {area})
                RETURN AS {no_value}
            PUBLISH TOPIC "netatmo/_status/cmd" WITH {no_value}
        ELSE
            KEEP TOPIC "netatmo/_cache/lastcmd" WITH ({area} + "|" + {temp})
            PUBLISH TOPIC "netatmo/_api/setroomthermpoint/request" WITH ("{\"room_id\":\u0022" + {rid} + "\u0022,\"temp\":" + {temp} + "}")
```

**Reads:** `netatmo/_api/setroomthermpoint`. **Writes:** `netatmo/_status/cmd`; a confirming poll.

```lot
DEFINE ACTION NetatmoCommandAnswer
ON TOPIC "netatmo/_api/setroomthermpoint" DO
    CALL PYTHON "NetatmoEnergy.cmd_status"
        WITH (PAYLOAD, GET TOPIC "netatmo/_cache/lastcmd")
        RETURN AS {report}
    PUBLISH TOPIC "netatmo/_status/cmd" WITH {report}
    PUBLISH TOPIC "netatmo/_api/homestatus/request" WITH "{}"
    IF (GET JSON "statusCode" IN PAYLOAD AS STRING) == "401" THEN
        PUBLISH TOPIC "netatmo/_auth/refresh/request" WITH "{}"
    IF (GET JSON "statusCode" IN PAYLOAD AS STRING) == "403" THEN
        PUBLISH TOPIC "netatmo/_auth/refresh/request" WITH "{}"
```

## Rules

**Run these last.** Create the accounts first: `-addUser hvac_operator <password>` for whoever may
change setpoints, and one account per application that only reads.

Priorities sit in the 2.14 user band. The lower number is the stronger band, and inside a band a DENY
wins. What the Rules see: an action's `PUBLISH TOPIC` is not subject to user publish Rules; an
action's `PUBLISH MODEL` and every Route publish **are**, under an empty user name.

### Rule 1: nobody but root reads the token hop (priority 200)

`netatmo/_auth/refresh/response` carries the new tokens in clear for the instant between Netatmo's
answer and the `KEEP SECRET`. This rule keeps every other account from subscribing to it.

```lot
DEFINE RULE NetatmoAuthSubscribe WITH PRIORITY 200 FOR Subscribe TO TOPIC "netatmo/_auth/#"
    IF USER IS "root" THEN
        ALLOW
    ELSE
        DENY
```

### Rule 2: no client drives the Netatmo plumbing (priority 200)

No client can force a refresh, call the API directly or forge an answer the actions would trust,
such as a fake token answer that would overwrite the stored pair.

The Route publishes its answers under the broker's own identity, an **empty user name** (as does any
action's `PUBLISH MODEL`). The rule must therefore admit `""` beside root, or the Route falls silent
the moment the rule is deployed. An empty user name is also what an anonymous client presents, which
is one more reason the broker must run with **anonymous login off** (`"AnonymousLogin": false` in the broker configuration).

```lot
DEFINE RULE NetatmoInternalPublish WITH PRIORITY 200 FOR Publish TO TOPIC "netatmo/#"
    IF USER IS "root" OR USER IS "" THEN
        ALLOW
    ELSE
        DENY
```

### Rule 3: setpoints are an operator act (priority 200)

```lot
DEFINE RULE NetatmoSetpointWriters WITH PRIORITY 200 FOR Publish TO TOPIC "acme/site01/+/Radiator01/Setpoint/set"
    IF USER IS "root" OR USER IS "hvac_operator" THEN
        ALLOW
    ELSE
        DENY
```

## How to verify

1. `netatmo/_status/auth` shows `{"event":"tokenRefresh","status":"Good",…,"expiresIn":10800}` after
   you publish `{}` to `netatmo/_auth/refresh/request` once. This first refresh also replaces the seed pair: from here on
   the tokens exist only in the broker.
2. Within a minute, `netatmo/discovery` lists your rooms and the map lines. Paste them into
   `NetatmoRoomMap` and redeploy that action.
3. `acme/site01/<Area>/Radiator01/#` fills on the next poll. Subscribe to `netatmo/_status/#` to watch
   the chain; it carries no secret.
4. Publish `{"value": 21}` to one room's `…/Setpoint/set` as `hvac_operator`. `netatmo/_status/cmd`
   shows a `Good` `setpoint` event for that area, and `Setpoint` reads 21 seconds later.

## When it breaks: the lock-out runbook

`netatmo/_status/auth` shows `"status":"Bad"` with `"error":"invalid_grant"`, and the leaves stop
updating. The
stored refresh token is no longer the latest one. Two causes are possible:

- the broker stopped between Netatmo's answer and the `KEEP SECRET`;
- the token was used from somewhere else (another integration on the same app shares the pair:
  **give every integration its own Netatmo app**).

Recovery takes no redeploy and no restart:

1. Note `NETATMO_TOKEN_REFRESHED_AT`. It is the last good rotation, and so the evidence for the cause.
2. Generate a new pair in the app's Token generator, with both scopes.
3. Overwrite `NETATMO_REFRESH_TOKEN` and `NETATMO_ACCESS_TOKEN`; the client id and secret stay.
4. Publish `{}` to `netatmo/_auth/refresh/request`. Expect a `Good` `tokenRefresh`, then a `Good`
   `homeStatus` on the next poll.

An offline period by itself does no harm. A request that never reaches Netatmo rotates nothing, and
the token store ignores every answer that is not a token pair.
