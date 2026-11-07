import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart'
    show Keyframe, KeyframeChannel, KeyframeEasing;
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/motion.dart';
import 'package:bruig/plugin_system/canvas/render/element_effects.dart'
    show paintArriving;
import 'package:bruig/plugin_system/canvas/render/motion_document.dart'
    show boxOf, motionSceneOf;
import 'package:bruig/plugin_system/canvas/render/motion_pose.dart'
    show MotionScene, sampleProp;
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/motion_curves.dart'
    show curveColour;
import 'package:bruig/plugin_system/canvas/ui/studio_colors.dart';
import 'package:bruig/plugin_system/canvas/ui/own_style.dart' show OwnStyle;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

// motion_clip_display.dart is the Motion clips card's screen (Ken,
// 2026-11-08: "more interactive, to show more detail of the animation ...
// edited from the visual display"). The picked clip as it plays: its path
// on the page with the element's ghosts along it -- their size, turn and
// opacity as the clip has them -- and its timing as dots, or its values
// over time. Edited there: a point dragged, a stretch's curve picked from
// its diamond, a point added with a double-click, taken out with a
// right-click. Hovered, it plays.

/// ClipView is what the screen shows: the path the element takes, or its
/// values over time.
enum ClipView { path, graph }

typedef ClipEditFn = void Function(MotionClip Function(MotionClip) change,
    {bool live});

/// MotionClipDisplay is [clip] of [element] drawn and edited: [edit]
/// changes it -- live while dragged, then ended with the controller's
/// endInteraction. [onReset], given, puts it back as its preset made it.
class MotionClipDisplay extends StatefulWidget {
  final CanvasController controller;
  final CanvasElement element;
  final MotionClip? clip;
  final Color accent;
  final ClipEditFn edit;
  final VoidCallback? onReset;
  const MotionClipDisplay(
      {required this.controller,
      required this.element,
      required this.clip,
      required this.accent,
      required this.edit,
      this.onReset,
      super.key});

  @override
  State<MotionClipDisplay> createState() => _MotionClipDisplayState();
}

class _MotionClipDisplayState extends State<MotionClipDisplay>
    with SingleTickerProviderStateMixin {
  ClipView? _view;
  late final Ticker _ticker = createTicker(_tick);

  /// _preview is where in the clip the hovered screen is playing.
  double? _preview;

  /// _hover is the handle under the pointer, and _picked the point clicked.
  ClipHandle? _hover, _picked;
  _Drag? _drag;

  /// _look is the studio's look as last built, for the curve menu opened
  /// from a tap, where the theme cannot be looked up.
  MixerLook? _look;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  MotionClip? get _clip => widget.clip;

  void _tick(Duration elapsed) {
    var c = _clip;
    if (c == null || c.length <= 0) return;
    // Once through and a breath, round again; a loop round and round.
    var speed = math.max(0.05, c.speed);
    var round = c.length / speed + (c.loop ? 0 : 0.5);
    var s = elapsed.inMicroseconds / 1e6 % round;
    setState(() => _preview = math.min(c.length, s * speed));
  }

  void _play(bool on) {
    if (on && !_ticker.isActive) _ticker.start();
    if (!on) {
      if (_ticker.isActive) _ticker.stop();
      setState(() => _preview = null);
    }
  }

  ClipView _shown(MotionClip c) {
    var hasPath =
        c.keys.containsKey(MotionProp.x) || c.keys.containsKey(MotionProp.y);
    return _view ?? (hasPath ? ClipView.path : ClipView.graph);
  }

  /// _ownSays is what a text's or a chart's own style is called, for its
  /// screen.
  String _ownSays(MotionClip c) {
    var style = OwnStyle.of(widget.element);
    if (style == null) return "";
    var leaving = c.kind == MotionKind.leave;
    var name = style.labelOf(style.preset(leaving: leaving));
    return "${leaving ? "Its own way out" : "Its own arrival"}: $name";
  }

  ClipLayout _layoutFor(MotionClip c, Size size) {
    var doc = widget.controller.document;
    return ClipLayout(c, _shown(c), size, boxOf(widget.element),
        motionSceneOf(doc, widget.controller.frame));
  }

  @override
  Widget build(BuildContext context) {
    var look = _look = MixerLook.of(context);
    var studio = look.studio;
    var c = _clip;
    var own = c != null && c.keys.isEmpty && c.inside["own"] == true;
    return LayoutBuilder(builder: (context, box) {
      var size = box.biggest;
      var layout = c == null || own ? null : _layoutFor(c, size);
      var seconds = widget.controller.frame /
          math.max(1, widget.controller.document.frameRate);
      var screen = CustomPaint(
        key: const ValueKey("motionClipsPath"),
        painter: _ClipPainter(
          clip: c,
          layout: layout,
          // A box's own style drawn as frames; the words' and a chart's,
          // named (their pieces are timed against the page, not a box).
          own: own && CanvasController.animates(widget.element)
              ? CanvasController.elementAnimationOf(widget.element)
              : null,
          ownSays: own && !CanvasController.animates(widget.element)
              ? _ownSays(c)
              : null,
          box: boxOf(widget.element),
          at: _preview ??
              (c == null || c.length <= 0
                  ? 0
                  : c.loop
                      ? seconds * c.speed % c.length
                      : math.min(
                          c.length, seconds * c.speed % (c.length * 1.5))),
          playing: _preview != null,
          hover: _hover,
          picked: _picked,
          studio: studio,
          accent: widget.accent,
        ),
        child: const SizedBox.expand(),
      );
      var hasPath = c != null &&
          (c.keys.containsKey(MotionProp.x) ||
              c.keys.containsKey(MotionProp.y));
      return MouseRegion(
        onEnter: (_) => _play(true),
        onExit: (_) {
          _play(false);
          setState(() => _hover = null);
        },
        onHover: (e) {
          var h = layout?.hit(e.localPosition);
          if (h != _hover) setState(() => _hover = h);
        },
        cursor: _hover == null
            ? SystemMouseCursors.basic
            : _hover!.ease
                ? SystemMouseCursors.click
                : SystemMouseCursors.grab,
        child: Stack(children: [
          Positioned.fill(
            child: layout == null
                ? screen
                : _gestures(context, c!, layout, child: screen),
          ),
          // Which it shows, where it has a path; and back to its preset.
          if (c != null && !own && c.keys.isNotEmpty)
            Positioned(
              top: 5,
              right: 5,
              child: _Chips(studio: studio, accent: widget.accent, chips: [
                if (hasPath)
                  (
                    "motionClipsView-path",
                    "Path",
                    _shown(c) == ClipView.path,
                    () => setState(() => _view = ClipView.path)
                  ),
                (
                  "motionClipsView-values",
                  "Values",
                  _shown(c) == ClipView.graph,
                  () => setState(() => _view = ClipView.graph)
                ),
              ]),
            ),
          if (widget.onReset != null)
            Positioned(
              top: 5,
              left: 5,
              child: _Chips(studio: studio, accent: widget.accent, chips: [
                (
                  "motionClipsReset",
                  "Reset",
                  false,
                  () {
                    setState(() => _picked = null);
                    widget.onReset!();
                  }
                ),
              ]),
            ),
        ]),
      );
    });
  }

  /// _gestures edits [c] on the screen: see the file's comment. A press on
  /// a point takes hold of it at once, before the Chain's row can take the
  /// drag for scrolling.
  Widget _gestures(BuildContext context, MotionClip c, ClipLayout layout,
          {required Widget child}) =>
      Listener(
        // A right-click takes a point out.
        onPointerDown: (e) {
          if (e.buttons & kSecondaryMouseButton == 0) return;
          var h = layout.hit(e.localPosition);
          if (h == null || h.ease) return;
          widget.edit((x) => layout.withoutPoint(x, h));
          setState(() => _picked = null);
        },
        child: RawGestureDetector(
          gestures: {
            _GrabRecognizer:
                GestureRecognizerFactoryWithHandlers<_GrabRecognizer>(
              () => _GrabRecognizer(),
              (g) => g
                ..dragStartBehavior = DragStartBehavior.down
                ..grabs = ((at) {
                  var h = layout.hit(at);
                  return h != null && !h.ease;
                })
                ..onStart = (d) {
                  var h = layout.hit(d.localPosition);
                  if (h == null || h.ease) return;
                  setState(() {
                    _picked = h;
                    _drag = _Drag(h, c, layout, d.localPosition);
                  });
                }
                ..onUpdate = (d) {
                  var drag = _drag;
                  if (drag == null) return;
                  var keys = HardwareKeyboard.instance;
                  var moved = drag.layout.dragged(
                      drag.from, drag.handle, d.localPosition - drag.start,
                      oneAxis: keys.isShiftPressed, free: keys.isAltPressed);
                  drag.moved = true;
                  widget.edit((_) => moved, live: true);
                }
                ..onEnd = (_) {
                  var drag = _drag;
                  _drag = null;
                  if (drag?.moved ?? false) widget.controller.endInteraction();
                },
            ),
          },
          child: GestureDetector(
            onTapUp: (d) {
              var h = layout.hit(d.localPosition);
              if (h != null && h.ease) {
                _easeMenu(context, d.globalPosition, h, layout);
                return;
              }
              setState(() => _picked = h);
            },
            onDoubleTapDown: (d) {
              var made = layout.withPointAt(c, d.localPosition);
              if (made == null) return;
              widget.edit((_) => made);
            },
            onDoubleTap: () {},
            child: child,
          ),
        ),
      );

  /// _easeMenu is the curves a stretch can take, at [at] on the screen.
  Future<void> _easeMenu(
      BuildContext context, Offset at, ClipHandle h, ClipLayout layout) async {
    var look = _look;
    if (look == null) return;
    var overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    var picked = await showMenu<KeyframeEasing>(
      context: context,
      color: look.studio.raised,
      position: RelativeRect.fromRect(
          Rect.fromCenter(center: at, width: 1, height: 1),
          Offset.zero & overlay.size),
      items: [
        for (var e in KeyframeEasing.values)
          PopupMenuItem(
            key: ValueKey("motionClipsEase-${e.name}"),
            value: e,
            height: 28,
            child: Text(e.label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight:
                        e == h.easing ? FontWeight.w700 : FontWeight.w400,
                    color: look.studio.text)),
          ),
      ],
    );
    if (picked == null || !mounted) return;
    widget.edit((x) => layout.withEase(x, h, picked));
  }
}

class _Drag {
  final ClipHandle handle;
  final MotionClip from;
  final ClipLayout layout;
  final Offset start;
  bool moved = false;
  _Drag(this.handle, this.from, this.layout, this.start);
}

/// _GrabRecognizer is a pan that wins at once where [grabs] says the press
/// is on something to drag: a point, which the Chain's row would otherwise
/// take for scrolling.
class _GrabRecognizer extends PanGestureRecognizer {
  bool Function(Offset local)? grabs;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (grabs?.call(event.localPosition) ?? false) {
      resolve(GestureDisposition.accepted);
    }
  }
}

/// ClipHandle is something on the screen to take hold of: a point -- the
/// keys of [props] at [t] -- or, [ease], the diamond on the stretch that
/// ends at [t], whose curve is [easing].
class ClipHandle {
  final bool ease;
  final double t;
  final List<MotionProp> props;
  final Offset at;
  final KeyframeEasing easing;
  const ClipHandle(this.ease, this.t, this.props, this.at,
      [this.easing = KeyframeEasing.linear]);

  @override
  bool operator ==(Object other) =>
      other is ClipHandle &&
      other.ease == ease &&
      (other.t - t).abs() < 1e-9 &&
      other.props.length == props.length &&
      other.props.every(props.contains);

  @override
  int get hashCode => Object.hash(ease, t, props.length);
}

/// ClipPose is the element at one moment of a clip: moved by [move] from
/// where it is set, [scale]d, turned [turn] degrees, [opacity] seen.
typedef ClipPose = ({Offset move, double scale, double turn, double opacity});

/// ClipLayout is [clip] laid out on a screen [size]: where each moment of it
/// is drawn, its handles, and the edits made by moving them.
class ClipLayout {
  final MotionClip clip;
  final ClipView view;
  final Size size;
  final Rect self;
  final MotionScene scene;

  ClipLayout(this.clip, this.view, this.size, this.self, this.scene) {
    view == ClipView.path ? _fitPath() : _fitValues();
  }

  static const double _top = 26, _foot = 18, _side = 12;

  // ---- What it does at a moment

  double value(MotionProp p, double t) =>
      sampleProp(clip, p, t, self, scene) ?? p.rest;

  ClipPose pose(double t) => (
        move: Offset(value(MotionProp.x, t), value(MotionProp.y, t)),
        scale: value(MotionProp.scale, t),
        turn: value(MotionProp.turn, t),
        opacity: value(MotionProp.opacity, t),
      );

  /// timesOf are the moments [props] have keys at, in order.
  List<double> timesOf(Iterable<MotionProp> props) {
    var out = <double>[];
    for (var p in props) {
      for (var k in clip.keys[p] ?? const <MotionKey>[]) {
        if (!out.any((t) => (t - k.t).abs() < 1e-6)) out.add(k.t);
      }
    }
    return out..sort();
  }

  // ---- The path

  late Rect page;
  late Rect bounds;
  late double _scale;
  late Offset _origin;
  final List<ClipHandle> handles = [];
  final Map<MotionProp, (double, double)> ranges = {};
  late Rect area;

  static const _pathProps = [MotionProp.x, MotionProp.y];

  void _fitPath() {
    page = Rect.fromLTWH(
        -self.center.dx, -self.center.dy, scene.page.width, scene.page.height);
    var len = math.max(clip.length, 1e-3);
    // Where it goes, with the element round each moment, and where it rests.
    var b = Rect.fromCenter(
        center: Offset.zero, width: self.width, height: self.height);
    for (var i = 0; i <= 60; i++) {
      var p = pose(len * i / 60);
      b = b.expandToInclude(Rect.fromCenter(
          center: p.move,
          width: self.width * p.scale.abs(),
          height: self.height * p.scale.abs()));
    }
    // At least a few of the element across, so a small wiggle is not
    // blown up to fill the screen; the page's edges drawn where they fall.
    var least = math.max(self.width, self.height) * 3;
    if (b.width < least) {
      b = Rect.fromCenter(center: b.center, width: least, height: b.height);
    }
    if (b.height < least) {
      b = Rect.fromCenter(center: b.center, width: b.width, height: least);
    }
    bounds = b.inflate(math.max(b.width, b.height) * 0.06 + 4);
    var room =
        Rect.fromLTRB(_side, _top, size.width - _side, size.height - _foot);
    _scale = math.min(room.width / math.max(1, bounds.width),
        room.height / math.max(1, bounds.height));
    _origin = room.center - bounds.center * _scale;
    // A point at each moment the path has a key; a diamond on each stretch.
    var times = timesOf(_pathProps);
    for (var (i, t) in times.indexed) {
      var props = [
        for (var p in _pathProps)
          if (_keyAt(p, t) != null) p
      ];
      handles.add(ClipHandle(false, t, props, toScreen(pose(t).move)));
      if (i > 0) {
        var mid = (times[i - 1] + t) / 2;
        handles.add(ClipHandle(true, t, props, toScreen(pose(mid).move),
            _keyAt(props.first, t)?.ease ?? KeyframeEasing.linear));
      }
    }
  }

  Offset toScreen(Offset move) => _origin + move * _scale;
  Offset toMove(Offset screen) => (screen - _origin) / _scale;

  /// scale is how many screen pixels a page unit is drawn as.
  double get scale => _scale;

  // ---- The values

  void _fitValues() {
    area = Rect.fromLTRB(_side, _top, size.width - _side, size.height - _foot);
    var len = math.max(clip.length, 1e-3);
    for (var p in MotionProp.values) {
      var keys = clip.keys[p];
      if (keys == null || keys.isEmpty) continue;
      var lo = p.rest, hi = p.rest;
      for (var i = 0; i <= 60; i++) {
        var v = value(p, len * i / 60);
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
      if (hi - lo < 1e-6) {
        var r = hi.abs() * 0.5 + 1;
        lo -= r;
        hi += r;
      }
      var pad = (hi - lo) * 0.12;
      ranges[p] = (lo - pad, hi + pad);
    }
    for (var p in ranges.keys) {
      var keys = clip.keys[p]!;
      for (var (i, k) in keys.indexed) {
        handles.add(ClipHandle(false, k.t, [p], at(p, k.t)));
        if (i > 0) {
          var mid = (keys[i - 1].t + k.t) / 2;
          handles.add(ClipHandle(true, k.t, [p], at(p, mid), k.ease));
        }
      }
    }
  }

  double xOf(double t) =>
      area.left + t / math.max(clip.length, 1e-3) * area.width;
  double yOf(MotionProp p, double v) {
    var (lo, hi) = ranges[p]!;
    return area.bottom - (v - lo) / (hi - lo) * area.height;
  }

  Offset at(MotionProp p, double t) => Offset(xOf(t), yOf(p, value(p, t)));

  // ---- Taking hold

  /// hit is the handle at [spot]: a point before a diamond.
  ClipHandle? hit(Offset spot) {
    ClipHandle? best;
    var near = double.infinity;
    for (var h in handles) {
      var d = (h.at - spot).distance - (h.ease ? 0 : 2);
      if (d < near && d <= 9) {
        near = d;
        best = h;
      }
    }
    return best;
  }

  MotionKey? _keyAt(MotionProp p, double t) {
    for (var k in clip.keys[p] ?? const <MotionKey>[]) {
      if ((k.t - t).abs() < 1e-6) return k;
    }
    return null;
  }

  /// stored is [move] -- an offset from where the element is set -- as
  /// [c] keeps a number for [p]: a place on the page, where it sets places.
  double stored(MotionClip c, MotionProp p, double move) {
    if (!c.absolute) return move;
    if (p == MotionProp.x) return move + self.center.dx;
    if (p == MotionProp.y) return move + self.center.dy;
    return move;
  }

  /// _withKey is [c] with [p] keyed [v] (as it draws) at [t]: the key there
  /// changed, or one put in. A value with no keys yet is keyed at each of
  /// [times] as it is now, so the rest of it stays where it was.
  MotionClip _withKey(MotionClip c, MotionProp p, double t, double v,
      {double? to, List<double> times = const []}) {
    var keys = [...c.keys[p] ?? const <MotionKey>[]];
    if (keys.isEmpty) {
      for (var o in times) {
        if ((o - t).abs() > 1e-6) {
          keys.add(MotionKey(o, MotionNumber(stored(c, p, p.rest))));
        }
      }
    }
    var i = keys.indexWhere((k) => (k.t - t).abs() < 1e-6);
    var value = MotionNumber(stored(c, p, v));
    if (i >= 0) {
      keys[i] = keys[i].copyWith(t: to ?? t, value: value);
    } else {
      // A new one curves as the stretch it lands in did.
      var after = keys.where((k) => k.t > t).firstOrNull;
      keys.add(MotionKey(to ?? t, value,
          ease: after?.ease ?? KeyframeEasing.linear));
    }
    keys.sort((a, b) => a.t.compareTo(b.t));
    return c.copyWith(keys: {...c.keys, p: keys}, edited: true);
  }

  /// dragged is [from] with [h] moved [by] screen pixels: on the path, to
  /// a new place (one way only, [oneAxis]); among the values, to a new time
  /// and value, the time on twentieths of a second unless [free].
  MotionClip dragged(MotionClip from, ClipHandle h, Offset by,
      {bool oneAxis = false, bool free = false}) {
    var c = from;
    if (view == ClipView.path) {
      var d = by / _scale;
      if (oneAxis) {
        d = d.dx.abs() >= d.dy.abs() ? Offset(d.dx, 0) : Offset(0, d.dy);
      }
      var was = pose(h.t).move;
      var times = timesOf(_pathProps);
      // Moved across only, its down stays unkeyed, and the other way round.
      if (d.dx != 0 || h.props.contains(MotionProp.x)) {
        c = _withKey(c, MotionProp.x, h.t, was.dx + d.dx, times: times);
      }
      if (d.dy != 0 || h.props.contains(MotionProp.y)) {
        c = _withKey(c, MotionProp.y, h.t, was.dy + d.dy, times: times);
      }
      return c;
    }
    var p = h.props.single;
    var keys = clip.keys[p]!;
    var i = keys.indexWhere((k) => (k.t - h.t).abs() < 1e-6);
    var lo = i > 0 ? keys[i - 1].t + 0.01 : 0.0;
    var hi = i < keys.length - 1 ? keys[i + 1].t - 0.01 : clip.length;
    var t = h.t + by.dx / area.width * math.max(clip.length, 1e-3);
    if (!free) t = (t * 20).roundToDouble() / 20;
    t = t.clamp(lo, math.max(lo, hi));
    var (vlo, vhi) = ranges[p]!;
    var v = value(p, h.t) - by.dy / area.height * (vhi - vlo);
    return _withKey(c, p, h.t, v, to: t);
  }

  /// withEase is [c] with the stretch [h] marks curving as [e].
  MotionClip withEase(MotionClip c, ClipHandle h, KeyframeEasing e) {
    var keys = {...c.keys};
    for (var p in h.props) {
      keys[p] = [
        for (var k in keys[p] ?? const <MotionKey>[])
          (k.t - h.t).abs() < 1e-6 ? k.copyWith(ease: e) : k
      ];
    }
    return c.copyWith(keys: keys, edited: true);
  }

  /// withoutPoint is [c] with the point [h] taken out, where what is left
  /// still has a start and an end.
  MotionClip withoutPoint(MotionClip c, ClipHandle h) {
    var keys = {...c.keys};
    for (var p in h.props) {
      var now = keys[p] ?? const <MotionKey>[];
      if (now.length <= 2) continue;
      keys[p] = [
        for (var k in now)
          if ((k.t - h.t).abs() > 1e-6) k
      ];
    }
    return c.copyWith(keys: keys, edited: true);
  }

  /// withPointAt is [c] with a point put in where [spot] is on its path,
  /// or on a value's line -- null where it is on neither.
  MotionClip? withPointAt(MotionClip c, Offset spot) {
    var len = math.max(clip.length, 1e-3);
    if (view == ClipView.path) {
      var best = -1.0;
      var near = 12.0;
      for (var i = 0; i <= 120; i++) {
        var t = len * i / 120;
        var d = (toScreen(pose(t).move) - spot).distance;
        if (d < near) {
          near = d;
          best = t;
        }
      }
      if (best < 0) return null;
      var at = pose(best).move;
      var out = c;
      for (var p in _pathProps) {
        if (clip.keys[p]?.isNotEmpty ?? false) {
          out = _withKey(out, p, best, p == MotionProp.x ? at.dx : at.dy);
        }
      }
      return out;
    }
    var t = ((spot.dx - area.left) / area.width * len).clamp(0.0, len);
    MotionProp? best;
    var near = 10.0;
    for (var p in ranges.keys) {
      var d = (yOf(p, value(p, t)) - spot.dy).abs();
      if (d < near) {
        near = d;
        best = p;
      }
    }
    if (best == null) return null;
    return _withKey(c, best, t, value(best, t));
  }
}

/// _ClipPainter draws the screen: see MotionClipDisplay.
class _ClipPainter extends CustomPainter {
  final MotionClip? clip;
  final ClipLayout? layout;
  final ElementAnimation? own;

  /// ownSays names an own style there are no frames of here.
  final String? ownSays;
  final Rect box;
  final double at;
  final bool playing;
  final ClipHandle? hover, picked;
  final StudioColors studio;
  final Color accent;
  _ClipPainter(
      {required this.clip,
      required this.layout,
      required this.own,
      this.ownSays,
      required this.box,
      required this.at,
      required this.playing,
      required this.hover,
      required this.picked,
      required this.studio,
      required this.accent});

  static const _dot = Color(0xFFE2B04A);

  @override
  void paint(Canvas canvas, Size size) {
    var w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = studio.display);
    var grid = Paint()..color = Color.lerp(studio.display, Colors.white, 0.05)!;
    for (var i = 1; i < 8; i++) {
      canvas.drawRect(
          Rect.fromLTWH((i * w / 8).roundToDouble(), 0, 1, h), grid);
    }
    for (var i = 1; i < 4; i++) {
      canvas.drawRect(
          Rect.fromLTWH(0, (i * h / 4).roundToDouble(), w, 1), grid);
    }
    var c = clip;
    if (c == null) return;
    if (own != null) return _paintOwn(canvas, size, c);
    if (ownSays case var says?) {
      var tp = TextPainter(
          text: TextSpan(
              text: says,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: studio.text)),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: size.width - 24);
      tp.paint(
          canvas,
          Offset(
              (size.width - tp.width) / 2, (size.height - tp.height) / 2 - 6));
      _say(canvas, size, "Its words or bars, as the page plays it");
      return;
    }
    var l = layout;
    if (l == null || c.keys.isEmpty) {
      _say(canvas, size, "No keys: pick a preset, or add them in Curves");
      return;
    }
    l.view == ClipView.path
        ? _paintPath(canvas, size, c, l)
        : _paintValues(canvas, size, c, l);
    _paintHandles(canvas, l);
    // What is under the pointer, or what it is.
    var status = hover == null
        ? "${at.toStringAsFixed(2)} / ${c.length.toStringAsFixed(2)} s"
            "${c.speed == 1 ? "" : " · ×${c.speed.toStringAsFixed(2)}"}"
            "${playing ? "" : " · hover to play"}"
        : hover!.ease
            ? "${hover!.easing.label} · click for its curve"
            : _describe(c, l, hover!);
    _say(canvas, size, status);
  }

  String _describe(MotionClip c, ClipLayout l, ClipHandle h) {
    String num(MotionProp p) {
      var v = l.value(p, h.t);
      return switch (p) {
        MotionProp.scale => "${(v * 100).round()}%",
        MotionProp.opacity => "${(v * 100).round()}%",
        MotionProp.turn => "${v.round()}°",
        _ => "${v.round()}",
      };
    }

    var parts =
        l.view == ClipView.path ? [MotionProp.x, MotionProp.y] : h.props;
    return "${h.t.toStringAsFixed(2)} s · "
        "${[for (var p in parts) "${p.label} ${num(p)}"].join(" · ")}"
        " · drag it";
  }

  void _paintPath(Canvas canvas, Size size, MotionClip c, ClipLayout l) {
    var s = l.scale;
    // The page, where the path leaves it, and where the element is set.
    var page = Rect.fromPoints(
        l.toScreen(l.page.topLeft), l.toScreen(l.page.bottomRight));
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
        page, Paint()..color = Colors.white.withValues(alpha: 0.035));
    canvas.drawRect(
        page,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.28));
    canvas.restore();
    var rest = Rect.fromCenter(
        center: l.toScreen(Offset.zero),
        width: box.width * s,
        height: box.height * s);
    _dashedRect(canvas, rest, studio.muted.withValues(alpha: 0.7));
    // The element as it goes: its size, turn and opacity at each step.
    var len = math.max(c.length, 1e-3);
    const ghosts = 5;
    for (var i = 0; i < ghosts; i++) {
      var p = l.pose(len * i / (ghosts - 1));
      _ghost(canvas, l.toScreen(p.move), box.size * s, p,
          alpha: 0.10 + 0.12 * i / (ghosts - 1));
    }
    // Its path, and a dot each twentieth of its time: close where it is
    // slow, far apart where it is fast.
    var path = Path();
    for (var i = 0; i <= 80; i++) {
      var o = l.toScreen(l.pose(len * i / 80).move);
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = accent.withValues(alpha: 0.85));
    for (var i = 1; i < 20; i++) {
      canvas.drawCircle(l.toScreen(l.pose(len * i / 20).move), 1.6,
          Paint()..color = accent.withValues(alpha: 0.7));
    }
    // Where it is now.
    var now = l.pose(at);
    _ghost(canvas, l.toScreen(now.move), box.size * s, now,
        alpha: 0.55, solid: true);
    canvas.drawCircle(l.toScreen(now.move), 4.5, Paint()..color = _dot);
  }

  void _paintValues(Canvas canvas, Size size, MotionClip c, ClipLayout l) {
    var len = math.max(c.length, 1e-3);
    var a = l.area;
    canvas.drawLine(a.bottomLeft, a.bottomRight,
        Paint()..color = Colors.white.withValues(alpha: 0.12));
    var x = 0.0;
    for (var p in l.ranges.keys) {
      var path = Path();
      for (var i = 0; i <= 100; i++) {
        var o = l.at(p, len * i / 100);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..color = curveColour(p));
      // Its name, in its colour, along the top.
      var tp = TextPainter(
          text: TextSpan(
              text: p.label,
              style: TextStyle(fontSize: 9.5, color: curveColour(p))),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(8 + x, 7));
      x += tp.width + 8;
    }
    // Where it is now.
    var px = l.xOf(at);
    canvas.drawLine(Offset(px, a.top), Offset(px, a.bottom),
        Paint()..color = _dot.withValues(alpha: 0.8));
  }

  void _paintHandles(Canvas canvas, ClipLayout l) {
    var times = [
      for (var h in l.handles)
        if (!h.ease) h.t
    ];
    var first = times.isEmpty ? 0.0 : times.reduce(math.min);
    var last = times.isEmpty ? 0.0 : times.reduce(math.max);
    for (var h in l.handles) {
      var lit = h == hover || h == picked;
      var colour =
          l.view == ClipView.graph ? curveColour(h.props.first) : Colors.white;
      if (h.ease) {
        var r = lit ? 5.0 : 3.6;
        var d = Path()
          ..moveTo(h.at.dx, h.at.dy - r)
          ..lineTo(h.at.dx + r, h.at.dy)
          ..lineTo(h.at.dx, h.at.dy + r)
          ..lineTo(h.at.dx - r, h.at.dy)
          ..close();
        canvas.drawPath(d, Paint()..color = studio.display);
        canvas.drawPath(
            d,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.3
              ..color = (lit ? colour : colour.withValues(alpha: 0.6)));
        continue;
      }
      var r = lit ? 5.5 : 4.2;
      // The start hollow, the end filled, those between half and half.
      var start = (h.t - first).abs() < 1e-6;
      var end = (h.t - last).abs() < 1e-6;
      canvas.drawCircle(
          h.at, r, Paint()..color = start ? studio.display : colour);
      canvas.drawCircle(
          h.at,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = start || lit ? 1.6 : 1
            ..color = end && !lit ? studio.display : colour);
      if (lit) {
        canvas.drawCircle(
            h.at,
            r + 3,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = colour.withValues(alpha: 0.4));
      }
    }
  }

  /// _paintOwn is an element's own style -- a fade, a wipe -- as frames
  /// across, drawn as the page draws it, and played large while hovered.
  void _paintOwn(Canvas canvas, Size size, MotionClip c) {
    var a = own!;
    var leaving = c.kind == MotionKind.leave;
    var len = math.max(c.length, 1e-3);
    var w = size.width, h = size.height;
    void frame(Rect r, double p) {
      var pose = Keyframe(
          frame: 0,
          values: leaving
              ? {KeyframeChannel.close: math.max(1e-3, p)}
              : {KeyframeChannel.reveal: p});
      var aspect = box.width / math.max(1, box.height);
      var bw = math.min(r.width * 0.7, r.height * 0.7 * aspect);
      var shape =
          Rect.fromCenter(center: r.center, width: bw, height: bw / aspect);
      canvas.save();
      canvas.clipRect(r);
      paintArriving(canvas, shape, a, pose, () {
        canvas.drawRRect(
            RRect.fromRectAndRadius(shape, Radius.circular(bw * 0.1)),
            Paint()..color = accent);
      });
      canvas.restore();
    }

    if (playing) {
      frame(Rect.fromLTWH(0, 22, w, h - 40), at / len);
    } else {
      const n = 5;
      var cell = (w - 16) / n;
      for (var i = 0; i < n; i++) {
        var r = Rect.fromLTWH(8 + i * cell, h * 0.25, cell - 4, h * 0.5);
        canvas.drawRect(
            r, Paint()..color = Colors.white.withValues(alpha: 0.03));
        frame(r, (i + 1) / n);
      }
    }
    _say(
        canvas,
        size,
        "Its own ${leaving ? "way out" : "arrival"}: "
        "${(leaving ? a.exit : a.preset).label} · "
        "${len.toStringAsFixed(2)} s${playing ? "" : " · hover to play"}");
  }

  void _ghost(Canvas canvas, Offset at, Size size, ClipPose p,
      {required double alpha, bool solid = false}) {
    var o = p.opacity.clamp(0.0, 1.0);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(p.turn * math.pi / 180);
    var r = Rect.fromCenter(
        center: Offset.zero,
        width: math.max(2, size.width * p.scale.abs()),
        height: math.max(2, size.height * p.scale.abs()));
    var rr = RRect.fromRectAndRadius(r, Radius.circular(r.shortestSide * 0.12));
    canvas.drawRRect(rr, Paint()..color = accent.withValues(alpha: alpha * o));
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = solid ? 1.4 : 1
          ..color = accent.withValues(
              alpha: (solid ? 0.9 : 0.35) * math.max(0.25, o)));
    canvas.restore();
  }

  void _dashedRect(Canvas canvas, Rect r, Color colour) {
    var paint = Paint()
      ..color = colour
      ..strokeWidth = 1;
    void line(Offset a, Offset b) {
      var len = (b - a).distance;
      var dir = (b - a) / math.max(1e-6, len);
      for (var d = 0.0; d < len; d += 6) {
        canvas.drawLine(a + dir * d, a + dir * math.min(len, d + 3), paint);
      }
    }

    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  void _say(Canvas canvas, Size size, String text) {
    var tp = TextPainter(
        text: TextSpan(
            text: text, style: TextStyle(fontSize: 10, color: studio.muted)),
        maxLines: 1,
        ellipsis: "…",
        textDirection: TextDirection.ltr)
      ..layout(maxWidth: size.width - 12);
    tp.paint(canvas, Offset(6, size.height - tp.height - 3));
  }

  @override
  bool shouldRepaint(_ClipPainter old) =>
      old.clip != clip ||
      old.at != at ||
      old.hover != hover ||
      old.picked != picked ||
      old.own != own ||
      old.ownSays != ownSays ||
      old.playing != playing ||
      old.layout?.size != layout?.size ||
      old.layout?.view != layout?.view ||
      old.accent != accent;
}

/// _Chips are small buttons on the screen's corner.
class _Chips extends StatelessWidget {
  final StudioColors studio;
  final Color accent;
  final List<(String, String, bool, VoidCallback)> chips;
  const _Chips(
      {required this.studio, required this.accent, required this.chips});

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        for (var (key, label, on, tap) in chips)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Material(
              color: on
                  ? accent.withValues(alpha: 0.25)
                  : studio.raised.withValues(alpha: 0.9),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                  side: BorderSide(color: on ? accent : studio.edge)),
              child: InkWell(
                key: ValueKey(key),
                onTap: tap,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 10,
                          color: on ? Colors.white : studio.text)),
                ),
              ),
            ),
          ),
      ]);
}
