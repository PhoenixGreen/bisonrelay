import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/play_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/sheet_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart'
    show panelRow, cell, CanvasQuickStrip;
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:flutter/material.dart';

// play_task_settings.dart is a play task card's settings: what it listens
// to and its steps in Content, its box and type in Look.

List<Widget> playTaskSettings(
  BuildContext context,
  CanvasController controller,
  PlayTaskElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit,
) {
  void now(PlayTaskElement next) {
    begin();
    controller.setPlayTask(next);
    commit();
  }

  void typing(PlayTaskElement next) {
    begin();
    controller.setPlayTask(next, transient: true);
  }

  var instruments = [
    for (var a in controller.document.elements.whereType<AudioElement>())
      if (a.instrument != null) a,
  ];
  var sheets = controller.document.elements.whereType<SheetElement>().toList();

  Widget stepCard(int k, PlayCheck c) {
    void set(PlayCheck next, {bool keep = false}) {
      var checks = [
        for (var (j, x) in e.checks.indexed) j == k ? next : x,
      ];
      keep
          ? typing(e.copyWith(checks: checks))
          : now(e.copyWith(checks: checks));
    }

    var read = c.keys.length;
    return CanvasControlGroup(
        key: ValueKey("playCheck-$k"),
        label: "Step ${k + 1}",
        children: [
          panelRow([
            cell(
                CanvasDropdown<PlayCheckKind>(
                  key: ValueKey("playCheckKind-$k"),
                  label: "Ticked when",
                  value: c.kind,
                  options: [for (var x in PlayCheckKind.values) (x, x.label)],
                  onChanged: (x) => set(c.copyWith(kind: x)),
                ),
                flex: 3),
            cell(
                CanvasIconButton(
                  key: ValueKey("playCheckDelete-$k"),
                  icon: Icons.close,
                  tooltip: "Delete this step",
                  onPressed: () => now(e.copyWith(checks: [
                    for (var (j, x) in e.checks.indexed)
                      if (j != k) x
                  ])),
                ),
                width: 36,
                min: 36),
          ]),
          CanvasTextField(
            key: ValueKey("playCheckLabel-$k"),
            label: "What it says",
            value: c.label,
            maxLines: 2,
            onChanged: (v) => set(c.copyWith(label: v), keep: true),
            onCommit: commit,
          ),
          if (c.kind.byKeys)
            CanvasTextField(
              key: ValueKey("playCheckSteps-$k"),
              label: "Notes (${read == 0 ? "none read" : "$read read"})",
              hint: c.kind == PlayCheckKind.order
                  ? "C4 D4 E4  or chords  C3+E3+G3 F3+A3+C4"
                  : "C2 C3 C4 C5",
              value: c.steps,
              onChanged: (v) => set(c.copyWith(steps: v), keep: true),
              onCommit: commit,
            ),
          if (c.kind == PlayCheckKind.keys)
            CanvasStepper(
              key: ValueKey("playCheckCount-$k"),
              label: "Each",
              value: c.count.toDouble(),
              min: 1,
              max: 99,
              step: 1,
              suffix: c.count == 1 ? " time" : " times",
              onChanged: (v) => set(c.copyWith(count: v.round()), keep: true),
              onCommit: commit,
            ),
          if (c.kind == PlayCheckKind.along)
            CanvasStepper(
              key: ValueKey("playCheckPercent-$k"),
              label: "Right",
              value: c.percent.toDouble(),
              min: 1,
              max: 100,
              step: 5,
              suffix: "%",
              onChanged: (v) => set(c.copyWith(percent: v.round()), keep: true),
              onCommit: commit,
            ),
        ]);
  }

  return [
    elementPanel(context, controller, e, write, begin, commit,
        quick: CanvasQuickStrip(key: const ValueKey("quickStrip"), children: [
          panelRow([
            cell(
                CanvasTextButton(
                  key: const ValueKey("playTaskAgain"),
                  label: "Start again",
                  icon: Icons.restart_alt,
                  onPressed: () => controller.startPlayTaskAgain(e),
                ),
                flex: 3),
            cell(
                CanvasStepper(
                  key: const ValueKey("playTaskSize"),
                  label: "Text size",
                  value: e.spec.fontSize,
                  min: 4,
                  max: 400,
                  onChanged: (v) => typing(e.copyWith(
                      spec: e.spec.copyWith(fontSize: v),
                      titleSpec: e.titleSpec.copyWith(
                          fontSize:
                              v * e.titleSpec.fontSize / e.spec.fontSize))),
                  onCommit: commit,
                ),
                flex: 2),
          ]),
        ]),
        contentOpen: true,
        bits: [
          PanelBit(PanelSection.content,
              summary: "${e.checks.length} step"
                  "${e.checks.length == 1 ? "" : "s"}",
              children: [
                CanvasControlGroup(
                    key: const ValueKey("playTaskWords"),
                    label: "Task",
                    children: [
                      CanvasTextField(
                        key: const ValueKey("playTaskTitle"),
                        label: "Title",
                        value: e.title,
                        onChanged: (v) => typing(e.copyWith(title: v)),
                        onCommit: commit,
                      ),
                      CanvasTextField(
                        key: const ValueKey("playTaskText"),
                        label: "Under the title",
                        value: e.text,
                        maxLines: 3,
                        onChanged: (v) => typing(e.copyWith(text: v)),
                        onCommit: commit,
                      ),
                      CanvasDropdown<String>(
                        key: const ValueKey("playTaskInstrument"),
                        label: "Listens to",
                        value: instruments.any((a) => a.id == e.instrument)
                            ? e.instrument
                            : "",
                        options: [
                          ("", "Any instrument"),
                          for (var a in instruments) (a.id, a.name),
                        ],
                        onChanged: (id) => now(e.copyWith(instrument: id)),
                      ),
                      if (e.checks.any((c) => c.kind == PlayCheckKind.along))
                        CanvasDropdown<String>(
                          key: const ValueKey("playTaskSheet"),
                          label: "Music",
                          value:
                              sheets.any((s) => s.id == e.sheet) ? e.sheet : "",
                          options: [
                            ("", "The first on the page"),
                            for (var s in sheets) (s.id, s.name),
                          ],
                          onChanged: (id) => now(e.copyWith(sheet: id)),
                        ),
                    ]),
                CanvasControlGroup(
                    key: const ValueKey("playTaskChecks"),
                    label: "Steps",
                    help: "Each step ticks itself as it is played on the "
                        "page's keys: notes by name and octave (C4 is Middle "
                        "C; F#3, Bb2), a chord's joined with + (C3+E3+G3). "
                        "\"Play these keys\" wants each, in any order; \"in "
                        "order\" one after another; \"Play along\" a take on "
                        "the music with that much right. A step no key can "
                        "show is ticked by the student, on the card.",
                    children: [
                      for (var (k, c) in e.checks.indexed) stepCard(k, c),
                      CanvasTextButton(
                        key: const ValueKey("playTaskAddCheck"),
                        label: "Add a step",
                        icon: Icons.add,
                        onPressed: () => now(e.copyWith(checks: [
                          ...e.checks,
                          const PlayCheck(PlayCheckKind.keys, "Play Middle C",
                              steps: "C4"),
                        ])),
                      ),
                    ]),
                CanvasControlGroup(
                    key: const ValueKey("playTaskSays"),
                    label: "When every step is done",
                    children: [
                      CanvasTextField(
                        key: const ValueKey("playTaskPassed"),
                        label: "It says",
                        value: e.passed,
                        maxLines: 2,
                        onChanged: (v) => typing(e.copyWith(passed: v)),
                        onCommit: commit,
                      ),
                    ]),
              ]),
          PanelBit(PanelSection.look, children: [
            CanvasControlGroup(
                key: const ValueKey("playTaskLook"),
                label: "Colour",
                children: [
                  CanvasColorButton(
                    key: const ValueKey("playTaskFill"),
                    label: "Fill",
                    color: e.box.fill,
                    onChanged: (c) =>
                        now(e.copyWith(box: e.box.copyWith(fill: c))),
                  ),
                  CanvasColorButton(
                    key: const ValueKey("playTaskBorder"),
                    label: "Border",
                    color: e.box.borderColor,
                    onChanged: (c) =>
                        now(e.copyWith(box: e.box.copyWith(borderColor: c))),
                  ),
                  CanvasColorButton(
                    key: const ValueKey("playTaskAccent"),
                    label: "Numbers",
                    color: e.accent,
                    onChanged: (c) => now(e.copyWith(accent: c)),
                  ),
                  CanvasColorButton(
                    key: const ValueKey("playTaskTitleColour"),
                    label: "Title",
                    color: e.titleSpec.color,
                    onChanged: (c) => now(
                        e.copyWith(titleSpec: e.titleSpec.copyWith(color: c))),
                  ),
                  CanvasColorButton(
                    key: const ValueKey("playTaskTextColour"),
                    label: "Words",
                    color: e.spec.color,
                    onChanged: (c) =>
                        now(e.copyWith(spec: e.spec.copyWith(color: c))),
                  ),
                ]),
            CanvasControlGroup(
                key: const ValueKey("playTaskBox"),
                label: "Box",
                children: [
                  CanvasStepper(
                    key: const ValueKey("playTaskRound"),
                    label: "Corners",
                    value: e.box.borderRadius,
                    min: 0,
                    max: 200,
                    onChanged: (v) => typing(
                        e.copyWith(box: e.box.copyWith(borderRadius: v))),
                    onCommit: commit,
                  ),
                  CanvasStepper(
                    key: const ValueKey("playTaskBorderWidth"),
                    label: "Border",
                    value: e.box.borderWidth,
                    min: 0,
                    max: 40,
                    onChanged: (v) =>
                        typing(e.copyWith(box: e.box.copyWith(borderWidth: v))),
                    onCommit: commit,
                  ),
                ]),
          ]),
        ]),
  ];
}
