import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/elements/stage_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/stage_gizmo.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// stage_nav_controls.dart is the 3D view controls floating at the right of a
// scene showing a 3D stage: an orbit ball to swing the camera, pads to drag for
// zoom and pan, and buttons to frame the selection and reset the camera. The
// bar's view-controls button folds them to the ball alone or hides them
// (StageNav).
//
// They steer the stage the controller says is steered (the selected element's,
// or the scene's first) and write its camera as anything else does. A drag is
// one undo step.

/// StageNavControls is the column of view controls.
class StageNavControls extends StatelessWidget {
  final CanvasController controller;
  const StageNavControls({required this.controller, super.key});

  @override
  Widget build(BuildContext context) {
    var stage = controller.steeredStage;
    if (stage == null || controller.stageNav == StageNav.none) {
      return const SizedBox.shrink();
    }
    var colors = ThemeNotifier.of(context).colors;
    var camera = stage.cameraAt(controller.frame);
    var all = controller.stageNav == StageNav.all;
    var framable = controller.selection.length == 1 &&
        controller.document
                .elementById(controller.selection.first)
                ?.base
                .spot !=
            null;
    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 6),
          child: Text(text,
              style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _OrbitBall(controller: controller, camera: camera),
      if (all) ...[
        const SizedBox(height: 8),
        _NavPad(
          key: const ValueKey("stageNavZoom"),
          icon: Icons.zoom_in,
          tooltip: "Drag up to bring the camera nearer, down to take it "
              "further off",
          controller: controller,
          onDrag: (d) =>
              controller.dollyBy(math.exp(d.dy * 0.01), transient: true),
        ),
        label("Zoom"),
        _NavPad(
          key: const ValueKey("stageNavPan"),
          icon: Icons.open_with,
          tooltip: "Drag to slide the camera sideways and up",
          controller: controller,
          onDrag: (d) => controller.panCameraBy(
              d / _pageScale(context, controller),
              transient: true),
        ),
        label("Pan"),
        _NavPad(
          key: const ValueKey("stageNavFrame"),
          icon: Icons.center_focus_strong_outlined,
          tooltip: framable
              ? "Frame the selected element (F)"
              : "Frame the selected element (F) — select something standing "
                  "on the stage first",
          controller: controller,
          onTap: framable ? controller.frameSelected : null,
        ),
        label("Frame"),
        _NavPad(
          key: const ValueKey("stageNavReset"),
          icon: Icons.restart_alt,
          tooltip: "Put the camera back where a stage's camera starts (Home)",
          controller: controller,
          onTap: controller.resetCamera,
        ),
        label("Reset"),
      ],
    ]);
  }

  /// _pageScale is screen pixels to a page unit, so a pad's drag pans the
  /// stage by as much as the pointer went.
  static double _pageScale(BuildContext context, CanvasController c) =>
      c.viewScale <= 0 ? 1 : c.viewScale;
}

/// _NavPad is one round control: dragged, or pressed.
class _NavPad extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final CanvasController controller;
  final void Function(Offset delta)? onDrag;
  final VoidCallback? onTap;

  const _NavPad(
      {required this.icon,
      required this.tooltip,
      required this.controller,
      this.onDrag,
      this.onTap,
      super.key});

  @override
  State<_NavPad> createState() => _NavPadState();
}

class _NavPadState extends State<_NavPad> {
  bool _held = false;

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var off = widget.onDrag == null && widget.onTap == null;
    var ink = off
        ? colors.onSurfaceVariant.withValues(alpha: 0.35)
        : _held
            ? colors.onPrimary
            : colors.onSurface;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: off
            ? SystemMouseCursors.basic
            : widget.onDrag != null
                ? (_held
                    ? SystemMouseCursors.grabbing
                    : SystemMouseCursors.grab)
                : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onPanStart: widget.onDrag == null
              ? null
              : (_) {
                  widget.controller.beginInteraction();
                  setState(() => _held = true);
                },
          onPanUpdate:
              widget.onDrag == null ? null : (d) => widget.onDrag!(d.delta),
          onPanEnd: widget.onDrag == null
              ? null
              : (_) {
                  widget.controller.endInteraction();
                  setState(() => _held = false);
                },
          onPanCancel: widget.onDrag == null
              ? null
              : () {
                  if (_held) widget.controller.endInteraction();
                  setState(() => _held = false);
                },
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _held ? colors.primary : colors.surfaceContainerLow,
              border: Border.all(
                  color: _held ? colors.primary : colors.outlineVariant),
            ),
            child: Icon(widget.icon, size: 18, color: ink),
          ),
        ),
      ),
    );
  }
}

/// _OrbitBall is the orbit ball: the stage's three ways as the camera
/// sees them. Dragged, it swings the camera round; an axis clicked looks
/// along it.
class _OrbitBall extends StatefulWidget {
  final CanvasController controller;
  final StageCamera camera;
  const _OrbitBall({required this.controller, required this.camera});

  /// size is how wide it is.
  static const double size = 92;

  @override
  State<_OrbitBall> createState() => _OrbitBallState();
}

class _OrbitBallState extends State<_OrbitBall> {
  bool _held = false;
  bool _moved = false;

  void _click(Offset at) {
    var hit = orbitAxes(widget.camera, _OrbitBall.size)
        .reversed
        .where((a) => (a.at - at).distance < 12)
        .firstOrNull;
    if (hit == null) return;
    widget.controller.steer(
        (c) => c.copyWith(yaw: hit.look.$1 ?? c.yaw, pitch: hit.look.$2));
  }

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return Tooltip(
      message: "Drag to swing the camera round the stage. Click an axis to "
          "look along it.",
      child: MouseRegion(
        cursor: _held ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
        child: GestureDetector(
          key: const ValueKey("stageNavOrbit"),
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _click(d.localPosition),
          onPanStart: (_) {
            widget.controller.beginInteraction();
            setState(() {
              _held = true;
              _moved = false;
            });
          },
          onPanUpdate: (d) {
            _moved = true;
            widget.controller
                .orbitBy(d.delta.dx * 0.4, d.delta.dy * 0.4, transient: true);
          },
          onPanEnd: (_) {
            widget.controller.endInteraction();
            setState(() => _held = false);
          },
          onPanCancel: () {
            if (_held) widget.controller.endInteraction();
            setState(() => _held = false);
          },
          child: Container(
            width: _OrbitBall.size,
            height: _OrbitBall.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.surfaceContainerLow.withValues(alpha: 0.85),
              border: Border.all(
                  color:
                      _held && _moved ? colors.primary : colors.outlineVariant),
            ),
            child: CustomPaint(painter: _OrbitBallPainter(widget.camera)),
          ),
        ),
      ),
    );
  }
}

/// OrbitAxis is one end of one of the stage's axes on the orbit ball: where it
/// is drawn, its letter (none for the far ends), its colour, how far towards
/// the camera it points, and the yaw (null keeps the camera's) and pitch that
/// look along it.
typedef OrbitAxis = ({
  Offset at,
  String name,
  Color colour,
  double depth,
  (double?, double) look,
});

/// orbitAxes are the six ends of the stage's three axes as [camera] sees
/// them, on a ball [size] across, furthest first so the nearest draw on top.
List<OrbitAxis> orbitAxes(StageCamera camera, double size) {
  var yaw = camera.yaw * math.pi / 180, pitch = camera.pitch * math.pi / 180;
  // From the eye to what it looks at, its right along the floor, and
  // its up, as StageView has them.
  var f = (
    -math.sin(yaw) * math.cos(pitch),
    -math.sin(pitch),
    -math.cos(yaw) * math.cos(pitch)
  );
  var r = (-f.$3, 0.0, f.$1);
  var rl = math.sqrt(r.$1 * r.$1 + r.$3 * r.$3);
  r = rl == 0 ? (1.0, 0.0, 0.0) : (r.$1 / rl, 0.0, r.$3 / rl);
  var u = (
    r.$2 * f.$3 - r.$3 * f.$2,
    r.$3 * f.$1 - r.$1 * f.$3,
    r.$1 * f.$2 - r.$2 * f.$1
  );
  double dot((double, double, double) a, (double, double, double) b) =>
      a.$1 * b.$1 + a.$2 * b.$2 + a.$3 * b.$3;
  var c = size / 2, reach = size * 0.34;
  var ends = <(String, (double, double, double), Color, (double?, double))>[
    ("X", (1, 0, 0), gizmoColours[GizmoPart.x]!, (90, 0)),
    ("Y", (0, 1, 0), gizmoColours[GizmoPart.y]!, (null, 89)),
    ("Z", (0, 0, 1), gizmoColours[GizmoPart.z]!, (0, 0)),
    ("", (-1, 0, 0), gizmoColours[GizmoPart.x]!, (-90, 0)),
    ("", (0, -1, 0), gizmoColours[GizmoPart.y]!, (null, -10)),
    ("", (0, 0, -1), gizmoColours[GizmoPart.z]!, (180, 0)),
  ];
  var axes = <OrbitAxis>[
    for (var (name, v, colour, look) in ends)
      (
        at: Offset(c + dot(v, r) * reach, c - dot(v, u) * reach),
        name: name,
        colour: colour,
        depth: -dot(v, f),
        look: look,
      ),
  ];
  axes.sort((a, b) => a.depth.compareTo(b.depth));
  return axes;
}

class _OrbitBallPainter extends CustomPainter {
  final StageCamera camera;
  const _OrbitBallPainter(this.camera);

  @override
  void paint(Canvas canvas, Size size) {
    var c = size.center(Offset.zero);
    for (var a in orbitAxes(camera, size.width)) {
      var named = a.name.isNotEmpty;
      var colour = named ? a.colour : a.colour.withValues(alpha: 0.45);
      if (named) {
        canvas.drawLine(
            c,
            a.at,
            Paint()
              ..color = colour
              ..strokeWidth = 2
              ..strokeCap = StrokeCap.round);
      }
      canvas.drawCircle(a.at, named ? 8 : 6, Paint()..color = colour);
      if (named) {
        var text = TextPainter(
          text: TextSpan(
              text: a.name,
              style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, a.at - Offset(text.width / 2, text.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_OrbitBallPainter old) =>
      old.camera.yaw != camera.yaw || old.camera.pitch != camera.pitch;
}
