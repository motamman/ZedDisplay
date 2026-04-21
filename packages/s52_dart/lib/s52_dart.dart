/// S-52 chart symbology engine for S-57 electronic navigational charts.
///
/// Pure Dart, renderer-agnostic. Given an S-57 vector-tile feature
/// (attribute map + geometry type), the engine returns a list of typed
/// S-52 drawing instructions. Adapters in consuming applications
/// translate those instructions into concrete paint operations for
/// their renderer of choice (OpenLayers, MapLibre, flutter_map /
/// vector_map_tiles, CustomPainter, etc.).
///
/// Derived in structure from Freeboard-SK's S-57 TypeScript
/// implementation (Apache 2.0). See LICENSE-NOTICES.
library;

export 'src/color.dart';
export 'src/cs/depare01.dart';
export 'src/cs/depcnt02.dart';
export 'src/cs/lights05.dart';
export 'src/cs/obstrn04.dart';
export 'src/cs/procedures.dart';
export 'src/cs/quapos01.dart';
export 'src/cs/resare02.dart';
export 'src/cs/restrn01.dart';
export 'src/cs/slcons03.dart';
export 'src/cs/soundg02.dart';
export 'src/cs/topmar01.dart';
export 'src/cs/wrecks02.dart';
export 'src/engine.dart';
export 'src/enums.dart';
export 'src/feature.dart';
export 'src/instruction.dart';
export 'src/lookup.dart';
export 'src/options.dart';
export 'src/sprite.dart';
