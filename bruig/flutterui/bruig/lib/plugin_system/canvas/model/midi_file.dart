import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/instrument.dart';

// midi_file.dart reads a Standard MIDI File -- the .mid every notation
// program and sequencer writes -- into notes an instrument can play.
//
// Formats 0 and 1: one track, or several played together. Times in the file
// are ticks; the tempo changes as the file says, so seconds are worked out
// through every tempo change in turn. MIDI's tenth channel is drums by
// convention, and is left out: a piano playing a drum part is a piano
// playing nonsense.

/// MidiImport is what a file held: its notes, and the sound its first
/// instrument asked for.
class MidiImport {
  final List<MidiNote> notes;
  final int? program;
  const MidiImport(this.notes, this.program);
}

/// readMidiFile reads [bytes], or throws a FormatException.
MidiImport readMidiFile(Uint8List bytes) {
  var d = ByteData.sublistView(bytes);
  String tag(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));
  if (bytes.length < 14 || tag(0) != "MThd") {
    throw const FormatException("Not a MIDI file");
  }
  var headerLength = d.getUint32(4);
  var division = d.getUint16(12);
  if (division & 0x8000 != 0) {
    throw const FormatException("Timecode MIDI files are not read");
  }
  var at = 8 + headerLength;

  // Every event of every track, with its tick: tempos, and notes.
  var tempos = <(int, int)>[(0, 500000)];
  var events = <(int, int, int, int, int)>[]; // tick, kind, channel, key, vel
  int? program;
  while (at + 8 <= bytes.length) {
    var id = tag(at);
    var length = d.getUint32(at + 4);
    var start = at + 8, end = math.min(bytes.length, start + length);
    at = end;
    if (id != "MTrk") continue;
    var p = start, tick = 0, status = 0;
    int vlq() {
      var v = 0;
      for (var i = 0; i < 4 && p < end; i++) {
        var b = bytes[p++];
        v = (v << 7) | (b & 0x7F);
        if (b & 0x80 == 0) break;
      }
      return v;
    }

    while (p < end) {
      tick += vlq();
      if (p >= end) break;
      var b = bytes[p];
      if (b & 0x80 != 0) {
        status = b;
        p++;
      }
      if (status == 0xFF) {
        var type = bytes[p++];
        var len = vlq();
        if (type == 0x51 && len == 3 && p + 3 <= end) {
          tempos.add((tick, (bytes[p] << 16) | (bytes[p + 1] << 8) | bytes[p + 2]));
        }
        p += len;
        // A meta event does not set the running status.
        status = 0;
        continue;
      }
      if (status == 0xF0 || status == 0xF7) {
        p += vlq();
        status = 0;
        continue;
      }
      var kind = status & 0xF0, channel = status & 0x0F;
      int data(int i) => p + i < end ? bytes[p + i] : 0;
      switch (kind) {
        case 0x80 || 0x90:
          events.add((tick, kind, channel, data(0), data(1)));
          p += 2;
        case 0xA0 || 0xB0 || 0xE0:
          p += 2;
        case 0xC0:
          if (channel != 9) program ??= data(0);
          p += 1;
        case 0xD0:
          p += 1;
        default:
          p += 1;
      }
    }
  }

  // Ticks to seconds, through the tempo changes.
  tempos.sort((a, b) => a.$1.compareTo(b.$1));
  double seconds(int tick) {
    var s = 0.0, from = 0, tempo = 500000;
    for (var (t, us) in tempos) {
      if (t >= tick) break;
      s += (t - from) * tempo / division / 1e6;
      from = t;
      tempo = us;
    }
    return s + (tick - from) * tempo / division / 1e6;
  }

  events.sort((a, b) => a.$1.compareTo(b.$1));
  var open = <(int, int), (int, int)>{}; // (channel, key) -> (tick, vel)
  var notes = <MidiNote>[];
  void close((int, int) k, int tick) {
    var o = open.remove(k);
    if (o == null) return;
    var from = seconds(o.$1);
    notes.add(MidiNote(k.$2, from, math.max(0.01, seconds(tick) - from), o.$2));
  }

  for (var (tick, kind, channel, key, vel) in events) {
    if (channel == 9) continue;
    var k = (channel, key);
    if (kind == 0x90 && vel > 0) {
      // Pressed again before it was let go: the first ends here.
      close(k, tick);
      open[k] = (tick, vel);
    } else {
      close(k, tick);
    }
  }
  // Never let go: to the last event.
  var last = events.isEmpty ? 0 : events.last.$1;
  for (var k in [...open.keys]) {
    close(k, last);
  }
  notes.sort((a, b) => a.start.compareTo(b.start));
  return MidiImport(notes, program);
}
