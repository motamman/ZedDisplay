import 'package:flutter/material.dart';

/// Shared AIS ship type utilities — single source of truth for label, color,
/// and icon across all widgets (chart plotter, AIS polar chart, etc.).

/// Decode AIS ship type integer to human-readable label.
String shipTypeLabel(int? type) {
  if (type == null) return 'Unknown';
  if (type >= 20 && type <= 29) return 'Wing in Ground';
  if (type == 30) return 'Fishing';
  if (type == 31 || type == 32) return 'Towing';
  if (type == 33) return 'Dredging';
  if (type == 34) return 'Diving ops';
  if (type == 35) return 'Military';
  if (type == 36) return 'Sailing';
  if (type == 37) return 'Pleasure craft';
  if (type >= 40 && type <= 49) return 'High speed craft';
  if (type == 50) return 'Pilot vessel';
  if (type == 51) return 'SAR';
  if (type == 52) return 'Tug';
  if (type == 53) return 'Port tender';
  if (type == 55) return 'Law enforcement';
  if (type >= 60 && type <= 69) return 'Passenger';
  if (type >= 70 && type <= 79) return 'Cargo';
  if (type >= 80 && type <= 89) return 'Tanker';
  return 'Other ($type)';
}

/// Get vessel type color based on AIS ship type code (MarineTraffic convention).
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
