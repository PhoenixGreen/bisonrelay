import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/musicxml.dart';
import 'package:bruig/plugin_system/canvas/model/notation.dart' show keyNames;
import 'package:bruig/plugin_system/canvas/render/sheet_painter.dart'
    show sheetFifths;
import 'package:file_picker/file_picker.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// sheet_settings.dart is Sheet music's settings: the instrument whose part
// it engraves, and practising it -- how, which hand, how fast -- with the
// take's score while one goes.

List<Widget> sheetSettings(
  BuildContext context,
  CanvasController controller,
  SheetElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit,
) {
  void now(SheetElement next) {
    begin();
    write(next);
    commit();
  }

  var instruments = [
    for (var x in controller.document.elements)
      if (x is AudioElement && x.instrument != null) x,
  ];
  var followed = instruments.where((x) => x.id == e.follows).firstOrNull;
  var colors = ThemeNotifier.of(context).colors;
  var going = controller.practising == e.id;
  var (right, wrong) = controller.practiceScore;
  var tried = right + wrong;

  return [
    section(e, "sheet",
        icon: Icons.queue_music,
        title: "Sheet music",
        summary: followed == null
            ? "No instrument chosen"
            : "${followed.name}'s part",
        initiallyOpen: true,
        children: [
          CanvasControlGroup(
            label: "Sheet music",
            hideCaption: true,
            rule: false,
            children: [
              CanvasDropdown<String>(
                key: const ValueKey("sheetFollows"),
                label: "Shows the part of",
                value: e.follows,
                width: 190,
                options: [
                  if (followed == null)
                    (
                      "",
                      instruments.isEmpty
                          ? "Add an instrument first"
                          : "Choose one"
                    ),
                  for (var x in instruments) (x.id, x.name),
                ],
                onChanged: (id) {
                  if (id.isEmpty) return;
                  var x = instruments.firstWhere((x) => x.id == id);
                  now(e.copyWith(
                      follows: id, title: e.title.isEmpty ? x.name : null));
                },
              ),
              CanvasTextField(
                key: const ValueKey("sheetTitle"),
                label: "Title",
                value: e.title,
                width: 190,
                onChanged: (v) {
                  begin();
                  write(e.copyWith(title: v));
                },
                onCommit: commit,
              ),
              CanvasColorButton(
                label: "Paper",
                color: e.paper,
                onChanged: (c) => now(e.copyWith(paper: c)),
              ),
              CanvasColorButton(
                label: "Ink",
                color: e.ink,
                onChanged: (c) => now(e.copyWith(ink: c)),
              ),
              // Its key: worked out, or chosen. 99 is "worked out".
              CanvasDropdown<int>(
                key: const ValueKey("sheetKey"),
                label: "Key",
                value: e.key ?? 99,
                width: 190,
                options: [
                  (
                    99,
                    followed?.instrument == null
                        ? "Worked out"
                        : "Worked out: ${keyNames[sheetFifths(followed!.instrument!, null)]!.split(" / ").first}"
                  ),
                  for (var k in keyNames.keys) (k, keyNames[k]!),
                ],
                onChanged: (k) => now(
                    k == 99 ? e.copyWith(autoKey: true) : e.copyWith(key: k)),
              ),
              // How many lines to a page.
              CanvasDropdown<int>(
                key: const ValueKey("sheetLines"),
                label: "Lines",
                value: e.lines,
                width: 190,
                options: [
                  for (var n = 1; n <= 8; n++)
                    (n, n == 1 ? "1 line" : "$n lines"),
                ],
                onChanged: (n) => now(e.copyWith(lines: n)),
              ),
              const CanvasHint(
                  "The part is written out in the document's tempo and time "
                  "signature, to the nearest sixteenth — or third of a beat, "
                  "for a beat played in threes: the right hand from "
                  "middle C up on the treble staff, the left on the bass. "
                  "A page of lines shows at a time; at its last line, the "
                  "lines above are already the next page's. "
                  "Its key, worked out, is the Scale effect's where the "
                  "instrument has one, else the one its notes are heard in."),
              CanvasTextButton(
                key: const ValueKey("sheetImport"),
                label: "Open MusicXML…",
                icon: Icons.file_open_outlined,
                onPressed: followed == null
                    ? null
                    : () => _importScore(context, controller, e),
              ),
              CanvasTextButton(
                key: const ValueKey("sheetExport"),
                label: "Save as MusicXML…",
                icon: Icons.save_alt,
                onPressed: followed == null
                    ? null
                    : () => _exportScore(context, controller, e),
              ),
              const CanvasHint(
                  "MusicXML is what MuseScore, Sibelius, Finale and Dorico "
                  "read and write. Opened, a score's notes take the place of "
                  "the instrument's part, on this canvas's tempo."),
            ],
          ),
        ]),
    section(e, "practice",
        icon: Icons.school_outlined,
        title: "Practice",
        summary: "${e.mode.label} · ${e.hands.label} hand"
            "${e.hands == PracticeHands.both ? "s" : ""} · "
            "${(e.tempo * 100).round()}%",
        initiallyOpen: true,
        children: [
          CanvasControlGroup(
            label: "Practice",
            hideCaption: true,
            rule: false,
            children: [
              CanvasDropdown<PracticeMode>(
                key: const ValueKey("practiceMode"),
                label: "How",
                value: e.mode,
                width: 140,
                options: [for (var m in PracticeMode.values) (m, m.label)],
                onChanged: (m) => now(e.copyWith(mode: m)),
              ),
              CanvasDropdown<PracticeHands>(
                key: const ValueKey("practiceHands"),
                label: "Hands",
                value: e.hands,
                width: 100,
                options: [for (var h in PracticeHands.values) (h, h.label)],
                onChanged: (h) => now(e.copyWith(hands: h)),
              ),
              CanvasSlider(
                key: const ValueKey("practiceTempo"),
                label: "Tempo",
                value: e.tempo,
                min: 0.4,
                max: 1.2,
                decimals: 2,
                onChanged: (v) {
                  begin();
                  write(e.copyWith(tempo: (v * 20).round() / 20));
                },
                onCommit: commit,
              ),
              CanvasTextButton(
                key: const ValueKey("practiceGo"),
                label: going ? "Stop" : "Practise",
                icon: going ? Icons.stop : Icons.play_arrow,
                primary: true,
                onPressed: followed == null
                    ? null
                    : () => going
                        ? controller.stopPractice()
                        : controller.startPractice(e),
              ),
              Text(
                  key: const ValueKey("practiceScore"),
                  tried == 0
                      ? (going
                          ? "Play along on the keyboard, or a MIDI one."
                          : "")
                      : "$right right · $wrong wrong · "
                          "${(right / tried * 100).round()}%",
                  style: TextStyle(fontSize: 12, color: colors.onSurface)),
              CanvasHint(switch (e.mode) {
                PracticeMode.listen =>
                  "It plays the piece, and you listen: the keys are lit as "
                      "it goes.",
                PracticeMode.along =>
                  "It plays at the tempo set; play with it. Each note is "
                      "marked right or wrong, and those that go by unplayed "
                      "grey.",
                PracticeMode.wait =>
                  "It waits on each note until you play it. A wrong note is "
                      "marked, and it waits on.",
              }),
            ],
          ),
        ]),
  ];
}

/// _importScore asks for a MusicXML file and puts its notes into the part
/// [e] shows -- saying why not, where it cannot.
Future<void> _importScore(
    BuildContext context, CanvasController controller, SheetElement e) async {
  var messenger = ScaffoldMessenger.maybeOf(context);
  void say(String text) =>
      messenger?.showSnackBar(SnackBar(content: Text(text)));
  var picked = await FilePicker.platform.pickFiles(
      dialogTitle: "Open a MusicXML score",
      type: FileType.custom,
      allowedExtensions: const ["musicxml", "xml", "mxl"],
      withData: true);
  var file = picked?.files.firstOrNull;
  if (file == null) return;
  var bytes = file.bytes ??
      (file.path == null ? null : await File(file.path!).readAsBytes());
  if (bytes == null) return say("That file could not be read.");
  try {
    var score = readMusicXml(bytes);
    var problem = controller.importScore(e, score);
    say(problem ??
        "${score.notes.length} notes from ${file.name}, in "
            "${keyNames[score.fifths]!.split(" / ").first}.");
  } on MusicXmlException catch (x) {
    say(x.message);
  }
}

/// _exportScore asks where to save the part [e] shows, as MusicXML.
Future<void> _exportScore(
    BuildContext context, CanvasController controller, SheetElement e) async {
  var messenger = ScaffoldMessenger.maybeOf(context);
  var xml = controller.exportScore(e);
  if (xml == null) return;
  var name = (e.title.isEmpty ? "Score" : e.title)
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), "-");
  var bytes = Uint8List.fromList(utf8.encode(xml));
  var at = await FilePicker.platform.saveFile(
      dialogTitle: "Save as MusicXML",
      fileName: "$name.musicxml",
      bytes: bytes);
  if (at == null) return;
  // Written here as well: on the desktop the dialog only names the place.
  await File(at).writeAsBytes(bytes);
  messenger?.showSnackBar(SnackBar(content: Text("Saved to $at")));
}
