#!/bin/zsh
set -euo pipefail

# Renews the seven-day Personal Team signature: rebuilds, installs and opens the app.
# The Xcode project must already build for your device (team and bundle identifier set,
# see docs/INSTALACAO-PT-BR.md). Device settings stay outside the repository, either as
# environment variables or in ~/.config/myproxy/renew.env:
#   MPP_DEVICE_UDID=<iPhone UDID>
#   MPP_BUNDLE_ID=<bundle identifier used when signing the app>
CONFIG_FILE="${MPP_RENEW_CONFIG:-$HOME/.config/myproxy/renew.env}"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
fi
SOURCE_DIR="${MPP_SOURCE_DIR:-${0:A:h:h}}"
DEVICE_UDID="${MPP_DEVICE_UDID:?defina MPP_DEVICE_UDID em $CONFIG_FILE}"
BUNDLE_ID="${MPP_BUNDLE_ID:?defina MPP_BUNDLE_ID em $CONFIG_FILE}"
STATE_DIR="${MPP_STATE_DIR:-$HOME/.local/state/myproxy}"
BUILD_DIR="$STATE_DIR/build-renewal"
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
IPROXY="/opt/homebrew/bin/iproxy"
TUNNEL_PID=""
LOG="$STATE_DIR/renewal-latest.log"

export DEVELOPER_DIR
mkdir -p "$STATE_DIR"

cleanup() {
  if [[ -n "$TUNNEL_PID" ]]; then
    kill -TERM "$TUNNEL_PID" 2>/dev/null || true
    wait "$TUNNEL_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

print 'Renovar MyProxy — conecte e desbloqueie o iPhone pelo USB.'
print 'Mantenha esta janela aberta durante a renovação.'
print ''

if [[ ! -d "$SOURCE_DIR/ios/MobilePhoneProxy.xcodeproj" ]]; then
  print "Não encontrei o projeto do MyProxy em: $SOURCE_DIR"
  exit 1
fi
if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  print 'Xcode não encontrado. Instale ou abra o Xcode e tente novamente.'
  exit 1
fi

DEVICE_JSON="$STATE_DIR/renewal-devices.json"
if ! xcrun devicectl list devices --json-output "$DEVICE_JSON" >/dev/null 2>&1; then
  print 'Não consegui falar com o iPhone. Confira o cabo, desbloqueie a tela e aceite “Confiar neste computador”.'
  exit 1
fi
if ! /usr/bin/python3 - "$DEVICE_JSON" "$DEVICE_UDID" <<'CHECKPY'
import json, sys
try:
    devices = json.load(open(sys.argv[1], encoding='utf-8'))['result']['devices']
    found = any(d.get('hardwareProperties', {}).get('udid') == sys.argv[2]
                and d.get('connectionProperties', {}).get('transportType') == 'wired'
                and d.get('connectionProperties', {}).get('tunnelState') == 'connected'
                for d in devices)
    raise SystemExit(0 if found else 1)
except Exception:
    raise SystemExit(1)
CHECKPY
then
  print 'O iPhone esperado não está conectado pelo USB. Confira o cabo e tente novamente.'
  exit 1
fi

print 'iPhone conectado. Gerando uma nova assinatura de sete dias…'
if ! xcodebuild \
  -project "$SOURCE_DIR/ios/MobilePhoneProxy.xcodeproj" \
  -scheme MobilePhoneProxy \
  -destination "id=$DEVICE_UDID" \
  -derivedDataPath "$BUILD_DIR" \
  -allowProvisioningUpdates \
  clean build >"$LOG" 2>&1; then
  print 'O Xcode não conseguiu compilar/renovar. Últimas mensagens:'
  /usr/bin/tail -n 24 "$LOG"
  exit 1
fi

APP="$BUILD_DIR/Build/Products/Debug-iphoneos/MobilePhoneProxy.app"
if [[ ! -d "$APP" ]]; then
  print 'O Xcode terminou sem gerar o aplicativo.'
  exit 1
fi
if ! /usr/bin/python3 - "$APP" "$BUNDLE_ID" <<'CHECKPY'
import datetime, plistlib, subprocess, sys
from zoneinfo import ZoneInfo
from pathlib import Path
app = Path(sys.argv[1])
try:
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    raw = subprocess.check_output(['security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')], stderr=subprocess.DEVNULL)
    profile = plistlib.loads(raw)
    expires = profile['ExpirationDate'].replace(tzinfo=datetime.timezone.utc)
    if info.get('CFBundleIdentifier') != sys.argv[2] or expires <= datetime.datetime.now(datetime.timezone.utc):
        raise ValueError('Identidade ou validade da assinatura incorreta')
    print('Assinatura válida até ' + expires.astimezone(ZoneInfo('America/Sao_Paulo')).strftime('%d/%m/%Y às %H:%M BRT'))
except Exception as exc:
    print(f'Não confirmei uma assinatura válida: {exc}')
    raise SystemExit(1)
CHECKPY
then
  print 'A instalação foi interrompida porque a nova assinatura não passou na conferência.'
  exit 1
fi
if ! codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
  print 'A assinatura do aplicativo não passou na validação local.'
  exit 1
fi

print 'Instalando MyProxy…'
if ! xcrun devicectl device install app --device "$DEVICE_UDID" --timeout 90 "$APP" >>"$LOG" 2>&1; then
  print 'A instalação falhou. Detalhes no log renewal-latest.log, na pasta privada do projeto.'
  exit 1
fi

print 'Abrindo MyProxy…'
if ! xcrun devicectl device process launch --device "$DEVICE_UDID" --timeout 20 "$BUNDLE_ID" >>"$LOG" 2>&1; then
  print ''
  print 'O iPhone precisa confiar novamente no certificado de desenvolvedor.'
  xcrun devicectl device process launch --device "$DEVICE_UDID" --timeout 15 com.apple.Preferences >>"$LOG" 2>&1 || true
  print 'No iPhone: Ajustes → Geral → VPN e Gerenciamento de Dispositivo → App de Desenvolvedor → sua conta → Confiar.'
  print 'Confirme a confiança. Vou tentar abrir o MyProxy novamente por até dois minutos.'
  opened=0
  for attempt in {1..24}; do
    /bin/sleep 5
    if xcrun devicectl device process launch --device "$DEVICE_UDID" --timeout 15 "$BUNDLE_ID" >>"$LOG" 2>&1; then
      opened=1
      break
    fi
  done
  if [[ "$opened" -ne 1 ]]; then
    print 'O app foi instalado e assinado. Conclua a confiança nos Ajustes e abra o MyProxy na tela inicial.'
    exit 2
  fi
fi

print 'MyProxy abriu. Conferindo o proxy USB…'
if [[ -x "$IPROXY" ]]; then
  expected="$IPROXY -l -s 127.0.0.1 -u $DEVICE_UDID 8889:8888"
  current_pid=$(/usr/sbin/lsof -nP -t -iTCP:8889 -sTCP:LISTEN 2>/dev/null || true)
  if [[ -z "$current_pid" ]]; then
    "$IPROXY" -l -s 127.0.0.1 -u "$DEVICE_UDID" 8889:8888 >>"$LOG" 2>&1 &
    TUNNEL_PID=$!
    /bin/sleep 2
    current_pid=$TUNNEL_PID
  else
    current_command=$(/bin/ps -p "$current_pid" -o command= 2>/dev/null || true)
    if [[ "$current_command" != "$expected" ]]; then
      print 'MyProxy renovado e aberto. A porta 8889 está ocupada por outro programa; pulei o teste USB.'
      exit 0
    fi
  fi
  if /usr/bin/curl --noproxy '*' --connect-timeout 2 --max-time 5 --fail --silent http://127.0.0.1:8889/__status | /usr/bin/grep -q '"appActive":true'; then
    print 'Tudo certo: MyProxy respondeu pelo USB na porta 8889.'
  else
    print 'O app abriu, mas não confirmei o status pelo USB. Abra o MyProxy e confira a tela.'
    exit 1
  fi
else
  print 'MyProxy renovado e aberto. iproxy não foi encontrado; pulei o teste USB.'
fi

print 'Renovação concluída. O log fica em renewal-latest.log na pasta privada do projeto.'
