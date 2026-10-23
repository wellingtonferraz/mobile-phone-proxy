# Mobile Phone Proxy — iOS community improvements

An open-source fork of **[Mobile Phone Proxy by Matija Stepanic (@stepanic)](https://github.com/stepanic/mobile-phone-proxy)**, with iPhone usability, local-network access controls, diagnostics, and USB tooling contributed by **Wellington Ferraz**. The original project and Git history are preserved under the [MIT license](LICENSE). See [credits](CREDITS.md).

Use an iPhone as an **HTTP proxy with HTTPS CONNECT**, reached from a Mac over USB or from a computer on the same private Wi-Fi subnet. Outbound connections try cellular first; the inherited fallback can use the default route, including Wi-Fi. This is not a VPN or a guarantee of cellular-only egress.

**[Installation guide (English)](docs/INSTALL.md) · [Guia de instalação (Português)](docs/INSTALACAO-PT-BR.md)**

## What's improved in this fork

- **Background audio keepalive:** enabled on first launch, remembers your ON/OFF choice. Silent audio is generated locally; Spotify is not required. iOS can still interrupt or suspend the app.
- **Local access policy:** IPv4 loopback or the current private Wi-Fi subnet only; rejects inbound cellular/other interfaces and IPv6. This policy applies to the iOS app, not the inherited Android/Windows apps.
- **Clear connection instructions:** current Wi-Fi address in the app; separate USB instructions for `127.0.0.1:8889` on the Mac running the tunnel.
- **Diagnostics:** 300 recent events in memory, timestamps/levels/categories, filters, copy/clear, common credential redaction, and connection counting that closes each client once.
- **Manual IP rotation:** `Rotação do IP → Trocar IP agora` opens your **Rotate IP** Shortcut. Request, completion, and a newly observed public IP are separate states. Duplicate requests and stale callbacks/lookups cannot confirm a new IP. No periodic rotation is scheduled.
- **Portable USB launcher:** explicitly targets a physical device, reuses only a matching tunnel, diagnoses a stopped app, and cleans up only a tunnel it created.
- **Repeatable checks:** Swift tests, launcher tests, an unsigned Shortcut source, and local simulator build instructions.

The modified iOS interface is currently primarily Portuguese. The upstream Android, Windows, relay and iMessage components are retained for developers; this fork has not revalidated their end-to-end behavior. Direct Tailscale access to the modified iOS listener is intentionally incompatible with its local-only access policy.

## Quick start

You need a Mac, a compatible full Xcode installation, an Apple Account for your own signing, XcodeGen, and a physical iPhone with mobile data. The deployment target is iOS 16; use Xcode that supports your macOS and device OS.

```bash
git clone https://github.com/wellingtonferraz/mobile-phone-proxy.git
cd mobile-phone-proxy
brew install xcodegen libusbmuxd
# Optional: prepare a locally signed Shortcut, without running it.
./macos/prepare-shortcut.sh
cd ios
xcodegen generate
open MobilePhoneProxy.xcodeproj
```

In Xcode, select **your own team**, replace `com.example.mobilephoneproxy` with a **unique bundle identifier**, choose your connected iPhone and Run. Unlock/trust the device, enable Developer Mode if requested, and allow Local Network access. The app starts the proxy after launch; `Start proxy` restarts it after a manual stop. See the full guides for signing, reinstalling and command-line builds. Project regeneration resets Xcode-only signing edits; update `ios/project.yml` locally or pass build settings when needed.

For **Wi-Fi**, use the address shown in the app, port `8888`, proxy type **HTTP**, and blank username/password. For **USB**, keep the app open and run:

```bash
xcrun xctrace list devices  # copy the physical iPhone UDID in parentheses
MPP_BUNDLE_ID=com.yourname.mobilephoneproxy \
  ./macos/start-usb-proxy.sh YOUR_DEVICE_UDID
curl --noproxy '' --proxy http://127.0.0.1:8889 https://example.com/
```

The USB address belongs to that Mac; it is not the iPhone's Wi-Fi address. Closing a terminal that owns the tunnel stops that tunnel. A second iPhone needs its own signing/device registration and a separate Mac port, for example `8890`.

## Manual rotation

Create or import a Shortcut named **Rotate IP**: **Airplane Mode ON → Wait 91 seconds → Airplane Mode OFF**. [Readable source](shortcuts/Rotate%20IP.plist) and [installation details](docs/INSTALL.md#5-manual-ip-rotation) are included. The signed package is generated locally and excluded from Git.

Tap **Trocar IP agora** with the proxy app in the foreground and Guided Access off. Keep Shortcuts open until it finishes. The connection will drop temporarily; the carrier may return the same IP. If you interrupt the Shortcut, make sure Airplane Mode is off. The 30-second public-IP check only observes the address; it does not rotate it.

## Access and privacy

The current Wi-Fi subnet is trusted **without authentication**. The local admission rule covers proxy traffic and control endpoints such as `/__status`, `/__log`, `/__rotate`, and the time-limited pairing endpoint. A permitted local computer can therefore view diagnostics or request rotation while the app is in the foreground. Use a trusted network; do not publish/forward the listener to the Internet. Local relays/NAT can forward outside traffic, so this is not absolute protection from forwarding by a trusted device.

Logs may contain IPs and destination hosts. Common credentials are redacted, but inspect copied diagnostics before sharing. HTTPS CONNECT tunnels TLS bytes without terminating TLS; destination/connection metadata is still visible. The app periodically queries an external IP service. Optional relay support is **unconfigured by default**; configure your own server deliberately if you develop that path.

To avoid the inherited Wi-Fi fallback, use **USB with Wi-Fi disabled in iPhone Settings** and mobile data enabled. Check the actual exit IP and logs for your carrier. One iPhone does not provide a separate public IP for each browser profile or proxy port.

## Validation and limitations

The local build underlying these changes was installed on an **iPhone 15 Pro Max / iOS 26.6**, using **Xcode 26.6 on macOS 26.4.1**. USB/Wi-Fi health and HTTPS requests passed, and keepalive was active. Logic tests cover rotation state, log sanitization and local admission; the public configuration is also built without signing for the simulator.

**Actual Airplane Mode rotation was not executed in this fork's validation.** The Shortcut was imported and its presence on the phone confirmed. Long-running background availability, a second phone on iOS 27.1, and a TestFlight/App Store release remain untested. Upstream experiments in `docs/2026-10-01-*` describe the original author's setup, not guarantees for this fork.

Free Personal Team signing expires after seven days. A GitHub link provides source code, not a universally installable iPhone app. TestFlight distribution requires Apple Developer Program membership and applicable beta review; no TestFlight link or signed IPA is provided here. See the guides and [Apple's account limits](https://developer.apple.com/help/account/basics/about-your-developer-account).

## Development

```bash
./scripts/test.sh
cd ios && xcodegen generate
xcodebuild -project MobilePhoneProxy.xcodeproj -scheme MobilePhoneProxy \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ../build CODE_SIGNING_ALLOWED=NO build
```

Tests and the local simulator build do not change Airplane Mode or contact a physical phone. [Contributing](CONTRIBUTING.md) · [Changes](CHANGELOG.md).

## License and authorship

**MIT. Original author: [Matija Stepanic](https://github.com/stepanic). Original repository: [stepanic/mobile-phone-proxy](https://github.com/stepanic/mobile-phone-proxy).** Fork improvements by [Wellington Ferraz](https://github.com/wellingtonferraz). This is an independent fork, not an official upstream release or endorsement.
