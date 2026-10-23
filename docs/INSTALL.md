# Install on iPhone (Mac + Xcode)

[Português](INSTALACAO-PT-BR.md) · [Project and original-author credits](../README.md)

This guide builds **your own signed copy**. GitHub hosts the source; it does not grant an Apple signing identity or install an IPA on any phone.

## 1. Requirements

- A Mac with the **full Xcode app** compatible with your macOS and the iPhone's iOS version. Command Line Tools alone are insufficient. Check [Apple's compatibility table](https://developer.apple.com/xcode/system-requirements).
- An Apple Account added in **Xcode → Settings → Accounts**. A free Personal Team works for local tests, with [seven-day provisioning and device/app limits](https://developer.apple.com/help/account/basics/about-your-developer-account).
- An iPhone, mobile data/SIM, a USB data cable, and permission to trust this Mac. The app's deployment target is iOS 16; actual device/Xcode compatibility still needs to be checked.
- [Homebrew](https://brew.sh), XcodeGen and libusbmuxd (`iproxy`). Python 3 is used by tests and the launcher health check; install it with Homebrew if `python3 --version` fails.

Open Xcode once, finish its component installation, and accept its terms yourself. If needed, select it in Xcode's Locations settings, or use a per-terminal selection:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -version
brew install xcodegen libusbmuxd
python3 --version
```

## 2. Get the source

```bash
git clone https://github.com/wellingtonferraz/mobile-phone-proxy.git
cd mobile-phone-proxy
```

Optional: prepare the Shortcut package before generating the project:

```bash
./macos/prepare-shortcut.sh
```

This uses Apple's `shortcuts sign --mode anyone` to sign the readable source locally. Signing may require Internet access to Apple's validation service. It does **not** execute the Shortcut or change network settings. The generated `.shortcut` file is ignored by Git. You can instead create the three actions manually in step 5.

## 3. Build, sign and install

```bash
cd ios
xcodegen generate
open MobilePhoneProxy.xcodeproj
```

1. Connect and unlock your iPhone. On the phone, accept **Trust This Computer** if shown.
2. In Xcode, select the `MobilePhoneProxy` target → **Signing & Capabilities**. Keep automatic signing enabled and select **your team**.
3. Replace `com.example.mobilephoneproxy` with a **unique bundle identifier**, such as a reverse-domain name you control. Remember it for the USB launcher. Do not use the original author's identifier.
4. Select your physical iPhone as the run destination. Let Xcode register the device and prepare support files if needed.
5. If iOS requests it, enable **Settings → Privacy & Security → Developer Mode**, restart and confirm on the phone. Run the app again in Xcode.
6. Allow **Local Network** access. The app automatically starts the proxy after launch. If stopped manually, tap **Start proxy**. Keep the port at **8888** for the default USB mapping.

No signing certificate or provisioning profile is supplied. Settings edited only inside the generated Xcode project will be reset if you run XcodeGen again. For repeat builds, set your own values in `ios/project.yml` locally (do not commit them) or pass build settings:

```bash
# Run from the repository root. Replace every placeholder yourself.
xcrun xctrace list devices
xcodebuild -project ios/MobilePhoneProxy.xcodeproj -scheme MobilePhoneProxy \
  -configuration Debug -destination 'id=YOUR_DEVICE_UDID' \
  -derivedDataPath build -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID PRODUCT_BUNDLE_IDENTIFIER=com.yourname.mobilephoneproxy build
xcrun devicectl device install app --device YOUR_DEVICE_UDID \
  build/Build/Products/Debug-iphoneos/MobilePhoneProxy.app
xcrun devicectl device process launch --device YOUR_DEVICE_UDID \
  com.yourname.mobilephoneproxy
```

Use the **physical iPhone UDID shown in parentheses by `xctrace`**, not a simulator ID or the separate CoreDevice UUID. Xcode must first be configured with your Apple Account and device.

## 4. Connect from a computer

### Same Wi-Fi

Connect the computer and iPhone to the same trusted private Wi-Fi subnet. Keep mobile data active. In your browser/proxy-capable app:

| Field | Value |
| --- | --- |
| Type | HTTP (HTTPS is tunneled with CONNECT) |
| Host | Current **IP Wi-Fi do iPhone** shown in the app |
| Port | `8888`, or the port selected in the app |
| Username / password | Blank |

Use host and port as separate fields if requested. The carrier's public IP is **not** the proxy host. The Wi-Fi address can change; read the app again. Guest Wi-Fi/client isolation may prevent devices from connecting to each other.

### USB on the same Mac

Keep the app open on the unlocked phone, then from the repository root:

```bash
xcrun xctrace list devices
MPP_BUNDLE_ID=com.yourname.mobilephoneproxy \
  ./macos/start-usb-proxy.sh YOUR_DEVICE_UDID
```

Configure **HTTP**, host **127.0.0.1**, port **8889**, username/password blank. This tunnel exists only on the Mac where the command runs. The launcher binds to loopback, explicitly targets that device, and maps Mac port 8889 to iPhone port 8888. If the app is unresponsive, it attempts to restart only that bundle on that device. Set `MPP_BUNDLE_ID` to the identifier you actually installed.

The Portuguese double-click wrapper is `macos/Iniciar Proxy iPhone.command`. It lists devices and asks for the physical UDID and the Bundle Identifier you used in Xcode. `MPP_DEVICE_UDID` and `MPP_BUNDLE_ID` can also be supplied in the environment. The Terminal command above makes both choices explicit.

- A new tunnel keeps the terminal running; **Ctrl+C** closes only that tunnel.
- A healthy matching tunnel is reused; the new terminal can close.
- An unrelated process using the port is left untouched. Choose another local port or manage that process yourself.
- Logs stay on your Mac in `~/Library/Logs/MobilePhoneProxy/usb-PORT.log`.

For a second iPhone, first sign/register/install it as in step 3. Then use its own UDID and a different Mac port:

```bash
MPP_BUNDLE_ID=com.yourname.mobilephoneproxy \
  ./macos/start-usb-proxy.sh SECOND_DEVICE_UDID 8890 8888
```

These are two separate devices. Creating more local ports for one iPhone does not create extra carrier IPs.

### Check connectivity

```bash
# App status through the USB tunnel (does not rotate anything):
curl --noproxy '*' --max-time 10 http://127.0.0.1:8889/__status
# HTTPS through the proxy:
curl --noproxy '' --proxy http://127.0.0.1:8889 --max-time 20 https://example.com/
```

For Wi-Fi, replace the URL with the phone's displayed private IPv4 and port. The app's public-IP checker queries an external service periodically; that check only observes the IP.

The inherited proxy attempts cellular first but may fall back to the default route. To avoid Wi-Fi fallback, use **USB**, turn Wi-Fi off in **iPhone Settings**, keep mobile data on, and verify exit-IP/logs. Do not infer cellular egress solely from a successful HTTP response.

## 5. Manual IP rotation

The app does not directly toggle Airplane Mode. It invokes **your Shortcut**, named exactly **Rotate IP**:

1. **Set Airplane Mode → On**.
2. **Wait → 91 seconds**.
3. **Set Airplane Mode → Off**.

Create this in the iPhone's Shortcuts app, or import your locally generated `ios/MobilePhoneProxy/Rotate IP.shortcut` using AirDrop/Files. If generated **before** XcodeGen/build, it is also available from **Configurar atalho Rotate IP → Compartilhar arquivo do atalho** inside the proxy app. Save to Files, open it and add it to Shortcuts. If iCloud has already synced that exact Shortcut, do not import a duplicate.

With the proxy app foregrounded and Guided Access off, tap **Rotação do IP → Trocar IP agora**. Keep Shortcuts open until it finishes; allow it to return to the proxy app if prompted. Expect a temporary connection interruption. If you cancel or interrupt it, check that Airplane Mode is **off** before trying again.

The app distinguishes request, Shortcut completion, a fresh IP lookup, a changed IP, the same IP, and an unconfirmed result. The carrier can reuse its IP; 91 seconds is an adjustable starting value inherited from upstream experiments, **not a guarantee for your carrier**. No recurring rotation is scheduled. Actual rotation was not executed during this fork's validation.

Advanced upstream iMessage/relay tooling is retained, but is not required for this manual workflow. The fork's relay URL is blank by default; it does not use the original author's deployed relay. Direct inbound Tailscale access is blocked by the new iOS local-access policy.

## 6. Background behavior, logs and troubleshooting

- **Keep alive in background (audio)** is ON at first launch and remembers your preference. It generates silent audio locally; no music app is needed. Calls, audio interruptions and iOS suspension can still stop service. Foreground use is the tested setup; continuous background operation is not guaranteed.
- **Diagnóstico** contains the last 300 events of the current process, with filters/copy/clear. Logs can include destination hosts and IPs. Common credential formats are redacted; review before sharing.
- **Port occupied:** do not kill unknown processes. The launcher reuses only the exact matching tunnel/device; use a different local port otherwise.
- **USB failure:** unlock/trust the phone, check data cable, run the launcher again, check `MPP_BUNDLE_ID`, and keep the app on port 8888.
- **Wi-Fi failure:** verify the current private IPv4, matching subnet, local-network permission, and router client isolation. IPv6 and inbound cellular/other interfaces are rejected.
- **Shortcut not found:** check the exact name and install it in the phone's Shortcuts app. Opening Shortcuts is not proof that the requested Shortcut ran.
- **App no longer opens after a week:** free Personal Team provisioning expires after seven days; reconnect and rebuild/reinstall. The existing provisioning profile does not automatically authorize a second device.
- **Newer iOS not recognized:** check Xcode/device support; a newer Xcode may also require a newer macOS. Do not assume compatibility solely from the app's deployment target.

## 7. Distribution and development

The source and instructions are MIT-licensed; Apple signing still applies. **Personal Team** is suitable for local tests. **TestFlight** requires Apple Developer Program membership (US$99/year or local price); external distribution is subject to beta review, and each build can be tested for up to 90 days. This repository provides no TestFlight link or public signed IPA and does not promise approval.

Official references: [Apple account limits](https://developer.apple.com/help/account/basics/about-your-developer-account), [Developer Program](https://developer.apple.com/programs/), [TestFlight](https://developer.apple.com/testflight/), [90-day beta builds](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/), [Xcode requirements](https://developer.apple.com/xcode/system-requirements).

Run `./scripts/test.sh` and the unsigned simulator build in the README before contributing. Those checks do not run a real Shortcut, use a physical iPhone or change network settings. The local signed build was checked on iPhone 15 Pro Max/iOS 26.6; a second phone with iOS 27.1 has not been validated.
