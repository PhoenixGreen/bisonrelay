import 'package:bruig/plugin_system/canvas/model/audio_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/model/motion_presets.dart';
import 'package:bruig/plugin_system/canvas/model/session.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_audio_fake.dart';

// canvas_slot_cues_test.dart is per-canvas cues (Ken, 2026-11-10: "when you move
// to a scene like whispering wood, you start to get some strange overlaps
// ... most scenes use the title and woods cues even though we're on a
// different scene"). A game's master has the cues of the channels every
// scene shares -- its music -- and each scene its own, for its own
// channels and elements: each launched, named, added and taken away apart.

/// shape is an element with clip [clip] in its first slot.
ShapeElement shape(String id, String clip) {
  var c = presetNamed("Fade up")!.clip(clip);
  return ShapeElement(ElementBase(
      id: id,
      width: 100,
      height: 40,
      motion: ElementMotion.none.withClip(c).inSlot(0, clip)));
}

AudioElement keys() => AudioElement(const ElementBase(id: "keys", name: "Keys"),
    clip: const MediaClip(timed: true),
    instrument: const InstrumentPart(notes: [MidiNote(60, 0, 0.5)]));

/// game is a master with the music (a MIDI channel, its first cue "Title")
/// and an element of its own, and a scene with an element whose first slot
/// is its own.
CanvasDocument game() => CanvasDocument(
      frameRate: 30,
      audio: const AudioSettings(tempo: 120),
      game: true,
      masterOn: true,
      master: CanvasScene(
          id: "master", elements: [keys(), shape("hud", "hudFade")]),
      scenes: [
        CanvasScene(id: "dawn", frames: 60, elements: [shape("title", "drop")]),
      ],
    ).copyWith(
        session: const SessionGrid(scenes: ["Title", "Woods"]).put(
            "keys",
            0,
            const SessionClip(
                id: "k0", midi: true, notes: [MidiNote(60, 0, 1)], bars: 1)));

void main() {
  test("a scene's cues are its own: named by number until it names them", () {
    var c = CanvasController(game(), audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    expect(c.cuesApart, isTrue);
    expect(c.cueName(0), "1", reason: "the scene's own, not the master's");
    expect(c.cueName(0, master: true), "Title");
    c.renameClipScene(0, "Sunrise");
    expect(c.cueName(0), "Sunrise");
    expect(c.cueName(0, master: true), "Title", reason: "the master's kept");
    expect(c.document.scene.cues?.first, "Sunrise");
  });

  test("a scene's cue launches the scene's; the master's, the master's", () {
    var c = CanvasController(game(), audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    c.launchCue(0);
    expect(c.motionPlayer.isPlaying("title"), isTrue,
        reason: "the scene's element");
    expect(c.motionPlayer.isPlaying("hud"), isFalse,
        reason: "not the master's");
    expect(c.clipState("keys", 0), ClipState.stopped,
        reason: "nor the master's music");
    expect(c.cueLaunched(), 0);
    expect(c.cueLaunched(master: true), isNull);
    c.launchCue(0, master: true);
    expect(c.clipState("keys", 0), isIn([ClipState.queued, ClipState.playing]),
        reason: "the master's music");
    expect(c.motionPlayer.isPlaying("hud"), isTrue);
    expect(c.cueLaunched(master: true), 0);
  });

  test("a cue added or taken away moves its own canvas's slots alone", () {
    var c = CanvasController(game(), audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    // A row put in above the scene's first: its element's clip moves down,
    // the master's music stays where it is.
    c.addClipScene(after: -1);
    expect(c.document.elementById("title")!.base.motion.slot(1)?.id, "drop");
    expect(c.session.at("keys", 0)?.id, "k0");
    expect(c.cueName(0, master: true), "Title");
    // And taken away: back.
    c.removeClipScene(0);
    expect(c.document.elementById("title")!.base.motion.slot(0)?.id, "drop");
    // The master's first taken away: its music goes, the scene's stays.
    c.removeClipScene(0, master: true);
    expect(c.session.at("keys", 0), isNull);
    expect(c.cueName(0, master: true), "Woods");
    expect(c.document.elementById("title")!.base.motion.slot(0)?.id, "drop");
    expect(c.session.rows, greaterThanOrEqualTo(1));
  });

  test("with no master of slots, the canvas has the document's cues", () {
    var c = CanvasController(
        CanvasDocument(scenes: [
          CanvasScene(id: "a", frames: 60, elements: [shape("x", "xFade")]),
        ]).copyWith(session: const SessionGrid(scenes: ["Verse", "Chorus"])),
        audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    expect(c.cuesApart, isFalse);
    expect(c.cueName(0), "Verse", reason: "as it always had");
    c.renameClipScene(0, "Intro");
    expect(c.session.scenes.first, "Intro");
  });
}
