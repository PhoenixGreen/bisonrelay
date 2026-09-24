import 'package:bruig/components/chat/input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// chat_composer_height_test.dart is the message field not eating the screen.
//
// The field grows with what is typed, which is right for the three or four
// lines a message usually is. Pasted a page of text into it, it grew to a
// page: the conversation was squeezed out above it and Flutter drew its
// overflow stripe across the bottom -- reported as "BOTTOM OVERFLOWED BY 84
// PIXELS" on a long paste.

void main() {
  group("how tall the composer may grow", () {
    test("a quarter of the window", () {
      expect(composerMaxHeight(1200), 300);
      expect(composerMaxHeight(800), 200);
    });

    test("and a floor under it, for a window with no room in it", () {
      // A quarter of 200 is 50, which is less than one line of text: a field
      // that cannot show what is being typed into it is worse than one that
      // takes a little more of a small window than its share.
      expect(composerMaxHeight(200), 96);
    });
  });

  testWidgets("a field that grows stops at the cap and scrolls inside it",
      (tester) async {
    // The arrangement the composer uses: a field with no line limit, inside
    // the cap, on a row. Without the cap this lays out taller than the
    // window it is in, which is the overflow.
    const window = Size(600, 800);
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var controller = TextEditingController(
        text: List.generate(80, (i) => "Line $i of a pasted essay").join("\n"));
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Row(children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: composerMaxHeight(window.height)),
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: null,
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: "nothing overflowed");
    expect(tester.getSize(find.byType(TextField)).height,
        lessThanOrEqualTo(composerMaxHeight(window.height)));
  });
}
