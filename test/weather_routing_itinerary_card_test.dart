import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zed_display/models/weather_route_result.dart';
import 'package:zed_display/widgets/chart_plotter/weather_routing_itinerary_card.dart';
import 'package:zed_display/widgets/chart_plotter/weather_routing_overlay.dart';

void main() {
  testWidgets('Itinerary card renders expected fields from real result',
      (WidgetTester tester) async {
    final file = File('test/fixtures/interactive_route.geojson');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final result = WeatherRouteResult.fromGeoJson(json);
    expect(result.waypoints.length, greaterThan(1));
    final wp = result.waypoints[1]; // a sailing waypoint
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox(
            width: 360,
            child: WeatherRoutingItineraryCard(
              index: 1,
              waypoint: wp,
              kind: legKindAt(result.waypoints, 1),
              selected: false,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    // Head row: index + time
    expect(find.text('2.'), findsOneWidget);

    // Text fields in the grid are rendered via RichText (key label + value
    // span in one RichText each). Scan the plain-text projections.
    final richTexts = find
        .byType(RichText)
        .evaluate()
        .map((e) => (e.widget as RichText).text.toPlainText())
        .toList();
    expect(richTexts.any((t) => t.startsWith('SOG')), isTrue,
        reason: 'SOG row missing: $richTexts');
    expect(richTexts.any((t) => t.startsWith('COG')), isTrue,
        reason: 'COG row missing: $richTexts');
    expect(richTexts.any((t) => t.startsWith('Wind')), isTrue,
        reason: 'Wind row missing: $richTexts');
    expect(richTexts.any((t) => t.startsWith('TWA')), isTrue,
        reason: 'TWA row missing: $richTexts');
    expect(richTexts.any((t) => t.startsWith('Depth')), isTrue,
        reason: 'Depth row missing: $richTexts');
  });
}
