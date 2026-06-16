import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:termode/main.dart';
import 'package:termode/widgets/blinking_cursor.dart';
import 'package:termode/services/terminal_session_service.dart';
import 'package:termode/services/settings_service.dart';
import 'package:termode/widgets/terminal_view.dart';

void main() {
  testWidgets('Terminal Cursor and Focus Hint behavior tests', (WidgetTester tester) async {
    final sessionService = TerminalSessionService();
    sessionService.clearMemoryStateForTesting();

    await tester.pumpWidget(const TermodeApp());
    await tester.pumpAndSettle();

    // 1. Verify in NORMAL mode (no blinking cursor, normal prompt present)
    expect(find.byType(BlinkingCursor), findsNothing);
    expect(
      find.byWidgetPredicate((widget) =>
        (widget is Text && widget.data != null && widget.data!.contains('user@termode')) ||
        (widget is RichText && widget.text.toPlainText().contains('user@termode'))
      ),
      findsAtLeast(1),
    );

    // 2. Switch to REAL PTY interaction mode
    sessionService.activeSession.isPtyInteractionActive = true;
    sessionService.activeSession.isRealPtyActive = true;
    sessionService.notifyListeners();

    await tester.pumpAndSettle();

    // Unfocused and empty -> should display focus hint, no cursor
    final tapToTypeFinder = find.byWidgetPredicate((widget) =>
      (widget is Text && widget.data == 'Tap terminal to type') ||
      (widget is RichText && widget.text.toPlainText().contains('Tap terminal to type'))
    );
    expect(tapToTypeFinder, findsAtLeast(1));
    expect(find.byType(BlinkingCursor), findsOneWidget);

    // 3. Tap terminal view canvas to request focus
    await tester.tap(find.byType(TerminalView));
    await tester.pump(const Duration(milliseconds: 100));

    // Focused -> should display BlinkingCursor, and focus hint should hide
    expect(find.byType(BlinkingCursor), findsOneWidget);
    expect(tapToTypeFinder, findsNothing);

    // 4. Update Settings - cursor style and verify change
    final settings = SettingsService();
    settings.setCursorStyle('underline');
    await tester.pump();

    var cursorWidget = tester.widget<BlinkingCursor>(find.byType(BlinkingCursor));
    expect(cursorWidget.style, equals('underline'));

    settings.setCursorStyle('bar');
    await tester.pump();

    cursorWidget = tester.widget<BlinkingCursor>(find.byType(BlinkingCursor));
    expect(cursorWidget.style, equals('bar'));
  });
}
