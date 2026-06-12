# Licensing Notice

The **source code** in this repository is MIT licensed (see LICENSE).

The **distributed app binary** bundles third-party components with their own
terms:

| Component | License |
|---|---|
| Kokoro-82M model weights (hexgrad) | Apache-2.0 |
| Supertonic model weights (Supertone) | MIT |
| sherpa-onnx runtime (k2-fsa) | Apache-2.0 |
| ONNX Runtime (Microsoft) | MIT |
| eSpeak NG phonemization (code + data) | **GPL-3.0** |

Because sherpa-onnx TTS builds incorporate eSpeak NG (GPL-3.0), the combined
**binary distribution** should be treated as subject to GPL-3.0 terms, even
though this project's own code is MIT. Practical effect for this repository:
everything is open source and freely redistributable; if you fork this into a
closed-source product, replace or remove the eSpeak NG-based components.
