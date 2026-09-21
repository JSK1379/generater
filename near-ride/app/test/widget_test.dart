import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:near_ride/features/ble/ble.dart';

void main() {
  testWidgets('BLE screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: BleScanBody()));
    expect(find.byType(BleScanBody), findsOneWidget);
  });
}
