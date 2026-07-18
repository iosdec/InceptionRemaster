# Somnia

> A reactive-audio **dream engine** for iOS. It reads your surroundings — motion,
> sound, light, weather, location — and plays generative soundscapes that respond
> to what you're doing and where you are.

Somnia is a modern reimplementation of the reactive-audio idea pioneered by RjDj:
scenes are living patches, not fixed tracks. Press **induce** and the engine picks
a scene to match your moment; move, fall quiet, travel, or wait for nightfall and
the scene shifts with you. With headphones, some scenes fold your own voice back
into the mix, transformed.

**This is an independent, unofficial project.** It is not affiliated with,
endorsed by, or connected to Warner Bros., RjDj / Reality Jockey, Hans Zimmer, or
any rights holder of the works it can play.

---

## Bring your own scenes

**Somnia ships with no audio, no artwork, and no scenes.** None of that content is
ours to distribute, so the repository and the built app contain zero bytes of it.

Instead, Somnia is an **engine** — like a console emulator that plays cartridges it
doesn't include. On first launch it asks you to import a copy of the original app
package (`.ipa`) that **you already own**. It extracts the scenes and interface
assets from *your* copy into the app's private storage and runs them. Nothing is
uploaded, shared, or redistributed; the extracted files never leave your device.

If you don't own the original, Somnia still runs — you just won't have scenes to
play until you supply your own RjDj-format scene bundles.

> **You are responsible for the content you import.** Only import material you are
> legally entitled to use. Importing does not grant you any rights you didn't
> already have.

---

## How it works

- **Sensors** → an `EnvironmentState` (acceleration, room loudness, GPS speed and
  location, time, moon phase, weather, and — with an Apple Watch — heart rate/HRV).
- **Rules** map that state to a scene: airport, sunshine, full moon, travelling,
  stillness, quiet, and so on. Induce, and the best match plays.
- **Live morphing**: while a scene is playing the engine keeps watching. Start
  moving and a stillness scene cross-fades into an active one — no reload.
- **Collapse**: each scene has an exit condition; when it no longer fits, the
  scene ends and you wake.
- **Voice augmentation** (headphones only): scenes whose original patches process
  the microphone route your voice through pitch/delay/reverb back into your ears.

Scenes are standard RjDj-format bundles (a zipped `.rj` folder of audio samples +
Pure Data patches). Somnia plays the samples through its own Swift audio graph; it
does not run the Pd patches.

---

## Building

Somnia uses [Tuist](https://tuist.io) to generate the Xcode project, so no
`.xcodeproj` is committed (that's where personal Team IDs and signing settings
would otherwise live).

```sh
tuist generate      # produces Somnia.xcodeproj locally
open Somnia.xcworkspace
```

Signing is yours to set: copy `Local.xcconfig.example` to `Local.xcconfig` and
fill in your own development team and bundle identifier. `Local.xcconfig` is
git-ignored and never committed.

Requirements: Xcode 26+, iOS 26+ device (Simulator works, but sensors, the mic
voice effect, and background audio need real hardware).

### WeatherKit (optional)

The Sunshine dream uses WeatherKit to know if it's clear and sunny. WeatherKit
needs a **paid** Apple Developer account and the **WeatherKit capability enabled
on your App ID** — it's tied to the exact bundle identifier you build with:

1. At [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list),
   open (or create) the App ID matching your `PRODUCT_BUNDLE_IDENTIFIER` and
   enable **WeatherKit**.
2. Allow up to ~30 minutes for Apple's servers to propagate, then let Xcode
   regenerate your provisioning profile and rebuild.

Without it you'll see a one-line "WeatherKit unavailable" log and the app carries
on as normal — only weather-driven dreams (Sunshine) won't trigger. Everything
else works.

---

## License

The Somnia **source code** is released under the MIT License — see
[LICENSE](LICENSE).

The MIT license covers **only this project's own code**. It grants no rights to any
third-party content you import (audio, artwork, scene patches, trademarks). Those
remain the property of their respective owners. See [NOTICE.md](NOTICE.md).
