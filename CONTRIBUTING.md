# Contributing

Start from the installation guide, make a focused change, and run `./scripts/test.sh` plus the unsigned simulator build in the README. Explain the behavior changed and whether you tested it on a simulator or physical device. Report the OS/Xcode version and preserve original credits and MIT notices.

Do not commit signing certificates, provisioning profiles, signed Shortcut packages, device identifiers, `.env` files, tokens, account credentials, or copied live logs. Set your own signing values locally and review the diff before opening a PR. Use the readable `shortcuts/Rotate IP.plist` as the Shortcut source; sign it locally with `macos/prepare-shortcut.sh`.

For device tests, state when a test interrupts connectivity. Do not treat a completed Shortcut as proof of a new carrier IP, or a brief successful request as proof of continuous background availability. Android/Windows and relay changes need their own validation; this fork's CI focuses on the iOS changes.

Use issues for reproducible bugs and ideas, without private diagnostics or credentials. This fork is independent from the original project; fixes that apply upstream can be proposed there separately.
