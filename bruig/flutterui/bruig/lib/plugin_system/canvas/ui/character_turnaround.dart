import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/ui/character_puppet.dart';
import 'package:flutter/painting.dart';

// character_turnaround.dart is a sketch's turnaround sheet, laid out on the
// canvas beside it as an animator lays out a model sheet: each of its other
// views in a panel of its own to its right, the character's own place the
// view being drawn on, and lines across them all at the heights a turn has
// to keep -- the top of the head, the eyes, the chin, the shoulders, the
// waist, the hips, the knees and the ground. A panel clicked turns the
// character to that view, to draw on there. The view next to the one drawn
// on can be shown faintly over it, as a light table shows the drawing
// before.

/// TurnaroundPanel is one of the other views on the sheet: which, named,
/// and where it is laid out on the page.
class TurnaroundPanel {
  final String key;
  final String label;
  final Rect rect;
  const TurnaroundPanel(this.key, this.label, this.rect);
}

/// TurnaroundGuide is one of the lines across the sheet: what it marks and
/// how far down the page.
class TurnaroundGuide {
  final String label;
  final double y;
  const TurnaroundGuide(this.label, this.y);
}

/// Turnaround is [character]'s sheet on [frame].
class Turnaround {
  final CharacterElement character;
  final int frame;

  /// current is the view it is seen from: its own place on the sheet.
  final String current;
  final List<TurnaroundPanel> panels;
  final List<TurnaroundGuide> guides;
  const Turnaround._(this.character, this.frame, this.current, this.panels, this.guides);

  /// of is [e]'s sheet: a panel for each of its views but the one it is
  /// seen from -- each turned both ways, as the views are listed -- to its
  /// right, as big as it is, in a row.
  factory Turnaround.of(CharacterElement e, int frame, int frameRate,
      List<(String, String)> views) {
    var pose = e.inView(e.poseAtFrame(frame));
    var current = e.viewKey(pose);
    var b = e.bounds;
    var gap = b.width * 0.18;
    var panels = <TurnaroundPanel>[];
    for (var (key, label) in views) {
      if (key == current) continue;
      var x = b.right + gap + panels.length * (b.width + gap);
      panels.add(TurnaroundPanel(key, label.split(" · ").first,
          Rect.fromLTWH(x, b.top, b.width, b.height)));
    }
    // The heights the views keep, where the character stands now.
    var placed = CharacterPlacement.of(e, frame, frameRate: frameRate);
    var rig = placed.rig;
    double y(Offset local) => placed.toPage(local).dy;
    var head = rig.headCentre, r = rig.headRadii.height * rig.headScale;
    var guides = [
      TurnaroundGuide("Top of head", y(head - Offset(0, r))),
      TurnaroundGuide("Eyes", y(head + Offset(0, r * 0.2))),
      TurnaroundGuide("Chin", y(head + Offset(0, r))),
      TurnaroundGuide("Shoulders", y(Offset.lerp(rig.shoulderL, rig.shoulderR, 0.5)!)),
      TurnaroundGuide("Waist", y(Offset.lerp(rig.chest, rig.hips, 0.6)!)),
      TurnaroundGuide("Hips", y(rig.hips)),
      TurnaroundGuide("Knees", y(Offset.lerp(rig.kneeL, rig.kneeR, 0.5)!)),
      TurnaroundGuide("Ground", y(Offset(0, math.max(rig.ankleL.dy, rig.ankleR.dy) +
          rig.below * 0.06))),
    ];
    return Turnaround._(e, frame, current, panels, guides);
  }

  /// panelAt is the panel at [doc] on the page, or null.
  TurnaroundPanel? panelAt(Offset doc) {
    for (var p in panels) {
      if (p.rect.contains(doc)) return p;
    }
    return null;
  }

  /// right is where the sheet ends on the page.
  double get right => panels.isEmpty ? character.bounds.right : panels.last.rect.right;

  /// shownAs is the character as a panel draws it: at [rect], seen from the
  /// view [key] names, as it stands on this frame.
  CharacterElement shownAs(String key, Rect rect) {
    var at = key.indexOf("@");
    var panel = at < 0 ? key : key.substring(0, at);
    var parts = panel.split(",");
    var turn = double.tryParse(parts.first) ?? 0;
    var tilt = parts.length > 1 ? double.tryParse(parts[1]) ?? 0 : 0.0;
    var pose = character.poseAtFrame(frame);
    if (at >= 0) {
      var name = key.substring(at + 1);
      for (var v in character.views) {
        if (v.pose == name && v.posed != null) pose = v.posed!;
      }
    }
    pose = pose.withTurn(turn).withTilt(tilt);
    // Its own still pose, not the timeline's, which would turn it back.
    var moved = character.withBase(x: rect.left, y: rect.top, track: ElementTrack.empty)
        as CharacterElement;
    return moved.copyWith(pose: character.inView(pose));
  }

  /// neighbour is the view next round from the one it is seen from: what a
  /// light table shows faintly over it.
  String? get neighbour {
    double turnOf(String key) {
      var panel = key.split("@").first;
      return double.tryParse(panel.split(",").first) ?? 0;
    }

    var mine = turnOf(current);
    String? best;
    var nearest = double.infinity;
    for (var p in panels) {
      var d = (turnOf(p.key) - mine).abs();
      if (d > 0 && d < nearest) {
        nearest = d;
        best = p.key;
      }
    }
    return best;
  }
}

const Color _ink = Color(0xFF6E9BFF);

/// paintTurnaround draws [sheet]: its panels, each view in its own frame,
/// named under it; the lines across them all; and, with [onion], the view
/// next round faintly over the one drawn on. [at] takes a page point to
/// the screen; [scale] is screen pixels to a page unit.
void paintTurnaround(Canvas canvas, Turnaround sheet, Offset Function(Offset) at,
    double scale, Offset origin,
    {bool onion = false}) {
  var e = sheet.character;
  var frame = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = _ink.withValues(alpha: 0.45);
  // Each view, drawn as the character is drawn, in page units.
  for (var p in sheet.panels) {
    var r = Rect.fromPoints(at(p.rect.topLeft), at(p.rect.bottomRight));
    canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(4), const Radius.circular(6)),
        Paint()..color = const Color(0x14FFFFFF));
    canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(4), const Radius.circular(6)), frame);
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    paintElement(canvas, sheet.shownAs(p.key, p.rect), sheet.frame);
    canvas.restore();
    _label(canvas, p.label, Offset(r.center.dx, r.bottom + 8));
  }
  var own = Rect.fromPoints(at(e.bounds.topLeft), at(e.bounds.bottomRight));
  _label(canvas, "Drawing here", Offset(own.center.dx, own.bottom + 8), strong: true);
  // The light table: the view next round, faint, over the one drawn on.
  var key = onion ? sheet.neighbour : null;
  if (key != null) {
    canvas.saveLayer(null, Paint()..color = const Color(0x40FFFFFF));
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    paintElement(canvas, sheet.shownAs(key, e.bounds), sheet.frame);
    canvas.restore();
  }
  // The lines across, the left end named.
  var left = own.left - 70, right = at(Offset(sheet.right, 0)).dx + 12;
  var line = Paint()
    ..strokeWidth = 1
    ..color = _ink.withValues(alpha: 0.55);
  for (var g in sheet.guides) {
    var y = at(Offset(0, g.y)).dy;
    for (var x = left; x < right; x += 9) {
      canvas.drawLine(Offset(x, y), Offset(math.min(right, x + 5), y), line);
    }
    _label(canvas, g.label, Offset(left, y - 7), align: TextAlign.left, small: true);
  }
}

void _label(Canvas canvas, String text, Offset at,
    {TextAlign align = TextAlign.center, bool small = false, bool strong = false}) {
  var tp = TextPainter(
    text: TextSpan(
        text: text,
        style: TextStyle(
            fontSize: small ? 9.5 : 11,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
            color: _ink)),
    textDirection: TextDirection.ltr,
    textAlign: align,
  )..layout();
  var dx = align == TextAlign.center ? at.dx - tp.width / 2 : at.dx;
  tp.paint(canvas, Offset(dx, at.dy));
}
