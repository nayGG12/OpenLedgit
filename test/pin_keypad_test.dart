import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_ledger/widgets/pin_keypad.dart';

void main() {
  testWidgets('PIN keypad tracks digits and submits without a text keyboard', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    String? completedPin;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PinKeypad(length: 4, onCompleted: (pin) => completedPin = pin),
        ),
      ),
    );

    expect(find.byType(TextField), findsNothing);
    expect(find.bySemanticsLabel('0 chiffre(s) sur 4'), findsOneWidget);

    await tester.tap(find.text('1'));
    await tester.pump();
    expect(find.bySemanticsLabel('1 chiffre(s) sur 4'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    expect(find.bySemanticsLabel('0 chiffre(s) sur 4'), findsOneWidget);

    for (final digit in ['2', '4', '6', '8']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }

    expect(completedPin, '2468');
    semantics.dispose();
  });
}
