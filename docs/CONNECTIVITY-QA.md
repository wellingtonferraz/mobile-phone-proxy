# Build 13 — implementation validation, 2026-10-23

Scope: cellular HTTPS evidence, expiry, retries, Stop and reconnect of app-owned resources. Public/shared Swift sources are identical to the personalized build; signing identifiers/configuration were not copied to the public tree. Only `CURRENT_PROJECT_VERSION` changed from 12 to 13 in each project's configuration.

Assumptions and limits:

- One operator on the existing iPhone; same local admission policy, port, keepalive preference and relay configuration. Carrier signal and iOS background scheduling remain outside app control.
- The existing cellular-only IP lookup is the evidence source, not an assertion of all-destination or exclusive cellular egress. Its independent failure does not trigger connection teardown.
- Health validity is 45 seconds from request start; normal next check is after 30 seconds. Failure waits are 5/10/20/30 seconds. A ten-second deadline is checked using `ContinuousClock` and again at main-actor delivery; rejected late results do not update the displayed proof.
- A manual reconnect may interrupt active transfers. No request replay or rotation is introduced. Upstream fallback is allowed only before forwarding starts; establishment is bounded by a shared 15-second deadline.

Validation executed:

- Final `scripts/test.sh`: 44 connectivity/recovery checks, 18 rotation checks, 37 log checks, 23 admission checks, nine launcher tests and Shortcut source validation passed. No Shortcut was executed.
- Test-first additions initially failed because the new model/operations were absent. The late-delivery regression then reproduced a behavioral failure before its fix, and passed afterward. Tests cover stale generations, delayed proof, clock reversal, backoff, no overlap, explicit Stop, late autostart, socket ownership and no retry after forwarding.
- An earlier full run and an isolated repeat failed `test_early_tunnel_exit_is_reported`: exit code 1 with empty stderr rather than the expected diagnostic. A shell trace and the final full run passed without changing launcher/test code. Cause unproven; retain this intermittent test limitation.
- Both final Xcode builds succeeded: unsigned iOS Simulator in the public source and locally signed generic iOS build in the personalized source. Device `codesign --verify --deep --strict` returned 0; team identity and embedded provisioning were present. Both Info.plists report build 13. The physical build retained the existing interface-orientation warning.
- Workspace `npm run lint`, `npm run typecheck`, `npm test` all failed because those scripts are absent. They are not PASS. Swift checks/builds are separate evidence.

Artifacts relative to each source:

- Public: `build/connectivity/Build/Products/Debug-iphonesimulator/MobilePhoneProxy.app`; `build-connectivity-tests.log`; `build-connectivity-simulator.log`.
- Personalized: `build/connectivity/Build/Products/Debug-iphoneos/MobilePhoneProxy.app`; `build-connectivity-device.log`.

No installation, phone restart, device network operation, Git push or PR was performed by the implementer. Simulator UI review, physical installation/runtime, sustained background behavior and carrier recovery must be reported separately by the coordinating agent/QA. This implementation report is not a hardware certification.


## Subsequent controlled runtime check — 2026-10-23

The executor installed and launched build 13 on the existing iPhone. The device status endpoint reported build 13, a listening server, a fresh confirmed cellular probe and active keep alive. Neutral HTTPS checks succeeded through USB, LAN and the local fallback relay. This is a short foreground observation, not certification of sustained background operation or cellular-only forwarding for every destination.

The executor exercised Reconnect and Stop in an isolated iOS simulator. Stop remained effective for over 31 seconds and after returning from the Home Screen; a full process relaunch retains the existing autostart behavior. Stop is not persisted across process restarts. The physical iPhone button was not exercised, and no network outage, airplane mode or rotation was induced. No release was pushed as part of this check.
