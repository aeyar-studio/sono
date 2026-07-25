# Third party notices

Sono itself is MIT licensed (see `LICENSE`). It ships, bundles or downloads the
work below. Every one of these is attribution-only; none of them is copyleft.

---

## NVIDIA Parakeet TDT 0.6B v3

Speech recognition model.

- Source: <https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3>
- Copyright NVIDIA Corporation
- Licence: **CC BY 4.0**, <https://creativecommons.org/licenses/by/4.0/legalcode.en>

**Modified.** Sono does not ship the original weights. It downloads
`sono-parakeet-v3-int8`, which is this model **quantised to int8** and repackaged
for sherpa-onnx. CC BY 4.0 requires that modifications be stated, and this is
that statement. The unmodified original is at the source link above.

Downloaded on first launch rather than bundled, so the app stays small. See
`Sources/ModelDownloader.swift`.

---

## sherpa-onnx

Inference runtime for the speech model. Vendored as prebuilt dylibs under
`Vendor/sherpa`.

- Source: <https://github.com/k2-fsa/sherpa-onnx>
- Copyright (c) 2023 Xiaomi Corporation
- Licence: **Apache 2.0**, <https://www.apache.org/licenses/LICENSE-2.0>

## ONNX Runtime

Bundled as `libonnxruntime.dylib`, a dependency of sherpa-onnx.

- Source: <https://github.com/microsoft/onnxruntime>
- Copyright (c) Microsoft Corporation
- Licence: **MIT**

---

## Sparkle

Update framework. Resolved via Swift Package Manager, not vendored.

- Source: <https://github.com/sparkle-project/Sparkle>
- Licence: **MIT**

---

## Fonts

Both bundled under `Resources/Fonts`.

- **Plus Jakarta Sans**, <https://github.com/tokotype/PlusJakartaSans>
- **Fraunces**, <https://github.com/undercasetype/Fraunces>
- Licence: **SIL Open Font License 1.1**, <https://openfontlicense.org>

The OFL permits bundling in a commercial or free product. It forbids selling the
fonts on their own, which Sono does not do.

---

## Apple frameworks

FoundationModels, AVFoundation, AppKit, SwiftUI, Charts and the Accessibility
APIs are system frameworks, used under the Apple SDK terms. Nothing is
redistributed.
