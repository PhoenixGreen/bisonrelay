import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/musicxml.dart';
import 'package:bruig/plugin_system/canvas/model/score_samples.dart';
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
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart'
    show panelRow, cell, CanvasQuickStrip;
import 'package:bruig/plugin_system/canvas/ui/settings/element_panel.dart';

// sheet_settings.dart is Sheet music's settings: the instrument whose part
// it engraves, and practising it -- how, which hand, how fast -- with the
// take's score while one goes.

List<Widget> sheetSettings(
  BuildContext context,
  CanvasController controller,
  SheetElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit, {
  /// panel lays the sections out as every rebuilt element's are (Ken,
  /// 2026-11-11: batch 5).
  bool panel = false,
}) {
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
  // A score's parts are shown as the score's, not as their channels.
  var scoreParts = [
    for (var s in controller.document.scores)
      for (var p in s.parts)
        if (instruments.any((x) => x.id == p.channel)) (s, p),
  ];
  String partValue(String score, String part) => "score:$score/$part";
  var chosen = e.score.isNotEmpty ? partValue(e.score, e.part) : e.follows;
  var colors = ThemeNotifier.of(context).colors;
  var going = controller.practising == e.id;
  var (right, wrong) = controller.practiceScore;
  var tried = right + wrong;

  var all = [
    section(e, "sheet",
        icon: Icons.queue_music,
        title: "Sheet music",
        summary: followed == null
            ? "No instrument chosen"
            : e.score.isNotEmpty
                ? "${followed.name}, from the score"
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
                value: chosen,
                width: 190,
                options: [
                  if (followed == null)
                    (
                      "",
                      instruments.isEmpty
                          ? "Add an instrument first"
                          : "Choose one"
                    ),
                  for (var (s, p) in scoreParts)
                    (
                      partValue(s.id, p.id),
                      "${s.title.isEmpty ? "Score" : s.title} · ${p.name}"
                    ),
                  for (var x in instruments)
                    if (!(x.instrument?.fromScore ?? false)) (x.id, x.name),
                ],
                onChanged: (id) {
                  if (id.isEmpty) return;
                  for (var (s, p) in scoreParts) {
                    if (partValue(s.id, p.id) != id) continue;
                    now(e.copyWith(
                        follows: p.channel,
                        score: s.id,
                        part: p.id,
                        title: e.title.isEmpty ? s.title : null,
                        key: s.fifths));
                    return;
                  }
                  var x = instruments.firstWhere((x) => x.id == id);
                  now(e.copyWith(
                      follows: id,
                      score: "",
                      part: "",
                      title: e.title.isEmpty ? x.name : null));
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
                key: const ValueKey("sheetPaper"),
                label: "Paper",
                color: e.paper,
                // Down to none: the music on whatever is behind it.
                allowAlpha: true,
                onChanged: (c) => now(e.copyWith(paper: c)),
              ),
              CanvasColorButton(
                key: const ValueKey("sheetInk"),
                label: "Ink",
                color: e.ink,
                onChanged: (c) => now(e.copyWith(ink: c)),
              ),
              // A score's heading over the music, each line shown or not.
              if (e.score.isNotEmpty)
                for (var (key, label, on, set)
                    in <(String, String, bool, SheetElement Function(bool))>[
                  (
                    "sheetShowTitle",
                    "Title",
                    e.showTitle,
                    (v) => e.copyWith(showTitle: v)
                  ),
                  (
                    "sheetShowSubtitle",
                    "Subtitle",
                    e.showSubtitle,
                    (v) => e.copyWith(showSubtitle: v)
                  ),
                  (
                    "sheetShowComposer",
                    "Composer and words",
                    e.showComposer,
                    (v) => e.copyWith(showComposer: v)
                  ),
                  (
                    "sheetShowTempo",
                    "Tempo",
                    e.showTempo,
                    (v) => e.copyWith(showTempo: v)
                  ),
                ])
                  CanvasToggle(
                      key: ValueKey(key),
                      label: label,
                      value: on,
                      onChanged: (v) => now(set(v))),
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
              // The score it shows, written in the Score Studio.
              if (e.score.isNotEmpty && controller.scoreById(e.score) != null)
                CanvasTextButton(
                  key: const ValueKey("sheetStudio"),
                  label: "Edit in the Score Studio",
                  icon: Icons.edit_note,
                  onPressed: () => controller.openScoreStudio(e.score),
                )
              else ...[
                CanvasTextButton(
                  key: const ValueKey("sheetNewScore"),
                  label: followed == null
                      ? "New score"
                      : "Make a score of its notes",
                  icon: Icons.queue_music,
                  onPressed: () =>
                      controller.openScoreStudio(controller.newScoreFor(e)),
                ),
                CanvasTextButton(
                  key: const ValueKey("sheetSampleScore"),
                  label: "Start from “Ode to Joy”",
                  icon: Icons.library_music_outlined,
                  onPressed: () => controller.openScoreStudio(
                      controller.newScoreFor(e, score: odeToJoy())),
                ),
                const CanvasHint(
                    "A score is written in the Score Studio, as MuseScore "
                    "writes one: every part plays on a channel of its own, "
                    "and the sheet shows the part you choose."),
              ],
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
              // A score part's playhead, by hand (Ken, 2026-11-14): to a
              // note pressed on the sheet, or a note at a time.
              if (e.score.isNotEmpty) ...[
                CanvasTextButton(
                  key: const ValueKey("sheetStart"),
                  label: "To the start",
                  icon: Icons.skip_previous,
                  onPressed: () => controller.sheetToStart(e),
                ),
                CanvasTextButton(
                  key: const ValueKey("sheetStepBack"),
                  label: "Back a note",
                  icon: Icons.chevron_left,
                  onPressed: () => controller.stepSheet(e, -1),
                ),
                CanvasTextButton(
                  key: const ValueKey("sheetStepOn"),
                  label: "On a note",
                  icon: Icons.chevron_right,
                  onPressed: () => controller.stepSheet(e, 1),
                ),
                CanvasDropdown<bool>(
                  key: const ValueKey("sheetPlayhead"),
                  label: "Playhead",
                  value: e.playhead,
                  width: 150,
                  options: const [(true, "Show"), (false, "Highlight only")],
                  onChanged: (v) => now(e.copyWith(playhead: v)),
                ),
                if (controller.sheetKeyboard(e) case var keys?)
                  CanvasTextButton(
                    key: const ValueKey("sheetKeyboard"),
                    label: keys.base.visible
                        ? "Hide its keyboard"
                        : "Show its keyboard",
                    icon: Icons.piano,
                    onPressed: () =>
                        controller.showSheetKeyboard(e, !keys.base.visible),
                  ),
                const CanvasHint(
                    "With the sheet picked, press a note on it and the "
                    "playhead goes there. The notes under the playhead are "
                    "lit, on the sheet and on its keyboard."),
              ],
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
  if (!panel) return all;
  var [sheet, practice] = all;
  // The part it shows in Content, with how it is practised a fold under it
  // that stays open; the paper and ink are also in the quick strip.
  return [
    elementPanel(context, controller, e, write, begin, commit,
        quick: CanvasQuickStrip(key: const ValueKey("quickStrip"), children: [
          panelRow([
            cell(
                CanvasDropdown<PracticeMode>(
                  key: const ValueKey("quickSheetMode"),
                  label: "Practice",
                  value: e.mode,
                  options: [for (var m in PracticeMode.values) (m, m.label)],
                  onChanged: (m) => now(e.copyWith(mode: m)),
                ),
                flex: 1,
                min: 110),
            cell(
                CanvasColorButton(
                  key: const ValueKey("quickSheetPaper"),
                  label: "Paper",
                  color: e.paper,
                  allowAlpha: true,
                  onChanged: (c) => now(e.copyWith(paper: c)),
                ),
                width: 96),
            cell(
                CanvasColorButton(
                  key: const ValueKey("quickSheetInk"),
                  label: "Ink",
                  color: e.ink,
                  onChanged: (c) => now(e.copyWith(ink: c)),
                ),
                width: 96),
          ]),
        ]),
        contentOpen: true,
        bits: [
          PanelBit(PanelSection.content,
              summary: (sheet as CanvasSection).summary,
              children: [...sectionContents(sheet), practice]),
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
