import 'dart:async';
import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/media/mix/pitch.dart'
    show AutoTune, snapNote;
import 'package:bruig/plugin_system/canvas/media/pitch_retune.dart'
    show driftTrack, pitchHeardAt;
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/midi_effects.dart'
    show scaleSteps;
import 'package:bruig/plugin_system/canvas/model/pitch_edit.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer_plugins.dart'
    show DeviceChoices;
import 'package:bruig/plugin_system/canvas/ui/pitch_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:flutter/material.dart';

// autotune_card.dart is the Auto-tune's card, as the prototype's: a screen
// with two pages -- Notes, the channel's recording as sung (red) and as
// corrected (purple) over the key's scale; Live, the note heard now and how
// far it is pulled -- over its knobs, its Key and Scale as rows of
// buttons, and Notes to MIDI at its foot.

/// sungInk and correctedInk are the pitch as sung and as corrected, here
/// and in the Pitch editor.
const sungInk = Color(0xFFE5484D);
const correctedInk = Color(0xFFA78BFA);

/// autoTuneLatencyMs is how far behind the Auto-tune puts what it hears.
double get autoTuneLatencyMs => AutoTune.latency * 2 / 48000 * 1000;

/// autoTuneSteps is [d]'s scale, as steps above its key: none for
/// Chromatic (every note).
List<int> autoTuneSteps(MixDevice d) {
  var scale = d.value("scale").round();
  return scale == 0
      ? const []
      : scaleSteps[(scale - 1).clamp(0, scaleSteps.length - 1)];
}

/// inAutoTuneScale is whether note [n] is in [d]'s key and scale.
bool inAutoTuneScale(MixDevice d, int n) {
  var steps = autoTuneSteps(d);
  return steps.isEmpty || steps.contains((n - d.value("key").round()) % 12);
}

/// correctedTrack is [track] -- a recording's pitch every 20ms -- as [d]
/// pulls it: each moment's note, a tenth of a second smoothed, onto the
/// scale, its vibrato kept by Vibrato, all of it by Amount. As the device
/// does live (see AutoTune), near enough to draw.
List<double?> correctedTrack(MixDevice d, List<double?> track) {
  var root = d.value("key").round();
  var steps = autoTuneSteps(d);
  var amount = d.value("amount");
  var vibrato = d.value("vibrato");
  var out = List<double?>.filled(track.length, null);
  double? slow;
  for (var (i, m) in track.indexed) {
    if (m == null) {
      slow = null;
      continue;
    }
    slow = slow == null ? m : slow + (m - slow) * 0.2;
    var to = snapNote(slow, root, steps) + vibrato * (m - slow);
    out[i] = m + (to - m) * amount;
  }
  return out;
}

/// AutoTuneScreen is the Auto-tune's screen: Notes or Live.
class AutoTuneScreen extends StatefulWidget {
  final CanvasController controller;
  final String owner;
  final MixDevice device;
  final int index;
  const AutoTuneScreen(
      {required this.controller,
      required this.owner,
      required this.device,
      required this.index,
      super.key});

  @override
  State<AutoTuneScreen> createState() => _AutoTuneScreenState();
}

class _AutoTuneScreenState extends State<AutoTuneScreen> {
  CanvasController get c => widget.controller;

  /// _live is whether Live is shown, or null for the page that suits: Notes
  /// where there is a recording, Live where not.
  bool? _live;

  /// _poll reads the pitch heard while Live is shown and something plays.
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      if (c.playing || c.sessionActive || c.keysHeld.value > 0) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var s = look.studio;
    var recorded = c.pitchSourceOf(widget.owner) != null;
    var live = _live ?? !recorded;
    Widget tab(String label, bool on, VoidCallback tap, String key) => InkWell(
          key: ValueKey("$key-${widget.index}"),
          onTap: tap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: on ? s.raised : s.display.withValues(alpha: 0.6),
              border: Border.all(color: on ? s.text : s.edge),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(label,
                style: TextStyle(fontSize: 10, color: on ? s.text : s.muted)),
          ),
        );
    return Stack(children: [
      Positioned.fill(
        child: ValueListenableBuilder<int>(
          valueListenable: pitchTracksRead,
          builder: (context, _, __) =>
              live ? _livePage(s) : _notesPage(context, s),
        ),
      ),
      Positioned(
        top: 5,
        right: 5,
        child: Row(children: [
          tab("Notes", !live, () => setState(() => _live = false),
              "autoTuneNotes"),
          const SizedBox(width: 3),
          tab("Live", live, () => setState(() => _live = true), "autoTuneLive"),
        ]),
      ),
    ]);
  }

  Widget _caption(StudioColors s, String text) => Positioned(
        left: 18,
        right: 6,
        bottom: 4,
        child: Text(text,
            key: ValueKey("autoTuneCaption-${widget.index}"),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 10,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: s.muted.withValues(alpha: 0.9))),
      );

  Widget _notesPage(BuildContext context, StudioColors s) {
    var key = widget.owner;
    var source = c.pitchSourceOf(key);
    var track = source == null ? null : c.pitchTrackOf(key);
    String caption;
    List<double?>? corrected;
    var edit = c.pitchEditOf(key);
    if (source == null) {
      caption = "No recording here: Live shows what is sung";
    } else if (track == null) {
      caption = c.pitchUnreadable(key)
          ? "Its recording could not be read"
          : "Reading its pitch…";
    } else {
      // What is heard: the notes as moved in the Pitch editor, then pulled
      // onto the scale.
      var moved = edit == null ? track : editedTrack(edit, track);
      corrected = correctedTrack(widget.device, moved);
      var notes = edit?.notes ?? findNotes(track);
      var changed = 0;
      for (var n in notes) {
        var i = ((n.start + n.end) / 2 / 0.02).round();
        if (i < 0 || i >= track.length) continue;
        var a = track[i], b = corrected[i];
        if (a != null && b != null && (a - b).abs() > 0.1) changed++;
      }
      caption = "$changed note${changed == 1 ? "" : "s"} corrected · "
          "open for the notes";
    }
    return Stack(children: [
      Positioned.fill(
        child: CustomPaint(
          key: ValueKey("autoTuneNotesView-${widget.index}"),
          painter: _NotesPainter(
            device: widget.device,
            track: track,
            corrected: corrected,
            from: source?.start ?? 0,
            to: source == null
                ? 1
                : (source.end > 0 ? source.end : source.length),
            playhead: c.pitchPlayhead(key),
            s: s,
          ),
        ),
      ),
      _caption(s, caption),
    ]);
  }

  Widget _livePage(StudioColors s) {
    var heard = c.pitch(widget.owner);
    var hz = heard?.hz;
    String big, caption;
    double? sungCents, correctedCents;
    if (hz == null || hz < 20) {
      big = "–";
      caption = "playing shows the pitch";
    } else {
      var midi = 69 + 12 * math.log(hz / 440) / math.ln2;
      var d = widget.device;
      var to = snapNote(midi, d.value("key").round(), autoTuneSteps(d));
      var heardAs = midi + (to - midi) * d.value("amount");
      big = noteName(to.round());
      sungCents = (midi - to) * 100;
      correctedCents = (heardAs - to) * 100;
      String ct(double v) => "${v >= 0 ? "+" : "−"}${v.abs().round()} ct";
      caption = "sung ${ct(sungCents)} · corrected ${ct(correctedCents)}";
    }
    return Stack(children: [
      Positioned.fill(
        child: CustomPaint(
          painter: _CentsPainter(sungCents, correctedCents, s),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        top: 14,
        child: Text(big,
            key: ValueKey("autoTuneHeard-${widget.index}"),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 30, fontWeight: FontWeight.w600, color: s.text)),
      ),
      _caption(s, caption),
    ]);
  }
}

/// editedTrack is [track] as [edit]'s notes move it, as the recording is
/// made again (see pitchHeardAt).
List<double?> editedTrack(PitchEdit edit, List<double?> track) {
  var out = [...track];
  var slow = driftTrack(track);
  for (var (k, n) in edit.notes.indexed) {
    if (!n.edited) continue;
    var before = k > 0 && n.start - edit.notes[k - 1].end < 0.3
        ? edit.notes[k - 1].target
        : null;
    var a = (math.min(n.start, n.heardStart) / 0.02).floor();
    var b = (math.max(n.end, n.heardEnd) / 0.02).ceil();
    for (var i = math.max(0, a); i < math.min(b, out.length); i++) {
      // Heard from where in the original: moved by Quantise timing.
      var from = n.sourceAt(i * 0.02);
      if (from == null) {
        out[i] = null;
        continue;
      }
      var j = (from / 0.02).round().clamp(0, track.length - 1);
      var m = track[j];
      if (m == null) {
        out[i] = null;
        continue;
      }
      out[i] = pitchHeardAt(n, from, m, slow[j] ?? m, before: before);
    }
  }
  return out;
}

class _NotesPainter extends CustomPainter {
  final MixDevice device;
  final List<double?>? track, corrected;
  final double from, to;
  final double? playhead;
  final StudioColors s;
  _NotesPainter(
      {required this.device,
      required this.track,
      required this.corrected,
      required this.from,
      required this.to,
      required this.playhead,
      required this.s});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = s.display);
    var t = track;
    // The notes sung, an octave either side of their middle where there are
    // none to go by.
    var lo = 55.0, hi = 72.0;
    if (t != null) {
      var heard = [
        for (var m in t)
          if (m != null) m
      ];
      if (heard.isNotEmpty) {
        lo = heard.reduce(math.min) - 2;
        hi = heard.reduce(math.max) + 2;
      }
    }
    if (hi - lo < 12) {
      var mid = (hi + lo) / 2;
      lo = mid - 6;
      hi = mid + 6;
    }
    const keyW = 12.0, top = 22.0, bottom = 18.0;
    var h = size.height - top - bottom;
    var w = size.width - keyW;
    double yOf(double m) => top + (hi - m) / (hi - lo) * h;
    var row = h / (hi - lo);
    // The scale's rows, shaded; the key's own darker.
    for (var n = lo.floor(); n <= hi.ceil(); n++) {
      var y = yOf(n + 0.5);
      if (inAutoTuneScale(device, n)) {
        var root = (n - device.value("key").round()) % 12 == 0;
        canvas.drawRect(
            Rect.fromLTWH(keyW, y, w, row),
            Paint()
              ..color = correctedInk.withValues(alpha: root ? 0.13 : 0.06));
        // And its mark on the strip of keys.
        canvas.drawRect(Rect.fromLTWH(2, y + row / 2 - 0.75, keyW - 5, 1.5),
            Paint()..color = s.muted.withValues(alpha: root ? 0.9 : 0.5));
      }
    }
    canvas.drawLine(
        Offset(keyW, top), Offset(keyW, top + h), Paint()..color = s.edge);
    if (t == null || t.isEmpty) return;
    var span = math.max(0.02, to - from);
    double xOf(int i) => keyW + (i * 0.02 - from) / span * w;
    void line(List<double?> m, Color colour, double width) {
      var p = Paint()
        ..color = colour
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      var path = Path();
      var down = false;
      for (var (i, v) in m.indexed) {
        var x = xOf(i);
        if (v == null || x < keyW || x > size.width) {
          down = false;
          continue;
        }
        if (down) {
          path.lineTo(x, yOf(v));
        } else {
          path.moveTo(x, yOf(v));
          down = true;
        }
      }
      canvas.drawPath(path, p);
    }

    if (corrected case var c?) line(c, correctedInk, 2.2);
    line(t, sungInk.withValues(alpha: 0.9), 1.0);
    if (playhead case var at?) {
      var x = keyW + (at - from) / span * w;
      canvas.drawLine(Offset(x, top - 6), Offset(x, top + h),
          Paint()..color = s.text.withValues(alpha: 0.85));
    }
  }

  @override
  bool shouldRepaint(_NotesPainter old) =>
      old.track != track ||
      old.corrected != corrected ||
      old.playhead != playhead ||
      old.device != device ||
      old.from != from ||
      old.to != to;
}

/// _CentsPainter is Live's bar: a hundred cents either way of the note,
/// the pitch sung a red dot on it and as corrected a purple one.
class _CentsPainter extends CustomPainter {
  final double? sung, corrected;
  final StudioColors s;
  _CentsPainter(this.sung, this.corrected, this.s);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = s.display);
    var y = size.height * 0.62;
    var left = 20.0, right = size.width - 20;
    canvas.drawLine(
        Offset(left, y),
        Offset(right, y),
        Paint()
          ..color = s.edge
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    var mid = (left + right) / 2;
    for (var k = -2; k <= 2; k++) {
      var x = mid + k / 2 * (right - left) / 2;
      canvas.drawLine(Offset(x, y - (k == 0 ? 9 : 5)),
          Offset(x, y + (k == 0 ? 9 : 5)), Paint()..color = s.muted);
    }
    double xOf(double cents) =>
        mid + cents.clamp(-100.0, 100.0) / 100 * (right - left) / 2;
    if (sung case var v?) {
      canvas.drawCircle(Offset(xOf(v), y), 6, Paint()..color = sungInk);
    }
    if (corrected case var v?) {
      canvas.drawCircle(Offset(xOf(v), y), 5, Paint()..color = correctedInk);
    }
  }

  @override
  bool shouldRepaint(_CentsPainter old) =>
      old.sung != sung || old.corrected != corrected;
}

/// AutoTuneKey is the Auto-tune's key, a button for each of the twelve.
class AutoTuneKey extends StatelessWidget {
  final MixDevice device;
  final int index;
  final ValueChanged<int> onPick;
  final double width;
  const AutoTuneKey(
      {required this.device,
      required this.index,
      required this.onPick,
      required this.width,
      super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var key = device.value("key").round();
    var names = device.kind.param("key").choices;
    return SizedBox(
      width: width,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Key", style: TextStyle(fontSize: 10, color: look.studio.muted)),
        const SizedBox(height: 3),
        DeviceChoices(options: [
          for (var (i, n) in names.indexed)
            (ValueKey("autoTuneKey-$index-$i"), n, i == key, () => onPick(i)),
        ]),
      ]),
    );
  }
}

/// AutoTuneScale is its scale: Major, Minor and Chromatic as buttons, as
/// the prototype's, and the others from a list behind the fourth.
class AutoTuneScale extends StatelessWidget {
  final MixDevice device;
  final int index;
  final ValueChanged<int> onPick;
  final double width;
  const AutoTuneScale(
      {required this.device,
      required this.index,
      required this.onPick,
      required this.width,
      super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var s = look.studio;
    var scale = device.value("scale").round();
    var names = device.kind.param("scale").choices;
    // Chromatic is 0, Major 1, Minor 2; the rest more.
    var other = scale >= 3;
    return SizedBox(
      width: width,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("Scale", style: TextStyle(fontSize: 10, color: s.muted)),
        const SizedBox(height: 3),
        Row(children: [
          Expanded(
            flex: 3,
            child: DeviceChoices(options: [
              for (var i in const [1, 2, 0])
                (
                  ValueKey("autoTuneScale-$index-$i"),
                  names[i],
                  i == scale,
                  () => onPick(i)
                ),
            ]),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: other ? look.colors.primary : null,
                border: Border.all(color: s.edge),
                borderRadius: BorderRadius.circular(5),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  key: ValueKey("autoTuneScaleMore-$index"),
                  isExpanded: true,
                  isDense: true,
                  value: other ? scale : null,
                  hint: Text("More",
                      style: TextStyle(fontSize: 10, color: s.muted)),
                  iconSize: 14,
                  iconEnabledColor: other ? look.colors.onPrimary : s.muted,
                  dropdownColor: look.colors.surfaceContainerHigh,
                  selectedItemBuilder: (_) => [
                    for (var i = 3; i < names.length; i++)
                      Text(names[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10, color: look.colors.onPrimary)),
                  ],
                  items: [
                    for (var i = 3; i < names.length; i++)
                      DropdownMenuItem(
                          value: i,
                          child: Text(names[i],
                              style: TextStyle(
                                  fontSize: 11, color: look.colors.onSurface))),
                  ],
                  onChanged: (v) {
                    if (v != null) onPick(v);
                  },
                ),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// AutoTuneKeyScaleRow is its key and scale as two lists on one row: where
/// the card is shorter, or its text larger, than the rows of buttons fit.
class AutoTuneKeyScaleRow extends StatelessWidget {
  final MixDevice device;
  final int index;
  final void Function(String param, int value) onPick;
  final double width;
  const AutoTuneKeyScaleRow(
      {required this.device,
      required this.index,
      required this.onPick,
      required this.width,
      super.key});

  @override
  Widget build(BuildContext context) {
    var look = MixerLook.of(context);
    var s = look.studio;
    Widget list(String label, String param, String k) {
      var names = device.kind.param(param).choices;
      var at = device.value(param).round().clamp(0, names.length - 1);
      return Expanded(
        child: Row(children: [
          Text(label, style: TextStyle(fontSize: 10, color: s.muted)),
          const SizedBox(width: 5),
          Expanded(
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                border: Border.all(color: s.edge),
                borderRadius: BorderRadius.circular(5),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  key: ValueKey("$k-$index"),
                  isExpanded: true,
                  isDense: true,
                  value: at,
                  iconSize: 14,
                  iconEnabledColor: s.muted,
                  dropdownColor: look.colors.surfaceContainerHigh,
                  selectedItemBuilder: (_) => [
                    for (var n in names)
                      Text(n,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, color: s.text)),
                  ],
                  items: [
                    for (var (i, n) in names.indexed)
                      DropdownMenuItem(
                          value: i,
                          child: Text(n,
                              style: TextStyle(
                                  fontSize: 11, color: look.colors.onSurface))),
                  ],
                  onChanged: (v) {
                    if (v != null) onPick(param, v);
                  },
                ),
              ),
            ),
          ),
        ]),
      );
    }

    return SizedBox(
      width: width,
      child: Row(children: [
        list("Key", "key", "autoTuneKeyList"),
        const SizedBox(width: 10),
        list("Scale", "scale", "autoTuneScaleList"),
      ]),
    );
  }
}
