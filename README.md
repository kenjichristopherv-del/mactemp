# mactemp

A SwiftBar/xbar menubar plugin for Apple Silicon thermals. Reads real hardware
sensors with **no sudo, no kext, no helper daemon, and no third-party
dependencies** — just IOKit's HID event system, the same source Activity
Monitor uses.

```
68°                 ← normal
68° throttling      ← red; sustained thermal pressure
68° battery hot     ← amber; sustained 45 °C+
```

## What it answers

Not *"is my Mac in danger?"* — on a fanless Mac it essentially never is. The SoC
is designed to run hot and clamp its own clocks, and there is no wear mechanism
you can trigger by working it hard. A temperature-threshold alarm would fire
constantly on a healthy machine and get ignored within a week.

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

Alerts fire only after:

- **10 consecutive** `serious`/`critical` samples (5 minutes at the default 30s
  refresh) — not on a spike, not on a compile.
- Battery at **45 °C+** for the same duration. This is the one sensor where
  sustained heat has a genuine lifespan cost, and where "unplug it, get it off
  the blanket" is real advice.

Repeats are rate-limited to once per 30 minutes.

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
