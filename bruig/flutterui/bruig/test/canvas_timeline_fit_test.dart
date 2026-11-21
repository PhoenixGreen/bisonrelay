import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/ui/screen/panel_heights.dart';

// The panels under the canvas are sized as one stack under the settings
// bar (panel_heights.dart). Fitted to a shorter window, the top ones give
// way first, each to its least. Resized, a panel made taller takes the free
// room and then the room of those over it, never pushing them past the top:
// once the stack fills the room the top stays pinned under the bar.

void main() {
  group("fitted to the window", () {
    test("the top panels give way first", () {
      // Mixer, effects, timeline in 700: the mixer to its least, then the
      // effects.
      expect(fitPanels([400, 300, 200], [100, 200, 150], 700), [200, 300, 200]);
      expect(fitPanels([400, 300, 200], [100, 200, 150], 450), [100, 200, 150]);
    });
  });

  group("resized", () {
    const least = [100.0, 200.0, 150.0];

    test("taller, into the free room, and never past the top", () {
      // 600 of 1000 used: the timeline takes the free 400 first, then what
      // the mixer has over its least -- the effects are at theirs.
      var out = resizePanel([200, 200, 200], least, 2, 600, 1000);
      expect(out, [200, 200, 600]);
      out = resizePanel([200, 200, 200], least, 2, 900, 1000);
      expect(out, [100, 200, 700]);
      expect(out.reduce((a, b) => a + b), lessThanOrEqualTo(1000));
    });

    test("filling the room, taller takes from the panels over it", () {
      // The effects nearest first, then the mixer, each to its least.
      var out = resizePanel([300, 400, 300], least, 2, 450, 1000);
      expect(out, [300, 250, 450]);
      out = resizePanel([300, 400, 300], least, 2, 900, 1000);
      expect(out, [100, 200, 700], reason: "as far as their least allows");
    });

    test("filling the room, shorter gives to the one over it: the top stays",
        () {
      var out = resizePanel([300, 400, 300], least, 2, 200, 1000);
      expect(out, [300, 500, 200]);
      expect(out.reduce((a, b) => a + b), 1000);
      // The effects' edge: the mixer over it takes the room.
      out = resizePanel([300, 400, 300], least, 1, 250, 1000);
      expect(out, [450, 250, 300]);
    });

    test("the top panel's own edge lets the stack come away from the top", () {
      var out = resizePanel([300, 400, 300], least, 0, 150, 1000);
      expect(out, [150, 400, 300]);
    });

    test("not filling the room, shorter is only shorter", () {
      var out = resizePanel([200, 300, 200], least, 2, 160, 1000);
      expect(out, [200, 300, 160]);
    });

    test("a fixed panel -- the keyframe bar -- neither gives nor takes", () {
      // Mixer, keyframe bar, timeline, filling 800.
      var out =
          resizePanel([400, 40, 360], [100, 40, 150], 2, 300, 800, fixed: {1});
      expect(out, [460, 40, 300], reason: "the mixer over the bar takes it");
      out =
          resizePanel([400, 40, 360], [100, 40, 150], 2, 500, 800, fixed: {1});
      expect(out, [260, 40, 500]);
    });

    test("never under its least", () {
      expect(resizePanel([300, 400, 300], least, 1, 50, 1000)[1], 200);
    });
  });
}
