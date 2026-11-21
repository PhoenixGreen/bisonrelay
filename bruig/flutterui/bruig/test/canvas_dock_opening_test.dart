import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/dock_layout.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/canvas_audio_fake.dart';

// canvas_dock_opening_test.dart holds every way a panel under the canvas is
// opened to one rule: it shows, in place of whatever shared its place. With
// the panels as they start, the Timeline and the Chain share the main place.

const _sound = "0123456789abcdef0123456789abcdef";

/// _withClip is a session on a canvas with one sound channel, "a", and a
/// clip in its first slot.
CanvasController _withClip() {
  var c = CanvasController(
      CanvasDocument(
          frames: 120 * 60,
          frameRate: 120,
          audio: const AudioSettings(tempo: 120),
          elements: [
            AudioElement(const ElementBase(id: "a", name: "a"),
                clip: const MediaClip(playlist: [
                  MediaSource(assetId: _sound, name: "Loop", length: 16)
                ], timed: true)),
          ]),
      audioEngine: FakeEngine({_sound: 16}));
  c.setSessionClip(
      "a",
      0,
      const SessionClip(
          id: "one",
          name: "Beat",
          sound: MediaSource(assetId: _sound, name: "Loop", length: 16),
          bars: 1));
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("to begin with the Timeline has the main place", () {
    var c = _withClip();
    addTearDown(c.dispose);
    expect(c.dockShownIn(DockPlace.main), DockPanel.timeline);
  });

  test("a clip opened in its editor shows the Chain, not the Timeline", () {
    // The editor is in the Chain. Opened without shutting the Timeline that
    // shares its place, the Chain's button lit and the Timeline stayed.
    var c = _withClip();
    addTearDown(c.dispose);
    c.openClipEditor("a", 0);
    expect(c.dockShownIn(DockPlace.main), DockPanel.chain);
    expect(c.rowsShown, isFalse);
    expect(c.effectsOpen, isTrue);
  });

  for (var (name, open) in <(String, void Function(CanvasController))>[
    ("the effects", (c) => c.openEffects("a")),
    ("the pitch editor", (c) => c.showPitch("a")),
    ("the instrument editor", (c) => c.showInstrument("a")),
    ("Speech", (c) => c.showSpeech("a")),
    ("the Chain's motion", (c) => c.animationOpen = true),
    ("a scene's chain", (c) => c.pickScene(0)),
    ("the Chain's button", (c) => c.setDockOpen(DockPanel.chain, true)),
  ]) {
    test("$name opened shows the Chain in the Timeline's place", () {
      var c = _withClip();
      addTearDown(c.dispose);
      open(c);
      expect(c.dockShownIn(DockPlace.main), DockPanel.chain);
      expect(c.rowsShown, isFalse);
    });
  }

  test("the Chain reopens on the view it was last on", () {
    var c = _withClip();
    addTearDown(c.dispose);
    c.pickScene(0);
    expect(c.chainShowsMotion, isTrue);
    c.setDockOpen(DockPanel.chain, false);
    expect(c.dockOpen(DockPanel.chain), isFalse);
    // Nothing picked that says which: the last view.
    c.clearSelection();
    c.setDockOpen(DockPanel.chain, true);
    expect(c.chainShowsMotion, isTrue);
  });

  test("the mixer and the Slots share the left, the mixer's size its own", () {
    var c = _withClip();
    addTearDown(c.dispose);
    c.slotsBeside = true;
    c.mixerSize = MixerSize.minimised;
    expect(c.mixerOpen, isTrue, reason: "sizing it opens it");
    expect(c.slotsBeside, isFalse);
    expect(c.mixerMinimised, isTrue);
    expect(c.mixerSmallest, isFalse);
    c.mixerSize = MixerSize.smallest;
    expect(c.mixerMinimised, isTrue, reason: "smaller still is minimised too");
    expect(c.mixerSmallest, isTrue);
    c.mixerOpen = false;
    c.mixerOpen = true;
    expect(c.mixerSize, MixerSize.full);
  });

  test("which panels are open is kept and put back", () {
    var c = _withClip();
    addTearDown(c.dispose);
    c.pickScene(0);
    c.mixerSize = MixerSize.minimised;
    var kept = c.panelState;

    var next = _withClip();
    addTearDown(next.dispose);
    next.restorePanels(kept);
    expect(next.dockShownIn(DockPlace.main), DockPanel.chain);
    expect(next.chainShowsMotion, isTrue);
    expect(next.mixerMinimised, isTrue);
    expect(next.rowsShown, isFalse);
  });
}
