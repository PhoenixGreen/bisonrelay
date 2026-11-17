import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/render/paint_util.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/motion/motion_editing.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/asset_elements.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/automation_lanes.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/video_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart'
    show isMidiId;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/model/audio_settings.dart'
    show sectionColors;
import 'package:bruig/plugin_system/canvas/ui/motion/motion_lanes.dart'
    show MotionLanes, motionPlacementsIn;
import 'package:bruig/plugin_system/canvas/ui/timeline/canvas_rows.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/row_header.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer/slot_face.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/scene_strip.dart'
    show sceneBoxHeight, sceneStripHeight, sceneStripLead;
import 'package:bruig/plugin_system/canvas/ui/sound/element_sound.dart'
    show soundOwnerOf;
import 'package:bruig/plugin_system/canvas/model/session.dart'
    show SessionSlotDrag;
import 'package:bruig/plugin_system/canvas/ui/mixer/canvas_mixer.dart'
    show DbReading;
import 'package:bruig/plugin_system/canvas/ui/picking/media_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/timeline_view.dart';
import 'package:bruig/plugin_system/canvas/ui/mixer/slots_window.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/cue_launches.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/ui/timeline/timeline_columns.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'canvas_channels_gestures.dart';
part 'canvas_channels_rows.dart';

// canvas_channels.dart is the sound on the timeline: a lane for each
// channel, on the same frames as the rows above. An empty lane always sits
// at the bottom: a sound dropped there, or chosen by clicking it, starts a
// channel; a channel left empty is gone. Each sound is a bar, dragged to
// move it (onto another lane too), by its ends to trim it, by its top
// corners to fade it, by its line to set its volume; the knife cuts it.

/// channelsLaneHeight is a lane as it starts, and the shortest it goes to
/// while its strip keeps everything on one line.
const double channelsLaneHeight = 32;

/// laneSizeHeights are the heights the timeline's channel-height button
/// steps every channel through: the least, the height at which a strip
/// spreads over two lines (its name and lock, then S and M), and twice that.
const laneSizeHeights = [channelsLaneHeight, _tall, _tall * 2];

/// _laneMin and _laneMax bound a lane dragged taller or shorter.
const double _laneMin = 26;
const double _laneMax = 180;

/// _tall is how tall a lane is before its strip spreads over two lines and
/// shows the channel's name.
const double _tall = 52;

/// _waveformFrom is how tall a lane has to be before it shows its waveform.
const double _waveformFrom = 46;

const double _edgeGrab = 7;

/// _fadeGrab is how far down from the top of a bar its fade handles reach.
const double _fadeGrab = 10;

/// _volumeGrab is how near the volume line a press has to be to take it.
const double _volumeGrab = 4;

/// _snapReach is how near, on screen, a dragged edge has to come to a second
/// or the playhead to land on it.
const double _snapReach = 8;

/// channelColour is the edge of a channel's strip: green for sound, yellow
/// for the sound of a video.
Color channelColour(bool video) =>
    video ? const Color(0xFFD9A93A) : const Color(0xFF3AA66A);

class CanvasChannels extends StatefulWidget {
  final CanvasController controller;

  /// view is the frames on screen: the rows', so a sound and a key on the
  /// same frame line up. See TimelineView.
  final TimelineView view;

  /// motionRows is whether the elements' rows are here -- each with its own
  /// sound's channel under it -- above the canvas's other channels.
  final bool motionRows;

  /// leading is rows above the channels that scroll with them: a drawing's
  /// shapes, where they are shown. See VectorShapeLanes.
  final Widget? leading;

  /// scenesLane is the scenes' strip, while every scene plays: the first
  /// row, "Scenes", with the transitions' sounds as its sound under it.
  final Widget? scenesLane;

  const CanvasChannels(
      {this.scenesLane,
      required this.controller,
      required this.view,
      this.leading,
      this.motionRows = false,
      super.key});

  /// hint is what the empty lane says after its name.
  static const String hint =
      "+ for an audio or a MIDI channel, or drop a sound or video here";

  @override
  State<CanvasChannels> createState() => _CanvasChannelsState();
}

enum _Grip { move, start, end, fadeIn, fadeOut, volume }

// ---- canvas_channels_gestures.dart --------------------------------------

class _CanvasChannelsState extends State<CanvasChannels> {
  // The parts are extensions, and call setState: overridden so the call
  // is this class's own, not State's protected one.
  @override
  void setState(VoidCallback fn) => super.setState(fn);

  /// _heard is the controller less its frames of play: nothing here moves
  /// with the playhead but the line through a slots-only lane, which repaints
  /// on its own (_InteractiveLanePainter), and the view, which the timeline
  /// hands down, building this again when it moves. Heard whole, every lane
  /// was built and painted again every frame of play.
  late _NotPlayhead _heard = _NotPlayhead(widget.controller);

  @override
  void didUpdateWidget(CanvasChannels old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      _heard.dispose();
      _heard = _NotPlayhead(widget.controller);
    }
  }

  @override
  void dispose() {
    _heard.dispose();
    super.dispose();
  }

  // What a press took hold of, and the clip as it was when it did.
  TimedLane? _held;
  _Grip _grip = _Grip.move;
  MediaClip? _was;
  bool _dragging = false;

  /// _pressedX and _pressedY are where the press was, on screen. A drag is
  /// measured from them rather than by adding up its steps, because the
  /// stretch before a drag is recognised never arrives as a step.
  double _pressedX = 0, _pressedY = 0;

  /// _over is the lane a sound being dragged is over, by channel key --
  /// [_newLane] for the empty one -- while it is off its own.
  String? _over;
  static const String _newLane = "\u0000new";

  /// _laneKeys find each lane on screen, for which one a drag is over.
  final Map<String, GlobalKey> _laneKeys = {};

  /// _gripFrom and _gripHeight are where a lane's bottom edge was taken hold
  /// of and how tall the lane was then. Measured from there rather than by
  /// adding up the drag's steps: the first few pixels never arrive as one.
  double _gripFrom = 0, _gripHeight = channelsLaneHeight;

  /// _wasRun is where the held clip started on the run's clock when it was
  /// taken hold of: what a move is measured from, so it can cross into
  /// another scene. Null for one on the backdrop, which moves as it did.
  int? _wasRun;

  /// _cursors is the pointer each lane shows, from what is under it.
  final Map<String, MouseCursor> _cursors = {};

  // The box dragged across empty lanes: where it began and has got to, on
  // screen, and what was picked before it when Shift was held.
  Offset? _boxFrom, _boxTo;
  Set<String> _boxBase = {};
  Set<String> _boxChannels = {};
  final GlobalKey _stack = GlobalKey();

  /// _boxMotion are the motion clips picked before the box, Shift held.
  Set<(String, String)> _boxMotion = {};

  /// The sound last pressed and when, for a double-click opening it.
  String? _tappedClip;
  DateTime _tappedAt = DateTime(0);

  /// _group is the other sounds picked, as they were and where each started
  /// on the run's clock, while one of them is dragged along -- see _drag.
  Map<String, (CanvasElement, MediaClip, int?)> _group = const {};

  /// _links are the motion clips linked to the sound being moved, and where
  /// each started: by its element's id, its own, and its start in seconds.
  List<(String, String, double)> _links = const [];

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return ListenableBuilder(
      listenable: _heard,
      builder: (context, _) {
        var show = controller.timelineShow;
        // The rows every panel shows (see canvas_rows.dart): each element
        // with its own sound, then the sounds that are nobody's. Without the
        // elements' rows, every channel is listed on its own.
        var rows = canvasRowsOf(controller);
        var grouped = widget.motionRows
            ? [
                for (var r in rows)
                  if (r.element case var e?) e
              ]
            : const <CanvasElement>[];
        var owned = <String, List<TimelineChannel>>{
          if (widget.motionRows)
            for (var r in rows)
              if (r.element case var e?) e.id: r.channels,
        };
        // The transitions' sounds: the Scenes row's own, where it is.
        var transitions = widget.scenesLane == null
            ? const <TimelineChannel>[]
            : [
                for (var r in rows)
                  if (r.transitions) ...r.channels
              ];
        // The others: the ones whose strips move among themselves.
        var channels = _withMoving([
          for (var ch in widget.motionRows
              ? [
                  for (var r in rows)
                    if (r.element == null) ...r.channels
                ]
              : controller.timelineChannels)
            if (!transitions.contains(ch)) ch
        ]);
        // The All group's: on the master canvas, there in every scene.
        var everyScene = {
          for (var r in rows)
            if (r.group == RowGroup.all)
              for (var ch in r.channels) ch.key
        };
        var inAll = [
          for (var ch in channels)
            if (everyScene.contains(ch.key)) ch
        ];
        var width = controller.headerWidth;
        return Stack(key: _stack, children: [
          ListView(
            padding: EdgeInsets.zero,
            children: [
              // The scenes, first: their strip with its header, and the
              // transitions' sounds under it as the same row, from M up.
              if (widget.scenesLane case var lane?) ...[
                _row("scenes", sceneStripHeight, width,
                    header: _scenesHeader(theme, width, transitions),
                    lane: Padding(
                      padding: const EdgeInsets.only(top: sceneStripLead),
                      child: Align(
                          alignment: Alignment.topLeft,
                          child: SizedBox(height: sceneBoxHeight, child: lane)),
                    )),
                // Folded (at S, unless its arrow opened it), the strip
                // alone.
                if (show != TimelineShow.animation &&
                    !controller.rowFolded("scenes"))
                  for (var channel in transitions)
                    ..._channelRows(channel, width, theme, channels,
                        movable: false, owned: true, accent: sceneColour),
              ],
              if (widget.leading case var leading?) leading,
              // Each element's rows, with its own sound's channel under
              // them; then the canvas's other channels.
              for (var (k, e) in grouped.indexed) ...[
                if (show != TimelineShow.sound)
                  MotionLanes(
                      controller: controller,
                      view: _view,
                      only: e.id,
                      alt: k.isOdd,
                      onBoxStart: _boxStart,
                      onBox: _box,
                      onBoxEnd: _boxEnd),
                // At channel height S, an element's row is its motion alone;
                // its sound from M up, or opened by its arrow. Not a video's:
                // its channel is the video itself, its clip on the timeline,
                // which must show at S too.
                if (show != TimelineShow.animation &&
                    (controller.laneSize > 0 ||
                        !controller.rowFolded(e.id) ||
                        e is VideoElement ||
                        show == TimelineShow.sound))
                  for (var channel in owned[e.id] ?? const <TimelineChannel>[])
                    ..._channelRows(channel, width, theme, channels,
                        movable: false, owned: true, alt: k.isOdd),
              ],
              if (show != TimelineShow.animation) ...[
                for (var (j, channel) in channels.indexed)
                  if (!everyScene.contains(channel.key))
                    ..._channelRows(channel, width, theme, channels,
                        alt: (grouped.length + j).isOdd),
                // The All group, last, under a heading that folds it away.
                if (inAll.isNotEmpty) ...[
                  _allHeading(theme, inAll.length, width),
                  if (!controller.allFolded)
                    for (var channel in inAll)
                      ..._channelRows(channel, width, theme, channels,
                          all: true),
                ],
              ],
              _row(_newLane, channelsLaneHeight, width,
                  header: _EmptyHeader(
                      width: width,
                      name: "Add a channel",
                      theme: theme,
                      onAudio: () async {
                        var chosen = await pickCanvasAudio(context, controller);
                        if (chosen != null && mounted) {
                          _addAt(chosen, controller.frame, null);
                        }
                      },
                      onMidi: () => controller.addMidiChannel(),
                      onEmptyAudio: () => controller.addEmptyAudioChannel(),
                      onEmptyMidi: () =>
                          controller.addMidiChannel(onCanvas: false)),
                  lane: _emptyLane(theme)),
            ],
          ),
          // The box being dragged across the lanes.
          if (_boxFrom != null && _boxTo != null) _boxOverlay(theme),
        ]);
      },
    );
  }

  // ---- canvas_channels_rows.dart ------------------------------------------

  /// _moving is the channel whose strip is being dragged up or down, and
  /// _moveTo where it would go. The list is shown in that order while it is
  /// dragged (see _withMoving), so the channel is seen going there.
  String? _moving;
  int? _moveTo;

  /// _rowsAtStart is the middle of each other channel's row when the drag
  /// began, measured once: the rows move as the list is reordered, and
  /// measuring them as they moved would have the channel chase itself.
  List<double> _rowsAtStart = const [];
}

/// _unityShare is how far down a clip nought decibels sits: a little above
/// the middle, so a sound that is too quiet has room to be turned up.
const double _unityShare = 0.45;

/// _mostDb is as far up as a sound goes: six decibels, twice as loud, which
/// is generally as much as turning one up will stand.
const double _mostDb = 6.0206;

/// _volumeShare is how far down the clip [volume]'s line is, nought at the
/// top to one at the bottom: decibels above nought -- up to six at the top --
/// and a straight fade to silence below.
double _volumeShare(double volume) {
  if (volume >= 1) {
    var db = math.min(_mostDb, 20 * math.log(volume) / math.ln10);
    return _unityShare * (1 - db / _mostDb);
  }
  return _unityShare + (1 - volume.clamp(0.0, 1.0)) * (1 - _unityShare);
}

/// _volumeAt is the volume whose line is [share] of the way down.
double _volumeAt(double share) {
  var p = share.clamp(0.0, 1.0);
  if (p <= _unityShare) {
    var db = _mostDb * (1 - p / _unityShare);
    return math.pow(10, db / 20).toDouble();
  }
  return 1 - (p - _unityShare) / (1 - _unityShare);
}

/// _shapeOf is the stored sound whose waveform a clip's file is drawn with:
/// the file itself for a sound, its soundtrack for a video.
String _shapeOf(TimedLane lane, MediaSource source) =>
    lane.element is VideoElement ? source.soundId : source.assetId;

/// _volumeY is where a clip's volume line sits in a lane [height] tall.
double _volumeY(double volume, double height) {
  // Inset from the clip's edges, so the line is never the edge itself.
  var top = 3.0 + 5, bottom = height - 3 - 5;
  return top + _volumeShare(volume) * (bottom - top);
}

/// gainToDb is a level as decibels, -90 standing for silence.
double gainToDb(double gain) =>
    gain <= 0.0000316 ? -90 : 20 * math.log(gain) / math.ln10;

/// _paintSeconds draws a faint line at every second across [size], as the
/// strip above ticks them: the lanes and the strip are one timeline. In each
/// lane and not under the empty one, so the lines stop where the channels do.
void _paintSeconds(Canvas canvas, Size size, TimelineView view, int frameRate,
    ColorScheme colors) {
  var w = size.width;
  var rate = math.max(1, frameRate);
  if (w / view.span * rate <= 8) return;
  var grid = Paint()
    ..color = colors.outlineVariant.withValues(alpha: 0.35)
    ..strokeWidth = 1;
  var s = (view.first / rate).ceil();
  for (var f = s * rate; f <= view.first + view.span; f += rate) {
    var x = view.xOf(f, w);
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
  }
}

/// paintPastScene marks the frames from [scene] on as outside the scene:
/// shaded and hatched, with a line where the scene ends. The timeline runs on
/// past the scene where a clip does -- see CanvasController.timelineReach --
/// and what is drawn out there is not played.
void paintPastScene(Canvas canvas, Size size, TimelineView view, int scene,
        ColorScheme colors) =>
    paintOutsideScene(canvas, size, view, null, scene, colors);

/// paintOutsideScene shades and hatches everything before [from] and from
/// [to] on -- either left open with null -- with a line at each edge: the
/// frames a lane's clips are not played in, so a clip running on past its
/// scene does not look as if it plays in the next.
void paintOutsideScene(Canvas canvas, Size size, TimelineView view, int? from,
    int? to, ColorScheme colors) {
  var hatch = Paint()
    ..color = colors.onSurfaceVariant.withValues(alpha: 0.18)
    ..strokeWidth = 1;
  var edge = Paint()
    ..color = colors.onSurfaceVariant.withValues(alpha: 0.6)
    ..strokeWidth = 1;
  void shade(double a, double b, double edgeAt) {
    a = math.max(0.0, a);
    b = math.min(size.width, b);
    if (b <= a) return;
    var out = Rect.fromLTRB(a, 0, b, size.height);
    canvas.save();
    canvas.clipRect(out);
    canvas.drawRect(out, Paint()..color = const Color(0x66000000));
    // Pinned to the frames rather than the screen, so the hatching moves
    // with the timeline as it scrolls: the first line on the same 8 px step
    // as the edge that reaches the shaded part's left end.
    var start = edgeAt - 8 * ((edgeAt - (a - size.height)) / 8).ceilToDouble();
    for (var x = start; x < b; x += 8) {
      canvas.drawLine(
          Offset(x, size.height), Offset(x + size.height, 0), hatch);
    }
    canvas.restore();
    if (edgeAt >= 0 && edgeAt <= size.width) {
      canvas.drawLine(Offset(edgeAt, 0), Offset(edgeAt, size.height), edge);
    }
  }

  if (from != null) {
    var x = view.xOf(from, size.width);
    shade(0, x, x);
  }
  if (to != null) {
    var x = view.xOf(to, size.width);
    shade(x, size.width, x);
  }
}

class _LanePainter extends CustomPainter {
  /// linked are the sounds a motion clip moves with: each marked so.
  final Set<String> linked;

  /// own is the colour of the element whose own sound this is, which its
  /// clips are drawn toward; null for any other.
  final Color? own;
  final TimelineChannel channel;
  final List<({double from, double to, List<double> cuts})> spans;
  final TimelineView view;
  final int frame;
  final int frameRate;
  final ColorScheme colors;
  final Set<String> selected;
  final bool chosenChannel;
  final String? held;
  final bool showVolume;
  final bool target;
  final Map<String, Float32List?> shapes;

  /// sceneFrom and sceneTo are the frames, in this lane's view, its clips
  /// are played in: their scene's, or the whole run's for the master's.
  /// Outside them is shaded. Null is open on that side.
  final int? sceneFrom;
  final int? sceneTo;

  /// onMaster is whether the master is being edited: seen from a scene, a
  /// clip of the master's says so.
  final bool onMaster;

  _LanePainter({
    this.linked = const {},
    this.own,
    required this.onMaster,
    required this.sceneFrom,
    required this.sceneTo,
    required this.channel,
    required this.spans,
    required this.view,
    required this.frame,
    required this.frameRate,
    required this.colors,
    required this.selected,
    required this.chosenChannel,
    required this.held,
    required this.showVolume,
    required this.target,
    required this.shapes,
  });

  double _x(num f, double width) => view.xOf(f, width);

  @override
  void paint(Canvas canvas, Size size) {
    var top = 3.0, bottom = size.height - 3;
    // Zoomed in, a clip reaches past either edge: drawn, and cut off there.
    canvas.clipRect(Offset.zero & size);

    // The channel picked, which a cut at the playhead is made on; and a lane
    // something is being dropped on, or dragged onto.
    if (chosenChannel || target) {
      canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..color = colors.primary.withValues(alpha: target ? 0.10 : 0.05));
    }

    _paintSeconds(canvas, size, view, frameRate, colors);

    for (var (i, lane) in channel.lanes.indexed) {
      _paintClip(canvas, size, lane, spans[i], top, bottom);
    }
    // Over the clips, so the part of one that runs on past the scene reads
    // as not played.
    paintOutsideScene(canvas, size, view, sceneFrom, sceneTo, colors);

    // No line under the lane: the channels' lines are their strips'. No
    // playhead either: the timeline draws one down every row.
  }

  void _paintClip(
      Canvas canvas,
      Size size,
      TimedLane lane,
      ({double from, double to, List<double> cuts}) span,
      double top,
      double bottom) {
    var w = size.width;
    var clip = lane.clip;
    if (clip.isEmpty) return;
    var video = lane.element is VideoElement;
    var locked = lane.element.locked;
    // An instrument's part is notes, not a recording: coloured apart.
    var instrument = lane.element is AudioElement &&
        (lane.element as AudioElement).isInstrument;
    // A sound made a clip (see timeline_clips.dart) in its clip's colour.
    var asClip = lane.element is AudioElement && clip.playlist.isNotEmpty
        ? clip.playlist.first.clip
        : null;
    // As its slot is: an instrument's notes amber, speech pink, any other
    // sound blue; a video violet.
    var fill = (video
            ? const Color(0xFF7B5CC4)
            : asClip != null && asClip.color != timelineClipColour
                ? Color(sectionColors[asClip.color % sectionColors.length])
                : soundSlotColour(
                    midi: instrument,
                    speech: channel.mix.speech != null,
                    own: own))
        .withValues(alpha: lane.editable && !locked ? 1 : 0.5);
    // Writing on it: dark on a light clip, white on a video's.
    var ink = video ? const Color(0xFFFFFFFF) : slotInk;

    var from = _x(span.from, w), to = _x(span.to, w);

    // A repeat carries on to the end, drawn fainter: the same file again,
    // not more of the clip.
    if (clip.loop != MediaLoop.none && span.to > span.from) {
      canvas.drawRRect(
          RRect.fromLTRBR(to, top, w, bottom, const Radius.circular(3)),
          Paint()..color = fill.withValues(alpha: fill.a * 0.35));
    }

    var bar = RRect.fromLTRBR(
        from, top, math.max(from + 2, to), bottom, const Radius.circular(4));
    canvas.drawRRect(bar, Paint()..color = fill);

    canvas.save();
    // Everything of the clip's is inside the clip: the waveform, the lines
    // and its name.
    canvas.clipRRect(bar);

    var rate = frameRate <= 0 ? 1 : frameRate;

    // An instrument's part: its notes, each where it is played and as high
    // as its key -- a piano roll in small -- rather than the shape of the
    // file they were played into.
    var part = switch (lane.element) {
      AudioElement a => a.instrument,
      _ => null,
    };
    if (part != null && part.notes.isNotEmpty) {
      var lo = part.notes.map((n) => n.key).reduce(math.min) - 1;
      var hi = part.notes.map((n) => n.key).reduce(math.max) + 1;
      var row = (bottom - top - 4) / math.max(1, hi - lo + 1);
      var notes = Paint()..color = ink.withValues(alpha: 0.75);
      for (var n in part.notes) {
        var a = _x(span.from + n.start * rate, w);
        var b = _x(span.from + n.end * rate, w);
        if (b < 0 || a > w) continue;
        var y = bottom - 2 - (n.key - lo + 1) * row;
        canvas.drawRRect(
            RRect.fromLTRBR(a, y, math.max(a + 1.5, b),
                y + math.max(1.5, row - 0.5), const Radius.circular(1)),
            notes);
      }
    } else if (size.height >= _waveformFrom) {
      // The sound as it will come out -- its peaks times its own volume --
      // where the lane is tall enough. A peak past full stops at the edge in
      // red, where it would clip.
      var wave = Paint()
        ..color = ink.withValues(alpha: 0.5)
        ..strokeWidth = 1;
      var over = Paint()
        ..color = const Color(0xFFE05050)
        ..strokeWidth = 1;
      var mid = (top + bottom) / 2 + 5;
      var reach = (bottom - top) / 2 - 7;
      var gain = clip.volume;
      for (var (i, cut) in span.cuts.indexed) {
        var source = clip.playlist[i];
        var peaks = shapes[_shapeOf(lane, source)];
        if (peaks == null || peaks.isEmpty || source.length <= 0) continue;
        var a = math.max(0.0, _x(cut, w));
        var b = math.min(w, _x(cut + source.span * rate, w));
        for (var x = a; x < b; x += 2) {
          var t = source.start + (view.first + x / w * view.span - cut) / rate;
          var at = (t / source.length * peaks.length).floor();
          if (at < 0 || at >= peaks.length) continue;
          var level = peaks[at] * gain;
          var h = math.min(1.0, level) * reach;
          canvas.drawLine(
              Offset(x, mid - h), Offset(x, mid + h), level >= 1 ? over : wave);
        }
      }
    }

    // Where each file begins, after the first.
    for (var cut in span.cuts.skip(1)) {
      var x = _x(cut, w);
      canvas.drawLine(Offset(x, top), Offset(x, bottom),
          Paint()..color = const Color(0x88FFFFFF));
    }

    // The fades, as slopes at the ends of each file.
    var shade = Paint()..color = const Color(0x55000000);
    for (var (i, cut) in span.cuts.indexed) {
      var length = clip.playlist[i].span * rate;
      var a = _x(cut, w), b = _x(cut + length, w);
      if (clip.fadeIn > 0) {
        var x = _x(cut + clip.fadeIn * rate, w).clamp(a, b);
        canvas.drawPath(
            Path()
              ..moveTo(a, top)
              ..lineTo(x, top)
              ..lineTo(a, bottom)
              ..close(),
            shade);
      }
      if (clip.fadeOut > 0) {
        var x = _x(cut + length - clip.fadeOut * rate, w).clamp(a, b);
        canvas.drawPath(
            Path()
              ..moveTo(b, top)
              ..lineTo(x, top)
              ..lineTo(b, bottom)
              ..close(),
            shade);
      }
    }

    // The volume line: this clip's own level, dragged up or down -- a
    // video's soundtrack the same as a sound.
    {
      var y = _volumeY(clip.volume, size.height);
      canvas.drawLine(
          Offset(from, y),
          Offset(to, y),
          Paint()
            ..color = const Color(0xCCFFFFFF)
            ..strokeWidth = 1.2);
      if (showVolume && held == lane.element.id) {
        var reading = labelPainter(
            clip.volume <= 0
                ? "−∞ dB"
                : "${clip.volume > 1.0001 ? "+" : ""}"
                    "${gainToDb(clip.volume).toStringAsFixed(1)} dB",
            size: 10,
            colour: const Color(0xFFFFFFFF),
            weight: FontWeight.w600);
        reading.paint(
            canvas,
            Offset(math.max(from, 0) + 6,
                (y - reading.height - 2).clamp(top, bottom - reading.height)));
      }
    }

    // The name, inside the bar, and not at all where the bar is too short
    // for any of it.
    var room = to - math.max(from, 0) - 12;
    if (room >= 24) {
      // Said where it lives, seen from a scene: changed from here, it is
      // the master's that changes.
      var name = lane.scene < 0 && !onMaster
          ? "${lane.element.name} (master)"
          : lane.element.name;
      var text = labelPainter(name,
          size: 10.5,
          colour: ink,
          weight: FontWeight.w500,
          maxLines: 1,
          ellipsis: "…",
          maxWidth: room);
      // Along the bottom of a tall lane, so the waveform and the volume line
      // have the rest; in the middle of a short one.
      var y = size.height >= _waveformFrom
          ? bottom - text.height - 2
          : (size.height - text.height) / 2;
      text.paint(canvas, Offset(math.max(from, 0) + 6, y));
    }
    // Linked to a motion clip: its mark, top right.
    if (linked.contains(lane.element.id) && to - from >= 30) {
      paintLinkMark(canvas, Offset(to - 14, top + 2), ink);
    }
    canvas.restore();

    // Chosen, it keeps an outline for as long as it is: its settings are
    // the ones on screen.
    var chosen = selected.contains(lane.element.id);
    if (chosen || held == lane.element.id) {
      canvas.drawRRect(
          bar,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = chosen ? 2 : 1.5
            ..color = chosen ? colors.onSurface : colors.primary);
    }

    // The fade handles, on the top edge: at the corners until a fade is
    // drawn, and at the end of each slope after.
    if (lane.editable && !locked && to - from > 24) {
      var handle = Paint()..color = const Color(0xFFFFFFFF);
      var inX = _x(span.from + clip.fadeIn * rate, w).clamp(from, to);
      var outX = _x(span.to - clip.fadeOut * rate, w).clamp(from, to);
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset(inX + 3, top + 3), width: 6, height: 6),
          handle);
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset(outX - 3, top + 3), width: 6, height: 6),
          handle);
    }
  }

  @override
  bool shouldRepaint(_LanePainter old) => true;
}

/// _InteractiveLanePainter draws a lane with no time on it: hatched grey,
/// saying why, with the playhead going through it like every other lane.
class _InteractiveLanePainter extends CustomPainter {
  final String label;
  final ColorScheme colors;
  final bool chosen;

  /// frameNow is where the playhead is as it is painted: this repaints on
  /// its own as it moves (see _CanvasChannelsState._heard).
  final int Function() frameNow;
  final TimelineView view;

  _InteractiveLanePainter({
    super.repaint,
    required this.label,
    required this.colors,
    required this.chosen,
    required this.frameNow,
    required this.view,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    var body = Rect.fromLTRB(0, 3, size.width, size.height - 3);
    canvas.drawRect(
        body,
        Paint()
          ..color = colors.onSurface.withValues(alpha: chosen ? 0.10 : 0.06));
    var hatch = Paint()
      ..color = colors.onSurface.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (var x = -size.height; x < size.width; x += 9) {
      canvas.drawLine(
          Offset(x, body.bottom), Offset(x + body.height, body.top), hatch);
    }
    var text = labelPainter(label,
        size: 11,
        height: 1.2,
        colour: colors.onSurfaceVariant.withValues(alpha: 0.9),
        maxLines: 1,
        ellipsis: "…",
        maxWidth: math.max(0, size.width - 16));
    if (size.height >= text.height + 4) {
      text.paint(canvas, Offset(8, (size.height - text.height) / 2));
    }
    var head = view.centreOf(frameNow(), size.width);
    canvas.drawLine(Offset(head, 0), Offset(head, size.height),
        Paint()..color = colors.primary.withValues(alpha: 0.5));
  }

  @override
  bool shouldRepaint(_InteractiveLanePainter old) =>
      old.label != label ||
      old.chosen != chosen ||
      old.view != view ||
      old.colors != colors;
}

class _EmptyLanePainter extends CustomPainter {
  final String label;
  final ColorScheme colors;
  final bool lit;
  _EmptyLanePainter(
      {required this.label, required this.colors, required this.lit});

  @override
  void paint(Canvas canvas, Size size) {
    var box = RRect.fromLTRBR(
        0.5, 3, size.width - 0.5, size.height - 3, const Radius.circular(4));
    if (lit) {
      canvas.drawRRect(
          box, Paint()..color = colors.primary.withValues(alpha: 0.08));
    }
    canvas.drawRRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = lit ? colors.primary : colors.outlineVariant);
    var text = labelPainter(label,
        size: 10.5,
        colour: colors.onSurfaceVariant,
        maxLines: 1,
        ellipsis: "…",
        maxWidth: math.max(0, size.width - 12));
    text.paint(canvas, Offset(6, (size.height - text.height) / 2));
  }

  @override
  bool shouldRepaint(_EmptyLanePainter old) =>
      old.label != label || old.lit != lit || old.colors != colors;
}

/// _ChannelHeader is a channel's strip at the left of its lane: a coloured
/// edge for its kind; its short name (A1, V1); its whole name on a tall
/// lane, double-clicked to rename; its level in decibels, clicked to type
/// one; and lock, solo and mute, given up one at a time as it narrows. Its
/// bottom edge drags the lane taller; a click picks the channel.
class _ChannelHeader extends StatelessWidget {
  final TimelineChannel channel;
  final String label;
  final double width;
  final double height;
  final bool selected;
  final bool soloed;
  final ThemeNotifier theme;
  final VoidCallback onSelect;
  final ValueChanged<String> onRename;
  final ValueChanged<ChannelMix> onMix;
  final VoidCallback onLock;
  final VoidCallback onSolo;
  final ValueChanged<double> onGripStart;
  final ValueChanged<double> onGripMove;

  /// onMoveStart, onMove and onMoveEnd are the strip pressed and dragged up
  /// or down, to put the channel somewhere else in the list.
  final ValueChanged<double> onMoveStart;
  final ValueChanged<double> onMove;
  final VoidCallback onMoveEnd;

  /// mix is the channel's as it plays now, its lanes' settings put in --
  /// what its level reads. See CanvasController.mixNow.
  final ChannelMix mix;

  /// automation is whether its lanes are open under it, and onAutomation
  /// its A button, opening or shutting them.
  final bool automation;
  final VoidCallback onAutomation;

  /// controller reads its level, for the meter beside its lane.
  final CanvasController? controller;

  /// owned is an element's own sound, under the element's header as the
  /// same row: only its band's label and meter, the name being above.
  final bool owned;

  /// onBack sends it back to the timeline, while it plays from its slots.
  final VoidCallback? onBack;

  /// fold is its fold arrow: none on an element's own sound, which its
  /// element's folds.
  final Widget? fold;

  /// rowColour is its row's colour (an element's own sound, its element's),
  /// and onColour picks another from its right-click menu, null for its own
  /// again.
  final Color? rowColour;
  final ValueChanged<Color?>? onColour;

  const _ChannelHeader({
    this.fold,
    this.rowColour,
    this.onColour,
    this.controller,
    this.owned = false,
    this.onBack,
    required this.mix,
    required this.automation,
    required this.onAutomation,
    required this.channel,
    required this.label,
    required this.width,
    required this.height,
    required this.selected,
    required this.soloed,
    required this.theme,
    required this.onSelect,
    required this.onRename,
    required this.onMix,
    required this.onLock,
    required this.onSolo,
    required this.onGripStart,
    required this.onGripMove,
    required this.onMoveStart,
    required this.onMove,
    required this.onMoveEnd,
    super.key,
  });

  /// kind is what the channel is, said small under its name.
  String get kind {
    if (channel.video) return "Video";
    if (channel.interactive) return "Played when pressed";
    var e = channel.first.element;
    if (e is AudioElement && e.instrument != null) return "MIDI instrument";
    return "Audio";
  }

  /// _menu is the strip's right-click menu: what a short row has no room
  /// for -- the lock and the automation's lanes.
  Future<void> _menu(BuildContext context, Offset at) async {
    var choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
      items: [
        PopupMenuItem(
            key: const ValueKey("channelMenuLock"),
            value: "lock",
            height: 32,
            child: Text(channel.locked ? "Unlock its clips" : "Lock its clips",
                style: const TextStyle(fontSize: 12.5))),
        if (channel.editable)
          PopupMenuItem(
              key: const ValueKey("channelMenuAutomation"),
              value: "automation",
              height: 32,
              child: Text(
                  automation ? "Hide its automation" : "Show its automation",
                  style: const TextStyle(fontSize: 12.5))),
        // Its row's colour.
        if (onColour != null && rowColour != null) ...[
          const PopupMenuDivider(),
          ...rowColourMenu(rowColour!),
        ],
      ],
    );
    if (choice == "lock") onLock();
    if (choice == "automation") onAutomation();
    var (picked, colour) = rowColourPicked(choice);
    if (picked) onColour?.call(colour);
  }

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    var locked = channel.locked;

    // Which canvas its clips are on -- M the master, S1 the first scene.
    Widget code = Container(
      key: const ValueKey("channelCode"),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
          color: colors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(6)),
      child: Text(label,
          maxLines: 1,
          style: TextStyle(
              fontSize: 9,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant)),
    );

    // The channel's level, as a number: clicked, it takes a typed one --
    // the same level as its fader in the mixer.
    var reading = SizedBox(
      width: 32,
      child: DbReading(
        key: const ValueKey("channelLevel"),
        db: mix.gainDb,
        fieldHeight: 14,
        unit: "",
        onSet: (db) => onMix(mix.copyWith(gainDb: db)),
        style: TextStyle(
            fontSize: 10,
            height: 1.1,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: colors.onSurfaceVariant),
      ),
    );

    var strip = GestureDetector(
      supportedDevices: timelinePointers,
      behavior: HitTestBehavior.opaque,
      onTap: onSelect,
      onSecondaryTapUp: (d) => _menu(context, d.globalPosition),
      child: RowHeader(
        colour: rowColour ?? channelColour(channel.video),
        width: width,
        height: height,
        selected: selected,
        fold: owned ? null : fold,
        name: ChannelNameEditor(
            name: channel.name, theme: theme, onRename: onRename),
        kind: kind,
        badges: [code],
        // A tall row's own: its automation's lanes, the lock, the level.
        tools: [
          if (channel.editable)
            _StripButton(
              key: const ValueKey("channelAutomation"),
              text: "A",
              on: automation,
              onColor: automationColour,
              theme: theme,
              onTap: onAutomation,
            ),
          _StripButton(
            key: const ValueKey("channelLock"),
            icon: locked ? Icons.lock : Icons.lock_open,
            on: locked,
            onColor: colors.onSurface,
            theme: theme,
            onTap: onLock,
          ),
          // The level typed, as the mixer's fader: on the widest strip,
          // giving its room to the way back while it plays from its slots.
          if (width >= 230 && onBack == null) reading,
        ],
        sound: RowToggle(const ValueKey("channelMute"),
            on: !mix.mute, onTap: () => onMix(mix.copyWith(mute: !mix.mute))),
        solo:
            RowToggle(const ValueKey("channelSolo"), on: soloed, onTap: onSolo),
        bands: [
          RowBand(0, height, channel.video ? "Video" : "Sound", soundColour)
        ],
        meter: channel.key,
        controller: controller,
        continued: owned,
        back: onBack == null
            ? null
            : SlotsReturn(
                key: ValueKey("rowBack-${channel.key}"), onTap: onBack!),
      ),
    );

    return Stack(children: [
      Positioned.fill(
        // Pressed and dragged up or down, the channel moves in the list --
        // any channel, the master's and another scene's too, so this is
        // round the strip rather than in it.
        child: GestureDetector(
          key: ValueKey("channelMove-${channel.key}"),
          supportedDevices: timelinePointers,
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (d) => onMoveStart(d.globalPosition.dy),
          onVerticalDragUpdate: (d) => onMove(d.globalPosition.dy),
          onVerticalDragEnd: (_) => onMoveEnd(),
          onVerticalDragCancel: onMoveEnd,
          // A channel from the master is changed there, as in the mixer.
          child: channel.editable
              ? strip
              : IgnorePointer(child: Opacity(opacity: 0.55, child: strip)),
        ),
      ),
      // The bottom edge: dragged, the lane is taller or shorter.
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: 5,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: GestureDetector(
            key: ValueKey("laneGrip-${channel.key}"),
            supportedDevices: timelinePointers,
            behavior: HitTestBehavior.opaque,
            // Measured from the press, not from where the drag was noticed.
            dragStartBehavior: DragStartBehavior.down,
            onVerticalDragStart: (d) => onGripStart(d.globalPosition.dy),
            onVerticalDragUpdate: (d) => onGripMove(d.globalPosition.dy),
          ),
        ),
      ),
    ]);
  }
}

/// ChannelNameEditor is a channel's whole name, double-clicked to rename it:
/// on its strip beside the timeline, and in the mixer.
class ChannelNameEditor extends StatefulWidget {
  final String name;
  final ThemeNotifier theme;
  final ValueChanged<String> onRename;
  final double fontSize;
  final FontWeight weight;

  /// textKey and fieldKey are the name's and, while it is typed, the
  /// field's.
  final Key textKey;
  final Key fieldKey;

  /// color is the name's, where it is drawn on something other than the
  /// app's own surface -- the mixer's studio strip.
  final Color? color;

  /// byDoubleClick is whether a double-click starts it being typed: not
  /// where a double-click opens something (a transition's slot), and the
  /// name is typed from a menu instead -- see ChannelNameEditorState.edit.
  final bool byDoubleClick;
  const ChannelNameEditor(
      {this.byDoubleClick = true,
      required this.name,
      required this.theme,
      required this.onRename,
      this.fontSize = 11,
      this.weight = FontWeight.w500,
      this.textKey = const ValueKey("channelName"),
      this.fieldKey = const ValueKey("channelNameField"),
      this.color,
      super.key});

  @override
  State<ChannelNameEditor> createState() => ChannelNameEditorState();
}

class ChannelNameEditorState extends State<ChannelNameEditor> {
  bool _typing = false;
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// edit starts the name being typed, as a double-click does: from a menu's
  /// "Name it".
  void edit() => setState(() {
        _typing = true;
        _text.text = widget.name;
        _text.selection =
            TextSelection(baseOffset: 0, extentOffset: _text.text.length);
      });

  void _commit() {
    if (!_typing) return;
    setState(() => _typing = false);
    var named = _text.text.trim();
    if (named.isNotEmpty && named != widget.name) widget.onRename(named);
  }

  @override
  Widget build(BuildContext context) {
    var style = TextStyle(
        fontSize: widget.fontSize,
        height: 1.2,
        fontWeight: widget.weight,
        color: widget.color ?? widget.theme.colors.onSurface);
    if (_typing) {
      return TextField(
        key: widget.fieldKey,
        controller: _text,
        autofocus: true,
        style: style,
        decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none),
        onSubmitted: (_) => _commit(),
        onTapOutside: (_) => _commit(),
      );
    }
    var text = Text(widget.name,
        key: widget.textKey,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style);
    if (!widget.byDoubleClick) return text;
    return GestureDetector(
      onDoubleTap: edit,
      child: Text(widget.name,
          key: widget.textKey,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style),
    );
  }
}

/// _EmptyHeader is the strip beside the empty lane: the channel it would be.
class _EmptyHeader extends StatelessWidget {
  final double width;
  final String name;
  final ThemeNotifier theme;

  /// onAudio and onMidi add a channel of either kind: a sound chosen, or an
  /// instrument to play into.
  final VoidCallback onAudio;
  final VoidCallback onMidi;

  /// onEmptyAudio and onEmptyMidi add one of either with nothing on it: an
  /// audio channel waiting for a sound, a MIDI channel on the timeline alone.
  final VoidCallback onEmptyAudio;
  final VoidCallback onEmptyMidi;
  const _EmptyHeader(
      {required this.width,
      required this.name,
      required this.theme,
      required this.onAudio,
      required this.onMidi,
      required this.onEmptyAudio,
      required this.onEmptyMidi});

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    // The + is a menu of the two kinds of channel there are.
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          key: const ValueKey("addAudioChannel"),
          leadingIcon: const Icon(Icons.graphic_eq, size: 16),
          onPressed: onAudio,
          child: const Text("Audio channel: choose a sound",
              style: TextStyle(fontSize: 12)),
        ),
        MenuItemButton(
          key: const ValueKey("addEmptyAudioChannel"),
          leadingIcon: const Icon(Icons.graphic_eq, size: 16),
          onPressed: onEmptyAudio,
          child:
              const Text("Empty audio channel", style: TextStyle(fontSize: 12)),
        ),
        const Divider(height: 1),
        MenuItemButton(
          key: const ValueKey("addMidiChannel"),
          leadingIcon: const Icon(Icons.piano, size: 16),
          onPressed: onMidi,
          child: const Text("MIDI channel: an instrument to play",
              style: TextStyle(fontSize: 12)),
        ),
        MenuItemButton(
          key: const ValueKey("addEmptyMidiChannel"),
          leadingIcon: const Icon(Icons.piano_outlined, size: 16),
          onPressed: onEmptyMidi,
          child: const Text("Empty MIDI channel: on the timeline only",
              style: TextStyle(fontSize: 12)),
        ),
      ],
      builder: (context, menu, _) => Tooltip(
        message: "Add an audio or a MIDI channel",
        child: InkWell(
          key: const ValueKey("addChannel"),
          onTap: () => menu.isOpen ? menu.close() : menu.open(),
          child: Container(
            // Less to either side when the column is narrow, so the icon
            // alone fits.
            padding: width < 64
                ? const EdgeInsets.fromLTRB(4, 3, 2, 3)
                : const EdgeInsets.fromLTRB(8, 3, 8, 3),
            decoration: BoxDecoration(
                border:
                    Border(right: BorderSide(color: colors.outlineVariant))),
            child: Row(children: [
              Icon(Icons.add, size: 14, color: colors.primary),
              if (width >= 64) ...[
                const SizedBox(width: 4),
                Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10.5,
                          height: 1.2,
                          color: colors.onSurfaceVariant)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// _StripButton is one of a strip's small square buttons: lock, solo, mute.
class _StripButton extends StatelessWidget {
  final String? text;
  final IconData? icon;
  final bool on;
  final Color onColor;
  final ThemeNotifier theme;
  final VoidCallback onTap;

  const _StripButton({
    this.text,
    this.icon,
    required this.on,
    required this.onColor,
    required this.theme,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var colors = theme.colors;
    var ink = on
        ? (onColor == colors.onSurface ? colors.surface : Colors.white)
        : colors.onSurfaceVariant;
    return GestureDetector(
      supportedDevices: timelinePointers,
      onTap: onTap,
      child: Container(
        width: 20,
        height: 17,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? onColor : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(3),
        ),
        child: icon != null
            ? Icon(icon, size: 11, color: ink)
            : Text(text!,
                style: TextStyle(
                    fontSize: 9.5,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    color: ink)),
      ),
    );
  }
}

/// SessionRowSlots are a channel's clip slots beside its row on the
/// timeline, a cue each, as on its strip in the mixer: its triangle
/// launches it -- an empty one's square stops the channel; its name clicked
/// picks it (Delete then empties it), double-clicked opens it; an empty one
/// double-clicked has a clip made in it; dragged, onto a lane.
class SessionRowSlots extends StatelessWidget {
  final CanvasController controller;
  final String channel;
  const SessionRowSlots(
      {required this.controller, required this.channel, super.key});

  @override
  Widget build(BuildContext context) {
    var c = controller;
    var colors = ThemeNotifier.of(context).colors;
    return SlotsWindow(controller: c, cell: (i) => _cell(c, colors, i));
  }

  Widget _cell(CanvasController c, ColorScheme colors, int row) {
    var clip = c.session.at(channel, row);
    var state = c.clipState(channel, row);
    var lit = state == ClipState.playing ||
        state == ClipState.stopping ||
        state == ClipState.queued;
    var launch = Listener(
      key: ValueKey("rowClipLaunch-$channel-$row"),
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => c.pressClip(channel, row),
      onPointerUp: (_) => c.releaseClip(channel, row),
      child: clip == null
          ? Icon(Icons.stop, size: 9, color: colors.onSurfaceVariant)
          : SizedBox.expand(
              child: Icon(Icons.play_arrow,
                  size: 10, color: lit ? slotPlayingInk : slotInk)),
    );
    var picked = c.selectedSlot == (channel, row);
    // One design everywhere (slot_face.dart): round-cornered, its wave or
    // its notes.
    Widget cell;
    if (clip == null) {
      cell = Stack(key: ValueKey("rowClip-$channel-$row"), children: [
        Positioned.fill(child: SlotFace(side: SlotSide.sound, empty: launch)),
        // Double-clicked: a clip made in it.
        Positioned(
          left: 20,
          top: 0,
          right: 0,
          bottom: 0,
          child: GestureDetector(
            key: ValueKey("rowClipNew-$channel-$row"),
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () => c.makeSessionClip(channel, row),
          ),
        ),
      ]);
    } else {
      cell = DecoratedBox(
        key: ValueKey("rowClip-$channel-$row"),
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: picked ? Border.all(color: colors.onSurface) : null),
        child: SlotFace(
          side: SlotSide.sound,
          colour: Color(sectionColors[clip.color % sectionColors.length]),
          playing: lit,
          seed: clip.id,
          midi: clip.midi,
          go: launch,
          label: SlotFocus(
            key: ValueKey("rowClipKeys-$channel-$row"),
            onDelete: () {
              c.beginInteraction();
              c.setSessionClip(channel, row, null);
              c.endInteraction();
            },
            builder: (focus) => GestureDetector(
              key: ValueKey("rowClipName-$channel-$row"),
              behavior: HitTestBehavior.opaque,
              onTap: () {
                c.selectSlot(channel, row);
                focus.requestFocus();
              },
              onDoubleTap: () => c.openClipEditor(channel, row),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(clip.name.isEmpty ? "Clip" : clip.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ),
        ),
      );
    }
    if (clip == null) return cell;
    return Draggable<Object>(
      data: SessionSlotDrag(channel, row, clip),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Color(sectionColors[clip.color % sectionColors.length]),
        borderRadius: BorderRadius.circular(3),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(clip.name.isEmpty ? "Clip" : clip.name,
              style: const TextStyle(fontSize: 10, color: Color(0xFF0E0F12))),
        ),
      ),
      child: cell,
    );
  }
}

/// _NotPlayhead tells its listeners of [controller]'s changes but not of
/// its frames of play (CanvasController.notifyingPlayhead).
class _NotPlayhead extends ChangeNotifier {
  final CanvasController controller;

  _NotPlayhead(this.controller) {
    controller.addListener(_told);
  }

  void _told() {
    if (!controller.notifyingPlayhead) notifyListeners();
  }

  @override
  void dispose() {
    controller.removeListener(_told);
    super.dispose();
  }
}
