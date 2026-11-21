import 'package:bruig/plugin_system/canvas/model/dock_layout.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_dock_state_test.dart is which panels under the canvas are open.
// The rule it holds: each place shows one panel at a time, so opening a
// panel shuts whatever shared its place.

void main() {
  const layout = DockLayout(); // Timeline and Chain in main, the rest left.

  test("to begin with, the Timeline is open and nothing else", () {
    const state = DockState();
    expect(state.open, {DockPanel.timeline});
    expect(state.shownIn(DockPlace.main, layout), DockPanel.timeline);
    expect(state.shownIn(DockPlace.left, layout), isNull);
  });

  test("opening a panel shuts the one that shared its place", () {
    var state = const DockState().opened(DockPanel.chain, layout);
    expect(state.open, {DockPanel.chain});
    state = state.opened(DockPanel.mixer, layout);
    expect(state.open, {DockPanel.chain, DockPanel.mixer});
    state = state.opened(DockPanel.slots, layout);
    expect(state.open, {DockPanel.chain, DockPanel.slots},
        reason: "the mixer and the slots share the left");
  });

  test("with one place, every panel shuts every other", () {
    const one = DockLayout(places: DockPlaces.one);
    var state = const DockState().opened(DockPanel.mixer, one);
    expect(state.open, {DockPanel.mixer});
  });

  test("a mixer shut is full size when it is next opened", () {
    var state = const DockState().withMixer(MixerSize.smallest, layout);
    expect(state.isOpen(DockPanel.mixer), isTrue);
    expect(state.mixer, MixerSize.smallest);
    state = state.closed(DockPanel.mixer);
    expect(state.mixer, MixerSize.full);
    expect(state.opened(DockPanel.mixer, layout).mixer, MixerSize.full);
  });

  test("the Chain keeps its view while it is shut", () {
    var state = const DockState()
        .onView(ChainView.motion)
        .opened(DockPanel.chain, layout);
    expect(state.showsMotion, isTrue);
    expect(state.showsSound, isFalse);
    state = state.closed(DockPanel.chain);
    expect(state.showsMotion, isFalse);
    expect(state.opened(DockPanel.chain, layout).showsMotion, isTrue);
  });

  test("settled leaves the first panel in each place", () {
    var state = const DockState().showing({
      DockPanel.timeline,
      DockPanel.slots,
      DockPanel.mixer,
      DockPanel.chain
    });
    expect(state.settled(layout).open, {DockPanel.timeline, DockPanel.slots});
  });

  test("a panel moved elsewhere no longer shuts what it left", () {
    var three = const DockLayout(places: DockPlaces.three)
        .withHome(DockPanel.chain, DockPlace.above);
    var state = const DockState().opened(DockPanel.chain, three);
    expect(state.open, {DockPanel.timeline, DockPanel.chain});
    expect(state.shownIn(DockPlace.above, three), DockPanel.chain);
  });

  test("kept and read back as it was", () {
    var state = const DockState()
        .opened(DockPanel.chain, layout)
        .onView(ChainView.motion)
        .withMixer(MixerSize.minimised, layout);
    expect(DockState.fromJson(state.toJson(), layout), state);
    // Shut, the Chain still knows its view.
    var shut = state.closed(DockPanel.chain);
    expect(DockState.fromJson(shut.toJson(), layout).chain, ChainView.motion);
  });

  test("what an earlier build kept is read: no view named", () {
    var state = DockState.fromJson(
        {"mixer": "smallest", "rows": false, "animation": true}, layout);
    expect(state.open, {DockPanel.mixer, DockPanel.chain});
    expect(state.mixer, MixerSize.smallest);
    expect(state.chain, ChainView.motion);
    // Nothing kept: as it starts.
    expect(DockState.fromJson(const {}, layout), const DockState());
  });

  test("two panels kept open in one place are put right", () {
    var state = DockState.fromJson({"rows": true, "effects": true}, layout);
    expect(state.open, {DockPanel.timeline});
  });

  test("every panel has a home, and a layout with none moved uses it", () {
    for (var panel in DockPanel.values) {
      expect(layout.homeOf(panel), panel.home);
    }
    expect(layout.toJson()["homes"], isEmpty);
  });
}
