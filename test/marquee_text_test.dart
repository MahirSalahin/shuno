import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuno/widgets/marquee_text.dart';

void main() {
  group('MarqueeText Widget', () {
    testWidgets('renders short non-overflowing text statically without marquee scroll', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: MarqueeText(
                text: 'Short Title',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Short Title'), findsOneWidget);
      // When not overflowing, no horizontal scroll view is created
      expect(find.byType(SingleChildScrollView), findsNothing);
    });

    testWidgets('renders overflowing long text with ShaderMask and scrollable marquee', (
      tester,
    ) async {
      const longTitle =
          'This is an exceptionally long track title that is guaranteed to overflow a narrow constraint';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 120,
              child: MarqueeText(
                text: longTitle,
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ShaderMask), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.text(longTitle), findsOneWidget);

      // Advance clock past pauseDuration (1600ms) to trigger smooth scroll
      await tester.pump(const Duration(milliseconds: 1700));
      await tester.pump(const Duration(milliseconds: 1000));

      // Advance clock to complete forward animation and return
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('gracefully updates text and resets position when widget properties change', (
      tester,
    ) async {
      const titleA = 'Very long title A that definitely overflows and begins marquee';
      const titleB = 'Short B';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 100,
              child: MarqueeText(text: titleA),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(titleA), findsOneWidget);

      // Change text to titleB
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 100,
              child: MarqueeText(text: titleB),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(titleB), findsOneWidget);
    });
  });
}

