import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/material.dart';

// source_cards.dart is the Source zone of a sound's chain, as the
// prototype's: what the channel plays, before anything is done to it. A MIDI
// channel's is its Note clips (instrument_editor.dart); an audio channel's,
// its Clips here.

/// audioColour is an audio channel's colour, as the prototype's.
const audioColour = Color(0xFF4F8FD6);

/// AudioClipsDevice is an audio channel's Clips: its sounds on the timeline,
/// one at a time -- its shape, its level and its fades -- and the clips in
/// its slots, opened in the clip editor.
class AudioClipsDevice extends StatefulWidget {
  final CanvasController controller;
  final String channel;
  final bool folded;
  final VoidCallback onFold;
  final double height;
  final DeviceSkin skin;

  const AudioClipsDevice({
    required this.controller,
    required this.channel,
    required this.folded,
    required this.onFold,
    required this.height,
    required this.skin,
    super.key,
  });

  @override
  State<AudioClipsDevice> createState() => _AudioClipsDeviceState();
}

class _AudioClipsDeviceState extends State<AudioClipsDevice> {
  CanvasController get c => widget.controller;

  /// _shown is which of the channel's sounds the card shows and sets.
  int _shown = 0;

  @override
  Widget build(BuildContext context) {
    var studio = MixerLook.of(context).studio;
    var lane =
        c.timelineChannels.where((l) => l.key == widget.channel).firstOrNull;
    if (lane == null) return const SizedBox();
    var sounds = lane.lanes;
    var at = _shown.clamp(0, sounds.length - 1);
    var sound = sounds[at];
    var clip = sound.clip;
    var source = clip.playlist.firstOrNull;
    var slots = [
      for (var (row, s)
          in (c.session.slots[widget.channel] ?? const []).indexed)
        if (s != null && !s.midi) row
    ];
    var length = clip.playlist.fold(
        0.0,
        (sum, s) =>
            sum + math.max(0.0, (s.end > 0 ? s.end : s.length) - s.start));

    // Its level and fades, written to the sound shown.
    void set(MediaClip Function(MediaClip clip) change,
        {bool transient = false}) {
      if (!sound.editable) return;
      if (transient) c.beginInteraction();
      c.setTimedClip(sound.element, change(clip), transient: transient);
      if (!transient) c.endInteraction();
    }

    var muted = TextStyle(fontSize: 10, color: studio.muted);
    var strong = TextStyle(fontSize: 10.5, color: studio.text);
    Widget knob(
            DeviceTier tier,
            String key,
            String label,
            String text,
            double value,
            double initial,
            double min,
            double max,
            MediaClip Function(double v) change) =>
        DeviceKnob(
          key: ValueKey(key),
          label: label,
          text: text,
          value: value,
          initial: initial,
          min: min,
          max: max,
          size: switch (tier) {
            DeviceTier.large => 46,
            DeviceTier.medium => 38,
            _ => 28,
          },
          accent: audioColour,
          ink: studio.text,
          onChanged: (v, {transient = false}) =>
              set((_) => change(v), transient: transient),
          onCommit: c.endInteraction,
        );
    String seconds(double s) =>
        s < 1 ? "${(s * 1000).round()} ms" : "${s.toStringAsFixed(1)} s";
    var peaks = source == null ? null : c.waveformOf(source.assetId);
    return DeviceFrame(
      id: "audioClips",
      title: "Clips",
      help: "What the channel plays: its sounds on the timeline, one at a "
          "time here -- its level and its fades -- and the clips in its "
          "slots, opened in the clip editor.",
      skin: widget.skin,
      icon: Icons.graphic_eq,
      accent: audioColour,
      folded: widget.folded,
      onFold: widget.onFold,
      width: 360,
      height: widget.height,
      actions: [
        if (slots.isNotEmpty)
          IconButton(
            key: const ValueKey("audioClipsEdit"),
            tooltip: "Open the first clip in its slot",
            icon: const Icon(Icons.open_in_new),
            onPressed: () => c.openClipEditor(widget.channel, slots.first),
          ),
      ],
      summary: "${sounds.length} sound${sounds.length == 1 ? "" : "s"}"
          "${slots.isEmpty ? "" : " · ${slots.length} in slots"}",
      foldedBody: const SizedBox(),
      display: Stack(children: [
        Positioned.fill(
          child: CustomPaint(
            key: const ValueKey("audioClipsWave"),
            painter: _WavePainter(peaks,
                start: source == null || source.length <= 0
                    ? 0
                    : source.start / source.length,
                end: source == null || source.length <= 0
                    ? 1
                    : (source.end > 0 ? source.end : source.length) /
                        source.length,
                fadeIn: length <= 0 ? 0 : clip.fadeIn / length,
                fadeOut: length <= 0 ? 0 : clip.fadeOut / length,
                accent: audioColour,
                back: studio.display,
                line: studio.edge),
          ),
        ),
        Positioned(
          left: 6,
          top: 4,
          right: 6,
          child: Row(children: [
            Expanded(
              child: Text(
                  source == null
                      ? sound.element.name
                      : source.name.isEmpty
                          ? sound.element.name
                          : source.name,
                  key: const ValueKey("audioClipsName"),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: studio.text)),
            ),
            // One sound of several: the others, stepped through.
            if (sounds.length > 1) ...[
              _step(studio, "audioClipsPrev", Icons.chevron_left,
                  at > 0 ? () => setState(() => _shown = at - 1) : null),
              Text("${at + 1} of ${sounds.length}", style: muted),
              _step(
                  studio,
                  "audioClipsNext",
                  Icons.chevron_right,
                  at < sounds.length - 1
                      ? () => setState(() => _shown = at + 1)
                      : null),
            ],
          ]),
        ),
      ]),
      controls: (tier) => [
        knob(
            tier,
            "audioClipsLevel",
            "Level",
            "${(clip.volume * 100).round()}%",
            clip.volume,
            0.8,
            0,
            1,
            (v) => clip.copyWith(volume: v)),
        knob(tier, "audioClipsFadeIn", "Fade in", seconds(clip.fadeIn),
            clip.fadeIn, 0, 0, 4, (v) => clip.copyWith(fadeIn: v)),
        knob(tier, "audioClipsFadeOut", "Fade out", seconds(clip.fadeOut),
            clip.fadeOut, 0, 0, 8, (v) => clip.copyWith(fadeOut: v)),
        SizedBox(
          width: 150,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  SizedBox(width: 44, child: Text("Length", style: muted)),
                  Text(seconds(length), style: strong),
                ]),
                const SizedBox(height: 3),
                Row(children: [
                  SizedBox(width: 44, child: Text("Slots", style: muted)),
                  Flexible(
                    child: Text(
                        slots.isEmpty ? "none" : "${slots.length} clips",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: strong),
                  ),
                ]),
              ]),
        ),
      ],
      body: const SizedBox(),
    );
  }

  Widget _step(StudioColors studio, String key, IconData icon,
          VoidCallback? onTap) =>
      InkWell(
        key: ValueKey(key),
        onTap: onTap,
        child: Icon(icon,
            size: 15, color: onTap == null ? studio.muted : studio.text),
      );
}

/// _WavePainter draws a sound's shape across its file, the part played
/// bright and its fades as ramps over it.
class _WavePainter extends CustomPainter {
  final Float32List? peaks;
  final double start, end, fadeIn, fadeOut;
  final Color accent, back, line;
  _WavePainter(this.peaks,
      {required this.start,
      required this.end,
      required this.fadeIn,
      required this.fadeOut,
      required this.accent,
      required this.back,
      required this.line});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
        Paint()..color = back);
    var mid = size.height / 2 + 6;
    var half = math.max(1.0, size.height / 2 - 14);
    var p = peaks;
    if (p == null || p.isEmpty) {
      canvas.drawLine(
          Offset(4, mid), Offset(size.width - 4, mid), Paint()..color = line);
      return;
    }
    var w = size.width - 8;
    for (var x = 0; x < w; x++) {
      var i = (x / w * p.length).floor().clamp(0, p.length - 1);
      var t = x / w;
      var played = t >= start && t <= end;
      var h = p[i] * half;
      canvas.drawLine(
          Offset(4 + x.toDouble(), mid - h),
          Offset(4 + x.toDouble(), mid + h),
          Paint()
            ..color = accent.withValues(alpha: played ? 0.9 : 0.25)
            ..strokeWidth = 1);
    }
    // The fades: a line from the foot up, and back down at the end.
    var a = 4 + start * w, b = 4 + end * w;
    var span = b - a;
    var ramp = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.7)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    if (fadeIn > 0) {
      canvas.drawLine(
          Offset(a, mid + half), Offset(a + span * fadeIn, mid - half), ramp);
    }
    if (fadeOut > 0) {
      canvas.drawLine(
          Offset(b - span * fadeOut, mid - half), Offset(b, mid + half), ramp);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.peaks != peaks ||
      old.start != start ||
      old.end != end ||
      old.fadeIn != fadeIn ||
      old.fadeOut != fadeOut ||
      old.accent != accent;
}
