import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_timeline_keys_test.dart is which stretches between keyframes have a
// bar (bandsIn): drawn on the Chain's Keyframes card, as they were on the
// timeline's keyframe row before keyframing moved to the Chain (Ken,
// 2026-11-09). Taking hold of the marks is canvas_keyframes_card_test.dart.

void main() {
  group("the bar between two marks", () {
    // What a reader takes it to mean is "something changes over this
    // stretch", so that is what it says: one bar for each stretch a counted
    // number moves over.
    ElementTrack counting(List<(int, double)> points) => ElementTrack([
          for (var (frame, value) in points)
            Keyframe(frame: frame, values: {KeyframeChannel.count: value}),
        ]);

    test("is drawn for every stretch the number changes over", () {
      var bands = bandsIn(counting([(0, 0), (10, 50), (20, 100)]));
      expect(bands, hasLength(2));
      expect([bands[0].from, bands[0].to], [0, 10]);
      expect([bands[1].from, bands[1].to], [10, 20]);
    });

    test("and not over a stretch that holds", () {
      // The bar says the number is *travelling* here, and a held one does
      // not travel: it stays as it is and steps at the far end.
      var track = ElementTrack([
        const Keyframe(
            frame: 0,
            easing: KeyframeEasing.hold,
            values: {KeyframeChannel.count: 0}),
        const Keyframe(frame: 12, values: {KeyframeChannel.count: 100}),
      ]);
      expect(bandsIn(track), isEmpty);
    });

    test("and it is the keyframe the stretch leaves that decides", () {
      // Ease, hold, ease, hold: a bar over the first stretch, none over the
      // second, a bar over the third.
      var track = ElementTrack([
        const Keyframe(
            frame: 0,
            easing: KeyframeEasing.easeIn,
            values: {KeyframeChannel.count: 0}),
        const Keyframe(
            frame: 10,
            easing: KeyframeEasing.hold,
            values: {KeyframeChannel.count: 25}),
        const Keyframe(
            frame: 20,
            easing: KeyframeEasing.easeIn,
            values: {KeyframeChannel.count: 50}),
        const Keyframe(
            frame: 30,
            easing: KeyframeEasing.hold,
            values: {KeyframeChannel.count: 75}),
      ]);
      var bands = bandsIn(track);
      expect([
        for (var b in bands) [b.from, b.to]
      ], [
        [0, 10],
        [20, 30],
      ]);
    });

    test("and not where the two ends read the same", () {
      // Nothing happens there, and a bar over it would be saying something
      // untrue.
      var bands = bandsIn(counting([(0, 40), (10, 40), (20, 90)]));
      expect(bands, hasLength(1));
      expect([bands.single.from, bands.single.to], [10, 20]);
    });

    test("is drawn between keyframes laid by hand, on any element", () {
      // It used to be drawn only for the two channels a preset lays down, so
      // a chart moved across the canvas by hand had four marks and nothing
      // between them.
      var track = ElementTrack(const [
        Keyframe(frame: 0, dx: 0),
        Keyframe(frame: 10, dx: 80),
        Keyframe(frame: 20, dx: 80, easing: KeyframeEasing.hold),
        Keyframe(frame: 30, dx: 200),
      ]);
      var bands = bandsIn(track);
      expect([
        for (var b in bands) [b.from, b.to]
      ], [
        [0, 10],
      ], reason: "10 to 20 says the same thing twice, and 20 holds");
    });

    test("and every kind of change counts as one", () {
      for (var (still, moved) in [
        (const Keyframe(frame: 0), const Keyframe(frame: 10, dy: 40)),
        (const Keyframe(frame: 0), const Keyframe(frame: 10, scale: 1.4)),
        (const Keyframe(frame: 0), const Keyframe(frame: 10, rotate: 90)),
        (const Keyframe(frame: 0), const Keyframe(frame: 10, opacity: 0.2)),
        (
          const Keyframe(frame: 0, values: {KeyframeChannel.slide: 0}),
          const Keyframe(frame: 10, values: {KeyframeChannel.slide: 0.5}),
        ),
      ]) {
        expect(bandsIn(ElementTrack([still, moved])), hasLength(1),
            reason: "$moved");
      }
    });

    test("but a channel only one of them pins is not a change", () {
      // A channel the other does not carry holds whatever was set before it,
      // so the end of a slide and the start of a bow have nothing happening
      // between them -- which is what they look like.
      var track = ElementTrack(const [
        Keyframe(frame: 0, values: {KeyframeChannel.slide: 0}),
        Keyframe(frame: 10, values: {KeyframeChannel.slide: 1}),
        Keyframe(frame: 30, values: {KeyframeChannel.bow: 0}),
        Keyframe(frame: 47, values: {KeyframeChannel.bow: 1}),
      ]);
      var bands = bandsIn(track);
      expect([
        for (var b in bands) [b.from, b.to]
      ], [
        [0, 10],
        [30, 47],
      ], reason: "the slide and the bow, and nothing in the gap");
    });
  });
}
