#!/usr/bin/env bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_dir"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/mpp-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
swift_dir=ios/MobilePhoneProxy
xcrun swiftc "$swift_dir/IPRotation.swift" tests/RotationTests.swift -o "$test_dir/rotation"
"$test_dir/rotation"
xcrun swiftc "$swift_dir/ProxyLog.swift" tests/ProxyLogTests.swift -o "$test_dir/logs"
"$test_dir/logs"
xcrun swiftc "$swift_dir/LocalProxyAccess.swift" "$swift_dir/NetworkInterface.swift" tests/LocalProxyAccessTests.swift -o "$test_dir/access"
"$test_dir/access"
bash -n macos/start-usb-proxy.sh macos/prepare-shortcut.sh 'macos/Iniciar Proxy iPhone.command' macos/rotate-ip.sh
python3 tests/test_usb_launcher.py
python3 - <<'PY'
from pathlib import Path
import plistlib
d=plistlib.loads(Path('shortcuts/Rotate IP.plist').read_bytes())
a=d['WFWorkflowActions']
assert d['WFWorkflowName']=='Rotate IP' and len(a)==3
assert [x['WFWorkflowActionIdentifier'] for x in a]==['is.workflow.actions.airplanemode.set','is.workflow.actions.delay','is.workflow.actions.airplanemode.set']
assert a[0]['WFWorkflowActionParameters']['WFOnValue'] is True
assert a[1]['WFWorkflowActionParameters']['WFDelayTime']==91
assert a[2]['WFWorkflowActionParameters']['WFOnValue'] is False
print('PASS: shortcut source structure (not executed)')
PY
