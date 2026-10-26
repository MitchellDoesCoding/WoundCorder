# Vendored runtime

## MNN 3.5.0

- Source: https://github.com/alibaba/MNN/releases/tag/3.5.0
- Archive: `mnn_3.5.0_ios_armv82_cpu_metal_coreml.zip`
- SHA-256: `fd9b6c5769718286f07ff300897c72ff6511a1d2a25ef79b3b2f8b2b3313281a`
- License: `MNN-LICENSE.txt`

The published framework is a static arm64 iOS runtime. WoundCorder links it only for physical-device builds and uses a Simulator fallback for development.

## llama.cpp b11577 (vision-enabled iOS runtime)

- Source: https://github.com/ggml-org/llama.cpp/releases/tag/b11577
- Archive: llama-b11577-xcframework.zip
- SHA-256: 8b2af91c7a1ffe2b3635ed5241bc30f216e64fa6abc15a6f2cbd2ccaaf8813c0
- Included slice: ios-arm64/llama.framework (includes mtmd vision APIs)
- License: llama-LICENSE.txt
- The framework is linked and embedded only in physical-device builds. Simulator uses the bundled CNN.
- Qwen3.5-4B Q4_K_S plus F16 vision projector are downloaded from a pinned Hugging Face revision with per-file SHA-256 verification. The model weights are not bundled.

- Matching crash symbols: `llama.dSYM`, extracted from `ios-arm64/dSYMs/llama.dSYM` in the same verified release archive.
- Framework and dSYM UUID (arm64): `A9BEDCC8-6DA2-307E-970C-7B8AB2ED851F`.
- The native “Archive llama symbols” copy phase places the dSYM in Xcode's built-products directory so Xcode includes it in the archive's `dSYMs` directory, outside the app bundle. When replacing the runtime, replace its dSYM from the same build and verify both UUIDs with `xcrun dwarfdump --uuid`.
