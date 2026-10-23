# Fork changes

## 2026-10-23 — iProxy name and app icon (build 10)

- Name the installed iOS app and its main screen **iProxy**.
- Add an original opaque app icon through the Xcode asset catalog.
- Keep bundle identifiers, callback scheme and project/target names unchanged for existing installations.
- Document the visible name separately from build commands; local checks remain available, with no GitHub Actions workflow.

## 2026-10-23 — iOS local improvements (build 9)

Based on upstream `23b009febe6038ff561d863b024359415310f99c`.

- Persist background-audio preference; default to enabled on first launch.
- Restrict iOS inbound connections to IPv4 loopback/current private Wi-Fi subnet.
- Show dynamic Wi-Fi settings and explain the separate USB tunnel.
- Add 300-entry in-memory structured/redacted log, filters, copy and clear.
- Count each client connection once on close.
- Add manual Rotate IP action, setup instructions and stale-result protection.
- Include reproducible tests and unsigned Shortcut source.
- Package a portable USB launcher, simulator CI and English/Portuguese installation guides.
- Remove personal signing/device defaults and disable the default third-party relay in the public configuration.

Physical-device checks were performed on the local signed build before publication. The public source configuration is validated by tests and an unsigned simulator build. Actual rotation, prolonged background operation and new-device installation are not claimed as tested.
