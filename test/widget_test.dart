import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:microtask_stop_repro/main.dart';

void main() {
  testWidgets('AnimatedProgressBar toggle test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Verify animation widget is shown initially
    expect(find.byType(AnimatedProgressBar), findsOneWidget);
    expect(find.text('Hide Animation'), findsOneWidget);

    // Tap button to hide animation (triggers dispose)
    await tester.tap(find.text('Hide Animation'));
    await tester.pump();

    // Verify animation widget is hidden
    expect(find.byType(AnimatedProgressBar), findsNothing);
    expect(find.text('Show Animation'), findsOneWidget);
  });
}
