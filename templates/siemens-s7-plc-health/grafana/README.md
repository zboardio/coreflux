# Grafana: PLC fleet and PLC detail

A Grafana provisioning tree for the PLC historian of this template: one datasource, three dashboards and the alert
rules. Mount it into a stock Grafana next to the template's database and the PLCs the broker stores appear: the fleet
first, then one page per PLC.

```text
provisioning/
  datasources/datasources.yml       the PLC historian (PostgreSQL / TimescaleDB), uid timescale-edge, from environment variables
  dashboards/dashboards.yml         the provider: every file under json/, one folder per sub-directory
  dashboards/json/PLC/
    plc-fleet.json                  PLC fleet — the home page
    plc-detail-s7-300.json          PLC detail — S7-300
    plc-detail-s7-1500.json         PLC detail — S7-1500
  alerting/rules-plc.yml            nine rules, once per PLC family
  alerting/contactpoints.yml        one contact point that never delivers
  alerting/policies.yml             everything muted (alerts are shown, not sent)
  alerting/mute-timings.yml
  plugins/plugins.yml               no plugins
```

**The dashboards' JSON and `rules-plc.yml` are generated** from one set of definitions shared by every PLC family, so
the pages stay alike. Do not edit them in this repository (a change is regenerated over), and do not save the
dashboards from the UI (the provider refuses it). In your own copy, adapt them freely.

## Pages

- **PLC fleet** (home): every PLC, worst first: how many are in RUN, STOP, unreachable or silent, which path is down,
  whose health loop or cycle is in trouble, the state of each PLC over time, the inventory by family, model, firmware
  and area, every PLC's cycle against its own watchdog, and a feed of state changes and faults. Filters: area, family,
  model. Click a PLC to open its detail page.
- **PLC detail — S7-300** and **PLC detail — S7-1500**: one page per family, each with only what that family has. The
  PLC's state first (CPU state, path status, scanning, health loop, last boot, identity, cycle tiles, its alerts),
  then the family's diagnostics (S7-300: the diagnostic buffer with Siemens' texts, mode changes, faults recorded
  before STOP, SZL answers; S7-1500: the error OBs with Siemens' meaning, LEDs, RT_INFO, communication load), the
  boots, the health loop, the cycle (trend, histograms) and the reads per path. `$plc` lists the family's PLCs only;
  every path-shaped panel follows the PLC's own registered paths.

Trend panels switch to the 5 min and 1 h roll-ups on long ranges by themselves. Every panel has a description (the
`i` next to its title) that says what it shows and how to read it.

**Values written by the PLC program are frozen while the CPU is in STOP.** The program fills its data blocks every cycle,
and does not run in STOP: the cycle figures, the LEDs, RT_INFO, the communication load and the health loop's
counters keep their last values of RUN. The pages say so where it matters, and do not take those values at face
value: the CPU state, path status and scanning tiles come from the broker's verdicts (a frozen sequence counter on a
path that still answers = STOP), the health loop shows NOT JUDGED, and the S7-1500 LED tile shows `STOP (derived)`
and `NOT READ` instead of the LEDs frozen in RUN.

## Alerts

`rules-plc.yml` holds nine rules (not scanning, path down, unreachable, cycle near the watchdog, fault, records lost,
clock skew, health loop stalled, health loop corrupt), each once per family: uid `<rule>-<family>`, label `family`,
and a link to the panel on that family's page that explains it. Their state shows in the alert lists on the fleet
page and on each detail page, and under Alerting in Grafana.

**As shipped, nothing is sent.** The one contact point points at the container's own loopback and the policy mutes
every alert, so a fresh install neither fails on an unconfigured mail server nor sends anything you did not ask for.
To be notified:

1. add your contact point to `alerting/contactpoints.yml` (email, Slack, Teams, webhook…; Grafana's alerting
   documentation lists each type's settings; a secret goes in an environment variable, `$VAR`, never in the file);
2. name it as the `receiver` in `alerting/policies.yml` and remove `mute_time_intervals: [always]` from the route;
3. restart Grafana (alerting provisioning is read at start only).

## Environment

Grafana reads `$VAR` in provisioning files from **its own process environment**: pass these to the Grafana container.

| Variable | Value |
|---|---|
| `TIMESCALE_HOST` | the database host as Grafana reaches it, `host` or `host:port` (default port 5432) |
| `TIMESCALE_DB` | the historian's database |
| `GRAFANA_READER_USER` | a read-only role: `SELECT` on the PLC tables and views, `EXECUTE` on their functions |
| `GRAFANA_READER_PASSWORD` | its password |
| `GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH` | `/etc/grafana/provisioning/dashboards/json/PLC/plc-fleet.json` (the fleet as home page) |
| `GF_SECURITY_ADMIN_PASSWORD` | Grafana's `admin` password (applied on the first start of an empty data volume) |

Recommended, so that Grafana does not dial out (plugin installs, update and news checks) and works on a network
without internet: `GF_PLUGINS_PREINSTALL_DISABLED=true`, `GF_ANALYTICS_REPORTING_ENABLED=false`,
`GF_ANALYTICS_CHECK_FOR_UPDATES=false`, `GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES=false`, `GF_NEWS_NEWS_FEED_ENABLED=false`.
`GF_DATABASE_WAL=true` makes a harmless `database is locked` line at the first start (Grafana retries) rarer.

`datasources.yml` connects with `sslmode: disable`, for a database on the same container network; set `require` (or
`verify-full`) there for a remote one.

## Mount

Grafana **13.2.0** (`grafana/grafana:13.2.0`) is the version this tree is tested on; use it or a newer one.

```yaml
services:
  grafana:
    image: grafana/grafana:13.2.0
    environment:
      - TIMESCALE_HOST=timescaledb
      - TIMESCALE_DB=${TIMESCALE_DB}
      - GRAFANA_READER_USER=${GRAFANA_READER_USER}
      - GRAFANA_READER_PASSWORD=${GRAFANA_READER_PASSWORD}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      - GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=/etc/grafana/provisioning/dashboards/json/PLC/plc-fleet.json
      - GF_PLUGINS_PREINSTALL_DISABLED=true
    volumes:
      - ../grafana/provisioning:/etc/grafana/provisioning:ro
      - grafana_data:/var/lib/grafana
    ports:
      - "127.0.0.1:3000:3000"
```

The tree replaces Grafana's whole `/etc/grafana/provisioning`. To add it to a Grafana that already provisions other
things, copy the files into that Grafana's own tree instead (the datasource uid `timescale-edge` must stay: the
dashboards and rules refer to it).

The dashboards expect the historian's objects as the template's SQL defines them (`plc_registry`, `plc_model`,
`plc_latest`, the `plc_cycle` roll-ups, the `plc_*` functions); a PLC appears once it is registered there.
