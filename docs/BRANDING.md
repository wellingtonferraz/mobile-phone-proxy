# MyProxy name and icon

The iOS display name is **MyProxy**. This fork is based on **Mobile Phone Proxy by Matija Stepanic (@stepanic)**; see [credits](../CREDITS.md). The repository, Xcode project/target, bundle identifiers and callback scheme retain their existing technical names so the visual update can replace an existing installation.

## Icon asset

- File: [`AppIcon.png`](../ios/MobilePhoneProxy/Assets.xcassets/AppIcon.appiconset/AppIcon.png).
- Format: opaque PNG, 1024 × 1024, full square background. The system applies its corner mask.
- Mascot: **Polvo Hub**, a friendly pixel-art octopus with connection nodes on its tentacles and a Wi-Fi signal above its head.
- Palette: warm ivory, lavender and lime green on dark eggplant purple, selected from the Coelho Link concept.
- Created for this fork on 2026-10-23 using the built-in **imagegen** tool. The edit combined two original generated concepts: Polvo Hub for the character and Coelho Link for colors. No third-party brand artwork was used as input. The generated 1254 × 1254 artwork was mechanically resized with macOS `sips` to 1024 × 1024 for the asset catalog.
- The asset is included under the repository's [MIT license](../LICENSE).

Final edit prompt:

> Use case: precise-object-edit. Asset: final MyProxy iOS app icon. Image 1 is the edit target, Polvo Hub: retain this exact cute octopus character, symmetrical composition, big expressive eyes, happy open mouth, four curled tentacles with square connection nodes, chunky stair-step pixel-art silhouette. Image 2 is ONLY a color palette and Wi-Fi-symbol reference, Coelho Link: use its warm ivory/cream main body, lavender/lilac shading, lime-green accents and very dark eggplant-purple background. Recolor the octopus accordingly: ivory head/body with lavender pixel shading and tentacles, lime-green highlights in the eyes and in the four connection nodes. Add a clearly recognizable lime-green pixelated Wi-Fi signal centered just above the octopus's head, two stepped arcs and a square dot, integrated with a small visible gap. Allow space above the head by scaling down the octopus modestly while preserving original proportions and facial expression. Full opaque square dark eggplant background, no pre-rounded outer corners. Crisp retro pixel art with visibly chunky square pixels; keep details legible at small app-icon sizes. Do not include any rabbit ears, rabbit features, extra characters, text, lettering, watermark or mockup. Preserve original octopus design rather than inventing a new mascot.

XcodeGen selects `AppIcon` using `ASSETCATALOG_COMPILER_APPICON_NAME`; the asset catalog supplies the universal iOS image. See [Apple's app icon configuration guide](https://developer.apple.com/documentation/xcode/configuring-your-app-icon).

The change does not alter the proxy's network behavior. Rebuild and reinstall the app with the same signing identity and bundle identifier to update its display name and icon while retaining its app data.
