# Connectivity and reconnect (build 13)

The app separates **Proxy escutando** (the local listener) from **Internet móvel** (a recent HTTPS check pinned to the cellular interface). A listening port, historical IP or keepalive does not confirm internet connectivity.

- The check uses `api.ipify.org`, TLS verification, HTTP 200 and a valid IPv4/IPv6 body. It has a ten-second total deadline. Failed, cancelled or late results cannot renew evidence.
- Evidence expires after 45 seconds measured conservatively from the request's start, including suspension/delayed delivery. The UI and `/__status` expose the same state. Old IPs are labelled historical.
- A successful check schedules the next check after 30 seconds. Failures schedule retries after 5, 10, 20 and then 30 seconds; probes do not overlap. A failed probe does not restart healthy proxy connections. A failed listener is rebuilt separately.
- **Reconectar proxy** closes connections owned by MyProxy, rebuilds its listener and starts a fresh check. It also starts a stopped proxy. Repeated taps cannot overlap the current reconnect cycle. Existing TCP/TLS connections cannot migrate and requests are not replayed.
- **Stop proxy** cancels probes, retries, listener and owned connections. Delayed callbacks and returning to the foreground cannot override an explicit Stop within the current process. Fully closing and reopening the app retains the existing autostart behavior; Stop is not persisted across process restarts.
- Reconnect does not switch mobile data, run Shortcuts, activate Airplane Mode or request another public IP. It cannot restore carrier signal. Keepalive only attempts to keep the app active; calls and iOS suspension can interrupt it.

Failure means the probe did not confirm cellular connectivity. It does not prove that all internet access is unavailable. Success does not prove the Mac's USB tunnel works or that every proxied request used cellular: the inherited outbound handler may still fall back to the phone's default route. Mac clients must continue their own end-to-end HTTPS checks.

`/__status` preserves existing fields and adds `listenerState`, `desiredRunning`, `cellularHealth` (`stopped`, `checking`, `confirmed`, `unconfirmed`), validity, attempt/proof timestamps, evidence age, next attempt and `reconnecting`. No remote reconnect endpoint is added.

Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/test.sh` and the unsigned simulator build documented in the README. Unit tests/builds do not establish carrier or background reliability on a physical phone. Revalidate USB/LAN HTTPS and lifecycle behavior after an authorized installation.
