"""Run the MyProxy relay on this Mac: 127.0.0.1:8890 -> iPhone over USB, Wi-Fi as fallback.

Usage:
  python3 relay.py --usb http://127.0.0.1:8889 --wifi http://192.168.0.10:8888

--usb is the local port forwarded to the iPhone (iproxy 8889:8888); --wifi is the
iPhone's address on the local network. Stop with Ctrl+C.
"""
import argparse
import signal
import threading

from proxy_fallback import MyProxyRelay


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--usb", required=True, help="MyProxy through the USB forward, e.g. http://127.0.0.1:8889")
    parser.add_argument("--wifi", required=True, help="MyProxy on the local network, e.g. http://192.168.0.10:8888")
    parser.add_argument("--port", type=int, default=8890, help="loopback port to listen on (default 8890)")
    args = parser.parse_args()

    relay = MyProxyRelay(("127.0.0.1", args.port), {"usb": args.usb, "wifi": args.wifi})
    relay.start()
    stop = threading.Event()
    for name in (signal.SIGINT, signal.SIGTERM):
        signal.signal(name, lambda *_: stop.set())
    print(f"MyProxy relay listening on 127.0.0.1:{args.port}")
    last = None
    try:
        while not stop.wait(5):
            reason = relay.snapshot()["reason"]
            if reason != last:
                print(reason, flush=True)
                last = reason
    finally:
        relay.stop()


if __name__ == "__main__":
    main()
