# mactemp

A SwiftBar menubar plugin for Apple Silicon thermals. Reads real hardware
sensors with **no sudo, no kext, no helper daemon** — just IOKit's HID event
system, the same source Activity Monitor uses.

## What it answers

Not *"is my Mac in danger?"* — on a fanless M3 Air it essentially never is. The
SoC is designed to run hot and clamp its own clocks, and there is no wear
mechanism you can trigger by working it hard.

It answers ***"why is my Mac slow right now?"***, which on a fanless machine is
a real and frequent thing:

- **Thermal pressure** (`nominal` / `fair` / `serious` / `critical`) — macOS's
  own signal for whether it is actively giving up speed to shed heat. This is
  the number that matters, not the temperature.
- **SoC die temperature**, hottest core cluster and average across all eight.
- **SSD and battery** temperatures, tracked separately.
- **Top CPU processes**, so a throttle event comes with a culprit.

## Alerts

Deliberately quiet. It notifies only when:

- Thermal pressure has been `serious`/`critical` for **10 consecutive samples**
  (5 minutes at the default 30s refresh) — not on a spike, not on a compile.
- Battery has been at **45 °C or above** for 5 minutes. This is the one sensor
  where sustained heat has a genuine lifespan cost, and where "unplug it, get it
  off the blanket" is real advice.

Repeat notifications are rate-limited to once every 30 minutes.

## Install

```sh
./install.sh
```

Builds the sensor binary, symlinks the plugin into SwiftBar's plugin directory,
and drops a `mactemp` command in `/opt/homebrew/bin`. The repo stays the source
of truth — edit here and the next refresh picks it up.

## CLI

```sh
mactemp           # one line of JSON
mactemp --list    # every sensor the machine exposes, named
```

## Tuning

Refresh rate is the filename: rename `mactemp.30s.sh` to `mactemp.15s.sh`,
`mactemp.1m.sh`, etc. (update the symlink too). Thresholds are the constants at
the top of the plugin script.

## How the sensor read works

`IOHIDEventSystemClient` is private API, so the symbols are resolved at runtime
with `dlsym` rather than linked. Matching on `PrimaryUsagePage 0xff00` /
`PrimaryUsage 5` selects temperature sensors; each service is then polled for a
`kIOHIDEventTypeTemperature` event.

Sensor naming on Apple Silicon:

- `PMU tdie*` / `PMU2 tdie*` — SoC die sensors. The ones that matter.
- `PMU tdev*` — surrounding board. Cooler, noisier, and some read garbage
  (small negatives) when unpopulated; those are filtered out.
- `gas gauge battery` — battery cells, several of them.
- `NAND CH0 temp` — internal SSD.
