# Contributing to Sono

Thanks for taking a look. This file covers the things that will otherwise cost
you an afternoon.

## Building

Requires Xcode 26+ and macOS 26+.

```bash
Scripts/fetch-sherpa.sh                        # 103 MB of sherpa-onnx libs, deliberately not in git
xcodebuild -downloadComponent MetalToolchain   # 704 MB, once per machine
xcodegen generate                              # Sono.xcodeproj is generated, not committed
xcodebuild -project Sono.xcodeproj -scheme Sono -configuration Debug \
  -skipMacroValidation build
```

Two of those lines exist because of MLX, which powers the local enhancement model.
It compiles **Metal kernels**, so the build dies with `cannot execute tool 'metal'`
until the Metal toolchain is installed, and Xcode does not fetch that on its own.
It also ships **Swift macros**, and Xcode refuses to run a package macro until it
has been trusted through a UI prompt that cannot appear in a terminal build, hence
`-skipMacroValidation`. Building inside Xcode shows that prompt once instead.

`Sono.xcodeproj` and `Info.plist` are **both generated from `project.yml`**. Edit
`project.yml`; anything you change in the other two is overwritten on the next
`xcodegen generate`, and neither is tracked in git.

## Running it

Open the built app directly:

```bash
open ~/Library/Developer/Xcode/DerivedData/Sono-*/Build/Products/Debug/Sono.app
```

**Do not use Xcode's ▶ Run button.** Sono's UI is a floating non-activating
`NSPanel`. When the debugger pauses the process the island freezes, permission
dialogs are orphaned behind it, and the process resists `SIGKILL` until you kill
its `debugserver` parent.

**Do not rebuild while a copy is running.** `xcodebuild` overwrites the dylibs
inside the app bundle, and the kernel kills any process whose mapped code changes
on disk. It surfaces as `SIGKILL (Code Signature Invalid)` with
`CODESIGNING / Invalid Page` in the crash report, which looks like a signing bug
and is not one. Quit Sono first.

On first launch it asks for **Microphone** and **Accessibility**, then downloads
the speech model once (~478 MB, checksum-verified). Accessibility is what lets it
paste into other apps; without it text goes to the clipboard instead.

## Tests

There is no CI and no test target. Each non-trivial component carries a
`selfTest()` that runs automatically at launch in Debug builds, from `init()` in
[`Sources/SonoApp.swift`](Sources/SonoApp.swift):

| Component | Covers |
|---|---|
| `Cleanup.selfTest()` | filler and stutter removal, list formatting preserved |
| `Metrics.selfTest()` | per-app grouping, ordering, entries without a bundle ID |
| `Injector.selfTest()` | clipboard save and restore, against a private pasteboard |
| `VoiceActivity.selfTest()` | silence trimming, soft speech kept, blips rejected |

If you add logic with a branch, a loop, or anything touching the clipboard, add
an assertion to the relevant `selfTest()`. If you break one, the app traps on
launch in Debug, which is the point.

## Conventions

- **No em dashes** in user-facing copy or in dictated output. Use a comma, a
  full stop, or brackets. See `542c8dd`.
- Match the surrounding code. Comments here explain *why*, not *what*.
- Keep `Cleanup` restricted to horizontal whitespace. Touching vertical
  whitespace flattens the lists the polish layer produces.

## Things that cannot change

These are compiled into copies of 1.0 already on people's machines:

- **`com.aeyar.Sono`** in `project.yml`. The bundle ID is the app's identity.
  Change it and every existing user's Microphone and Accessibility grants reset,
  Sparkle stops recognising its own updates, and their history moves.
- **The model URL** in [`Sources/ModelDownloader.swift`](Sources/ModelDownloader.swift).
  Point it elsewhere and existing installs fail their download.

## Privacy is a functional requirement

Sono makes exactly two kinds of network request, and neither carries audio or
text: the one-time model download, and Sparkle's daily version check
(`SUEnableSystemProfiling` is off, so it sends nothing identifying).

Please do not add analytics, telemetry, crash reporting or any usage ping. The
promise that nothing leaves the machine is the product. Usage is measured
server-side from requests the app already makes; see `Scripts/stats.sh`.

## Pull requests

Small and focused beats large and complete. Say what you changed and how you
checked it.

By contributing you agree your work is licensed under the MIT License, the same
terms as the rest of the project.
