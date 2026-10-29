import 'dart:async';
import 'dart:io';

import 'package:bruig/plugin_system/canvas/media/midi_input.dart';
import 'package:bruig/plugin_system/canvas/media/synth/part_render.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/midi_file.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_mixer.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/element_sections.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/placement_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/settings_shared.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

// instrument_settings.dart is an instrument's settings: what it sounds like,
// the keyboard it is drawn as, and its part -- the notes, where they came
// from, and clearing them. Then, as any sound's, where it is heard from.
//
// The part is played into its clip's file whenever it changes -- see
// CanvasController.renderParts -- so nothing here has to ask for it.

List<Widget> instrumentSettings(
  BuildContext context,
  CanvasController controller,
  AudioElement e,
  SettingsWrite write,
  VoidCallback begin,
  VoidCallback commit,
) {
  var part = e.instrument!;
  void set(InstrumentPart next) {
    begin();
    write(e.copyWith(instrument: next));
    commit();
  }

  void clipNow(MediaClip next) {
    begin();
    write(e.copyWith(clip: next));
    commit();
  }

  var keyboard = keyboards
      .where((k) => k.$2 == part.lowKey && k.$3 == part.keys)
      .firstOrNull;
  var seconds = part.notes.isEmpty
      ? 0.0
      : part.notes.map((n) => n.end).reduce((a, b) => a > b ? a : b);
  String clock(double s) =>
      "${s ~/ 60}:${(s % 60).floor().toString().padLeft(2, "0")}";

  Future<void> importMidi() async {
    var picked = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: const ["mid", "midi"]);
    var file = picked?.files.singleOrNull?.path;
    if (file == null) return;
    try {
      var read = readMidiFile(await File(file).readAsBytes());
      var now = controller.document.elementById(e.id);
      if (now is! AudioElement || now.instrument == null) return;
      controller.setInstrument(
          now,
          now.instrument!.copyWith(
              notes: read.notes,
              // The file's own sound, where the bank can play it.
              program: now.instrument!.sound == InstrumentSound.bank
                  ? read.program
                  : null));
    } on FormatException catch (exception) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text("That is not a MIDI file Canvas can read: "
              "${exception.message}")));
    }
  }

  return [
    section(e, "instrument",
        icon: Icons.piano,
        title: "Instrument",
        summary: part.look == InstrumentLook.keyboard
            ? "${part.name} · ${keyboard?.$1 ?? "${part.keys} keys"}"
            : "${part.name} · ${part.look.label}",
        initiallyOpen: true,
        children: [
          CanvasControlGroup(
            label: "Instrument",
            hideCaption: true,
            rule: false,
            children: [
              CanvasDropdown<InstrumentLook>(
                key: const ValueKey("instrumentLook"),
                label: "Played on",
                value: part.look,
                width: 140,
                options: [
                  for (var l in InstrumentLook.values) (l, l.label),
                ],
                onChanged: (l) {
                  // Reshaped to suit: pads squarer, a neck long and low.
                  var ratio = switch (l) {
                    InstrumentLook.keyboard => 0.3,
                    InstrumentLook.drums => 0.75,
                    InstrumentLook.guitar => 0.24,
                    InstrumentLook.bass => 0.2,
                  };
                  begin();
                  var next = e.copyWith(instrument: part.withLook(l));
                  write(next.rebase(next.base.copyWith(
                      height: e.width * ratio,
                      name: e.base.name == part.name || e.base.name.isEmpty
                          ? part.withLook(l).name
                          : null)));
                  commit();
                },
              ),
              CanvasDropdown<InstrumentSound>(
                key: const ValueKey("instrumentSound"),
                label: "Sound",
                value: part.sound,
                width: 170,
                options: [
                  for (var s in InstrumentSound.values) (s, s.label),
                ],
                onChanged: (s) => set(part.copyWith(sound: s)),
              ),
              if (part.sound == InstrumentSound.bank)
                CanvasDropdown<int>(
                  key: const ValueKey("instrumentProgram"),
                  label: "Plays",
                  value: part.program,
                  width: 190,
                  options: [
                    if (part.look == InstrumentLook.drums)
                      (0, "Standard kit")
                    else
                      for (var (i, name) in gmPrograms.indexed) (i, name),
                  ],
                  onChanged: (p) => set(part.copyWith(program: p)),
                ),
              if (part.look == InstrumentLook.keyboard)
                CanvasDropdown<int>(
                  key: const ValueKey("instrumentKeys"),
                  label: "Keyboard",
                  value: keyboard == null ? -1 : keyboards.indexOf(keyboard),
                  width: 150,
                  options: [
                    if (keyboard == null) (-1, "${part.keys} keys"),
                    for (var (i, k) in keyboards.indexed) (i, k.$1),
                  ],
                  onChanged: (i) {
                    if (i < 0) return;
                    var (_, low, keys) = keyboards[i];
                    set(part.copyWith(lowKey: low, keys: keys));
                  },
                ),
              if (part.sound == InstrumentSound.bank)
                _BankStatus(controller: controller),
              const _MidiKeyboard(),
            ],
          ),
          CanvasControlGroup(
            label: "Part",
            rule: false,
            children: [
              Text(
                  key: const ValueKey("partSummary"),
                  part.notes.isEmpty
                      ? "No notes yet"
                      : "${part.notes.length} note"
                          "${part.notes.length == 1 ? "" : "s"} · "
                          "${clock(seconds)}",
                  style: TextStyle(
                      fontSize: 12,
                      color: ThemeNotifier.of(context).colors.onSurface)),
              CanvasTextButton(
                key: const ValueKey("importMidi"),
                label: "Import a MIDI file",
                icon: Icons.file_open_outlined,
                onPressed: importMidi,
              ),
              CanvasTextButton(
                key: const ValueKey("clearPart"),
                label: "Clear the notes",
                icon: Icons.delete_sweep_outlined,
                onPressed: part.notes.isEmpty
                    ? null
                    : () => set(part.copyWith(notes: const [])),
              ),
              const CanvasHint(
                  "Select the keyboard and press its keys to play it. To "
                  "write down what you play, press Record on the timeline: "
                  "it plays, and what you play is added to the part where "
                  "the playhead is. Undo takes a take back."),
            ],
          ),
        ]),
    section(e, "placement",
        icon: Icons.surround_sound_outlined,
        title: "Placement",
        summary: placementSummary(e.clip.place),
        children: [
          placementGroup(controller, e, e.clip, clipNow, clipLive: (c) {
            begin();
            write(e.copyWith(clip: c));
          }, commit: commit),
        ]),
    // Its channel: level, effects, sends -- as any sound's.
    CanvasMixer.section(
        key: ValueKey(
            "mixerSection-${e.clip.channel.isEmpty ? e.id : e.clip.channel}"),
        controller: controller,
        channel: e.clip.channel.isEmpty ? e.id : e.clip.channel),
  ];
}

/// _BankStatus says whether the sound bank is here, and fetches it.
class _BankStatus extends StatefulWidget {
  final CanvasController controller;
  const _BankStatus({required this.controller});

  @override
  State<_BankStatus> createState() => _BankStatusState();
}

class _BankStatusState extends State<_BankStatus> {
  bool? _ready;
  double? _progress;

  @override
  void initState() {
    super.initState();
    soundBankReady().then((r) {
      if (mounted) setState(() => _ready = r);
    });
  }

  Future<void> _download() async {
    setState(() => _progress = 0);
    var ok = await downloadSoundBank(progress: (p) {
      if (mounted) setState(() => _progress = p);
    });
    if (!mounted) return;
    setState(() {
      _progress = null;
      _ready = ok;
    });
    if (ok) {
      await widget.controller.renderParts();
    } else {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text("The sound bank could not be downloaded. Until it "
              "is, the built-in piano plays.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var small = TextStyle(fontSize: 11, color: colors.onSurfaceVariant);
    if (_ready == null) return const SizedBox.shrink();
    if (_ready!) {
      return Text(
          "MuseScore General is here. It is MIT-licensed; what is made with "
          "it carries its licence.",
          style: small);
    }
    if (_progress case var p?) {
      return SizedBox(
        width: 220,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Downloading… ${(p * 100).round()}%", style: small),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: p),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
          "The General MIDI sounds come from MuseScore General, a "
          "${(soundBankBytes / 1e6).round()} MB download. Until it is here, "
          "the built-in piano plays.",
          style: small),
      const SizedBox(height: 4),
      CanvasTextButton(
        key: const ValueKey("downloadBank"),
        label: "Download the sounds",
        icon: Icons.download_outlined,
        onPressed: _download,
      ),
    ]);
  }
}

/// _MidiKeyboard chooses the MIDI keyboard that plays the instruments: the
/// one selected, or the first there is. See MidiInput.
class _MidiKeyboard extends StatefulWidget {
  const _MidiKeyboard();

  @override
  State<_MidiKeyboard> createState() => _MidiKeyboardState();
}

class _MidiKeyboardState extends State<_MidiKeyboard> {
  final MidiInput _midi = MidiInput.shared;

  @override
  void initState() {
    super.initState();
    _midi.addListener(_changed);
    unawaited(_midi.refresh());
  }

  @override
  void dispose() {
    _midi.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_midi.unavailable) return const SizedBox.shrink();
    var devices = _midi.devices;
    var chosen = _midi.device?.id ?? "";
    return Row(mainAxisSize: MainAxisSize.min, children: [
      CanvasDropdown<String>(
        key: const ValueKey("midiKeyboard"),
        label: "MIDI keyboard",
        value: chosen,
        width: 170,
        options: [
          ("", devices.isEmpty ? "None plugged in" : "None"),
          for (var d in devices) (d.id, d.name),
          if (chosen.isNotEmpty && !devices.any((d) => d.id == chosen))
            (chosen, _midi.device!.name),
        ],
        onChanged: (id) =>
            unawaited(_midi.use(devices.where((d) => d.id == id).firstOrNull)),
      ),
      CanvasIconButton(
        key: const ValueKey("midiRefresh"),
        icon: Icons.refresh,
        tooltip: "Look again for MIDI keyboards",
        onPressed: () => unawaited(_midi.refresh()),
      ),
    ]);
  }
}
