import 'package:bruig/plugin_system/canvas/ui/data_editor_shell.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_data_editor_height_test.dart is how tall the box round a grid of
// data is.
//
// It was one height whatever was in it, so a table of a dozen rows was eight
// rows and a scrollbar -- inside a panel that scrolls, which makes the wheel
// do whichever of the two the pointer is over. It now grows with its rows,
// and the arithmetic for that has three inputs that pull against each other.

void main() {
  group("how tall the box is", () {
    test("it fits the rows it holds", () {
      expect(editorHeight(wanted: 400), 400);
    });

    test("a height left over from last time is a floor, not the answer", () {
      // One number is shared by every table and saved whenever anybody drags
      // the grip, so a height chosen for a three-row table was making a
      // twenty-row one scroll -- and the way to find out was to drag it,
      // which is the thing that had gone wrong.
      expect(editorHeight(stored: 132, wanted: 500), 500);
      expect(editorHeight(stored: 600, wanted: 300), 600,
          reason: "and a box dragged taller than its rows stays that tall");
    });

    test("a drag in this sitting is obeyed exactly", () {
      // Shorter as well as taller: somebody dragging it down is asking for a
      // small box, and growing back over their hands would be the drag
      // quietly not working.
      expect(editorHeight(dragged: 200, stored: 600, wanted: 900), 200);
      expect(editorHeight(dragged: 800, wanted: 200), 800);
    });

    test("and nothing to go on is the plain default", () {
      expect(editorHeight(), 132);
    });

    test("it stops somewhere, however many rows there are", () {
      // A thousand rows is not a box a sidebar can hold, and past the cap
      // scrolling is the only thing left.
      expect(editorHeight(wanted: 40000), lessThan(2000));
      expect(editorHeight(wanted: 40000), greaterThan(1000),
          reason: "but generous: eight rows and a scrollbar was the bug");
      expect(editorHeight(dragged: 5, wanted: 0), greaterThan(20),
          reason: "and never smaller than a row");
    });
  });
}
