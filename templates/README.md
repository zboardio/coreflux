# Templates

LoT notebooks for the Coreflux broker, one folder per template. Each one generalises a pattern
that runs in production and carries what operating it taught us. None of them needs the device
or the cloud account to try: every template ships a simulator notebook.

| Template | What | Verified |
|---|---|---|
| [`zigbee2mqtt-sonoff-uns/`](zigbee2mqtt-sonoff-uns/README.md) | Zigbee2MQTT + a Sonoff USB coordinator → a position-based UNS: device map, key-by-key mapper, liveness chain (device, bridge, broker session), pairing from the broker, Rules confining Z2M | 2.14.3: 21 cells, 23 checks ([`VERIFICATION.md`](zigbee2mqtt-sonoff-uns/VERIFICATION.md)) |
| [`netatmo-energy-oauth/`](netatmo-energy-oauth/README.md) | Netatmo Energy over REST: OAuth 2 refresh-token rotation on the broker, self-heal, collision-proof timing, room fan-out without room ids in code, setpoint writes from the UNS, Rules | 2.14.3: 39 cells, 25 checks, against a mock API that rotates tokens like Netatmo ([`VERIFICATION.md`](netatmo-energy-oauth/VERIFICATION.md)) |

## A template folder

The layout follows the one Coreflux uses for its own community templates:

```text
<name>/
  README.md                 what / what you will see / architecture / notebooks / assets /
                            topic dictionary / quick start / how it works / production readiness /
                            adapting / security notes / field notes
  <name>.lotnb              the solution notebook
  <name>-simulator.lotnb    the hardware-free data source
  src/<notebook>.lotnb.md   the same notebooks as Markdown, for reading and reviewing
  compose/                  docker-compose.yml, broker-config.json (anonymous off, durability on), .env.example
  VERIFICATION.md           what was proved, on which broker version
  GALLERY.md                the entry on templates.coreflux.org, field by field
  …                         template-specific assets (zigbee2mqtt/, host-install/)
```

**`src/` and the `.lotnb`.** A `.lotnb` is a JSON list of cells, which is hard to read in a diff.
`src/` holds the same notebook as Markdown: every ```` ```lot ```` or ```` ```python ```` block is one
code cell, and the prose between two blocks is one Markdown cell. The `.lotnb` is rendered from it,
so the two always say the same thing. If you adapt a template, edit the `.lotnb` in your editor and
ignore `src/`.

**Notebook structure.** An overview cell (purpose, run order, requirements), then
**Models → Python → Routes → Actions → Rules (last)**. Every code cell is preceded by a prose cell
that names what it **Reads** and what it **Writes**.

## Conventions shared by every template

- **The UNS.** Example root `acme/site01/<Area>/<Position>/<Leaf>`. Every leaf is the five-key
  envelope `value`, `timestamp`, `datatype`, `status`, `units`. `timestamp` is the observation time
  in ISO-8601 Z, never the publish time, and `units` appears on numeric leaves only.
- **Planes.** The raw plane keeps the source's own vocabulary. Bookkeeping lives under
  `ingest/<source>/…` or `<source>/_…`. Internal state is `KEEP TOPIC`.
- **The map.** One map action (`ON START`) holds the only knowledge of which device or room sits at
  which position. Anything unmapped is published on an `…/unmapped/…` topic, never dropped.
- **Guards.** A guard tests a value positively, never with `== EMPTY` on a `GET JSON`.
- **Rules last in the notebook, first in production.** The notebook deploys them last so a demo
  never locks the deploying session out; a production broker gets its accounts and Rules before
  any client connects.

## How a template is verified

`VERIFICATION.md` is written by a harness that, for each template:

1. starts a fresh broker of the version named there, in local Docker;
2. deploys every code cell in notebook order, with the Rules held back;
3. runs the simulator, then asserts what arrives on the wire, in which shape, and what must not;
4. deploys the Rules and checks the allow/deny matrix with real MQTT accounts;
5. scans the broker log for runtime errors. An action is compiled when it first runs, so a green
   deploy alone proves little.

For Netatmo, a mock API that rotates tokens the way Netatmo does takes the place of
`api.netatmo.com`.

## LoT lessons, measured on 2.14.3

Each of these cost us a failure before it became a rule. The templates follow all of them.

| Avoid | Because |
|---|---|
| `GET JSON … == EMPTY` | a missing JSON path reads as the string `"null"`, so the guard never fires (it cost us a production token store); compare with `"null"` or test a present value |
| `(… AS DOUBLE) / <integer>` | inline division is integer division: 2900 mV became 2 V; write `* 0.001` or divide by `1000.0` |
| `TIMESTAMP "UTC"` for an envelope | it renders `yyyy-mm-dd hh:mm:ss`, not ISO; use `TIMESTAMP "ISO"` |
| a literal ending in `\"` inside a `+` concatenation | accepted on deploy, fails on first run; write `"` |
| `CALL PYTHON` on one line | refused; write `CALL PYTHON "Script.function"` / `WITH (…)` / `RETURN AS {r}` on three lines |
| a model field named `"unit"` | dropped from the JSON; use `"units"` |
| single-quoted numbers in route config | `MQTT_BRIDGE` refuses `'1883'`; double-quote them everywhere |
| rule priorities 0–99 | reserved since 2.14.2; use 100–999999 (the broker's allow-all seeds sit at 1000000) |
| `//` or `/*` in broker-hosted Python | `-addPython` cuts the line there (LoT comment syntax): `a // b` is stored as `a`, silently; write `int(a / b)` |
| comments before `DEFINE` | `DEFINE` must be the first line of a cell |

Behaviours to design around:

- **Rules see some publishers and not others.** An action's `PUBLISH MODEL` and every Route publish
  are subject to Publish Rules under an **empty user name**; an action's `PUBLISH TOPIC` is not. A
  Rule that must let a Route through admits the empty user name, which is only sound with
  anonymous login off.
- **No repeated callables.** A callable action may run only once per calling action.
- **No `GET JSON` on a Python result.** `GET JSON … IN {var}` fails at runtime when `{var}` holds a
  `CALL PYTHON` return value; a variable set from `PAYLOAD AS STRING` works.
- **Pin the secret-store key.** `COREFLUX_SECRET_KEY` encrypts the store behind `GET SECRET` and
  `KEEP SECRET`. Unpinned, it is machine-derived, and a restore onto other hardware cannot read a
  single secret.
