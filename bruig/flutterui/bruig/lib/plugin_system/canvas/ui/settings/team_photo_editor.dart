import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/render/image_store.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// team_photo_editor.dart is where each player's face is picked out of one
// photo of the whole squad: the photo, with a circle on it for every player
// -- the shape their portrait token is -- each moved, sized and turned until
// it is round that player's face.

/// TeamPhotoEditor shows [team]'s team photo with every player's crop on it.
/// One is chosen at a time: tap a circle, or pick the player from the list.
/// The chosen circle is dragged to move it, its edge handle to size it, and
/// the handle above it to turn it.
///
/// The photo zooms -- scroll or pinch over it, the zoom buttons, or Focus to
/// go straight to the chosen face -- and, zoomed, is dragged about from
/// anywhere off the circle. Shift-scroll sizes the chosen circle.
class TeamPhotoEditor extends StatefulWidget {
  final TeamElement team;
  final VoidCallback begin;
  final void Function(TeamElement) write;
  final VoidCallback commit;

  /// images is where the photo is read from: the canvas's own picture store
  /// unless one is given, as a test gives one.
  final CanvasImageSource? images;

  const TeamPhotoEditor({
    super.key,
    required this.team,
    required this.begin,
    required this.write,
    required this.commit,
    this.images,
  });

  @override
  State<TeamPhotoEditor> createState() => _TeamPhotoEditorState();
}

enum _Grab { move, size, turn, pan }

/// teamPhotoMargin is the room left round the photo, so the handles of a
/// circle at its very edge can still be reached.
const double teamPhotoMargin = 22;

/// teamPhotoMaxZoom is as far in as the photo goes.
const double teamPhotoMaxZoom = 12;

class _TeamPhotoEditorState extends State<TeamPhotoEditor> {
  final CanvasImageStore _store = CanvasImageStore();
  int _chosen = 0;
  _Grab? _grab;

  /// _live is the circle being dragged, as the drag has left it -- two moves
  /// can arrive before the team written by the first has come back -- and as
  /// it is kept: without a size of its own until it is sized.
  PhotoCrop? _live;

  /// _zoom and _pan are how far in the photo is shown and where: one is the
  /// whole photo, and the pan is in the editor's own pixels.
  double _zoom = 1;
  Offset _pan = Offset.zero;

  @override
  void initState() {
    super.initState();
    _store.addListener(_loaded);
  }

  @override
  void dispose() {
    _store.removeListener(_loaded);
    _store.dispose();
    super.dispose();
  }

  void _loaded() {
    if (mounted) setState(() {});
  }

  TeamElement get team => widget.team;

  /// _people is the players who can have a face: everybody but the ball.
  List<int> get _people => [
        for (var i = 0; i < team.players.length; i++)
          if (!team.players[i].ball) i,
      ];

  int get chosen {
    var people = _people;
    if (people.isEmpty) return -1;
    return people.contains(_chosen) ? _chosen : people.first;
  }

  /// _raw is player [i]'s crop as it is kept: their own where they have one,
  /// and otherwise where the guess puts them, with no size of its own.
  PhotoCrop _raw(int i, double aspect) {
    var own = team.players[i].crop;
    if (own != null) return own;
    var at = team.cropOf(i, aspect);
    return PhotoCrop(x: at.x, y: at.y);
  }

  void _setCrop(int i, PhotoCrop crop) =>
      widget.write(team.withPlayer(i, team.players[i].copyWith(crop: crop)));

  /// _View is where the photo is in the editor: its top-left corner and how
  /// many editor pixels an image pixel is.
  ({Offset origin, double scale}) _view(Size box, double iw, double ih) {
    var base = math.min((box.width - 2 * teamPhotoMargin) / iw,
        (box.height - 2 * teamPhotoMargin) / ih);
    var c = box.center(Offset.zero);
    var fitted = c - Offset(iw, ih) * base / 2;
    return (origin: c + (fitted - c) * _zoom + _pan, scale: base * _zoom);
  }

  /// _zoomAbout zooms by [factor], keeping what is under [at] there.
  void _zoomAbout(double factor, Offset at, Size box) {
    var next = (_zoom * factor).clamp(1.0, teamPhotoMaxZoom);
    var k = next / _zoom;
    var c = box.center(Offset.zero);
    setState(() {
      // A point p on the screen is c + (q - c) * zoom + pan for the photo's
      // own q, so holding p still means scaling the pan about it.
      _pan = (at - c) - ((at - c) - _pan) * k;
      _zoom = next;
      if (_zoom <= 1.0001) _pan = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) {
    var image = (widget.images ?? _store)
        .resolve(team.teamPhoto, const BackgroundRemoval());
    var colors = ThemeNotifier.of(context).colors;
    if (image == null) {
      return SizedBox(
        height: 60,
        child: Center(
            child: Text("Loading photo…",
                style:
                    TextStyle(fontSize: 11, color: colors.onSurfaceVariant))),
      );
    }
    var iw = image.width.toDouble(), ih = image.height.toDouble();
    var aspect = iw / ih;
    var who = chosen;
    var crop = who < 0 ? null : team.cropOf(who, aspect);

    return LayoutBuilder(builder: (context, constraints) {
      var w = constraints.maxWidth.isFinite ? constraints.maxWidth : 280.0;
      var h = math.min((w - 2 * teamPhotoMargin) / aspect, 300.0) +
          2 * teamPhotoMargin;
      var box = Size(w, h);
      var v = _view(box, iw, ih);
      Offset toView(Offset p) => v.origin + p * v.scale;
      Offset toImage(Offset q) => (q - v.origin) / v.scale;

      /// hit is the player whose circle is under [q], nearest first.
      int? hit(Offset q) {
        var at = toImage(q);
        int? best;
        var bestD = double.infinity;
        for (var i in _people) {
          var c = team.cropOf(i, aspect);
          var dist = (Offset(c.x * iw, c.y * ih) - at).distance;
          if (dist <= c.size * iw * 1.1 && dist < bestD) {
            best = i;
            bestD = dist;
          }
        }
        return best;
      }

      void sizeBy(double factor) {
        if (crop == null) return;
        widget.begin();
        _setCrop(
            who,
            _raw(who, aspect)
                .copyWith(radius: (crop.size * factor).clamp(0.005, 0.6)));
        widget.commit();
      }

      void focus() {
        if (crop == null) return;
        // The chosen face filling about half the editor's height.
        var r = crop.size * iw;
        var base = math.min(
            (w - 2 * teamPhotoMargin) / iw, (h - 2 * teamPhotoMargin) / ih);
        var zoom =
            (h * 0.25 / math.max(r * base, 1e-6)).clamp(1.0, teamPhotoMaxZoom);
        var c = box.center(Offset.zero);
        var fitted = c - Offset(iw, ih) * base / 2;
        var at = fitted + Offset(crop.x * iw, crop.y * ih) * base;
        setState(() {
          _zoom = zoom;
          _pan = -(at - c) * zoom;
        });
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Listener(
            onPointerSignal: (e) {
              if (e is! PointerScrollEvent) return;
              var factor = math.pow(1.0025, -e.scrollDelta.dy).toDouble();
              if (HardwareKeyboard.instance.isShiftPressed) {
                sizeBy(factor);
              } else {
                _zoomAbout(factor, e.localPosition, box);
              }
            },
            onPointerPanZoomUpdate: (e) {
              if (e.scale != 1) {
                _zoomAbout(1 + (e.scale - 1) * 0.08, e.localPosition, box);
              }
            },
            child: GestureDetector(
              key: const ValueKey("teamPhotoEditor"),
              behavior: HitTestBehavior.opaque,
              // What is grabbed is what was under the pointer when it went
              // down, not where it had got to by the time it counted as a
              // drag: a handle is smaller than that distance.
              dragStartBehavior: DragStartBehavior.down,
              onTapUp: (d) {
                var best = hit(d.localPosition);
                if (best != null) setState(() => _chosen = best);
              },
              onDoubleTap: focus,
              onPanStart: (d) {
                var p = d.localPosition;
                _grab = _Grab.pan;
                if (crop != null) {
                  var c = Offset(crop.x * iw, crop.y * ih);
                  var r = crop.size * iw;
                  var t = crop.turn * math.pi / 180;
                  var sizeHandle =
                      toView(c + Offset(math.cos(t), math.sin(t)) * r);
                  var up = Offset(math.sin(t), -math.cos(t));
                  var turnHandle = toView(c) + up * (r * v.scale + 16);
                  if ((p - turnHandle).distance < 12) {
                    _grab = _Grab.turn;
                  } else if ((p - sizeHandle).distance < 12) {
                    _grab = _Grab.size;
                  } else if ((toImage(p) - c).distance <= r * 1.1 &&
                      hit(p) == who) {
                    // Inside it -- and not nearer another player's middle,
                    // where two circles overlap.
                    _grab = _Grab.move;
                  }
                }
                // Pressed on another player's circle: that player, moved.
                if (_grab == _Grab.pan) {
                  var other = hit(p);
                  if (other == null) return;
                  setState(() => _chosen = other);
                  who = other;
                  _grab = _Grab.move;
                }
                _live = _raw(who, aspect);
                widget.begin();
              },
              onPanUpdate: (d) {
                var grab = _grab;
                if (grab == null) return;
                if (grab == _Grab.pan) {
                  if (_zoom > 1) setState(() => _pan += d.delta);
                  return;
                }
                var now = _live;
                if (now == null) return;
                var c = Offset(now.x * iw, now.y * ih);
                var p = toImage(d.localPosition);
                switch (grab) {
                  case _Grab.move:
                    var moved = c + d.delta / v.scale;
                    _setCrop(
                        who,
                        _live = now.copyWith(
                            x: (moved.dx / iw).clamp(0.0, 1.0),
                            y: (moved.dy / ih).clamp(0.0, 1.0)));
                  case _Grab.size:
                    _setCrop(
                        who,
                        _live = now.copyWith(
                            radius: ((p - c).distance / iw).clamp(0.005, 0.6)));
                  case _Grab.turn:
                    var o = p - c;
                    var deg = math.atan2(o.dx, -o.dy) * 180 / math.pi;
                    _setCrop(
                        who, _live = now.copyWith(turn: deg.roundToDouble()));
                  case _Grab.pan:
                    break;
                }
              },
              onPanEnd: (_) {
                if (_grab != null && _grab != _Grab.pan) widget.commit();
                _grab = null;
                _live = null;
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.precise,
                child: SizedBox(
                  width: w,
                  height: h,
                  child: CustomPaint(
                    painter: _PhotoPainter(
                      image: image,
                      origin: v.origin,
                      scale: v.scale,
                      crops: [
                        for (var i in _people)
                          (i, team.cropOf(i, aspect), team.players[i].number),
                      ],
                      chosen: who,
                      accent: colors.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // The view of the photo: how far in, and back out again.
          CanvasWrap(children: [
            CanvasNumberField(
              key: const ValueKey("teamPhotoZoom"),
              label: "Zoom",
              value: _zoom,
              min: 1,
              max: teamPhotoMaxZoom,
              decimals: 1,
              width: 50,
              onChanged: (z) =>
                  _zoomAbout(z / _zoom, box.center(Offset.zero), box),
            ),
            CanvasIconButton(
              key: const ValueKey("teamPhotoZoomIn"),
              icon: Icons.zoom_in,
              tooltip: "Zoom in",
              onPressed: () => _zoomAbout(1.5, box.center(Offset.zero), box),
            ),
            CanvasIconButton(
              key: const ValueKey("teamPhotoZoomOut"),
              icon: Icons.zoom_out,
              tooltip: "Zoom out",
              onPressed: _zoom <= 1
                  ? null
                  : () => _zoomAbout(1 / 1.5, box.center(Offset.zero), box),
            ),
            CanvasIconButton(
              key: const ValueKey("teamPhotoFocus"),
              icon: Icons.center_focus_strong_outlined,
              tooltip: "Focus player",
              onPressed: crop == null ? null : focus,
            ),
            CanvasIconButton(
              key: const ValueKey("teamPhotoFit"),
              icon: Icons.fit_screen_outlined,
              tooltip: "Whole photo",
              onPressed: _zoom <= 1
                  ? null
                  : () => setState(() {
                        _zoom = 1;
                        _pan = Offset.zero;
                      }),
            ),

            // Every circle's starting size, which each player's own size
            // then starts from.
            CanvasNumberField(
              key: const ValueKey("teamPhotoDefaultSize"),
              label: "Circle size",
              value: (team.photoCropSize ?? team.photoCropGuess(aspect)) * 100,
              min: 0.5,
              max: 60,
              decimals: 1,
              width: 54,
              onChanged: (v) {
                widget.begin();
                widget.write(team.copyWith(photoCropSize: v / 100));
              },
              onCommit: widget.commit,
            ),
            CanvasIconButton(
              key: const ValueKey("teamPhotoSizesReset"),
              icon: Icons.blur_circular,
              tooltip: "All to circle size",
              onPressed: () {
                widget.begin();
                widget.write(team.copyWith(players: [
                  for (var p in team.players)
                    p.crop == null
                        ? p
                        : p.copyWith(crop: p.crop!.copyWith(clearRadius: true)),
                ]));
                widget.commit();
              },
            ),
            const CanvasHint("Circle size is where every player's circle "
                "starts. Sizing one circle on its own keeps that one's size; "
                "the button beside it puts them all back to this size."),
          ]),
          if (crop != null)
            CanvasWrap(children: [
              _CropPreview(image: image, crop: crop, size: 40),
              CanvasDropdown<int>(
                key: const ValueKey("teamPhotoPlayer"),
                label: "Player",
                value: who,
                width: 118,
                options: [
                  for (var i in _people)
                    (
                      i,
                      [team.players[i].number, team.players[i].name]
                          .where((s) => s.isNotEmpty)
                          .join(" ")
                    ),
                ],
                onChanged: (v) => setState(() => _chosen = v),
              ),
              CanvasNumberField(
                key: const ValueKey("teamPhotoSize"),
                label: "Size",
                value: crop.size * 100,
                min: 0.5,
                max: 60,
                decimals: 1,
                width: 54,
                onChanged: (v) {
                  widget.begin();
                  _setCrop(who, _raw(who, aspect).copyWith(radius: v / 100));
                },
                onCommit: widget.commit,
              ),
              CanvasNumberField(
                key: const ValueKey("teamPhotoTurn"),
                label: "Turn",
                value: crop.turn,
                min: -180,
                max: 180,
                width: 54,
                suffix: "°",
                onChanged: (v) {
                  widget.begin();
                  _setCrop(who, _raw(who, aspect).copyWith(turn: v));
                },
                onCommit: widget.commit,
              ),
              CanvasIconButton(
                key: const ValueKey("teamPhotoReset"),
                icon: Icons.restart_alt,
                tooltip: "Reset circle",
                onPressed: () {
                  widget.begin();
                  widget.write(team.withPlayer(
                      who, team.players[who].copyWith(clearCrop: true)));
                  widget.commit();
                },
              ),
            ]),
        ],
      );
    });
  }
}

/// _PhotoPainter draws the team photo and every player's circle on it: the
/// chosen one bright, with its handles, the rest faint with their numbers.
class _PhotoPainter extends CustomPainter {
  final ui.Image image;
  final Offset origin;
  final double scale;
  final List<(int, PhotoCrop, String)> crops;
  final int chosen;
  final Color accent;

  _PhotoPainter({
    required this.image,
    required this.origin,
    required this.scale,
    required this.crops,
    required this.chosen,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    var iw = image.width.toDouble(), ih = image.height.toDouble();
    var dst = Rect.fromLTWH(origin.dx, origin.dy, iw * scale, ih * scale);
    canvas.drawImageRect(image, Rect.fromLTWH(0, 0, iw, ih), dst,
        Paint()..filterQuality = FilterQuality.medium);

    // Everything but the chosen face a little darker, so it stands out.
    PhotoCrop? mine;
    for (var (i, c, _) in crops) {
      if (i == chosen) mine = c;
    }
    if (mine != null) {
      var centre = origin + Offset(mine.x * iw, mine.y * ih) * scale;
      var r = mine.size * iw * scale;
      canvas.drawPath(
          Path()
            ..fillType = PathFillType.evenOdd
            ..addRect(dst)
            ..addOval(Rect.fromCircle(center: centre, radius: r)),
          Paint()..color = const Color(0x88000000));
    }

    for (var (i, c, number) in crops) {
      var centre = origin + Offset(c.x * iw, c.y * ih) * scale;
      var r = c.size * iw * scale;
      var on = i == chosen;
      canvas.drawCircle(
          centre,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = on ? 2 : 1.2
            ..color = on ? accent : const Color(0xCCFFFFFF));
      if (number.isNotEmpty) {
        var tp = TextPainter(
          text: TextSpan(
              text: number,
              style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFFFFFF),
                  shadows: [Shadow(blurRadius: 2)])),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, centre + Offset(-tp.width / 2, r + 1));
      }
      if (!on) continue;
      var t = c.turn * math.pi / 180;
      var up = Offset(math.sin(t), -math.cos(t));
      var across = Offset(math.cos(t), math.sin(t));
      var handle = Paint()..color = accent;
      var ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFFFFFFF);
      // Which way is up in the token, and the handle that turns it.
      var turnAt = centre + up * (r + 16);
      canvas.drawLine(
          centre + up * r,
          turnAt,
          Paint()
            ..strokeWidth = 1.5
            ..color = accent);
      canvas.drawCircle(turnAt, 5, handle);
      canvas.drawCircle(turnAt, 5, ring);
      // The handle that sizes it.
      var sizeAt = centre + across * r;
      canvas.drawRect(
          Rect.fromCenter(center: sizeAt, width: 9, height: 9), handle);
      canvas.drawRect(
          Rect.fromCenter(center: sizeAt, width: 9, height: 9), ring);
    }
  }

  @override
  bool shouldRepaint(_PhotoPainter old) =>
      old.image != image ||
      old.scale != scale ||
      old.origin != origin ||
      old.chosen != chosen ||
      old.accent != accent ||
      old.crops.length != crops.length ||
      [
        for (var k = 0; k < crops.length; k++)
          old.crops[k].$2 != crops[k].$2 || old.crops[k].$3 != crops[k].$3
      ].any((x) => x);
}

/// _CropPreview is the chosen player's token as it will be drawn: their part
/// of the photo, in a circle.
class _CropPreview extends StatelessWidget {
  final ui.Image image;
  final PhotoCrop crop;
  final double size;
  const _CropPreview(
      {required this.image, required this.crop, required this.size});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _CropPainter(image, crop)),
      );
}

class _CropPainter extends CustomPainter {
  final ui.Image image;
  final PhotoCrop crop;
  _CropPainter(this.image, this.crop);

  @override
  void paint(Canvas canvas, Size size) {
    var r = size.shortestSide / 2;
    var iw = image.width.toDouble(), ih = image.height.toDouble();
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: r)));
    canvas.scale(r / math.max(crop.size * iw, 1));
    canvas.rotate(-crop.turn * math.pi / 180);
    canvas.translate(-crop.x * iw, -crop.y * ih);
    canvas.drawImage(
        image, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    canvas.restore();
    canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        r - 0.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0x66000000));
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image || old.crop != crop;
}
