import 'dart:io';

import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/media/speech.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_network.dart';
import 'package:bruig/plugin_system/canvas/storage/stock/stock_client.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// cues_section.dart is the list of the run's cues: the named moments a
// voice-over's lines start on, that elements are timed against. See
// canvas_cues.dart.

/// CanvasCuesSection lists the cues, and adds them -- one at the playhead, or
/// one at every line of a voice-over.
class CanvasCuesSection extends StatefulWidget {
  final CanvasController controller;
  const CanvasCuesSection({required this.controller, super.key});

  @override
  State<CanvasCuesSection> createState() => _CanvasCuesSectionState();
}

class _CanvasCuesSectionState extends State<CanvasCuesSection> {
  CanvasController get controller => widget.controller;

  /// _voice is the clip picked to find cues in.
  String? _voice;
  bool _finding = false;
  String _said = "";

  /// _needsModel is whether the last listen stopped for want of the speech
  /// model, which is the one thing here that can be fetched.
  bool _needsModel = false;

  /// _voices are the timed sounds a voice-over could be, longest first --
  /// the voice is nearly always the longest thing on the timeline.
  List<AudioElement> get _voices {
    var d = controller.document;
    var all = <AudioElement>[
      for (var e in [
        ...?d.master?.elements,
        for (var s in d.allScenes) ...s.elements,
      ])
        if (e is AudioElement && e.clip.timed && !e.clip.isEmpty) e,
    ];
    all.sort((a, b) => b.clip.runLength.compareTo(a.clip.runLength));
    return all;
  }

  Future<void> _find(AudioElement voice) async {
    setState(() {
      _finding = true;
      _said = "";
    });
    var n = await controller.findCues(voice);
    if (!mounted) return;
    setState(() {
      _finding = false;
      _said = n == 0
          ? "No pauses found -- is the sound still being read?"
          : "$n cues, one at each line.";
    });
  }

  /// _hear listens to [voice] for its words and names its cues by them.
  Future<void> _hear(AudioElement voice) async {
    setState(() {
      _finding = true;
      _needsModel = false;
      _said = "Listening -- a minute or so for a few minutes of voice.";
    });
    var problem = await controller.hearWords(voice);
    if (!mounted) return;
    setState(() {
      _finding = false;
      _needsModel = problem == speechModelMissing;
      _said = problem ??
          "${controller.words.length} words heard; the cues are named "
              "by what is said at them.";
    });
  }

  /// _fetchModel downloads the speech model beside the library, then
  /// listens. Only with fetching allowed, and never through a proxy -- the
  /// same rules the stock sites keep.
  Future<void> _fetchModel(AudioElement voice) async {
    var allowed = context.read<CanvasPreferences>().allowFetching;
    var proxied = await networkIsProxied();
    var refused =
        StockClient.refusal(allowFetching: allowed, proxied: proxied);
    if (refused != null) {
      setState(() => _said = refused);
      return;
    }
    setState(() {
      _finding = true;
      _said = "Fetching the speech model (about 150 MB)…";
    });
    var to = File(await speechModelPath());
    await to.parent.create(recursive: true);
    var got = await StockClient.instance.download(speechModelUrl, to,
        maxBytes: speechModelBytes, allowFetching: allowed, proxied: proxied);
    if (!mounted) return;
    if (!got) {
      setState(() {
        _finding = false;
        _said = "The speech model could not be fetched.";
      });
      return;
    }
    await _hear(voice);
  }

  @override
  Widget build(BuildContext context) {
    var rate =
        controller.document.frameRate <= 0 ? 1 : controller.document.frameRate;
    var voices = _voices;
    var picked =
        voices.where((v) => v.id == _voice).firstOrNull ?? voices.firstOrNull;
    return CanvasControlGroup(
      key: const ValueKey("cues"),
      label: "Cues",
      children: [
        CanvasIconButton(
          key: const ValueKey("cueAdd"),
          icon: Icons.add_location_alt_outlined,
          tooltip: "Add a cue at the playhead",
          onPressed: () => controller.addCue(),
        ),
        if (voices.isNotEmpty) ...[
          CanvasDropdown<String>(
            label: "Voice",
            value: picked!.id,
            width: 120,
            options: [for (var v in voices) (v.id, v.name)],
            onChanged: (v) => setState(() => _voice = v),
          ),
          CanvasIconButton(
            key: const ValueKey("cueFind"),
            icon: Icons.graphic_eq,
            tooltip: "Put a cue where each line of this voice starts",
            onPressed: _finding ? null : () => _find(picked),
          ),
          CanvasIconButton(
            key: const ValueKey("cueHear"),
            icon: Icons.subtitles_outlined,
            tooltip: "Hear the words, and name the cues by what is said",
            onPressed: _finding ? null : () => _hear(picked),
          ),
          if (_needsModel)
            CanvasTextButton(
              key: const ValueKey("cueFetchModel"),
              label: "Fetch",
              icon: Icons.download_outlined,
              tooltip: "Fetch the speech model, about 150 MB, then listen",
              grow: false,
              onPressed: _finding ? null : () => _fetchModel(picked),
            ),
        ],
        // At the end of the line: whether the cues are marked on the
        // timeline's ruler.
        const CanvasFill(child: SizedBox(width: 0)),
        CanvasIconButton(
          key: const ValueKey("cuesShown"),
          icon: controller.cuesShown
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          tooltip: controller.cuesShown
              ? "Hide the cues on the timeline"
              : "Show the cues on the timeline",
          active: controller.cuesShown,
          onPressed: () => controller.cuesShown = !controller.cuesShown,
        ),
        if (_said.isNotEmpty) ...[
          const CanvasLineBreak(),
          CanvasStatus(_said, key: const ValueKey("cuesSaid")),
        ],
        if (controller.cues.isEmpty)
          const CanvasHint(
              "A cue is a named moment of the whole run -- a line of the "
              "voice-over, say. Tie an element to one in its settings and "
              "moving the cue moves the element with it."),
        for (var cue in controller.cues) ...[
          const CanvasLineBreak(),
          CanvasTextField(
            key: ValueKey("cueName-${cue.id}"),
            label: "",
            value: cue.name,
            width: 104,
            onChanged: (v) => controller.renameCue(cue.id, v),
          ),
          CanvasNumberField(
            key: ValueKey("cueAt-${cue.id}"),
            label: "",
            value: cue.frame / rate,
            min: 0,
            max: 100000,
            decimals: 2,
            suffix: "s",
            width: 66,
            onChanged: (v) {
              controller.beginInteraction();
              controller.moveCue(cue.id, (v * rate).round(), transient: true);
            },
            onCommit: controller.endInteraction,
          ),
          CanvasIconButton(
            key: ValueKey("cueRemove-${cue.id}"),
            icon: Icons.close,
            tooltip: "Remove this cue",
            onPressed: () => controller.removeCue(cue.id),
          ),
        ],
      ],
    );
  }
}
