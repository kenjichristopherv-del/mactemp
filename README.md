# mactemp

A SwiftBar/xbar menubar plugin for Apple Silicon thermals. Reads real hardware
sensors with **no sudo, no kext, no helper daemon, and no third-party
dependencies** — just IOKit's HID event system, the same source Activity
Monitor uses.

```
68°                 ← normal
97° throttling      ← red; sustained thermal pressure
97° hot             ← amber; sustained 95 °C+
68° battery hot     ← amber; sustained 45 °C+
```

## What it answers

Not *"is my Mac in danger?"* — on a fanless Mac it essentially never is. The SoC
is designed to run hot and clamp its own clocks, and there is no wear mechanism
you can trigger by working it hard. An *instantaneous* temperature alarm would
fire on every compile and get ignored within a week, which is why the high-temp
warning here requires the reading to be sustained, and why it arrives with a
named culprit instead of just a number.

It answers ***"why is my Mac slow right now?"***, which on a fanless machine is
a real and frequent thing:

- **Thermal pressure** (`nominal` / `fair` / `serious` / `critical`) — macOS's
  own signal for whether it is actively giving up speed to shed heat. This is
  the number that matters, not the temperature.
- **SoC die temperature**, hottest cluster and average across all sensors.
- **SSD and battery** temperatures, tracked separately.
- **Top CPU processes**, so a throttle event arrives with a culprit.

## Alerts

Deliberately quiet, and deliberately not dependent on notification permission.

The **menubar title itself** is the primary channel — it changes to
`throttling` or `battery hot` in colour. Nothing can silence it, no permission
is involved, and no Focus mode suppresses it.

Banner notifications are secondary (`NOTIFY_METHOD` at the top of the plugin —
`swiftbar`, `osascript`, `both`, `none`). SwiftBar's own banners require
SwiftBar to be allowed in System Settings › Notifications; the `osascript` path
goes through Script Editor instead. A plugin cannot detect a banner that failed
to deliver, which is exactly why the menubar carries the real signal.

Alerts fire only after a condition has been **continuously held for 5 minutes**:

- Thermal pressure at `serious`/`critical` — not on a spike, not on a compile.
- SoC die at **95 °C+** — running hot, approaching the throttle point.
- Battery at **45 °C+**. This is the one sensor where sustained heat has a
  genuine lifespan cost, and where "unplug it, get it off the blanket" is real
  advice.

One banner at a time, most informative first. Each carries a **suggested
action**, and the suggestion names the actual culprit rather than reciting a
checklist:

> **Mac running hot (97C)**
> Held above 95C for 6 min. Final Cut Pro is using 188.4% CPU - quit it if you
> don't need it.

When nothing dominates the CPU the advice falls back to placement, and mentions
unplugging only when actually on AC power.

Duration is measured in elapsed seconds, not sample counts, so changing the
refresh rate in the filename does not silently change the thresholds.

Repeats are rate-limited to once per 30 minutes.

## What counts as normal

Apple publishes no Tjmax for Apple Silicon, so these bands come from measured
behaviour rather than a datasheet. The plugin labels the current reading against
them.

| SoC die | Meaning |
|---|---|
| 30–45 °C | Idle. Nothing working hard. |
| 46–70 °C | Normal working range. |
| 71–90 °C | Heavy sustained load. Expected, and safe by design. |
| 91–99 °C | Very hot, near the throttle point. Still within design limits. |
| 100 °C+ | At the throttle ceiling. The chip is protecting itself. |

For scale: a fanless M3 MacBook Air has been measured **peaking at 114 °C** on
its hottest core under a stress test, settling near 100 °C once throttling
engaged. It did not fail, and it was not damaged — that is the cooling strategy
working. Throttling is reversible and by design.

**Ambient temperature is the number with a real limit.** Apple specifies
**10–35 °C** operating ambient for MacBooks, an ideal of 16–22 °C, and warns
that exposure above **35 °C ambient can permanently damage battery capacity**.
So the room matters more than the die reading — which is why this plugin tracks
battery temperature separately and says something about it, and why the "what to
do" advice mentions the room rather than telling you to stop working.

## Preferences

Exposed as `xbar.var` entries, so they are editable in the app's plugin
settings rather than by hand:

| Variable | Default | Meaning |
|---|---|---|
| `VAR_ALERT_MINUTES` | `5` | Minutes of sustained trouble before alerting |
| `VAR_HOT_WARN` | `95` | SoC temperature (°C) treated as running hot |
| `VAR_BATTERY_WARN` | `45` | Battery temperature (°C) treated as too hot |
| `VAR_NOTIFY` | `both` | Banner delivery: `swiftbar`, `osascript`, `both`, `none` |

## Install

```sh
./install.sh
```

SwiftBar only rescans its plugin folder at launch — if the plugin does not
appear, quit and reopen SwiftBar.

## CLI

```sh
mactemp           # one line of JSON
mactemp --list    # every sensor the machine exposes, named
```

## Layout

The published plugin is a **single self-contained file** so it works for anyone
who installs it from the plugin repository. That file is generated, not edited:

| File | Role |
|---|---|
| `mactemp.swift` | The sensor reader. Source of truth. |
| `plugin.template.sh` | The plugin shell. Source of truth. |
| `dist.sh` | Inlines the Swift into the template → `mactemp.30s.sh` |
| `mactemp.30s.sh` | **Generated.** The distributable plugin. Do not edit. |
| `build.sh` | Builds `bin/mactemp` for the `mactemp` CLI only. |

Edit the first two, run `./dist.sh`. The generator hashes the Swift source and
bakes the hash into the plugin, so the compiled cache invalidates itself
whenever the reader changes.

On first run the plugin writes the embedded Swift to
`~/Library/Caches/mactemp/` and compiles it **in the background** — the menubar
shows "Building sensor reader…" rather than blocking for several seconds, and
the next refresh picks up the finished binary. Builds go to a temp name and are
moved into place, so a half-written binary is never executable. A failed build
backs off for 10 minutes instead of retrying every refresh.

## How the sensor read works

`IOHIDEventSystemClient` is private API, so the symbols are resolved at runtime
with `dlsym` rather than linked. Matching on `PrimaryUsagePage 0xff00` /
`PrimaryUsage 5` selects temperature sensors; each service is then polled for a
`kIOHIDEventTypeTemperature` event.

Note the asymmetry that makes this easy to get wrong:
`IOHIDServiceClientCopyEvent` takes the event type **unshifted** (`15`), while
`IOHIDEventGetFloatValue` takes it **shifted** (`15 << 16`). Pass a shifted
value to the former and every sensor still enumerates but every event returns
nil — which looks exactly like a permissions failure and is not.

Sensor naming on Apple Silicon:

- `PMU tdie*` / `PMU2 tdie*` — SoC die sensors. The ones that matter.
- `PMU tdev*` — surrounding board. Cooler, noisier, and some read small
  negatives when unpopulated; those are filtered out.
- `gas gauge battery` — battery cells, several of them.
- `NAND CH0 temp` — internal SSD.

## Requirements

Apple Silicon, and the Command Line Tools for `swiftc` (`xcode-select
--install`). Intel Macs expose a different sensor set through the SMC and are
explicitly refused rather than shown wrong numbers.
