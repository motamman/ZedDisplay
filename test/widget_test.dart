import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zed_display/main.dart';

void main() {
  testWidgets('App launches with connection screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ZedDisplayApp());

    // Verify that the connection screen is displayed
    expect(find.text('Connect to SignalK'), findsOneWidget);
    expect(find.text('SignalK Display'), findsOneWidget);

    // Verify connection button exists
    expect(find.text('Connect'), findsOneWidget);
  });

  testWidgets('Server input field is present', (WidgetTester tester) async {
    await tester.pumpWidget(const ZedDisplayApp());

    // Verify the server input field exists
    expect(find.byType(TextFormField), findsOneWidget);
  });
}
