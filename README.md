# Coreflux templates and best practices

Field-tested templates and engineering notes for the [Coreflux](https://www.coreflux.org) MQTT
broker and its Language of Things (LoT). Each template generalises a pattern that runs in
production, keeps what operating it taught us, and is verified on a fresh broker before it is
published here.

## Contents

| Folder | What |
|---|---|
| [`templates/`](templates/README.md) | ready-to-run LoT notebooks, one folder per template, with their assets and verification record |

Best-practice notes (UNS conventions, Rules design, LoT pitfalls measured on real brokers) will be
added over time as folders of their own.

## Templates

| Template | What it does | Broker |
|---|---|---|
| [`zigbee2mqtt-sonoff-uns`](templates/zigbee2mqtt-sonoff-uns/README.md) | Zigbee2MQTT sensors on a Sonoff USB coordinator into a position-based UNS, with a liveness chain, pairing from the broker and Rules | 2.14.2+ |
| [`netatmo-energy-oauth`](templates/netatmo-energy-oauth/README.md) | Netatmo Energy valves and thermostats over REST into a UNS, setpoints written back, OAuth 2 token rotation inside the broker | 2.14.2+ |

The templates are also submitted to the community gallery at
[templates.coreflux.org](https://templates.coreflux.org).

## Using a template

1. Read the template's `README.md`: what it does, its topics, a quick start with and without hardware.
2. Open its `.lotnb` notebooks in the Hub's LoT Editor or in the Coreflux extension for VS Code,
   connected to your broker, and run the cells in the order the notebook gives.
3. Every template ships a simulator notebook, so it runs without the device or the cloud account.
4. `VERIFICATION.md` records what was proved on which broker version.

## Contributing

Issues and pull requests are welcome on [this repository](https://github.com/zboardio/coreflux).
A change to a notebook should say which broker version it was tested on.

## Licence

[MIT](LICENSE). Coreflux is a trademark of its owner; this repository is independent and not
affiliated with or endorsed by Coreflux.

Published by [zboardio](https://github.com/zboardio).
