#!/bin/bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
script_dir=$(cd "$(dirname "$0")" && pwd)
if [[ $# == 0 && -z ${MPP_DEVICE_UDID:-} ]]; then
  echo 'Conecte e desbloqueie o iPhone. Aparelhos disponíveis:'
  xcrun xctrace list devices
  read -r -p 'Cole o UDID entre parênteses ao lado do iPhone físico (não simulador): ' device_id
  if [[ -z ${MPP_BUNDLE_ID:-} ]]; then
    read -r -p 'Bundle Identifier usado no Xcode [com.example.mobilephoneproxy]: ' selected_bundle
    export MPP_BUNDLE_ID=${selected_bundle:-com.example.mobilephoneproxy}
  fi
  exec "$script_dir/start-usb-proxy.sh" "$device_id"
fi
exec "$script_dir/start-usb-proxy.sh" "$@"
