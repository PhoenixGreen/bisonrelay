import 'package:flutter/foundation.dart';

import 'package:bruig/plugin_system/canvas/model/instrument.dart'
    show MidiControl;
import 'package:bruig/plugin_system/canvas/model/midi_effects.dart'
    show scaleSteps;

// push_surface.dart is Ableton Push as an instrument: pads in key or
// chromatic, lit, octave and scale buttons, transport, touch strip as bend,
// encoders on the channel's controllers. Per the Push 2 MIDI manual (1.1):
// pads are notes 36 to 99, lit by echoing the note with a colour velocity;
// encoders are controllers 71-79, relative; it listens on its User port.
// Push 1 and 3 share the numbers (see PushModel). The display is left alone.

/// isPush is whether a MIDI device named [name] is a Push.
bool isPush(String name) => name.toLowerCase().contains("ableton push");

/// PushModel is which Push it is: the first (with Akai), or Ableton's
/// second or third. Played alike; lit and put in User mode differently.
enum PushModel {
  push1(
    userMode: [0xF0, 0x47, 0x7F, 0x15, 0x62, 0x00, 0x01, 0x01, 0xF7],
    off: 0,
    white: 3,
    grey: 1,
    blue: 45,
    green: 21,
    red: 5,
  ),
  push2(
    userMode: [0xF0, 0x00, 0x21, 0x1D, 0x01, 0x01, 0x0A, 0x01, 0xF7],
    off: 0,
    white: 122,
    grey: 124,
    blue: 125,
    green: 126,
    red: 127,
  );

  /// userMode is the message that puts it in User mode.
  final List<int> userMode;

  /// off, white, grey, blue, green and red are its palette's colours.
  final int off, white, grey, blue, green, red;

  const PushModel({
    required this.userMode,
    required this.off,
    required this.white,
    required this.grey,
    required this.blue,
    required this.green,
    required this.red,
  });

  /// of is the model a device named [name] is: Push 2 and 3 are Ableton's
  /// own, any other the first.
  static PushModel of(String name) {
    var n = name.toLowerCase();
    return n.contains("push 2") || n.contains("push 3") || n.contains("push2")
        ? push2
        : push1;
  }
}

/// pushPort is which of [names] to take: the Push's User port, where one is
/// named so.
String? pushPort(List<String> names) {
  var pushes = names.where(isPush).toList();
  if (pushes.isEmpty) return null;
  return pushes
          .where((n) =>
              n.toLowerCase().contains("user") ||
              n.toLowerCase().contains("port 2") ||
              n.toUpperCase().contains("MIDIIN2"))
          .firstOrNull ??
      pushes.first;
}

/// The buttons, by controller number.
abstract final class PushButton {
  static const play = 85;
  static const record = 86;
  static const octaveUp = 55;
  static const octaveDown = 54;
  static const scale = 58;
  static const layout = 31;
  static const shift = 49;
  static const left = 44;
  static const right = 45;
  static const note = 50;
  static const session = 51;
}

/// PadClip is a clip slot's state, for its pad's light.
enum PadClip { empty, stopped, playing, queued, recording }

/// pushEncoders are what the display encoders turn, left to right; the last
/// two turn nothing, and the master encoder turns volume too.
const pushEncoders = [
  MidiControl.volume,
  MidiControl.pan,
  MidiControl.expression,
  MidiControl.modulation,
  MidiControl.pitchBend,
  MidiControl.sustain,
];

/// PushSurface is a Push being played: its place in the layout, and what
/// it sends and is sent.
class PushSurface {
  /// send hands a message to the Push: a pad lit, a mode set.
  final void Function(Uint8List data) send;

  final PushModel model;

  /// onNote, onControl, onPlay and onRecord are what the Push asks for:
  /// keys, controllers, transport.
  void Function(int key, int velocity)? onNote;
  void Function(MidiControl control, double value)? onControl;
  void Function()? onPlay;
  void Function()? onRecord;

  /// session is whether the pads are clip slots (Session mode): eight
  /// channels across, eight rows down, offset by [sessionLeft], [sessionTop].
  bool session = false;
  int sessionLeft = 0, sessionTop = 0;

  /// onClip is a slot's pad pressed (at its velocity) or let go (nought);
  /// clipAt is a slot's state, to light its pad.
  void Function(int column, int row, int velocity)? onClip;
  PadClip Function(int column, int row)? clipAt;

  /// _shown is each pad's last light, so a refresh sends only changes.
  final Map<int, int> _shown = {};

  /// inKey is whether the pads are laid in the scale (every pad a note of
  /// it, each row a fourth up) or chromatically (each row five semitones).
  bool inKey = true;

  /// root and steps are the scale: its key, and its notes from it.
  int root = 0;
  List<int> steps = scaleSteps[0];

  /// octave is how far the layout is moved, in octaves, from C2 at the
  /// bottom left.
  int octave = 0;

  /// _down is each held pad and the key it played, so a let-go stops that
  /// key whatever has moved since.
  final Map<int, int> _down = {};

  /// _clipDown is each pad held in Session mode and its slot: let go, that
  /// slot is let go, whatever mode the Push is in by then.
  final Map<int, (int, int)> _clipDown = {};

  /// _values are where the encoders' controllers have been turned to.
  final Map<MidiControl, double> _values = {
    for (var c in MidiControl.values) c: c.rest,
  };

  PushSurface({required this.send, this.model = PushModel.push2});

  /// start puts the Push in User mode, where its User port is heard, and
  /// lights it.
  void start() {
    send(Uint8List.fromList(model.userMode));
    light();
  }

  /// keyOf is the key pad [pad] (36 to 99) plays.
  int? keyOf(int pad) {
    if (pad < 36 || pad > 99) return null;
    var row = (pad - 36) ~/ 8, col = (pad - 36) % 8;
    var base = 36 + 12 * octave + root;
    int key;
    if (inKey) {
      var degree = col + 3 * row;
      key = base + 12 * (degree ~/ steps.length) + steps[degree % steps.length];
    } else {
      key = base + col + 5 * row;
    }
    return key < 0 || key > 127 ? null : key;
  }

  /// slotOf is pad [pad]'s slot in Session mode: channel column and row,
  /// the top row of pads first.
  (int, int) slotOf(int pad) => (
        sessionLeft + (pad - 36) % 8,
        sessionTop + 7 - (pad - 36) ~/ 8,
      );

  /// colourOf is pad [pad]'s light: root blue, scale white, else dark, green
  /// while held. In Session mode: clip white, playing green, queued blue,
  /// recording red, empty dark.
  int colourOf(int pad) {
    if (session) {
      var (column, row) = slotOf(pad);
      return switch (clipAt?.call(column, row) ?? PadClip.empty) {
        PadClip.empty => model.off,
        PadClip.stopped => model.white,
        PadClip.playing => model.green,
        PadClip.queued => model.blue,
        PadClip.recording => model.red,
      };
    }
    if (_down.containsKey(pad)) return model.green;
    var key = keyOf(pad);
    if (key == null) return model.off;
    var rel = (key - root) % 12;
    if (rel == 0) return model.blue;
    return steps.contains(rel) ? model.white : model.grey;
  }

  /// light lights every pad, and the buttons it uses.
  void light() {
    for (var pad = 36; pad <= 99; pad++) {
      var colour = colourOf(pad);
      _shown[pad] = colour;
      send(Uint8List.fromList([0x90, pad, colour]));
    }
    for (var b in const [
      PushButton.octaveUp,
      PushButton.octaveDown,
      PushButton.scale,
      PushButton.play,
      PushButton.record,
      PushButton.note,
      PushButton.session,
      PushButton.left,
      PushButton.right,
    ]) {
      // The mode it is in, brighter than the other.
      var dim = (b == PushButton.session && !session) ||
          (b == PushButton.note && session);
      send(Uint8List.fromList([0xB0, b, dim ? 1 : 127]));
    }
  }

  /// refresh relights pads whose colour has changed, as slots launch and
  /// stop.
  void refresh() {
    for (var pad = 36; pad <= 99; pad++) {
      var colour = colourOf(pad);
      if (_shown[pad] == colour) continue;
      _shown[pad] = colour;
      send(Uint8List.fromList([0x90, pad, colour]));
    }
  }

  /// handle reads one message from the Push: true if it was the Push's own
  /// (a pad, button or encoder) and has been dealt with.
  bool handle(Uint8List data) {
    if (data.length < 3) return false;
    var kind = data[0] & 0xF0, a = data[1] & 0x7F, b = data[2] & 0x7F;
    if ((kind == 0x90 || kind == 0x80) && a >= 36 && a <= 99) {
      var on = kind == 0x90 && b > 0;
      // Let go as it was pressed, so a pad held across a Note/Session
      // switch does not leave a note ringing or a gate clip playing.
      if (!on) {
        if (_clipDown.remove(a) case (var column, var row)) {
          onClip?.call(column, row, 0);
        }
        if (_down.remove(a) case var key?) onNote?.call(key, 0);
        if (!session) send(Uint8List.fromList([0x90, a, colourOf(a)]));
        return true;
      }
      if (session) {
        var (column, row) = slotOf(a);
        _clipDown[a] = (column, row);
        onClip?.call(column, row, b);
        return true;
      }
      var key = keyOf(a);
      if (key == null) return true;
      _down[a] = key;
      onNote?.call(key, b);
      send(Uint8List.fromList([0x90, a, colourOf(a)]));
      return true;
    }
    // Encoder touches and the touch strip's touch: nothing to do.
    if ((kind == 0x90 || kind == 0x80) && a < 36) return true;
    if (kind != 0xB0) return false;
    if (a >= 71 && a <= 79) {
      var index = a == 79 ? 0 : a - 71;
      if (index >= pushEncoders.length) return true;
      var control = pushEncoders[index];
      // Relative (see the file comment); a step is 1/128 of the travel.
      var step = b < 64 ? b : b - 128;
      var value = (_values[control]! + step / 128).clamp(0.0, 1.0);
      _values[control] = value;
      onControl?.call(control, value);
      return true;
    }
    // Buttons: on their press, not their let-go.
    if (b == 0) {
      return const {
        PushButton.play,
        PushButton.record,
        PushButton.octaveUp,
        PushButton.octaveDown,
        PushButton.scale,
        PushButton.layout,
        PushButton.note,
        PushButton.session,
        PushButton.left,
        PushButton.right,
      }.contains(a);
    }
    switch (a) {
      case PushButton.play:
        onPlay?.call();
      case PushButton.record:
        onRecord?.call();
      case PushButton.session:
        session = true;
        light();
      case PushButton.note:
        session = false;
        light();
      // In Session mode the octave buttons move the slots up and down, and
      // left and right the channels.
      case PushButton.octaveUp when session:
        if (sessionTop > 0) sessionTop--;
        light();
      case PushButton.octaveDown when session:
        sessionTop++;
        light();
      case PushButton.left when session:
        if (sessionLeft > 0) sessionLeft--;
        light();
      case PushButton.right when session:
        sessionLeft++;
        light();
      case PushButton.octaveUp:
        if (octave < 5) octave++;
        light();
      case PushButton.octaveDown:
        if (octave > -3) octave--;
        light();
      case PushButton.scale || PushButton.layout:
        inKey = !inKey;
        light();
      default:
        return false;
    }
    return true;
  }

  /// setScale sets the pads' scale (the channel's Scale effect's, where it
  /// has one) and relights them.
  void setScale(int root, List<int> steps) {
    if (root == this.root && listEquals(steps, this.steps)) return;
    this.root = root;
    this.steps = steps;
    light();
  }
}
