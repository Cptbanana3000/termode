import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/main.dart';

void main() {
  testWidgets('Termode starts successfully with welcome banner', (
    WidgetTester tester,
  ) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const TermodeApp());

    // Verify that our app starts and displays the terminal title.
    expect(find.text('Termode'), findsOneWidget);

    // Verify welcome message is present
    expect(
      find.byWidgetPredicate(
        (widget) =>
            (widget is Text &&
                widget.data != null &&
                widget.data!.contains('Termode v0.43')) ||
            (widget is RichText &&
                widget.text.toPlainText().contains('Termode v0.43')),
      ),
      findsOneWidget,
    );
  });
}
