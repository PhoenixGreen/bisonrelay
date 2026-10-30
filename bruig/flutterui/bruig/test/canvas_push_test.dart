import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/media/midi_input.dart';
import 'package:bruig/plugin_system/canvas/media/push_surface.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/midi_effects.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_push_test.dart is Ableton Push as an instrument: its pads laid out
// in key or chromatically and lit to show it, its buttons, its encoders --
// Push 1, 2 and 3 -- per Ableton's Push 2 interface manual.

Uint8List m(List<int> bytes) => Uint8List.fromList(bytes);

void main() {
  group("which Push", () {
    test("is known by its name, and played on its User port", () {
      expect(isPush("Ableton Push 2 Live Port"), isTrue);
      expect(isPush("Keystation 49"), isFalse);
      expect(
          pushPort([
            "Ableton Push 2 Live Port",
            "Ableton Push 2 User Port",
            "Keystation 49",
          ]),
          "Ableton Push 2 User Port");
      expect(pushPort(["MIDIIN2 (Ableton Push 2)", "Ableton Push 2"]),
          "MIDIIN2 (Ableton Push 2)",
          reason: "Windows names its ports so");
      expect(pushPort(["Keystation 49"]), isNull);
    });

    test("the first Push is Akai's, the others Ableton's own", () {
      expect(PushModel.of("Ableton Push User Port"), PushModel.push1);
      expect(PushModel.of("Ableton Push 2 User Port"), PushModel.push2);
      expect(PushModel.of("Ableton Push 3 User Port"), PushModel.push2);
      // Each put in User mode by its own maker's message.
      expect(PushModel.push1.userMode.sublist(0, 2), [0xF0, 0x47]);
      expect(PushModel.push2.userMode,
          [0xF0, 0x00, 0x21, 0x1D, 0x01, 0x01, 0x0A, 0x01, 0xF7]);
    });
  });

  group("the pads", () {
    late List<Uint8List> sent;
    late PushSurface push;
    setUp(() {
      sent = [];
      push = PushSurface(send: sent.add);
    });

    test("in key: a row a fourth above the last, every pad in the scale", () {
      // C major from C2 at the bottom left.
      expect(push.keyOf(36), 36, reason: "C2");
      expect(push.keyOf(37), 38, reason: "D2: the next note of the scale");
      expect(push.keyOf(43), 48, reason: "the row's end: C3");
      expect(push.keyOf(44), 41, reason: "the row above starts a fourth up");
      push.octave = 1;
      expect(push.keyOf(36), 48);
    });

    test("chromatic: every semitone, a row five up", () {
      push.inKey = false;
      expect(push.keyOf(37), 37);
      expect(push.keyOf(44), 41);
    });

    test("they are lit: the root blue, the scale white, the rest dark", () {
      push.inKey = false;
      push.light();
      int colourSent(int pad) =>
          sent.lastWhere((d) => d[0] == 0x90 && d[1] == pad)[2];
      expect(colourSent(36), PushModel.push2.blue, reason: "C");
      expect(colourSent(38), PushModel.push2.white, reason: "D");
      expect(colourSent(37), PushModel.push2.grey, reason: "C sharp");
    });

    test("a pad played plays its key, lit green till let go", () {
      var played = <(int, int)>[];
      push.onNote = (k, v) => played.add((k, v));
      expect(push.handle(m([0x90, 37, 100])), isTrue);
      expect(sent.last, [0x90, 37, PushModel.push2.green]);
      // Moved up an octave while held: the let-go still stops what it
      // started.
      push.octave = 1;
      push.handle(m([0x80, 37, 0]));
      expect(played, [(38, 100), (38, 0)]);
    });

    test("they follow the channel's scale", () {
      push.setScale(9, scaleSteps[1]); // A minor
      expect(push.keyOf(36), 45);
      expect(push.keyOf(37), 47);
      expect(push.keyOf(38), 48, reason: "C: the minor third");
    });
  });

  // Session mode: the pads the clip slots, launched at their velocity.
  group("Session mode", () {
    late List<Uint8List> sent;
    late PushSurface push;
    var slots = <(int, int), PadClip>{};
    setUp(() {
      sent = [];
      slots = {(0, 0): PadClip.playing, (1, 0): PadClip.stopped};
      push = PushSurface(send: sent.add)
        ..clipAt = ((c, r) => slots[(c, r)] ?? PadClip.empty);
    });

    test("Session and Note switch the pads between slots and notes", () {
      expect(push.handle(m([0xB0, PushButton.session, 127])), isTrue);
      expect(push.session, isTrue);
      // The top row is the first row of slots: pads 92 to 99.
      expect(push.slotOf(92), (0, 0));
      expect(push.slotOf(36), (0, 7));
      expect(push.colourOf(92), PushModel.push2.green, reason: "playing");
      expect(push.colourOf(93), PushModel.push2.white, reason: "a clip");
      expect(push.colourOf(94), PushModel.push2.off, reason: "empty");
      push.handle(m([0xB0, PushButton.note, 127]));
      expect(push.session, isFalse);
    });

    test("a pad presses its slot at its velocity, and lets it go", () {
      var pressed = <(int, int, int)>[];
      push
        ..session = true
        ..onClip = (c, r, v) => pressed.add((c, r, v));
      var played = <int>[];
      push.onNote = (k, v) => played.add(k);
      push.handle(m([0x90, 93, 90]));
      push.handle(m([0x80, 93, 0]));
      expect(pressed, [(1, 0, 90), (1, 0, 0)]);
      expect(played, isEmpty, reason: "no note played in Session mode");
    });

    test("only the pads that changed are lit again", () {
      push.handle(m([0xB0, PushButton.session, 127]));
      sent.clear();
      slots[(1, 0)] = PadClip.playing;
      push.refresh();
      expect(sent, [
        [0x90, 93, PushModel.push2.green]
      ]);
    });

    test("the octave buttons move the slots; left and right the channels", () {
      push.handle(m([0xB0, PushButton.session, 127]));
      push.handle(m([0xB0, PushButton.octaveDown, 127]));
      expect(push.slotOf(92), (0, 1));
      push.handle(m([0xB0, PushButton.right, 127]));
      expect(push.slotOf(92), (1, 1));
      push.handle(m([0xB0, PushButton.octaveUp, 127]));
      push.handle(m([0xB0, PushButton.left, 127]));
      expect(push.slotOf(92), (0, 0));
      expect(push.octave, 0, reason: "the notes' octave left alone");
    });
  });

  group("the buttons and encoders", () {
    late PushSurface push;
    setUp(() => push = PushSurface(send: (_) {}));

    test("octave, scale, play and record", () {
      var played = 0, recorded = 0;
      push.onPlay = () => played++;
      push.onRecord = () => recorded++;
      push.handle(m([0xB0, PushButton.octaveUp, 127]));
      push.handle(m([0xB0, PushButton.octaveUp, 0]));
      expect(push.octave, 1, reason: "on the press, not the let-go");
      push.handle(m([0xB0, PushButton.scale, 127]));
      expect(push.inKey, isFalse);
      push.handle(m([0xB0, PushButton.play, 127]));
      push.handle(m([0xB0, PushButton.record, 127]));
      expect((played, recorded), (1, 1));
    });

    test("the encoders turn the controllers, a step at a time", () {
      var got = <(MidiControl, double)>[];
      push.onControl = (c, v) => got.add((c, v));
      // The first encoder, volume: four steps down from its rest.
      push.handle(m([0xB0, 71, 0x7C]));
      expect(got.last.$1, MidiControl.volume);
      expect(got.last.$2, closeTo(MidiControl.volume.rest - 4 / 128, 1e-9));
      // The second, pan: one step right.
      push.handle(m([0xB0, 72, 0x01]));
      expect(got.last, (MidiControl.pan, 0.5 + 1 / 128));
    });

    test("the touch strip is the pitch bend, read as any keyboard's", () {
      var input = MidiInput()..usePush(PushSurface(send: (_) {}));
      var got = <(MidiControl, double)>[];
      input.onControl = (c, v) => got.add((c, v));
      input.handle(m([0xE0, 0x40, 0x7F])); // the strip at its top
      expect(got.single.$1, MidiControl.pitchBend);
      expect(got.single.$2, greaterThan(0.99));
    });

    test("through the MIDI input, a pad is a key", () {
      var input = MidiInput();
      var notes = <(int, int)>[];
      input.onNote = (k, v) => notes.add((k, v));
      var sent = <Uint8List>[];
      input.usePush(PushSurface(send: sent.add));
      expect(sent.first, PushModel.push2.userMode,
          reason: "put in User mode as it is taken");
      input.handle(m([0x90, 44, 90]));
      expect(notes, [(41, 90)]);
    });
  });
}
