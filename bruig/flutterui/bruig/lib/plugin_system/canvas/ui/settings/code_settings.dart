import 'package:bruig/plugin_system/canvas/model/code_runners.dart';
import 'package:bruig/plugin_system/canvas/model/code_timing.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_run_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/code_task_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart'
    as parts;
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart'
    show panelRow, cell, CanvasQuickStrip, CanvasStateNote;
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:flutter/material.dart';

// code_settings.dart is a Code and Run panel's settings: files and panes in
// Content, colours in Look, typing and lit lines in Motion.

IconData _layoutIcon(CodeLayout l) => switch (l) {
      CodeLayout.one => Icons.crop_square,
      CodeLayout.twoSide => Icons.vertical_split_outlined,
      CodeLayout.twoStacked => Icons.view_agenda_outlined,
      CodeLayout.threeSide => Icons.view_week_outlined,
      CodeLayout.oneOverTwo => Icons.view_quilt_outlined,
    };

/// paneName is what pane [i] of [layout] is called.
String paneName(CodeLayout layout, int i) => switch (layout) {
      CodeLayout.one => "Tabs",
      CodeLayout.twoSide => ["Left pane", "Right pane"][i],
      CodeLayout.twoStacked => ["Top pane", "Bottom pane"][i],
      CodeLayout.threeSide => ["Left pane", "Middle pane", "Right pane"][i],
      CodeLayout.oneOverTwo => ["Top pane", "Bottom left", "Bottom right"][i],
    };

const _newFiles = [
  ("html", "HTML"),
  ("css", "CSS"),
  ("js", "JS"),
  ("py", "Python"),
  ("go", "Go"),
  ("dart", "Dart"),
];

List<Widget> codeSettings(
  BuildContext context,
  CanvasController controller,
  CodeElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit,
) {
  void now(CodeElement next) {
    begin();
    controller.replaceElement(next);
    commit();
  }

  var plan = codePlan(e);
  var panes = e.shownPanes;

  Widget fileRow(CodeFile f) => panelRow([
        cell(
            CanvasColorButton(
              key: ValueKey("codeFileColour-${f.id}"),
              color: f.colour,
              allowAlpha: false,
              onChanged: (c) => now(e.copyWith(files: [
                for (var g in e.files) g.id == f.id ? g.copyWith(colour: c) : g
              ])),
            ),
            width: 44,
            min: 44),
        cell(
            CanvasTextField(
              key: ValueKey("codeFileName-${f.id}"),
              label: f.language.label,
              value: f.name,
              onChanged: (v) {
                var name = v.trim();
                // File names are unique: a second "style.css" is refused.
                if (name.isEmpty || (e.fileNamed(name)?.id ?? f.id) != f.id) {
                  return;
                }
                begin();
                controller.replaceElement(e.copyWith(files: [
                  for (var g in e.files)
                    g.id == f.id ? g.copyWith(name: name) : g
                ]));
              },
              onCommit: commit,
            ),
            flex: 4),
        cell(
            CanvasIconButton(
              key: ValueKey("codeFileDelete-${f.id}"),
              icon: Icons.close,
              tooltip: "Delete ${f.name}",
              onPressed:
                  e.files.length < 2 ? null : () => now(e.withoutFile(f.id)),
            ),
            width: 36,
            min: 36),
      ]);

  Widget paneRow(int i, CodePane p) {
    var closed = [
      for (var f in e.files)
        if (!p.tabs.contains(f.id)) f
    ];
    return CanvasControlGroup(
        key: ValueKey("codePane-$i"),
        label: paneName(e.layout, i),
        rule: false,
        children: [
          Wrap(children: [
            for (var id in p.tabs)
              if (e.file(id) case var f?)
                CanvasChip(
                  key: ValueKey("codeTab-$i-$id"),
                  label: f.name,
                  here: id == p.shows,
                  onRemove: () => controller.closeCodeTab(e, i, id),
                ),
          ]),
          if (closed.isNotEmpty)
            CanvasDropdown<String>(
              key: ValueKey("codeOpen-$i"),
              label: "Open a file",
              value: "",
              options: [
                ("", "Open a file…"),
                for (var f in closed) (f.id, f.name),
              ],
              onChanged: (id) {
                if (id.isNotEmpty) controller.showCodeTab(e, i, id);
              },
            ),
        ]);
  }

  Widget stepCard(int k, CodeStep s) {
    void set(CodeStep next) {
      begin();
      controller.replaceElement(e.copyWith(
          steps: [for (var (j, t) in e.steps.indexed) j == k ? next : t]));
    }

    var lines = e.file(s.file)?.text.split("\n").length ?? 1;
    return CanvasControlGroup(
        key: ValueKey("codeStep-$k"),
        label: "Step ${k + 1}",
        children: [
          panelRow([
            cell(CanvasTextButton(
              key: ValueKey("codeStepShow-$k"),
              label: "Show",
              icon: Icons.visibility_outlined,
              onPressed: () => controller.frame =
                  ((s.at + 0.05) * controller.document.frameRate).round(),
            )),
            cell(CanvasTextButton(
              key: ValueKey("codeStepDelete-$k"),
              label: "Delete",
              icon: Icons.delete_outline,
              onPressed: () => now(e.copyWith(steps: [
                for (var (j, t) in e.steps.indexed)
                  if (j != k) t
              ])),
            )),
          ]),
          panelRow([
            cell(CanvasStepper(
              key: ValueKey("codeStepAt-$k"),
              label: "At",
              value: s.at,
              min: 0,
              max: 3600,
              decimals: 1,
              step: 0.2,
              suffix: " s",
              fill: true,
              onChanged: (v) => set(s.copyWith(at: v)),
              onCommit: commit,
            )),
            cell(CanvasStepper(
              key: ValueKey("codeStepFor-$k"),
              label: "For",
              value: s.length,
              min: 0.2,
              max: 600,
              decimals: 1,
              step: 0.2,
              suffix: " s",
              fill: true,
              onChanged: (v) => set(s.copyWith(length: v)),
              onCommit: commit,
            )),
          ]),
          CanvasDropdown<String>(
            key: ValueKey("codeStepFile-$k"),
            label: "File",
            value: e.file(s.file) == null ? "" : s.file,
            options: [
              if (e.file(s.file) == null) ("", "—"),
              for (var f in e.files) (f.id, f.name),
            ],
            onChanged: (id) {
              if (id.isEmpty) return;
              set(s.copyWith(file: id));
              commit();
            },
          ),
          panelRow([
            cell(CanvasStepper(
              key: ValueKey("codeStepFrom-$k"),
              label: "From line",
              value: s.from.toDouble(),
              min: 1,
              max: lines.toDouble(),
              fill: true,
              onChanged: (v) => set(s.copyWith(from: v.round())),
              onCommit: commit,
            )),
            cell(CanvasStepper(
              key: ValueKey("codeStepTo-$k"),
              label: "To line",
              value: s.to.toDouble(),
              min: 1,
              max: lines.toDouble(),
              fill: true,
              onChanged: (v) => set(s.copyWith(to: v.round())),
              onCommit: commit,
            )),
          ]),
          CanvasTextField(
            key: ValueKey("codeStepNote-$k"),
            label: "Note beside the lines",
            value: s.note,
            onChanged: (v) => set(s.copyWith(note: v)),
            onCommit: commit,
          ),
        ]);
  }

  return [
    elementPanel(context, controller, e, write, begin, commit,
        quick: CanvasQuickStrip(key: const ValueKey("quickStrip"), children: [
          panelRow([
            cell(
                CanvasDropdown<CodeKind>(
                  key: const ValueKey("codeProject"),
                  label: "Project",
                  value: e.project,
                  options: [for (var k in CodeKind.values) (k, k.label)],
                  // Restarted as an empty project of that kind; Undo brings
                  // the files back.
                  onChanged: (k) {
                    if (k != e.project) now(e.startedAs(k));
                  },
                ),
                flex: 3),
            cell(
                CanvasTextButton(
                  key: const ValueKey("codeOpenStudio"),
                  label: "Code Studio",
                  icon: Icons.open_in_full,
                  primary: true,
                  onPressed: () => controller.openCodeStudio(e.id),
                ),
                flex: 2),
          ]),
          const SizedBox(height: 8),
          panelRow([
            cell(
                CanvasDropdown<CodeTheme>(
                  key: const ValueKey("codeTheme"),
                  label: "Colours",
                  value: e.theme,
                  options: [for (var t in CodeTheme.values) (t, t.label)],
                  onChanged: (t) => now(e.copyWith(theme: t)),
                ),
                flex: 3),
            cell(
                CanvasStepper(
                  key: const ValueKey("codeFontSize"),
                  label: "Code size",
                  value: e.fontSize,
                  min: 4,
                  max: 1000,
                  fill: true,
                  onChanged: (v) {
                    begin();
                    controller.replaceElement(e.copyWith(fontSize: v));
                  },
                  onCommit: commit,
                ),
                flex: 2),
          ]),
          const SizedBox(height: 8),
          CanvasSegmented<CodeLayout>(
            key: const ValueKey("codeLayout"),
            label: "Layout",
            value: e.layout,
            options: [for (var l in CodeLayout.values) (l, l.label)],
            iconOf: _layoutIcon,
            keyOf: (l) => "codeLayout-${l.name}",
            onChanged: (l) => now(e.withLayout(l)),
          ),
        ]),
        contentOpen: true,
        bits: [
          PanelBit(PanelSection.content,
              summary: "${e.files.length} file${e.files.length == 1 ? "" : "s"}"
                  " · ${e.layout.label}",
              children: [
                CanvasControlGroup(
                    key: const ValueKey("codeFiles"),
                    label: "Files",
                    help: "The project's files. A file named in another's "
                        "code -- style.css in a page, an import -- is "
                        "underlined in its colour, so a learner can see "
                        "what uses what. Choosing a Project above starts "
                        "the files again, empty (Undo brings them back); "
                        "the examples are in More, under Presets.",
                    children: [
                      CanvasTextField(
                        key: const ValueKey("codeTitle"),
                        label: "Project",
                        value: e.title,
                        onChanged: (v) {
                          begin();
                          controller.replaceElement(e.copyWith(title: v));
                        },
                        onCommit: commit,
                      ),
                      for (var f in e.files) fileRow(f),
                      Wrap(children: [
                        for (var (ext, name) in _newFiles)
                          parts.CanvasChip("+ $name",
                              key: ValueKey("codeAddFile-$ext"), onPressed: () {
                            var n = 1;
                            String nameOf() =>
                                n == 1 ? "new.$ext" : "new$n.$ext";
                            while (e.fileNamed(nameOf()) != null) {
                              n++;
                            }
                            var f = CodeFile(
                                id: e.newFileId(),
                                name: nameOf(),
                                colour: codeFileColours[
                                    e.files.length % codeFileColours.length]);
                            now(e.withFile(f, pane: controller.codePane(e)));
                          }),
                      ]),
                      CanvasToggle(
                        key: const ValueKey("codeLinks"),
                        label: "Underline other files' names",
                        value: e.links,
                        onChanged: (v) => now(e.copyWith(links: v)),
                      ),
                    ]),
                CanvasControlGroup(
                    key: const ValueKey("codeTasks"),
                    label: "Tasks",
                    help: "A task card says what to do, ticks its checks as "
                        "the code meets them, and when Check is pressed "
                        "says whether it passed.",
                    children: [
                      CanvasTextButton(
                        key: const ValueKey("codeAddTask"),
                        label: "Add a task card",
                        icon: Icons.fact_check_outlined,
                        onPressed: () => controller.addCodeTask(e),
                      ),
                    ]),
                CanvasControlGroup(
                    key: const ValueKey("codeStart"),
                    label: "Starting code",
                    help: "The code as it began is kept the first time it "
                        "is typed into, on the canvas or in the Code "
                        "Studio. Reset, on the panel's bar, puts it back: "
                        "a student's mistakes undone in one press.",
                    children: [
                      CanvasStateNote(e.start == null
                          ? "Not typed into yet: this is the starting code."
                          : e.changedFromStart
                              ? "Changed since it began."
                              : "As it began."),
                      if (e.start != null)
                        panelRow([
                          cell(CanvasTextButton(
                            key: const ValueKey("codeReset"),
                            label: "Reset",
                            icon: Icons.restart_alt,
                            onPressed: e.changedFromStart
                                ? () => controller.resetCode(e)
                                : null,
                          )),
                          cell(CanvasTextButton(
                            key: const ValueKey("codeKeepStart"),
                            label: "Keep as the start",
                            onPressed: e.changedFromStart
                                ? () => controller.keepCodeAsStart(e)
                                : null,
                          )),
                        ]),
                    ]),
                CanvasControlGroup(
                    key: const ValueKey("codePanes"),
                    label: "Panes",
                    help: "Each pane's tabs. On the canvas, drag a tab along "
                        "its row to reorder it, or onto another pane to move "
                        "it there; drag the line between two panes to resize "
                        "them. Click a pane's code to edit it.",
                    children: [
                      for (var (i, p) in panes.indexed) paneRow(i, p),
                      if (e.layout.panes > 1)
                        CanvasTextButton(
                          key: const ValueKey("codeEvenPanes"),
                          label: "Make the panes the same size",
                          onPressed: () => now(e.copyWith(
                              columns: e.layout.evenColumns,
                              rows: e.layout.evenRows)),
                        ),
                    ]),
              ]),
          PanelBit(PanelSection.look,
              summary:
                  [e.theme.label, if (!e.showFiles) "no file list"].join(", "),
              children: [
                CanvasControlGroup(
                    key: const ValueKey("codeWindow"),
                    label: "Window",
                    children: [
                      CanvasToggle(
                        key: const ValueKey("codeShowFiles"),
                        label: "Files",
                        value: e.showFiles,
                        onChanged: (v) => now(e.copyWith(showFiles: v)),
                      ),
                      CanvasToggle(
                        key: const ValueKey("codeLineNumbers"),
                        label: "Line numbers",
                        value: e.lineNumbers,
                        onChanged: (v) => now(e.copyWith(lineNumbers: v)),
                      ),
                      CanvasToggle(
                        key: const ValueKey("codeWindowBar"),
                        label: "Window bar",
                        value: e.windowBar,
                        onChanged: (v) => now(e.copyWith(windowBar: v)),
                      ),
                      if (e.windowBar)
                        CanvasToggle(
                          key: const ValueKey("codePlaybar"),
                          label: "Play controls",
                          value: e.playbar,
                          onChanged: (v) => now(e.copyWith(playbar: v)),
                        ),
                    ]),
              ]),
          PanelBit(PanelSection.motion,
              summary: [
                if (e.typing.on) "types in" else "shown whole",
                if (e.steps.isNotEmpty)
                  "${e.steps.length} highlight${e.steps.length == 1 ? "" : "s"}",
              ].join(", "),
              children: [
                CanvasControlGroup(
                    key: const ValueKey("codeTyping"),
                    label: "Typing",
                    help: "The code types itself in, pane by pane and tab by "
                        "tab, on the scene's clock: the same in a video. "
                        "Indents type quickly.",
                    children: [
                      CanvasToggle(
                        key: const ValueKey("codeTypingOn"),
                        label: "Type the code in",
                        value: e.typing.on,
                        onChanged: (v) =>
                            now(e.copyWith(typing: e.typing.copyWith(on: v))),
                      ),
                      if (e.typing.on) ...[
                        panelRow([
                          cell(CanvasStepper(
                            key: const ValueKey("codeTypingSpeed"),
                            label: "Letters a second",
                            value: e.typing.speed,
                            min: 2,
                            max: 400,
                            step: 5,
                            fill: true,
                            onChanged: (v) {
                              begin();
                              controller.replaceElement(e.copyWith(
                                  typing: e.typing.copyWith(speed: v)));
                            },
                            onCommit: commit,
                          )),
                          cell(CanvasStepper(
                            key: const ValueKey("codeTypingStart"),
                            label: "Starts at",
                            value: e.typing.start,
                            min: 0,
                            max: 3600,
                            decimals: 1,
                            step: 0.5,
                            suffix: " s",
                            fill: true,
                            onChanged: (v) {
                              begin();
                              controller.replaceElement(e.copyWith(
                                  typing: e.typing.copyWith(start: v)));
                            },
                            onCommit: commit,
                          )),
                        ]),
                        panelRow([
                          cell(CanvasStepper(
                            key: const ValueKey("codeTypingPause"),
                            label: "Pause at line ends",
                            value: e.typing.pause,
                            min: 0,
                            max: 3,
                            decimals: 2,
                            step: 0.02,
                            suffix: " s",
                            fill: true,
                            onChanged: (v) {
                              begin();
                              controller.replaceElement(e.copyWith(
                                  typing: e.typing.copyWith(pause: v)));
                            },
                            onCommit: commit,
                          )),
                        ]),
                        CanvasSegmented<bool>(
                          key: const ValueKey("codeTypingOrder"),
                          label: "Order",
                          value: e.typing.together,
                          options: const [
                            (false, "Pane by pane"),
                            (true, "All at once"),
                          ],
                          onChanged: (v) => now(e.copyWith(
                              typing: e.typing.copyWith(together: v))),
                        ),
                        CanvasToggle(
                          key: const ValueKey("codeTypingCaret"),
                          label: "Show the caret",
                          value: e.typing.caret,
                          onChanged: (v) => now(
                              e.copyWith(typing: e.typing.copyWith(caret: v))),
                        ),
                        CanvasStateNote(
                            "The typing ends at ${plan.end.toStringAsFixed(1)} s."),
                      ],
                    ]),
                CanvasControlGroup(
                    key: const ValueKey("codeHighlights"),
                    label: "Highlights",
                    help: "Lines lit for a while, with a note beside them; "
                        "the pane holding the file shows it while they are.",
                    children: [
                      for (var (k, s) in e.steps.indexed) stepCard(k, s),
                      Wrap(children: [
                        parts.CanvasChip("+ Step at the playhead",
                            key: const ValueKey("codeAddStep"), onPressed: () {
                          var t =
                              controller.frame / controller.document.frameRate;
                          var pane = controller.codePane(e);
                          var file = controller.codeShownFile(e, pane) ??
                              (e.files.isEmpty ? "" : e.files.first.id);
                          if (file.isEmpty) return;
                          var steps = [
                            ...e.steps,
                            CodeStep(
                                at: double.parse(t.toStringAsFixed(1)),
                                file: file,
                                from: 1,
                                to: 2,
                                note: "New note"),
                          ]..sort((a, b) => a.at.compareTo(b.at));
                          now(e.copyWith(steps: steps));
                        }),
                      ]),
                      CanvasToggle(
                        key: const ValueKey("codeDim"),
                        label: "Dim the other lines",
                        value: e.dim,
                        onChanged: (v) => now(e.copyWith(dim: v)),
                      ),
                    ]),
              ]),
        ]),
  ];
}

String _runnerNote(CodeRunner r) => switch (r) {
      CodeRunner.web => "A real browser (WebKit). What the page prints with "
          "console.log, and its errors, come out in the output.",
      CodeRunner.python => "Python in the browser (Pyodide), fetched the "
          "first time it runs -- about 10 MB -- then kept. Offline after that.",
      CodeRunner.go => "Yaegi, a Go interpreter, in the browser. Nothing to "
          "install; running programs and the network are left out.",
      CodeRunner.dart => "Dart run inside the app (dart_eval). Nothing to "
          "install.",
      CodeRunner.flutter => "flutter_eval draws the app's widgets inside the "
          "app, offline, and they show in exports. Some of Flutter is not "
          "covered.",
      CodeRunner.dartpad => "DartPad: the real Flutter, built on Google's "
          "servers each time it runs. Needs the internet; an export shows "
          "the picture saved at the last run.",
      CodeRunner.none => "Pick a file to start from.",
    };

List<Widget> codeRunSettings(
  BuildContext context,
  CanvasController controller,
  CodeRunElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit,
) {
  void now(CodeRunElement next) {
    begin();
    controller.replaceElement(next);
    commit();
  }

  var codes = controller.document.elements.whereType<CodeElement>().toList();
  var code = codes.where((c) => c.id == e.code).firstOrNull;
  var runner = runnerOf(e, code);
  var entry = entryFile(e, code);
  var at = runAt(e, code);
  var running = controller.codeRunning(e.id);
  String ran(CodeRunResult r) {
    var t = r.at.toLocal();
    String two(int n) => n.toString().padLeft(2, "0");
    return "Ran at ${two(t.hour)}:${two(t.minute)}:${two(t.second)}"
        " · saved with the canvas";
  }

  return [
    elementPanel(context, controller, e, write, begin, commit,
        quick: CanvasQuickStrip(key: const ValueKey("quickStrip"), children: [
          panelRow([
            cell(
                CanvasReadout(
                    key: const ValueKey("codeRunner"),
                    label: "Runs with",
                    value: runner.online
                        ? "${runner.label} · online"
                        : runner.label),
                flex: 3),
            cell(
                CanvasTextButton(
                  key: const ValueKey("codeRunNow"),
                  label: running ? "Running…" : "Run now",
                  icon: Icons.play_arrow,
                  primary: true,
                  onPressed: running || code == null
                      ? null
                      : () => controller.runCode(e),
                ),
                flex: 2),
          ]),
        ]),
        contentOpen: true,
        bits: [
          PanelBit(PanelSection.content,
              summary: "${entry?.name ?? "—"} · ${runner.label}",
              children: [
                CanvasControlGroup(
                    key: const ValueKey("codeRunProgram"),
                    label: "Program",
                    children: [
                      CanvasDropdown<String>(
                        key: const ValueKey("codeRunCode"),
                        label: "Code from",
                        value: code == null ? "" : code.id,
                        options: [
                          if (code == null) ("", "—"),
                          for (var c in codes) (c.id, "${c.name} · ${c.title}"),
                        ],
                        onChanged: (id) {
                          if (id.isNotEmpty) {
                            now(e.copyWith(code: id, entry: ""));
                          }
                        },
                      ),
                      if (code != null)
                        CanvasDropdown<String>(
                          key: const ValueKey("codeRunEntry"),
                          label: "Starts from",
                          value: entry?.id ?? "",
                          options: [
                            if (entry == null) ("", "—"),
                            for (var f in code.files)
                              if (runnable(f.language)) (f.id, f.name),
                          ],
                          onChanged: (id) {
                            if (id.isNotEmpty) now(e.copyWith(entry: id));
                          },
                        ),
                      CanvasStateNote(_runnerNote(runner)),
                      if (runner == CodeRunner.flutter ||
                          runner == CodeRunner.dartpad)
                        CanvasToggle(
                          key: const ValueKey("codeRunDartpad"),
                          label: "Full Flutter through DartPad",
                          value: e.dartpad,
                          onChanged: (v) => now(e.copyWith(dartpad: v)),
                        ),
                    ]),
                CanvasControlGroup(
                    key: const ValueKey("codeRunWhen"),
                    label: "When it runs",
                    children: [
                      CanvasSegmented<CodeRunWhen>(
                        key: const ValueKey("codeRunWhenPick"),
                        value: e.when,
                        options: const [
                          (CodeRunWhen.press, "I press Run"),
                          (CodeRunWhen.typed, "Typing ends"),
                          (CodeRunWhen.start, "Scene starts"),
                        ],
                        keyOf: (w) => "codeRunWhen-${w.name}",
                        onChanged: (w) => now(e.copyWith(when: w)),
                      ),
                      if (at != null && e.when == CodeRunWhen.typed)
                        CanvasStateNote(
                            "Runs at ${at.toStringAsFixed(1)} s, as the typing ends."),
                      panelRow([
                        cell(
                            CanvasReadout(
                                key: const ValueKey("codeRunSaved"),
                                label: "Last run",
                                value: e.result == null
                                    ? "Not run yet"
                                    : ran(e.result!)),
                            flex: 3),
                        cell(
                            CanvasTextButton(
                              key: const ValueKey("codeRunAgain"),
                              label: "Run again",
                              onPressed: running || code == null
                                  ? null
                                  : () => controller.runCode(e),
                            ),
                            flex: 2),
                      ]),
                      const CanvasStateNote(
                          "A canvas someone sends you shows its saved run. "
                          "Its code never runs until you press Run."),
                    ]),
              ]),
          PanelBit(PanelSection.look, summary: e.shows.label, children: [
            CanvasControlGroup(
                key: const ValueKey("codeRunLook"),
                label: "Shows",
                children: [
                  CanvasSegmented<CodeRunShows>(
                    key: const ValueKey("codeRunShows"),
                    value: e.shows,
                    options: [
                      for (var s in CodeRunShows.values) (s, s.label),
                    ],
                    keyOf: (s) => "codeRunShows-${s.name}",
                    onChanged: (s) => now(e.copyWith(shows: s)),
                  ),
                  // How wide its page or app is laid out before fitting to
                  // the preview, picture and live app alike.
                  if (e.shows != CodeRunShows.output)
                    CanvasDropdown<double>(
                      key: const ValueKey("codeRunAppWidth"),
                      label: "App width",
                      value: codeAppWidths.any((w) => w.$1 == e.appWidth)
                          ? e.appWidth
                          : 0,
                      options: codeAppWidths,
                      onChanged: (w) => now(e.copyWith(appWidth: w)),
                    ),
                  panelRow([
                    if (e.shows == CodeRunShows.both)
                      cell(CanvasStepper(
                        key: const ValueKey("codeRunSplit"),
                        label: "Preview height",
                        value: e.split * 100,
                        min: 15,
                        max: 85,
                        step: 5,
                        suffix: "%",
                        fill: true,
                        onChanged: (v) {
                          begin();
                          controller.replaceElement(e.copyWith(split: v / 100));
                        },
                        onCommit: commit,
                      )),
                    cell(CanvasStepper(
                      key: const ValueKey("codeRunOutputSize"),
                      label: "Text size",
                      value: e.outputSize,
                      min: 4,
                      max: 1000,
                      fill: true,
                      onChanged: (v) {
                        begin();
                        controller.replaceElement(e.copyWith(outputSize: v));
                      },
                      onCommit: commit,
                    )),
                  ]),
                ]),
          ]),
          PanelBit(PanelSection.more, summary: "exports", children: [
            CanvasControlGroup(
                key: const ValueKey("codeRunExports"),
                label: "In exports",
                children: const [
                  CanvasStateNote("A video plays the saved run at its time on "
                      "the timeline: nothing runs again, so every export is "
                      "the same. A book runs a web page live; Python, Go and "
                      "Dart show the saved output."),
                ]),
          ]),
        ]),
  ];
}

/// codeTaskSettings is a Code task card's: its text, checks, and what it
/// says when checked.
List<Widget> codeTaskSettings(
  BuildContext context,
  CanvasController controller,
  CodeTaskElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit,
) {
  void now(CodeTaskElement next) {
    begin();
    controller.setCodeTask(next);
    commit();
  }

  void typing(CodeTaskElement next) {
    begin();
    controller.setCodeTask(next, transient: true);
  }

  var codes = controller.document.elements.whereType<CodeElement>().toList();
  var code = codes.where((c) => c.id == e.code).firstOrNull;
  Widget checkCard(int k, CodeCheck c) {
    void set(CodeCheck next, {bool keep = false}) {
      var checks = [
        for (var (j, x) in e.checks.indexed) j == k ? next : x,
      ];
      keep
          ? typing(e.copyWith(checks: checks))
          : now(e.copyWith(checks: checks));
    }

    return CanvasControlGroup(
        key: ValueKey("codeCheck-$k"),
        label: "Check ${k + 1}",
        children: [
          panelRow([
            cell(
                CanvasDropdown<CodeCheckKind>(
                  key: ValueKey("codeCheckKind-$k"),
                  label: "Kind",
                  value: c.kind,
                  options: [for (var x in CodeCheckKind.values) (x, x.label)],
                  onChanged: (x) => set(c.copyWith(kind: x)),
                ),
                flex: 3),
            cell(
                CanvasIconButton(
                  key: ValueKey("codeCheckDelete-$k"),
                  icon: Icons.close,
                  tooltip: "Delete this check",
                  onPressed: () => now(e.copyWith(checks: [
                    for (var (j, x) in e.checks.indexed)
                      if (j != k) x
                  ])),
                ),
                width: 36,
                min: 36),
          ]),
          CanvasTextField(
            key: ValueKey("codeCheckLabel-$k"),
            label: "What it says",
            value: c.label,
            onChanged: (v) => set(c.copyWith(label: v), keep: true),
            onCommit: commit,
          ),
          if (c.kind == CodeCheckKind.changes)
            CanvasTextField(
              key: ValueKey("codeCheckBefore-$k"),
              label: c.pattern ? "Before (pattern)" : "Before",
              hint: "coins++",
              value: c.before,
              onChanged: (v) => set(c.copyWith(before: v), keep: true),
              onCommit: commit,
            ),
          if (c.kind != CodeCheckKind.builds) ...[
            // Answers, one a line, any of which passes: spaces don't matter
            // and only whole words count, as patterns are hard to remember.
            CanvasTextField(
              key: ValueKey("codeCheckText-$k"),
              label: c.pattern
                  ? "Pattern"
                  : c.kind == CodeCheckKind.changes
                      ? "After (any of these, one a line)"
                      : "Any of these (one a line)",
              hint: c.pattern ? "" : "coins += 2",
              value: c.text,
              maxLines: c.pattern ? 1 : 3,
              onChanged: (v) => set(c.copyWith(text: v), keep: true),
              onCommit: commit,
            ),
            panelRow([
              if (c.kind != CodeCheckKind.prints && code != null)
                cell(
                    CanvasDropdown<String>(
                      key: ValueKey("codeCheckFile-$k"),
                      label: "In",
                      value: code.fileNamed(c.file) == null ? "" : c.file,
                      options: [
                        ("", "Any file"),
                        for (var f in code.files) (f.name, f.name),
                      ],
                      onChanged: (v) => set(c.copyWith(file: v)),
                    ),
                    flex: 3),
              if (c.kind == CodeCheckKind.has)
                cell(
                    CanvasStepper(
                      key: ValueKey("codeCheckCount-$k"),
                      label: "At least",
                      value: c.count.toDouble(),
                      min: 1,
                      max: 999,
                      step: 1,
                      suffix: c.count == 1 ? " time" : " times",
                      fill: true,
                      onChanged: (v) =>
                          set(c.copyWith(count: v.round()), keep: true),
                      onCommit: commit,
                    ),
                    flex: 2),
            ]),
            CanvasToggle(
              key: ValueKey("codeCheckPattern-$k"),
              label: "A pattern (regular expression)",
              value: c.pattern,
              onChanged: (v) => set(c.copyWith(pattern: v)),
            ),
          ],
        ]);
  }

  return [
    elementPanel(context, controller, e, write, begin, commit,
        quick: CanvasQuickStrip(key: const ValueKey("quickStrip"), children: [
          panelRow([
            cell(
                CanvasTextButton(
                  key: const ValueKey("codeTaskCheck"),
                  label: "Check it now",
                  icon: Icons.fact_check_outlined,
                  primary: true,
                  onPressed:
                      code == null ? null : () => controller.checkCodeTask(e),
                ),
                flex: 3),
            cell(
                CanvasStepper(
                  key: const ValueKey("codeTaskSize"),
                  label: "Text size",
                  value: e.textSize,
                  min: 4,
                  max: 1000,
                  fill: true,
                  onChanged: (v) => typing(e.copyWith(textSize: v)),
                  onCommit: commit,
                ),
                flex: 2),
          ]),
        ]),
        contentOpen: true,
        bits: [
          PanelBit(PanelSection.content,
              summary: "${e.checks.length} check"
                  "${e.checks.length == 1 ? "" : "s"}",
              children: [
                CanvasControlGroup(
                    key: const ValueKey("codeTaskWords"),
                    label: "Task",
                    children: [
                      CanvasDropdown<String>(
                        key: const ValueKey("codeTaskCode"),
                        label: "Marks the code in",
                        value: code?.id ?? "",
                        options: [
                          if (code == null) ("", "—"),
                          for (var c in codes) (c.id, "${c.name} · ${c.title}"),
                        ],
                        onChanged: (id) {
                          if (id.isNotEmpty) now(e.copyWith(code: id));
                        },
                      ),
                      CanvasTextField(
                        key: const ValueKey("codeTaskTitle"),
                        label: "Title",
                        value: e.title,
                        onChanged: (v) => typing(e.copyWith(title: v)),
                        onCommit: commit,
                      ),
                      CanvasTextField(
                        key: const ValueKey("codeTaskText"),
                        label: "What to do",
                        value: e.text,
                        maxLines: 4,
                        onChanged: (v) => typing(e.copyWith(text: v)),
                        onCommit: commit,
                      ),
                    ]),
                CanvasControlGroup(
                    key: const ValueKey("codeTaskChecks"),
                    label: "Checks",
                    help: "What the code must do. Each ticks as it is typed: "
                        "write what the code should say -- several "
                        "answers one a line, any of which passes; spaces "
                        "don't matter, and only whole words count. \"The "
                        "code changes\" wants Before gone and After there. "
                        "\"It builds and runs\" is looked at when Check is "
                        "pressed.",
                    children: [
                      for (var (k, c) in e.checks.indexed) checkCard(k, c),
                      CanvasTextButton(
                        key: const ValueKey("codeTaskAddCheck"),
                        label: "Add a check",
                        icon: Icons.add,
                        onPressed: () => now(e.copyWith(checks: [
                          ...e.checks,
                          const CodeCheck(CodeCheckKind.has, "The code has …"),
                        ])),
                      ),
                    ]),
                CanvasControlGroup(
                    key: const ValueKey("codeTaskSays"),
                    label: "When checked",
                    children: [
                      CanvasTextField(
                        key: const ValueKey("codeTaskPassed"),
                        label: "Passed",
                        value: e.passed,
                        maxLines: 2,
                        onChanged: (v) => typing(e.copyWith(passed: v)),
                        onCommit: commit,
                      ),
                      CanvasTextField(
                        key: const ValueKey("codeTaskNotYet"),
                        label: "Not yet",
                        value: e.notYet,
                        maxLines: 2,
                        onChanged: (v) => typing(e.copyWith(notYet: v)),
                        onCommit: commit,
                      ),
                    ]),
              ]),
          PanelBit(PanelSection.look, children: [
            CanvasControlGroup(
                key: const ValueKey("codeTaskLook"),
                label: "Colour",
                children: [
                  CanvasColorButton(
                    key: const ValueKey("codeTaskAccent"),
                    label: "Accent",
                    color: e.accent,
                    onChanged: (c) => now(e.copyWith(accent: c)),
                  ),
                ]),
          ]),
        ]),
  ];
}
