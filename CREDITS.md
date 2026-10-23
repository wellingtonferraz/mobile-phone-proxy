# Credits and provenance

- **Original author:** Matija Stepanic — [@stepanic](https://github.com/stepanic).
- **Original project:** [stepanic/mobile-phone-proxy](https://github.com/stepanic/mobile-phone-proxy).
- **Base commit:** `23b009febe6038ff561d863b024359415310f99c`.
- **Fork maintainer/contributions:** [Wellington Ferraz](https://github.com/wellingtonferraz).
- **License:** [MIT](LICENSE); original copyright and permission notice preserved, with an additional notice for fork contributions.

The original author created the proxy implementation and the iOS/Android/Windows, relay, Shortcut-trigger and silent-audio foundations. This fork adds the iOS behavior and tooling listed in the README: persisted keepalive preference, local-only admission, connection guidance, bounded/redacted diagnostics, corrected connection counting, a manual rotation button with verified result states, portable USB tooling, tests and installation documentation.

The silent-audio mechanism and Shortcut-based airplane-mode approach originated upstream; they are not inventions of this fork. Historical upstream documents remain in the repository and Git history. They must not be interpreted as validation of this fork's current network policy or deployment.

No personal signing identity, device identifier, provisioning profile, operational account file or signed app is intentionally distributed with these contributions. The human-readable Shortcut is signed locally by each developer when needed.
