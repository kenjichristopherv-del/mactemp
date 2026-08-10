#!/bin/bash
# <xbar.title>mactemp</xbar.title>
# <xbar.version>v1.0</xbar.version>
# <xbar.author>Kenji Tubera</xbar.author>
# <xbar.desc>Apple Silicon thermals: die temp, thermal pressure, and what is causing it.</xbar.desc>
# <xbar.dependencies>swift</xbar.dependencies>
#
# Rename the file to change the refresh rate (mactemp.15s.sh, mactemp.1m.sh, ...).

set -u

# Resolve through the symlink in ~/.swiftbar back to the repo checkout.
SELF="$(readlink -f "$0" 2>/dev/null || echo "$HOME/Developer/mactemp/mactemp.30s.sh")"
ROOT="$(dirname "$SELF")"
BIN="$ROOT/bin/mactemp"

STATE_DIR="$HOME/Library/Caches/mactemp"
STATE="$STATE_DIR/state"
mkdir -p "$STATE_DIR"

# --- thresholds ---------------------------------------------------------------
# The M3 Air is fanless: it is *designed* to run hot and clamp its own clocks.
# Temperature alone is therefore not a warning signal. Sustained thermal
# pressure is, because that is macOS saying it is actively giving up speed.
PRESSURE_SAMPLES=10   # consecutive serious/critical samples before speaking up
BATTERY_WARN=45       # deg C; sustained heat here does have a real lifespan cost
BATTERY_SAMPLES=10
NOTIFY_COOLDOWN=1800  # seconds between repeat notifications

if [ ! -x "$BIN" ]; then
  echo "thermals ⚠️ | sfimage=thermometer.medium color=#ff6b6b"
  echo "---"
  echo "mactemp binary not built"
  echo "Build it | bash='$ROOT/build.sh' terminal=true refresh=true"
  exit 0
fi

JSON="$("$BIN" 2>/dev/null)"
if [ -z "$JSON" ]; then
  echo "thermals ⚠️ | sfimage=thermometer.medium color=#ff6b6b"
  echo "---"
  echo "No sensor data returned"
  exit 0
fi

field() { echo "$JSON" | sed -n "s/.*\"$1\":\([0-9.]*\).*/\1/p"; }
DIE_MAX="$(field die_max)"
DIE_AVG="$(field die_avg)"
BATTERY="$(field battery)"
STORAGE="$(field storage)"
SENSORS="$(field sensors)"
STATE_NAME="$(echo "$JSON" | sed -n 's/.*"thermal_state":"\([a-z]*\)".*/\1/p')"

# --- sustained-pressure tracking ---------------------------------------------
PRESSURE_STREAK=0; BATTERY_STREAK=0; LAST_NOTIFY=0
# shellcheck disable=SC1090
[ -f "$STATE" ] && . "$STATE"

case "$STATE_NAME" in
  serious|critical) PRESSURE_STREAK=$((PRESSURE_STREAK + 1)) ;;
  *)                PRESSURE_STREAK=0 ;;
esac

if [ -n "$BATTERY" ] && [ "${BATTERY%.*}" -ge "$BATTERY_WARN" ] 2>/dev/null; then
  BATTERY_STREAK=$((BATTERY_STREAK + 1))
else
  BATTERY_STREAK=0
fi

NOW="$(date +%s)"
PLUGIN="$(basename "$0" | cut -d. -f1)"

notify() { # title, body
  local title="${1// /%20}" body="${2// /%20}"
  open "swiftbar://notify?plugin=${PLUGIN}&title=${title}&body=${body}" 2>/dev/null
  LAST_NOTIFY="$NOW"
}

if [ $((NOW - LAST_NOTIFY)) -ge "$NOTIFY_COOLDOWN" ]; then
  if [ "$PRESSURE_STREAK" -ge "$PRESSURE_SAMPLES" ]; then
    notify "Mac is throttling" "Sustained thermal pressure - expect things to feel slow. Check what is running."
  elif [ "$BATTERY_STREAK" -ge "$BATTERY_SAMPLES" ]; then
    notify "Battery is running hot" "${BATTERY}C sustained. Unplug or move it off soft surfaces."
  fi
fi

printf 'PRESSURE_STREAK=%s\nBATTERY_STREAK=%s\nLAST_NOTIFY=%s\n' \
  "$PRESSURE_STREAK" "$BATTERY_STREAK" "$LAST_NOTIFY" > "$STATE"

# --- render -------------------------------------------------------------------
case "$STATE_NAME" in
  nominal)  COLOR=""; ICON="thermometer.low";    PLAIN="Running free. No clocks are being held back." ;;
  fair)     COLOR=""; ICON="thermometer.medium"; PLAIN="Warm and working. Full speed, nothing to do." ;;
  serious)  COLOR="color=#ff9f0a"; ICON="thermometer.high"; PLAIN="Throttling. Speed is being clamped to shed heat." ;;
  critical) COLOR="color=#ff453a"; ICON="thermometer.high"; PLAIN="Heavily throttled. macOS is aggressively cutting speed." ;;
  *)        COLOR=""; ICON="thermometer.medium"; PLAIN="Unknown thermal state." ;;
esac

echo "${DIE_MAX%.*}° | sfimage=$ICON $COLOR"
echo "---"
echo "Thermal pressure: ${STATE_NAME} | sfimage=$ICON $COLOR"
echo "$PLAIN | size=11 color=#8e8e93"
echo "---"
echo "SoC die (hottest)  ${DIE_MAX}°C | font=Menlo size=12"
echo "SoC die (average)  ${DIE_AVG}°C | font=Menlo size=12"
[ -n "$STORAGE" ] && echo "SSD                ${STORAGE}°C | font=Menlo size=12"
if [ -n "$BATTERY" ]; then
  BCOL=""
  [ "${BATTERY%.*}" -ge "$BATTERY_WARN" ] 2>/dev/null && BCOL="color=#ff9f0a"
  echo "Battery            ${BATTERY}°C | font=Menlo size=12 $BCOL"
fi
echo "---"
echo "Top CPU right now"
ps -Ao %cpu,comm -r 2>/dev/null | sed -n '2,4p' | while read -r pct cmd; do
  echo "$(printf '%5s%%' "$pct")  $(basename "$cmd") | font=Menlo size=12"
done
echo "---"
echo "Open Activity Monitor | bash=/usr/bin/open param1=-a param2='Activity Monitor' terminal=false"
echo "All ${SENSORS} sensors | bash='$BIN' param1=--list terminal=true"
echo "Refresh | refresh=true"
