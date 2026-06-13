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
    final wps = result.waypoints;
    expect(wps.length, greaterThan(2));

    // The card samples SOG/COG/Wind/TWA from the *forward* waypoint (wp[i+1])
    // and Depth from wp[i]. TWA only renders on a sailing leg (twaDeg != null),
    // so pick a leg that actually exercises every asserted row rather than
    // assuming a fixed index (the fixture's index 1 is a motoring leg).
    final i = [
      for (var j = 1; j < wps.length - 1; j++) j
    ].firstWhere(
      (j) {
        final fwd = wps[j + 1];
        return fwd.twaDeg != null &&
            fwd.sogMs != null &&
            fwd.cogDeg != null &&
            fwd.windMs != null &&
            fwd.windDirDeg != null &&
            wps[j].depthM != null;
      },
      orElse: () => -1,
    );
    expect(i, greaterThan(0),
        reason: 'fixture has no sailing leg with full SOG/COG/Wind/TWA/Depth');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox(
            width: 360,
            child: WeatherRoutingItineraryCard(
              index: i,
              waypoint: wps[i],
              next: wps[i + 1],
              kind: legKindAt(wps, i),
              selected: false,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    // Head row: index + time (card renders the 1-based leg number).
    expect(find.text('${i + 1}.'), findsOneWidget);

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
