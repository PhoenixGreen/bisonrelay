import 'package:bruig/plugin_system/canvas/model/elements/synth_task_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_parts.dart'
    show panelRow, cell, CanvasQuickStrip;
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:flutter/material.dart';

// synth_settings.dart is a synth module's settings: its knobs and choice
// as sliders and a list (what its panel turns, for a reader of the panel
// rather than the canvas), its look, and the teacher's tools -- Set as
// start, Lock, Reset, Reset all -- with a module to add beside it.

List<Widget> synthSettings(
  BuildContext context,
  CanvasController controller,
  SynthModuleElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit,
) {
  // Through setSynth, so a note held hears each step.
  void live(SynthModuleElement next) {
    begin();
    controller.setSynth(next, transient: true);
  }

  void now(SynthModuleElement next) {
    live(next);
    commit();
  }

  var knobs = synthKnobs[e.module]!;
  var choice = synthChoiceOf(e.module);
  var cables = e.inputs.length;
  var changed = e.changed;
  return [
    elementPanel(context, controller, e, write, begin, commit,
        quick: CanvasQuickStrip(key: const ValueKey("quickStrip"), children: [
          panelRow([
            cell(
                CanvasDropdown<SynthLook>(
                  key: const ValueKey("synthLook"),
                  label: "Look",
                  value: e.look,
                  options: [for (var l in SynthLook.values) (l, l.label)],
                  onChanged: (l) => now(e.copyWith(look: l)),
                ),
                min: 110),
            if (e.module != SynthModuleKind.keys &&
                e.module != SynthModuleKind.out)
              cell(
                  CanvasTextButton(
                    key: const ValueKey("synthReset"),
                    label: "↺ Reset",
                    onPressed: changed && !e.fixed
                        ? () => controller.resetSynth(e)
                        : null,
                  ),
                  min: 90),
          ]),
        ]),
        contentOpen: true,
        bits: [
          PanelBit(PanelSection.content,
              summary: [
                e.module.label,
                if (cables > 0) "$cables cable${cables == 1 ? "" : "s"} in",
                if (e.fixed) "locked",
              ].join(" · "),
              children: [
                if (knobs.isNotEmpty || choice != null)
                  CanvasControlGroup(
                      label: "Settings",
                      help: "What its knobs turn. Double-click a knob on "
                          "the panel for the start's value.",
                      children: [
                        if (choice != null)
                          CanvasDropdown<String>(
                            key: const ValueKey("synthChoice"),
                            label: switch (choice) {
                              "wave" => "Wave",
                              "shape" => "Shape",
                              _ => "Type",
                            },
                            value: e.choice(choice),
                            options: [
                              for (var v in synthChoices[choice]!)
                                (v, _choiceLabel(v)),
                            ],
                            onChanged: (v) => now(e.withChoice(choice, v)),
                          ),
                        for (var k in knobs)
                          CanvasSlider(
                            key: ValueKey("synthKnob_${k.key}"),
                            label: k.label,
                            // As the knob turns: a log knob's slider too.
                            value: k.turn(e.value(k.key)),
                            width: 120,
                            onChanged: (t) => live(e.withValue(k.key, k.at(t))),
                            onCommit: commit,
                          ),
                      ]),
                CanvasControlGroup(
                    label: "Teaching",
                    help: "Set as start makes every module as it is now "
                        "the starting point students reset to (↺); Lock "
                        "keeps this one's settings as they are.",
                    children: [
                      CanvasToggle(
                        key: const ValueKey("synthLock"),
                        label: "Lock for students",
                        value: e.fixed,
                        onChanged: (v) => now(e.copyWith(fixed: v)),
                      ),
                      panelRow([
                        cell(CanvasTextButton(
                          key: const ValueKey("synthSetStart"),
                          label: "Set as start",
                          onPressed: controller.startSynthsHere,
                        )),
                        cell(CanvasTextButton(
                          key: const ValueKey("synthResetAll"),
                          label: "↺ Reset all",
                          onPressed: controller.resetAllSynths,
                        )),
                      ]),
                    ]),
                CanvasControlGroup(
                    label: "Rack",
                    help: "Every module's look at once, and another module "
                        "put down beside this one.",
                    children: [
                      panelRow([
                        for (var l in SynthLook.values)
                          cell(CanvasTextButton(
                            key: ValueKey("synthAll_${l.name}"),
                            label: "All ${l.label.toLowerCase()}",
                            onPressed: () => controller.lookAllSynths(l),
                          )),
                      ]),
                      CanvasTextButton(
                        key: const ValueKey("synthAddTask"),
                        label: "Add a task card",
                        icon: Icons.checklist,
                        onPressed: () => controller.addSynthTask(e),
                      ),
                      CanvasDropdown<SynthModuleKind?>(
                        key: const ValueKey("synthAdd"),
                        label: "Add a module",
                        value: null,
                        options: [
                          (null, "Choose…"),
                          for (var k in SynthModuleKind.values) (k, k.label),
                        ],
                        onChanged: (k) {
                          if (k != null) controller.addSynthModule(k, e);
                        },
                      ),
                    ]),
              ]),
        ]),
  ];
}

String _choiceLabel(String v) => switch (v) {
      "sine" => "Sine",
      "triangle" => "Triangle",
      "sawtooth" => "Saw",
      "square" => "Square",
      "lowpass" => "Low-pass",
      "highpass" => "High-pass",
      "bandpass" => "Band-pass",
      _ => v,
    };

/// synthTaskSettings are a task card's: what it says, its target set
/// from the rack, and its checks -- each worded, a knob's range set, or
/// taken out.
List<Widget> synthTaskSettings(
  BuildContext context,
  CanvasController controller,
  SynthTaskElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit,
) {
  // Each word typed fits the card to what it now says.
  void live(SynthTaskElement next) => write(controller.fitSynthTask(next));
  void now(SynthTaskElement next) {
    live(next);
    commit();
  }

  var (met, of) = controller.checkSynthTask(e);
  return [
    elementPanel(context, controller, e, write, begin, commit,
        contentOpen: true,
        bits: [
          PanelBit(PanelSection.content,
              summary:
                  e.target == null ? "No target yet" : "$met of $of checks met",
              children: [
                CanvasControlGroup(
                    label: "Task",
                    help: "What the student is to make.",
                    children: [
                      CanvasTextField(
                        key: const ValueKey("synthTaskTitle"),
                        label: "Title",
                        value: e.title,
                        width: 240,
                        onChanged: (v) => live(e.copyWith(title: v)),
                        onCommit: commit,
                      ),
                      CanvasTextField(
                        key: const ValueKey("synthTaskText"),
                        label: "Words",
                        value: e.text,
                        width: 240,
                        maxLines: 4,
                        onChanged: (v) => live(e.copyWith(text: v)),
                        onCommit: commit,
                      ),
                    ]),
                CanvasControlGroup(
                    label: "Target",
                    help: "Make the sound on the rack, then set it as the "
                        "target: the card keeps it to be heard, and checks "
                        "everything that differs from the rack's start. "
                        "Reset the rack after, for the student.",
                    children: [
                      panelRow([
                        cell(CanvasTextButton(
                          key: const ValueKey("synthTaskTarget"),
                          label: "Set target from the rack",
                          primary: e.target == null,
                          onPressed: () => controller.setSynthTarget(e),
                        )),
                      ]),
                      panelRow([
                        cell(CanvasTextButton(
                          key: const ValueKey("synthTaskHear"),
                          label: "▶ Hear it",
                          onPressed: e.target == null
                              ? null
                              : () => controller.hearSynthTarget(e),
                        )),
                        cell(CanvasTextButton(
                          key: const ValueKey("synthTaskReset"),
                          label: "↺ Reset the rack",
                          onPressed: controller.resetAllSynths,
                        )),
                      ]),
                    ]),
                if (e.checks.isNotEmpty)
                  CanvasControlGroup(
                      label: "Checks",
                      help: "Ticked on the card as the patch meets each.",
                      children: [
                        for (var (i, c) in e.checks.indexed) ...[
                          panelRow([
                            cell(
                                CanvasTextField(
                                  key: ValueKey("synthCheck$i"),
                                  label: "Check ${i + 1}",
                                  value: c.label,
                                  onChanged: (v) => live(e.copyWith(checks: [
                                    for (var (j, x) in e.checks.indexed)
                                      j == i ? x.copyWith(label: v) : x
                                  ])),
                                  onCommit: commit,
                                ),
                                flex: 4),
                            cell(
                                CanvasIconButton(
                                  key: ValueKey("synthCheckOut$i"),
                                  icon: Icons.close,
                                  tooltip: "",
                                  onPressed: () => now(e.copyWith(checks: [
                                    for (var (j, x) in e.checks.indexed)
                                      if (j != i) x
                                  ])),
                                ),
                                width: 36),
                          ]),
                          if (c.kind == SynthCheckKind.value)
                            panelRow([
                              cell(CanvasNumberField(
                                key: ValueKey("synthCheckMin$i"),
                                label: "From",
                                value: c.min,
                                decimals: 3,
                                onChanged: (v) => live(e.copyWith(checks: [
                                  for (var (j, x) in e.checks.indexed)
                                    j == i ? x.copyWith(min: v) : x
                                ])),
                                onCommit: commit,
                              )),
                              cell(CanvasNumberField(
                                key: ValueKey("synthCheckMax$i"),
                                label: "To",
                                value: c.max,
                                decimals: 3,
                                onChanged: (v) => live(e.copyWith(checks: [
                                  for (var (j, x) in e.checks.indexed)
                                    j == i ? x.copyWith(max: v) : x
                                ])),
                                onCommit: commit,
                              )),
                            ]),
                        ],
                      ]),
              ]),
        ]),
  ];
}
