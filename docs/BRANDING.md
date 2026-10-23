# iProxy name and icon

The iOS display name is **iProxy**. This fork is based on **Mobile Phone Proxy by Matija Stepanic (@stepanic)**; see [credits](../CREDITS.md). The repository, Xcode project/target, bundle identifiers and callback scheme retain their existing technical names so the visual update can replace an existing installation.

## Icon asset

- File: [`AppIcon.png`](../ios/MobilePhoneProxy/Assets.xcassets/AppIcon.appiconset/AppIcon.png).
- Format: opaque PNG, 1024 × 1024, full square background. The system applies its corner mask.
- Meaning: a phone and two connection arrows in blue/cyan on a dark background.
- Created for this fork on 2026-10-23 using the built-in **imagegen** tool. The generated 1254 × 1254 artwork was mechanically resized to 1024 × 1024 with macOS `sips` for the asset catalog. No existing brand artwork was used as input.
- The asset is included under the repository's [MIT license](../LICENSE).

Generation prompt:

> Create a polished original iOS app icon for iProxy, a utility that shares an iPhone internet connection as a proxy. One centered bold connection symbol: a simple upright phone outline integrated with two opposing curved arrows, in luminous cyan and electric blue on a deep midnight-blue background with subtle depth. Clean, restrained, readable at small sizes. Deliver a single 1024x1024 square icon, edge-to-edge opaque background, square outer corners (iOS applies the corner mask). No text, no letters, no watermark, no mockup, no extra objects, no imitation of an existing brand.

XcodeGen selects `AppIcon` using `ASSETCATALOG_COMPILER_APPICON_NAME`; the asset catalog supplies the universal iOS image. See [Apple's app icon configuration guide](https://developer.apple.com/documentation/xcode/configuring-your-app-icon).

The change does not alter the proxy's network behavior. Rebuild and reinstall the app with the same signing identity and bundle identifier to update its display name and icon while retaining its app data.
