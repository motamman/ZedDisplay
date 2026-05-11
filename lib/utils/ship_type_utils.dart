import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Shared AIS ship type utilities — single source of truth for label,
/// color, and icon across all widgets (chart plotter, AIS polar
/// chart, etc.).
///
/// Ship type codes are the **Type of Ship and Cargo Type** field in
/// AIS Message Types 5 (Class A) and 24 (Class B), defined by
/// **ITU-R M.1371-5 Annex 8, Table 53**. The field is a single byte
/// holding values 0–99; the tens digit groups vessels into broad
/// categories and the ones digit carries a hazardous-cargo
/// indicator on certain categories. The full canonical mapping
/// lives in `assets/ais/ship_types.json` — see that file for the
/// reference table. Loading is one-shot per app launch: call
/// [ensureShipTypesLoaded] in `main()` before `runApp` so the
/// synchronous [shipTypeLabel] never returns a placeholder.
///
/// **DG/HS/MP categories**: Dangerous Goods / Harmful Substances /
/// Marine Pollutants. The IMO sorts them into four severity bands —
/// A (most severe; IMDG class 1 explosives, class 2.1 flammable
/// gases, class 7 radioactives) through D (recognisable hazards /
/// marine pollutants). The asset labels render the category as the
/// parenthetical suffix `(Haz A)` through `(Haz D)`.

/// Asset-loaded label map. `null` until [ensureShipTypesLoaded]
/// resolves; after that, every [shipTypeLabel] call reads from
/// here.
Map<int, String>? _labels;

/// Future returned by an in-flight load so concurrent first calls
/// don't fight for the rootBundle.
Future<void>? _loadFuture;

/// Read `assets/ais/ship_types.json` into [_labels]. Idempotent;
/// safe to call multiple times — the in-flight Future is shared
/// across concurrent callers and short-circuits once the map is
/// populated. Wire from `main()` ahead of `runApp` so the first
/// frame already has labels available.
Future<void> ensureShipTypesLoaded() {
  if (_labels != null) return Future.value();
  return _loadFuture ??= _loadShipTypes();
}

Future<void> _loadShipTypes() async {
  try {
    final raw = await rootBundle.loadString('assets/ais/ship_types.json');
    final json = jsonDecode(raw);
    if (json is! Map<String, dynamic>) {
      _labels = const <int, String>{};
      return;
    }
    final parsed = <int, String>{};
    for (final entry in json.entries) {
      if (entry.key.startsWith('_')) continue; // doc / comment keys
      final code = int.tryParse(entry.key);
      if (code == null) continue;
      final value = entry.value;
      if (value is String) parsed[code] = value;
    }
    _labels = parsed;
  } catch (_) {
    // Asset bundle errors shouldn't crash the app — leave the map
    // empty so `shipTypeLabel` falls back to "Type $code".
    _labels = const <int, String>{};
  } finally {
    _loadFuture = null;
  }
}

/// Decode an AIS ship-type integer to a concise human-readable
/// label suitable for list rows and chips. Synchronous — reads
/// from the asset-backed table populated by [ensureShipTypesLoaded].
/// Returns `'Unknown'` for null; `'Type $type'` if the loader
/// hasn't run yet or if the code isn't in the table.
String shipTypeLabel(int? type) {
  if (type == null) return 'Unknown';
  final labels = _labels;
  if (labels == null) return 'Type $type';
  return labels[type] ?? 'Type $type';
}

/// Get vessel type color based on AIS ship type code (MarineTraffic
/// convention — broad-category colouring with sailing pulled out as
/// a distinct purple). Colour mapping is intentionally kept in code
/// rather than the JSON asset because it's a Flutter `Color` value,
/// not a string — the asset would only end up storing hex strings
/// that this function would have to re-parse anyway.
Color shipTypeColor(int? type, {String? aisClass}) {
  if (type == null) {
    return aisClass == 'A' ? Colors.grey.shade400 : Colors.grey;
  }
  if (type == 36) return Colors.purple; // Sailing
  switch (type ~/ 10) {
    case 1:
    case 2:
      return Colors.cyan; // Fishing, towing
    case 3:
      return Colors.amber; // Special craft (SAR, tug, pilot)
    case 4:
    case 5:
      return Colors.teal; // High-speed craft, special
    case 6:
      return Colors.blue; // Passenger
    case 7:
      return Colors.green.shade700; // Cargo
    case 8:
      return Colors.brown; // Tanker
    default:
      return Colors.grey;
  }
}

/// Get vessel type hex color string for JS bridge (same mapping as [shipTypeColor]).
String shipTypeHex(int? type, {String? aisClass}) {
  if (type == null) return aisClass == 'A' ? '#bdbdbd' : '#9e9e9e';
  if (type == 36) return '#9c27b0'; // Sailing / purple
  switch (type ~/ 10) {
    case 1:
    case 2:
      return '#00bcd4'; // Fishing, towing / cyan
    case 3:
      return '#ffc107'; // Special craft / amber
    case 4:
    case 5:
      return '#009688'; // HSC / teal
    case 6:
      return '#2196f3'; // Passenger / blue
    case 7:
      return '#388e3c'; // Cargo / green
    case 8:
      return '#795548'; // Tanker / brown
    default:
      return '#9e9e9e'; // Grey
  }
}

/// Get vessel icon based on motion state (type is conveyed by color).
IconData shipTypeIcon(int? type, String? navState, {double? sogMs}) {
  if (navState == 'anchored') return Icons.anchor;
  if (navState == 'moored') return Icons.local_parking;
  if (sogMs != null && sogMs < 0.1) return Icons.circle;
  return Icons.navigation;
}
