import 'dart:convert';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/notation.dart';
import 'package:xml/xml.dart';

// musicxml.dart is a score in MusicXML, the file every notation program --
// MuseScore, Sibelius, Finale, Dorico -- reads and writes: written out from
// a Score, and read back in as notes.
//
// Partwise, one part: a piano's two staves in one part, as MuseScore writes
// it. Read in, every part's notes are taken together, as one instrument
// plays them; grace notes are left out, ties joined into one held note, and
// a compressed file (.mxl, a zip) opened for the score inside it.

/// _divisions is how finely a quarter note is counted: a dotted semiquaver
/// is nine of them, a triplet quaver eight.
const int _divisions = 24;

String _typeOf(double base) => switch (base) {
      >= 4 => "whole",
      >= 2 => "half",
      >= 1 => "quarter",
      >= 0.5 => "eighth",
      _ => "16th",
    };

/// scoreToMusicXml is [score] as a MusicXML document: its key, time and
/// staves, every note and rest as written, its ties and signs, and
/// [tempo] quarter notes a minute.
String scoreToMusicXml(Score score, {String title = "", double tempo = 120}) {
  var b = XmlBuilder();
  b.processing("xml", 'version="1.0" encoding="UTF-8" standalone="no"');
  b.element("score-partwise", attributes: {"version": "4.0"}, nest: () {
    if (title.isNotEmpty) {
      b.element("work", nest: () => b.element("work-title", nest: title));
    }
    b.element("identification",
        nest: () => b.element("encoding",
            nest: () => b.element("software", nest: "Bison Relay Canvas")));
    b.element("part-list",
        nest: () => b.element("score-part",
            attributes: {"id": "P1"},
            nest: () =>
                b.element("part-name", nest: title.isEmpty ? "Piano" : title)));
    b.element("part", attributes: {"id": "P1"}, nest: () {
      // Whether each staff's last note was tied on, into the next.
      var tiedFrom = <(Staff, int), bool>{};
      for (var bar in score.bars) {
        b.element("measure", attributes: {"number": "${bar.number}"}, nest: () {
          if (bar.number == 1) {
            b.element("attributes", nest: () {
              b.element("divisions", nest: "$_divisions");
              b.element("key",
                  nest: () => b.element("fifths", nest: "${score.fifths}"));
              b.element("time", nest: () {
                b.element("beats", nest: "${score.beatsPerBar}");
                b.element("beat-type", nest: "${score.beatUnit}");
              });
              if (score.staves.length > 1) {
                b.element("staves", nest: "${score.staves.length}");
              }
              for (var (i, staff) in score.staves.indexed) {
                b.element("clef", attributes: {
                  if (score.staves.length > 1) "number": "${i + 1}"
                }, nest: () {
                  b.element("sign", nest: staff == Staff.treble ? "G" : "F");
                  b.element("line", nest: staff == Staff.treble ? "2" : "4");
                });
              }
            });
            b.element("direction", attributes: {"placement": "above"},
                nest: () {
              b.element("direction-type",
                  nest: () => b.element("metronome", nest: () {
                        b.element("beat-unit", nest: "quarter");
                        b.element("per-minute", nest: "${tempo.round()}");
                      }));
              b.element("sound", attributes: {"tempo": "${tempo.round()}"});
            });
          }
          var barLength = (score.barQuarters * _divisions).round();
          var firstVoice = true;
          for (var (i, staff) in score.staves.indexed) {
            // Each voice of the staff, back to the bar's start between
            // them -- numbered as MuseScore does: a staff's from four on.
            var voices = <int, List<Written>>{};
            for (var w in bar.staves[staff] ?? const <Written>[]) {
              (voices[w.voice] ??= []).add(w);
            }
            for (var MapEntry(key: v, value: items) in voices.entries) {
              if (!firstVoice) {
                b.element("backup",
                    nest: () => b.element("duration", nest: "$barLength"));
              }
              firstVoice = false;
              var voice = "${i * 4 + v + 1}";
              // Each triplet's first and last, for its bracket.
              var opens = <Written>{}, closes = <Written>{};
              for (var g in tupletGroups(items)) {
                opens.add(items[g.first]);
                closes.add(items[g.last]);
              }
              void threeInTwo() {
                b.element("time-modification", nest: () {
                  b.element("actual-notes", nest: "3");
                  b.element("normal-notes", nest: "2");
                });
              }

              void bracket(Written w) {
                if (opens.contains(w)) {
                  b.element("tuplet", attributes: {"type": "start"});
                }
                if (closes.contains(w)) {
                  b.element("tuplet", attributes: {"type": "stop"});
                }
              }

              for (var w in items) {
                var duration = (w.quarters * _divisions).round();
                if (w.isRest) {
                  b.element("note", nest: () {
                    b.element("rest");
                    b.element("duration", nest: "$duration");
                    b.element("voice", nest: voice);
                    b.element("type", nest: _typeOf(w.base));
                    if (w.tuplet) threeInTwo();
                    if (score.staves.length > 1) {
                      b.element("staff", nest: "${i + 1}");
                    }
                    if (opens.contains(w) || closes.contains(w)) {
                      b.element("notations", nest: () => bracket(w));
                    }
                  });
                  tiedFrom[(staff, v)] = false;
                  continue;
                }
                var stop = tiedFrom[(staff, v)] ?? false;
                for (var (j, key) in w.keys.indexed) {
                  var sp = spellKey(key, score.fifths);
                  b.element("note", nest: () {
                    if (j > 0) b.element("chord");
                    b.element("pitch", nest: () {
                      b.element("step", nest: "CDEFGAB"[sp.letter]);
                      if (sp.alter != 0) {
                        b.element("alter", nest: "${sp.alter}");
                      }
                      b.element("octave", nest: "${sp.octave}");
                    });
                    b.element("duration", nest: "$duration");
                    if (stop) b.element("tie", attributes: {"type": "stop"});
                    if (w.tiedOn) {
                      b.element("tie", attributes: {"type": "start"});
                    }
                    b.element("voice", nest: voice);
                    b.element("type", nest: _typeOf(w.base));
                    for (var d = 0; d < w.dots; d++) {
                      b.element("dot");
                    }
                    var sign =
                        j < w.accidentals.length ? w.accidentals[j] : null;
                    if (sign != null) {
                      b.element("accidental",
                          nest: switch (sign) {
                            1 => "sharp",
                            -1 => "flat",
                            _ => "natural",
                          });
                    }
                    if (w.tuplet) threeInTwo();
                    if (score.voicesIn(bar, staff) > 1) {
                      b.element("stem", nest: v == 0 ? "up" : "down");
                    }
                    if (score.staves.length > 1) {
                      b.element("staff", nest: "${i + 1}");
                    }
                    // The bracket on the chord's first note only.
                    var bracketed =
                        j == 0 && (opens.contains(w) || closes.contains(w));
                    if (stop || w.tiedOn || bracketed) {
                      b.element("notations", nest: () {
                        if (stop) {
                          b.element("tied", attributes: {"type": "stop"});
                        }
                        if (w.tiedOn) {
                          b.element("tied", attributes: {"type": "start"});
                        }
                        if (bracketed) bracket(w);
                      });
                    }
                  });
                }
                tiedFrom[(staff, v)] = w.tiedOn;
              }
            }
          }
        });
      }
    });
  });
  return b.buildDocument().toXmlString(pretty: true, indent: "  ");
}

/// MusicXmlScore is what a MusicXML file says: its notes, in quarter notes
/// from its start, its title, tempo, time and key.
class MusicXmlScore {
  /// notes are each key, its start and its length in quarters, and its
  /// velocity.
  final List<MidiNote> notes;
  final String title;
  final double? tempo;
  final int beatsPerBar, beatUnit, fifths;
  const MusicXmlScore(this.notes,
      {this.title = "",
      this.tempo,
      this.beatsPerBar = 4,
      this.beatUnit = 4,
      this.fifths = 0});

  /// played is the notes in seconds, at [tempo] quarter notes a minute.
  List<MidiNote> played(double tempo) {
    var spq = 60 / math.max(1, tempo);
    return [
      for (var n in notes)
        MidiNote(n.key, n.start * spq, n.length * spq, n.velocity),
    ];
  }
}

/// MusicXmlException is a file that is not a score that can be read.
class MusicXmlException implements Exception {
  final String message;
  const MusicXmlException(this.message);
  @override
  String toString() => message;
}

/// readMusicXml reads a MusicXML file's [bytes] -- a score, or a compressed
/// one (.mxl) with the score inside.
MusicXmlScore readMusicXml(List<int> bytes) {
  String text;
  // A zip: PK at its start.
  if (bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
    var zip = ZipDecoder().decodeBytes(bytes);
    String? rootPath;
    for (var f in zip.files) {
      if (f.name == "META-INF/container.xml") {
        var container = XmlDocument.parse(utf8.decode(f.content));
        rootPath = container
            .findAllElements("rootfile")
            .firstOrNull
            ?.getAttribute("full-path");
      }
    }
    var root = zip.files
            .where((f) => f.isFile && f.name == rootPath)
            .firstOrNull ??
        zip.files
            .where((f) =>
                f.isFile &&
                !f.name.startsWith("META-INF") &&
                (f.name.endsWith(".xml") || f.name.endsWith(".musicxml")))
            .firstOrNull;
    if (root == null) {
      throw const MusicXmlException("There is no score in that file.");
    }
    text = utf8.decode(root.content, allowMalformed: true);
  } else {
    text = utf8.decode(bytes, allowMalformed: true);
  }
  XmlDocument doc;
  try {
    doc = XmlDocument.parse(text);
  } on XmlException {
    throw const MusicXmlException("That file is not MusicXML.");
  }
  var score = doc.findElements("score-partwise").firstOrNull;
  if (score == null) {
    if (doc.findElements("score-timewise").isNotEmpty) {
      throw const MusicXmlException(
          "That score is written time-wise; export it part-wise.");
    }
    throw const MusicXmlException("That file is not MusicXML.");
  }
  String? textOf(XmlElement? e) => e?.innerText.trim();
  var title = textOf(score.findAllElements("work-title").firstOrNull) ??
      textOf(score.findAllElements("movement-title").firstOrNull) ??
      "";
  double? tempo;
  int? beats, beatType, fifths;
  var notes = <MidiNote>[];
  const steps = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11};
  for (var part in score.findElements("part")) {
    var divisions = 1.0;
    var measureStart = 0.0;
    // Each key held from a tie, for the next note of it to carry on.
    var open = <int, int>{};
    for (var measure in part.findElements("measure")) {
      var cursor = 0.0, furthest = 0.0, lastStart = 0.0;
      for (var child in measure.childElements) {
        switch (child.name.local) {
          case "attributes":
            var d = double.tryParse(
                textOf(child.findElements("divisions").firstOrNull) ?? "");
            if (d != null && d > 0) divisions = d;
            beats ??= int.tryParse(
                textOf(child.findAllElements("beats").firstOrNull) ?? "");
            beatType ??= int.tryParse(
                textOf(child.findAllElements("beat-type").firstOrNull) ?? "");
            fifths ??= int.tryParse(
                textOf(child.findAllElements("fifths").firstOrNull) ?? "");
          case "direction":
            var t = child
                .findAllElements("sound")
                .firstOrNull
                ?.getAttribute("tempo");
            tempo ??= double.tryParse(t ?? "");
          case "sound":
            tempo ??= double.tryParse(child.getAttribute("tempo") ?? "");
          case "backup":
            cursor -= (double.tryParse(
                        textOf(child.findElements("duration").firstOrNull) ??
                            "") ??
                    0) /
                divisions;
          case "forward":
            cursor += (double.tryParse(
                        textOf(child.findElements("duration").firstOrNull) ??
                            "") ??
                    0) /
                divisions;
            furthest = math.max(furthest, cursor);
          case "note":
            // A grace note takes no time: left out.
            if (child.findElements("grace").isNotEmpty) continue;
            var length = (double.tryParse(
                        textOf(child.findElements("duration").firstOrNull) ??
                            "") ??
                    0) /
                divisions;
            var chord = child.findElements("chord").isNotEmpty;
            var start = chord ? lastStart : cursor;
            if (!chord) {
              lastStart = cursor;
              cursor += length;
              furthest = math.max(furthest, cursor);
            }
            var pitch = child.findElements("pitch").firstOrNull;
            if (pitch == null) continue; // a rest, or unpitched
            var step = steps[textOf(pitch.findElements("step").firstOrNull)];
            var octave = int.tryParse(
                textOf(pitch.findElements("octave").firstOrNull) ?? "");
            if (step == null || octave == null) continue;
            var alter = double.tryParse(
                    textOf(pitch.findElements("alter").firstOrNull) ?? "") ??
                0;
            var key = ((octave + 1) * 12 + step + alter.round()).clamp(0, 127);
            var ties = {
              for (var t in child.findElements("tie")) t.getAttribute("type")
            };
            var at = measureStart + start;
            if (ties.contains("stop") && open.containsKey(key)) {
              // Carried on from the note it is tied to: that one held
              // longer.
              var i = open[key]!;
              var held = notes[i];
              notes[i] = held.copyWith(length: at + length - held.start);
              if (!ties.contains("start")) open.remove(key);
              continue;
            }
            notes.add(MidiNote(key, at, length, 90));
            if (ties.contains("start")) open[key] = notes.length - 1;
        }
      }
      measureStart += furthest;
    }
  }
  if (notes.isEmpty) {
    throw const MusicXmlException("That score has no notes to read.");
  }
  notes.sort((a, b) =>
      a.start != b.start ? a.start.compareTo(b.start) : a.key.compareTo(b.key));
  return MusicXmlScore(notes,
      title: title,
      tempo: tempo,
      beatsPerBar: beats ?? 4,
      beatUnit: beatType ?? 4,
      fifths: (fifths ?? 0).clamp(-7, 7));
}
