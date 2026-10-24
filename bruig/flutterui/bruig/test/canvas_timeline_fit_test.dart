import 'package:bruig/plugin_system/canvas/ui/canvas_screen.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

// A timeline sized tall in a big window, the window then made short: the
// page's column ran out of room and overflowed at the bottom. The timeline
// now gives way to the canvas, and comes back when there is room.

void main() {
  const top = 48.0;
  test("as set, where there is room", () {
    expect(timelineShownIn(1000, top, 300), 300);
  });

  test("as much as fits round the canvas, where its least does", () {
    var room = top + canvasLeast + timelineHeight + 40;
    expect(timelineShownIn(room, top, 500), timelineHeight + 40);
  });

  test("only the play bar, where not even its least fits", () {
    expect(timelineShownIn(top + canvasLeast + 20, top, 500),
        timelineCollapsedHeight);
  });

  test("shut to its bar, it stays its bar", () {
    expect(timelineShownIn(1000, top, timelineCollapsedHeight),
        timelineCollapsedHeight);
  });

  test("the overflow reported: a 587 point page", () {
    var shown = timelineShownIn(586.7, top, 586.7 * 0.6);
    expect(top + canvasLeast + shown, lessThanOrEqualTo(586.7));
  });
}
