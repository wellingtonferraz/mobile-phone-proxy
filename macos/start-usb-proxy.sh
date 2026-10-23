#!/usr/bin/env bash
# USB forwarding with explicit device selection; never stops another app's tunnel.
set -euo pipefail

usage() {
  cat <<'HELP'
Usage: macos/start-usb-proxy.sh DEVICE_UDID [LOCAL_PORT=8889] [PHONE_PORT=8888]
Find the physical iPhone UDID with: xcrun xctrace list devices
Use the UDID in parentheses next to the iPhone, not a simulator or CoreDevice UUID.
Environment: MPP_DEVICE_UDID, MPP_BUNDLE_ID (default com.example.mobilephoneproxy).
Use the same bundle identifier you selected when signing the iOS app.
The tunnel binds to 127.0.0.1 only. Keep this terminal open for a new tunnel.
HELP
}
if [[ ${1:-} == --help || ${1:-} == -h ]]; then usage; exit 0; fi
if (( $# > 3 )); then usage >&2; exit 2; fi
phone_id=${1:-${MPP_DEVICE_UDID:-}}
local_port=${2:-8889}
phone_port=${3:-8888}
bundle_id=${MPP_BUNDLE_ID:-com.example.mobilephoneproxy}
if [[ ! $phone_id =~ ^[[:alnum:]-]+$ ]]; then
  echo 'Choose a USB device ID first (not a device name).' >&2
  usage >&2; exit 2
fi
for port_number in "$local_port" "$phone_port"; do
  if [[ ! $port_number =~ ^[1-9][0-9]{0,4}$ ]] || (( port_number > 65535 )); then
    echo 'Ports must be integers from 1 to 65535, without leading zeros.' >&2; exit 2
  fi
done
if [[ ! $bundle_id =~ ^[A-Za-z0-9.-]+$ ]]; then echo 'Invalid MPP_BUNDLE_ID.' >&2; exit 2; fi
for tool in iproxy python3 curl lsof ps xcrun; do
  command -v "$tool" >/dev/null || { echo "Missing $tool. See docs/INSTALL.md." >&2; exit 1; }
done
proxy_tool=$(command -v iproxy)
proxy_pid=''
log_dir="$HOME/Library/Logs/MobilePhoneProxy"
umask 077
mkdir -p "$log_dir"
proxy_log="$log_dir/usb-$local_port.log"
expected_command="$proxy_tool -l -s 127.0.0.1 -u $phone_id $local_port:$phone_port"

proxy_ready() {
  curl --noproxy '*' --connect-timeout 1 --max-time 2 --fail --silent \
    "http://127.0.0.1:$local_port/__status" 2>/dev/null |
    python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(not (d.get("isRunning") is True and d.get("port")==int(sys.argv[1]) and "build" in d))' "$phone_port" 2>/dev/null
}
cleanup() {
  if [[ -n $proxy_pid ]]; then kill -TERM "$proxy_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "HTTP proxy on this Mac: 127.0.0.1:$local_port → iPhone:$phone_port"
current_pid=$(lsof -nP -t -iTCP:"$local_port" -sTCP:LISTEN 2>/dev/null || true)
if [[ -n $current_pid ]]; then
  current_command=$(ps -p "$current_pid" -o command= 2>/dev/null || true)
  if [[ $current_command != "$expected_command" ]]; then
    echo "Port $local_port belongs to another process or device. Nothing was stopped." >&2; exit 1
  fi
  echo 'Reusing the matching USB tunnel.'
else
  "$proxy_tool" -l -s 127.0.0.1 -u "$phone_id" "$local_port:$phone_port" >"$proxy_log" 2>&1 &
  proxy_pid=$!
  sleep 1
  kill -0 "$proxy_pid" 2>/dev/null || { echo "iproxy stopped. See $proxy_log" >&2; exit 1; }
fi
if ! proxy_ready; then
  echo 'App did not respond. Restarting only Mobile Phone Proxy on the selected device…'
  if ! xcrun devicectl device process launch --device "$phone_id" --terminate-existing \
      --timeout 15 "$bundle_id" >>"$proxy_log" 2>&1; then
    echo "Unlock/trust the iPhone and check MPP_BUNDLE_ID. Details: $proxy_log" >&2; exit 1
  fi
  for _retry in {1..6}; do
    if proxy_ready; then break; fi
    sleep 1
  done
fi
if ! proxy_ready; then
  echo "Tunnel opened, but app did not respond. Open the app, use port $phone_port, and check $proxy_log." >&2; exit 1
fi
echo "Ready: http://127.0.0.1:$local_port"
if [[ -n $proxy_pid ]]; then
  echo 'Keep this terminal open. Ctrl+C stops only the tunnel created here.'
  wait "$proxy_pid"
else
  echo 'The tunnel was already running; this terminal can be closed.'
fi
