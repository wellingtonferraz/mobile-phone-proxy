# USB/Wi-Fi fallback relay (macOS)

A small loopback relay for programs on the Mac that should always leave through the
iPhone. It listens on `127.0.0.1:8890` and forwards each connection to the app on the
phone: over USB when the cable is connected, over the local Wi-Fi otherwise.

It is unrelated to the Cloudflare Worker in `relay/`, which handles reachability from
outside the local network.

- Every five seconds it checks both paths: the app's `/__status` must answer and a real
  HTTPS request through the phone must succeed. A path is used only while that check is
  fresh (25 seconds).
- With no confirmed path it answers `503` instead of letting traffic leave through the
  Mac's own connection.
- It listens on loopback only, forwards bytes without reading them, and connects only to
  the two addresses you pass.
- If the phone reports a Wi-Fi address different from the one configured, the Wi-Fi path
  is disabled until restart.

## Use

With the app open on the iPhone and the USB forward running (`macos/start-usb-proxy.sh`):

```sh
python3 relay.py --usb http://127.0.0.1:8889 --wifi http://<iPhone Wi-Fi IP>:8888
```

Point your programs at `http://127.0.0.1:8890`. Requires only Python 3 and the `curl`
shipped with macOS. Stop with Ctrl+C.
