import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart'
    show dbToGain, gainToDb;
import 'package:bruig/plugin_system/canvas/model/session.dart';
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

/// AudioClipsDevice is an audio channel's Clips, as the prototype's: its
/// sounds -- on the timeline, and in its slots -- as a row of chips, one
/// picked; the picked one's shape over its knobs (Gain, and a slot clip's
/// Transpose; its fades) and a slot clip's Warp, with the Clip and Warp
/// pages of its screen. A slot's chip launches it, the one playing ringed.
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

/// _Pick is a chip of the card: a sound on the timeline, or a slot.
typedef _Pick = ({TimedLane? lane, int? row});

class _AudioClipsDeviceState extends State<AudioClipsDevice> {
  CanvasController get c => widget.controller;
  String get channel => widget.channel;

  /// _picked is the chip picked: a slot's row, or a timeline sound's index
  /// (as -1 - index); null for the playing slot, or else the first.
  int? _picked;

  /// _warpPage is whether the screen shows its warp markers.
  bool _warpPage = false;

  /// _tick redraws the playhead while something plays.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (mounted && (c.playing || c.clipPlaying(channel))) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  List<_Pick> _picks() {
    var lane = c.timelineChannels.where((l) => l.key == channel).firstOrNull;
    return [
      for (var l in lane?.lanes ?? const <TimedLane>[]) (lane: l, row: null),
      for (var (row, s) in (c.session.slots[channel] ?? const []).indexed)
        if (s != null && !s.midi) (lane: null, row: row),
    ];
  }

  int _keyOf(_Pick p, List<_Pick> all) =>
      p.row ?? -1 - all.where((q) => q.row == null).toList().indexOf(p);

  @override
  Widget build(BuildContext context) {
    var studio = MixerLook.of(context).studio;
    var picks = _picks();
    if (picks.isEmpty) return const SizedBox();
    var playingRow = [
      for (var p in picks)
        if (p.row case var r? when c.clipState(channel, r) == ClipState.playing)
          r
    ].firstOrNull;
    var pick = picks.firstWhere((p) => _keyOf(p, picks) == _picked,
        orElse: () => playingRow != null
            ? picks.firstWhere((p) => p.row == playingRow)
            : picks.first);
    var lane = pick.lane;
    var timed = lane?.clip;
    // A sound on the timeline is a clip as one in a slot is (Ken): the same
    // settings, kept on it.
    var timedSound = switch (lane?.element) {
      AudioElement a
          when a.instrument == null &&
              a.clip.playlist.isNotEmpty &&
              a.clip.playlist.first.assetId.isNotEmpty =>
        a,
      _ => null,
    };
    var slot = pick.row == null
        ? (timedSound == null ? null : c.timelineClipOf(timedSound))
        : c.session.at(channel, pick.row!);
    var sound = slot?.sound ?? timed?.playlist.firstOrNull;
    var spb = c.document.audio.secondsPerBeat;

    // Its settings, written to the chip picked.
    void setSlot(SessionClip Function(SessionClip clip) change,
        {bool transient = false}) {
      if (transient) c.beginInteraction();
      if (pick.row case var row?) {
        c.editSlotClip(channel, row, change, transient: transient);
      } else if (timedSound != null && (lane?.editable ?? false)) {
        c.editTimelineClip(timedSound, change, transient: transient);
      }
    }

    void setTimed(MediaClip Function(MediaClip clip) change,
        {bool transient = false}) {
      if (lane == null || !lane.editable || timed == null) return;
      if (transient) c.beginInteraction();
      c.setTimedClip(lane.element, change(timed), transient: transient);
      if (!transient) c.endInteraction();
    }

    var muted = TextStyle(fontSize: 10, color: studio.muted);
    Widget knob(
            DeviceTier tier,
            String key,
            String label,
            String text,
            double value,
            double initial,
            double min,
            double max,
            void Function(double v, {bool transient}) change) =>
        DeviceKnob(
          key: ValueKey(key),
          label: label,
          text: text,
          value: value,
          initial: initial,
          min: min,
          max: max,
          bipolar: min < 0 && max > 0,
          size: switch (tier) {
            DeviceTier.large => 46,
            DeviceTier.medium => 38,
            _ => 28,
          },
          accent: audioColour,
          ink: studio.text,
          onChanged: change,
          onCommit: c.endInteraction,
        );
    String seconds(double s) =>
        s < 1 ? "${(s * 1000).round()} ms" : "${s.toStringAsFixed(2)} s";
    String db(double v) => v <= -60
        ? "−∞ dB"
        : "${v >= 0 ? "" : "−"}${v.abs().toStringAsFixed(1)} dB";

    // Where its sound is played to now, seconds into its file.
    double? playhead;
    if (pick.row == null && slot != null && timed != null && sound != null) {
      // On the timeline: where the playhead is over it.
      if (c.playing) {
        var beat =
            (c.frame - timed.at) / c.document.frameRate / spb + slot.start;
        if (beat >= slot.start &&
            beat <= slot.loopEnd(c.document.audio.beatsPerBar)) {
          playhead = sound.start +
              (slot.warp ? slot.warpMap.sourceAt(beat) : beat * spb);
        }
      }
    } else if (slot != null && sound != null) {
      if (c.clipState(channel, pick.row!) == ClipState.playing) {
        var beat = c.clipAt(channel);
        if (beat != null) {
          playhead = sound.start +
              (slot.warp ? slot.warpMap.sourceAt(beat) : beat * spb);
        }
      }
    } else if (lane != null && timed != null && sound != null && c.playing) {
      var t = (c.frame - timed.at) / c.document.frameRate + sound.start;
      var end = sound.end > 0 ? sound.end : sound.length;
      if (t >= sound.start && t <= end) playhead = t;
    }
    var fileLength = sound == null || sound.length <= 0 ? 1.0 : sound.length;
    var fadeIn = slot?.fadeIn ?? timed?.fadeIn ?? 0;
    var fadeOut = slot?.fadeOut ?? timed?.fadeOut ?? 0;
    var span = sound == null
        ? 1.0
        : math.max(
            0.01, (sound.end > 0 ? sound.end : sound.length) - sound.start);
    var warpOn = slot != null && slot.warp;
    var slotCount = picks.where((p) => p.row != null).length;
    var playingCount = playingRow == null ? 0 : 1;

    Widget chip(_Pick p) {
      var k = _keyOf(p, picks);
      var on = identical(p, pick) || _keyOf(pick, picks) == k;
      var clip = p.row == null ? null : c.session.at(channel, p.row!);
      var state = p.row == null ? null : c.clipState(channel, p.row!);
      var playingNow = state == ClipState.playing || state == ClipState.queued;
      var name = clip != null
          ? (clip.name.isEmpty ? "Slot ${p.row! + 1}" : clip.name)
          : (p.lane!.clip.playlist.firstOrNull?.name.isNotEmpty ?? false)
              ? p.lane!.clip.playlist.first.name
              : p.lane!.element.name;
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Material(
          color: on ? audioColour.withValues(alpha: 0.35) : studio.raised,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(
                  color: playingNow
                      ? const Color(0xFF3FB950)
                      : on
                          ? audioColour
                          : studio.edge,
                  width: playingNow ? 1.6 : 1)),
          child: InkWell(
            key: ValueKey("audioClipsChip-$k"),
            borderRadius: BorderRadius.circular(4),
            onTap: () => setState(() => _picked = k),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (p.row != null)
                  // Launched, or stopped where it plays.
                  InkWell(
                    key: ValueKey("audioClipsLaunch-${p.row}"),
                    onTap: () {
                      setState(() => _picked = k);
                      playingNow
                          ? c.stopChannelClips(channel)
                          : c.launchClip(channel, p.row!);
                    },
                    child: Icon(
                        playingNow
                            ? Icons.radio_button_checked
                            : Icons.play_arrow,
                        size: 14,
                        color:
                            playingNow ? const Color(0xFF3FB950) : studio.text),
                  )
                else
                  Tooltip(
                    message: "On the timeline",
                    child: Icon(Icons.view_timeline_outlined,
                        size: 13, color: studio.muted),
                  ),
                const SizedBox(width: 3),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 96),
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: studio.text)),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    var peaks = sound == null ? null : c.waveformOf(sound.assetId);
    Widget page(String label, bool on, VoidCallback tap, String key) => InkWell(
          key: ValueKey(key),
          onTap: tap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: on ? studio.raised : studio.display.withValues(alpha: 0.6),
              border: Border.all(color: on ? studio.text : studio.edge),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 10, color: on ? studio.text : studio.muted)),
          ),
        );
    var showWarp = _warpPage && slot != null;
    return DeviceFrame(
      id: "audioClips",
      title: "Clips",
      help: "What the channel plays: its sounds on the timeline and in its "
          "slots, one picked at a time -- its gain, pitch and fades, and how "
          "a slot clip keeps to the tempo. ▶ on a slot launches it.",
      skin: widget.skin,
      icon: Icons.graphic_eq,
      accent: audioColour,
      folded: widget.folded,
      onFold: widget.onFold,
      width: 360,
      height: widget.height,
      actions: [
        if (slot != null)
          IconButton(
            key: const ValueKey("audioClipsEdit"),
            tooltip: "Open it in the clip editor",
            icon: const Icon(Icons.open_in_new),
            onPressed: () => c.openClipEditor(channel, pick.row ?? timelineRow),
          ),
      ],
      summary: "${picks.length} clip${picks.length == 1 ? "" : "s"}"
          "${slotCount == 0 ? "" : " · $playingCount playing"}",
      foldedBody: const SizedBox(),
      display: Stack(children: [
        Positioned.fill(
          child: CustomPaint(
            key: const ValueKey("audioClipsWave"),
            painter: _WavePainter(peaks,
                start: sound == null ? 0 : sound.start / fileLength,
                end: sound == null
                    ? 1
                    : (sound.end > 0 ? sound.end : sound.length) / fileLength,
                fadeIn: fadeIn / span,
                fadeOut: fadeOut / span,
                playhead: playhead == null ? null : playhead / fileLength,
                markers: showWarp
                    ? [
                        for (var m in slot.markers)
                          (sound!.start + m.seconds) / fileLength
                      ]
                    : const [],
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
                  sound == null || sound.name.isEmpty
                      ? (lane?.element.name ?? slot?.name ?? "")
                      : sound.name,
                  key: const ValueKey("audioClipsName"),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: studio.text)),
            ),
            if (slot != null) ...[
              page("Clip", !_warpPage, () => setState(() => _warpPage = false),
                  "audioClipsPageClip"),
              const SizedBox(width: 3),
              page("Warp", _warpPage, () => setState(() => _warpPage = true),
                  "audioClipsPageWarp"),
            ],
          ]),
        ),
        if (showWarp)
          Positioned(
            left: 6,
            right: 6,
            bottom: 4,
            child: Text(
                warpOn
                    ? "${slot.markers.length} warp marker"
                        "${slot.markers.length == 1 ? "" : "s"} · "
                        "${slot.warpMode.label}"
                    : "Warp off: it plays at its own speed",
                key: const ValueKey("audioClipsWarpReadout"),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: muted),
          ),
      ]),
      controls: (tier) => [
        // The chips: each sound, picked; a slot's launched. Short, its
        // knobs only.
        if (tier != DeviceTier.small)
          SizedBox(
            width: 344,
            child: SingleChildScrollView(
              key: const ValueKey("audioClipsChips"),
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (var p in picks) chip(p)]),
            ),
          ),
        if (slot != null) ...[
          knob(
              tier,
              "audioClipsGain",
              "Gain",
              db(slot.gain),
              slot.gain,
              0,
              -36,
              12,
              (v, {transient = false}) => setSlot(
                  (x) => x.copyWith(gain: (v * 10).roundToDouble() / 10),
                  transient: transient)),
          knob(
              tier,
              "audioClipsTranspose",
              "Transpose",
              "${slot.pitch > 0 ? "+" : slot.pitch < 0 ? "−" : ""}${slot.pitch.abs()} st",
              slot.pitch.toDouble(),
              0,
              -24,
              24,
              (v, {transient = false}) => setSlot(
                  (x) => x.copyWith(pitch: v.round()),
                  transient: transient)),
          knob(
              tier,
              "audioClipsFadeIn",
              "Fade in",
              seconds(slot.fadeIn),
              slot.fadeIn,
              0,
              0,
              4,
              (v, {transient = false}) =>
                  setSlot((x) => x.copyWith(fadeIn: v), transient: transient)),
          knob(
              tier,
              "audioClipsFadeOut",
              "Fade out",
              seconds(slot.fadeOut),
              slot.fadeOut,
              0,
              0,
              8,
              (v, {transient = false}) =>
                  setSlot((x) => x.copyWith(fadeOut: v), transient: transient)),
          if (tier != DeviceTier.small)
            SizedBox(
              width: 344,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Warp", style: muted),
                    const SizedBox(height: 3),
                    DeviceChoices(options: [
                      (
                        const ValueKey("audioClipsWarp-off"),
                        "Off",
                        !slot.warp,
                        () => setSlot((x) => x.copyWith(warp: false))
                      ),
                      for (var m in WarpMode.values)
                        (
                          ValueKey("audioClipsWarp-${m.name}"),
                          m.label,
                          slot.warp && slot.warpMode == m,
                          () => setSlot(
                              (x) => x.copyWith(warp: true, warpMode: m))
                        ),
                    ]),
                  ]),
            ),
        ] else if (timed != null) ...[
          knob(
              tier,
              "audioClipsGain",
              "Gain",
              db(gainToDb(timed.volume)),
              gainToDb(timed.volume).clamp(-60.0, 0.0),
              gainToDb(0.8),
              -60,
              0,
              (v, {transient = false}) => setTimed(
                  (x) => x.copyWith(volume: v <= -59.5 ? 0 : dbToGain(v)),
                  transient: transient)),
          knob(
              tier,
              "audioClipsFadeIn",
              "Fade in",
              seconds(timed.fadeIn),
              timed.fadeIn,
              0,
              0,
              4,
              (v, {transient = false}) =>
                  setTimed((x) => x.copyWith(fadeIn: v), transient: transient)),
          knob(
              tier,
              "audioClipsFadeOut",
              "Fade out",
              seconds(timed.fadeOut),
              timed.fadeOut,
              0,
              0,
              8,
              (v, {transient = false}) => setTimed(
                  (x) => x.copyWith(fadeOut: v),
                  transient: transient)),
        ],
      ],
      body: const SizedBox(),
    );
  }
}

/// _WavePainter draws a sound's shape across its file, the part played
/// bright and its fades as ramps over it.
class _WavePainter extends CustomPainter {
  final Float32List? peaks;
  final double start, end, fadeIn, fadeOut;

  /// playhead is where it is played to, and markers its warp markers, as
  /// parts of its file.
  final double? playhead;
  final List<double> markers;
  final Color accent, back, line;
  _WavePainter(this.peaks,
      {required this.start,
      required this.end,
      required this.fadeIn,
      required this.fadeOut,
      this.playhead,
      this.markers = const [],
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
    var w = size.width - 8;
    if (p == null || p.isEmpty) {
      canvas.drawLine(
          Offset(4, mid), Offset(size.width - 4, mid), Paint()..color = line);
      for (var m in markers) {
        canvas.drawLine(
            Offset(4 + m * w, 18),
            Offset(4 + m * w, size.height - 16),
            Paint()..color = const Color(0xFFE5A23C));
      }
      if (playhead case var at?) {
        canvas.drawLine(
            Offset(4 + at * w, 4),
            Offset(4 + at * w, size.height - 4),
            Paint()..color = const Color(0xFFFFFFFF));
      }
      return;
    }
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
    for (var m in markers) {
      var x = 4 + m * w;
      canvas.drawLine(
          Offset(x, 18),
          Offset(x, size.height - 16),
          Paint()
            ..color = const Color(0xFFE5A23C)
            ..strokeWidth = 1.5);
    }
    if (playhead case var at?) {
      var x = 4 + at * w;
      canvas.drawLine(
          Offset(x, 4),
          Offset(x, size.height - 4),
          Paint()
            ..color = const Color(0xFFFFFFFF)
            ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.peaks != peaks ||
      old.start != start ||
      old.end != end ||
      old.fadeIn != fadeIn ||
      old.fadeOut != fadeOut ||
      old.playhead != playhead ||
      old.markers.length != markers.length ||
      old.accent != accent;
}
