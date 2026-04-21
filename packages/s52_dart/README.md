# s52_dart

Pure-Dart S-52 chart symbology engine for S-57 electronic navigational
charts. Renderer-agnostic — produces typed drawing instructions that a
consuming application translates into paint operations for any map
renderer.

## Status

Early port in progress. See `../../devdocs/s52-dart-port.md` for the
phase plan and progress tracking.

## Scope

- Parses S-57 feature attributes into typed form.
- Resolves the matching S-52 lookup row for a feature.
- Runs the conditional symbology (CS) procedures — LIGHTS05, OBSTRN04,
  WRECKS02, DEPCNT02, DEPARE01, TOPMAR01, SLCONS03, SOUNDG02.
- Emits a list of typed S-52 drawing instructions (SY, LS, LC, AC, AP,
  TX, TE).

## Non-scope

- This package does not render. Consumers translate instructions into
  paint operations for their target renderer.
- This package does not parse MVT tiles. Consumers provide feature
  objects (attributes + geometry type) to the engine.
- This package does not supply the sprite sheet, lookup tables, or
  colour tables. Consumers load those assets and hand them to the engine.

## Licence

MIT — see repository root. Derivative-work attribution to Freeboard-SK
(Apache 2.0) in `LICENSE-NOTICES`.
