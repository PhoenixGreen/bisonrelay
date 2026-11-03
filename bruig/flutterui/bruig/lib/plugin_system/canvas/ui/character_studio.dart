import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_asset.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_gltf.dart'
    show HumanBone;
import 'package:bruig/plugin_system/canvas/model/elements/character_lipsync.dart'
    show mouthsOfWord;
import 'package:bruig/plugin_system/canvas/model/elements/character_motion.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_palettes.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_reference.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart'
    show BackgroundRemoval;
import 'package:bruig/plugin_system/canvas/render/character/character_parts.dart'
    show drawingProxy, drawnKey, drawnRig, faceForChart, partAt, shapesOnParts;
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/character/reference_trace.dart';
import 'package:bruig/plugin_system/canvas/render/character/reference_sheet.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/character_library.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/character_turnaround.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/image_picking.dart';
import 'package:bruig/plugin_system/canvas/ui/recent_pictures.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/character_appearance_settings.dart'
    show AppearanceEditor;
import 'package:bruig/plugin_system/canvas/ui/settings/character_layers_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/character_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/character_drawing_settings.dart'
    show drawingTarget;
import 'package:bruig/plugin_system/canvas/ui/settings/vector_settings.dart'
    show vectorSettings;
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// character_studio.dart is the Character Studio: a Sketch character made a
// step at a time, as character designers work -- from a model sheet laid
// under the views, through its proportions, its drawing part by part, its
// faces, its rig, to a check that it agrees with itself. The page is given
// over to it: the step bar in the band's place, the step's own in the
// sidebar, and on the canvas its turnaround with the reference over each
// view. Ken asked for a workflow like other character software; the board
// is "Character Studio" on the design canvas.

/// StudioWorkspace is one of the Studio's workspaces: a job, with only its
/// own controls -- as professional character tools give each job a mode
/// (Ken's boards, 2026-11-01).
enum StudioWorkspace {
  start("Start", Icons.add_circle_outline,
      "Pick the character this is, from the library, or begin it: what it is made of, who it starts as, and a model sheet to draw it from."),
  body("Body", Icons.accessibility_new,
      "Shape the figure: how tall in heads, its build, its face and limbs; how it is drawn. Fit it to the reference, joints and all."),
  clothes("Hair & clothes", Icons.checkroom,
      "Everything worn, inside to outside, and the hair."),
  draw("Draw", Icons.brush,
      "Draw the character view by view and part by part, over its reference. Trace the reference to start, then draw what the picture was too small to show."),
  rig("Rig", Icons.account_tree_outlined,
      "Put the bones where the drawing bends, and try it in a pose."),
  face("Face", Icons.face_retouching_natural,
      "Every face control in one place: expressions, the mouths lip sync uses, and on a drawn character the eyes, brows and mouths drawn for each state."),
  motion("Motion", Icons.directions_run,
      "Its motions, each tried on it here, and its walk tuned to it: how long a stride, how much bounce. A game plays the motions chosen below."),
  test("Test", Icons.fact_check_outlined,
      "Try it before you use it: play a motion, drive it with the arrow keys, say a line, and run the checks.");

  final String label;
  final IconData icon;
  final String says;
  const StudioWorkspace(this.label, this.icon, this.says);

  /// drawnOnly is whether only a drawn character has it.
  bool get drawnOnly => this == StudioWorkspace.draw;
}

/// _boneName is [b]'s name as the rest of the character says it: "Left
/// upper arm". A model's left is its own, which is the page's right as it
/// faces the reader; a character's left is the page's -- see BodyLayer.armL
/// and LoadedModel.of -- so the two sides change names.
String _boneName(HumanBone b) {
  var n = b.name;
  n = n.startsWith("left")
      ? "right${n.substring(4)}"
      : n.startsWith("right")
          ? "left${n.substring(5)}"
          : n;
  var words =
      n.replaceAllMapped(RegExp("[A-Z]"), (m) => " ${m[0]!.toLowerCase()}");
  return words[0].toUpperCase() + words.substring(1);
}

/// StudioFacePart is a part of the face the Face workspace works on: what
/// its chart draws, the states of it shown, and the controls that move it
/// between them.
enum StudioFacePart {
  eyes("Eyes", ChartKind.eyes, null, [
    FaceControl.eyesOpen,
    FaceControl.squint,
    FaceControl.lookX,
    FaceControl.lookY
  ]),
  brows("Brows", ChartKind.brows, null,
      [FaceControl.browRaise, FaceControl.browSqueeze, FaceControl.browWorry]),
  speech("Mouth: speech", ChartKind.mouth, {
    "rest",
    "closed",
    "teeth",
    "open",
    "wide",
    "round",
    "pucker",
    "lip",
    "tongue"
  }, []),
  feeling("Mouth: feeling", ChartKind.mouth, {"smile", "grin", "frown", "gasp"},
      [FaceControl.smile, FaceControl.jaw, FaceControl.wide]),
  turn("Head", null, null, [FaceControl.turn, FaceControl.nod]);

  final String label;

  /// chart is the chart its states are drawn in, and only these of its
  /// states its own -- or all of them.
  final ChartKind? chart;
  final Set<String>? only;
  final List<FaceControl> controls;
  const StudioFacePart(this.label, this.chart, this.only, this.controls);

  /// states is its chart's states, by key and name.
  List<(String, String)> get states => [
        for (var s in chart?.keys ?? const <(String, String)>[])
          if (only == null || only!.contains(s.$1)) s,
      ];
}

/// StudioView is which way round the Studio shows the character.
enum StudioView {
  front("Front", 0),
  threeQuarter("Three-quarter", 45),
  side("Side", 90),
  back("Back", 180),
  all("All views", 0);

  final String label;
  final double turn;
  const StudioView(this.label, this.turn);
}

/// _frontKey, _sideKey and _backKey are the views a sheet's figures are
/// taken for, left to right.
const _figureKeys = ["0,0", "90,0", "180,0"];

/// _viewNames are what each cut can be taken as. A sketch seen from 90°
/// faces left, and from 270° right: a side is taken for the one it faces
/// as, or a trace of it walks one way and looks the other.
const _cutNames = <String, String>{
  "0,0": "Front",
  "90,0": "Side, facing left",
  "270,0": "Side, facing right",
  "180,0": "Back",
  referenceFaces: "Faces",
  "": "Not used",
};

/// sheetPixels reads stored picture [assetId] as pixels, or null.
Future<SheetPixels?> sheetPixels(String assetId) async {
  var bytes = await CanvasAssets.load(assetId);
  if (bytes == null) return null;
  try {
    var codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
    var img = (await codec.getNextFrame()).image;
    var rgba = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) return null;
    return SheetPixels(rgba.buffer.asUint8List(), img.width, img.height);
  } catch (_) {
    return null;
  }
}

/// readReference makes picture [assetId] sketch [id]'s reference: its
/// figures found and taken as front, side and back, left to right, its
/// widest other part as the faces; each figure measured; and its colours
/// the character's palette. One step to undo. What it says back is how it
/// went.
Future<String> readReference(
    CanvasController c, String id, String assetId) async {
  var p = await sheetPixels(assetId);
  if (p == null) return "That picture could not be read.";
  var found = findCuts(p);
  var figures = [
    for (var f in found)
      if (f.figure) f.rect
  ];
  var others = [
    for (var f in found)
      if (!f.figure) f.rect
  ]..sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
  var cuts = <String, Rect>{};
  for (var (i, r) in figures.take(3).indexed) {
    var key = _figureKeys[i];
    // A side facing right is the view from 270°: seen from 90°, mirrored.
    if (key == "90,0" && facesRight(p, r) == true) key = "270,0";
    cuts[key] = r;
  }
  if (figures.isEmpty && found.isNotEmpty) {
    // One drawing of it, not a sheet: the whole of it is the front.
    cuts["0,0"] = found.first.rect;
  } else if (others.isNotEmpty) {
    cuts[referenceFaces] = others.first;
  }
  var skulls = <String, double>{};
  double heads = 0;
  for (var MapEntry(:key, value: r) in cuts.entries) {
    if (key == referenceFaces) continue;
    if (measureFigure(p, r) case var m?) {
      skulls[key] = m.skull;
      if (key == "0,0") heads = m.headsTall;
    }
  }
  // The sheet's background taken out, for the figures to be laid over the
  // views alone.
  var cutout = await _cutout(p);
  var colours = paletteOf(
      p,
      [
        for (var MapEntry(:key, value: r) in cuts.entries)
          if (key != referenceFaces) r,
        // Enough paints, near enough together, that a white tee is not the
        // skin beside it: they are what a trace is drawn in.
      ],
      most: 12,
      apart: 0.11);
  var e = c.document.elementById(id);
  if (e is! CharacterElement) return "";
  c.beginInteraction();
  c.replaceElement(e.copyWith(
    reference: CharacterReference(assetId,
        cutout: cutout ?? "", cuts: cuts, skulls: skulls, heads: heads),
    palette: e.palette.isEmpty ? namedSwatches(colours) : null,
  ));
  c.endInteraction();
  var views = [
    for (var k in ["0,0", "90,0", "270,0", "180,0"])
      if (cuts.containsKey(k))
        k.startsWith("0,")
            ? "Front"
            : k.startsWith("180")
                ? "Back"
                : "Side",
  ];
  if (views.isEmpty) return "Nothing was found on it to draw from.";
  return "Found ${views.join(", ")}"
      "${cuts.containsKey(referenceFaces) ? ", and faces" : ""}"
      "${heads > 0 ? ": ${heads.toStringAsFixed(1)} heads tall" : ""}.";
}

/// _cutout is [p] with its background taken out -- a pixel near the
/// sheet's colour clear, one a little further half clear, so the edge is
/// soft -- stored, or null where it could not be.
Future<String?> _cutout(SheetPixels p) async {
  var ground = p.background;
  var out = Uint8List.fromList(p.rgba);
  for (var i = 0; i < out.length; i += 4) {
    var dr = out[i] / 255 - ground.r,
        dg = out[i + 1] / 255 - ground.g,
        db = out[i + 2] / 255 - ground.b;
    var d = math.sqrt(dr * dr + dg * dg + db * db);
    // Clear within 0.08 of the background, solid past 0.16.
    var a = ((d - 0.08) / 0.08).clamp(0.0, 1.0);
    out[i + 3] = (out[i + 3] * a).round();
  }
  try {
    var done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
        out, p.width, p.height, ui.PixelFormat.rgba8888, done.complete);
    var img = await done.future;
    var png = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (png == null) return null;
    return await CanvasAssets.save(png.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

/// namedSwatches names [colours] as a designer would: the darkest the
/// line, a skin-like one skin, a near white white; the rest by their hue.
List<Swatch> namedSwatches(List<Color> colours) {
  var taken = <String>{};
  String unique(String name) {
    var n = name;
    for (var i = 2; taken.contains(n); i++) {
      n = "$name $i";
    }
    taken.add(n);
    return n;
  }

  var out = <Swatch>[];
  var darkest = colours.isEmpty
      ? null
      : colours.reduce((a, b) =>
          HSLColor.fromColor(a).lightness <= HSLColor.fromColor(b).lightness
              ? a
              : b);
  for (var c in colours) {
    var hsl = HSLColor.fromColor(c);
    String name;
    if (identical(c, darkest) && hsl.lightness < 0.3) {
      name = "Line";
    } else if (hsl.lightness > 0.9 && hsl.saturation < 0.35) {
      name = "White";
    } else if (hsl.hue >= 5 &&
        hsl.hue <= 40 &&
        hsl.saturation > 0.2 &&
        hsl.lightness > 0.5) {
      name = "Skin";
    } else {
      var hue = hsl.hue;
      var word = hue < 15 || hue >= 345
          ? "Red"
          : hue < 45
              ? "Orange"
              : hue < 70
                  ? "Yellow"
                  : hue < 160
                      ? "Green"
                      : hue < 200
                          ? "Teal"
                          : hue < 250
                              ? "Blue"
                              : hue < 300
                                  ? "Purple"
                                  : "Pink";
      name = hsl.saturation < 0.15
          ? (hsl.lightness < 0.5 ? "Dark grey" : "Grey")
          : hsl.lightness < 0.35
              ? "Dark $word".replaceFirst("Dark ", "Dark ")
              : word;
    }
    out.add(Swatch(unique(name), c));
  }
  return out;
}

/// fitToReference makes sketch [id] stand as many heads tall as its
/// reference's front figure. One step to undo.
void fitToReference(CanvasController c, String id) {
  var e = c.document.elementById(id);
  if (e is! CharacterElement) return;
  var heads = e.reference?.heads ?? 0;
  if (heads <= 0) return;
  c.beginInteraction();
  c.replaceElement(
      e.copyWith(dna: e.dna.copyWith(headsTall: heads.clamp(2.0, 9.0))));
  c.endInteraction();
}

/// fitBonesToReference turns sketch [id]'s arms, and sets their length, to
/// lie along its reference's front figure's: each arm's upper bone and
/// then its forearm swung until the bone runs down the drawn arm with the
/// sheet just outside it, then the arms made as long as the drawn hands
/// reach. A trace is cut, and moves, at the bones' joints: fitted first,
/// an elbow bends where the drawing's does. One step to undo. Says what it
/// did, or what stopped it.
Future<String> fitBonesToReference(CanvasController c, String id) async {
  var e = c.document.elementById(id);
  if (e is! CharacterElement) return "";
  var ref = e.reference;
  if (ref == null) return "Lay a reference under it first: step 1.";
  var pixels = await sheetPixels(ref.assetId);
  e = c.document.elementById(id);
  if (pixels == null || e is! CharacterElement) {
    return "The reference picture could not be read.";
  }
  var rate = math.max(1, c.document.frameRate);
  var front = e.copyWith(pose: e.pose.withTurn(0));
  var sheet = Turnaround.of(front, 0, rate, const []);
  double guide(String label) =>
      sheet.guides.firstWhere((g) => g.label == label).y - front.y;
  var box = Rect.fromLTWH(0, 0, front.width, front.height);
  var at = ref.laidOver("0,0", box, guide("Top of head"), guide("Ground"));
  if (at == null) return "The reference has no front to fit to.";
  var ground = pixels.background;
  var s = at.laid.height / at.cut.height;
  bool inked(Offset q) {
    var x = (at.cut.left + (q.dx - at.laid.left) / s).floor();
    var y = (at.cut.top + (q.dy - at.laid.top) / s).floor();
    if (x < 0 || y < 0 || x >= pixels.width || y >= pixels.height) return false;
    var p = pixels.at(x, y);
    var dr = p.r - ground.r, dg = p.g - ground.g, db = p.b - ground.b;
    return math.sqrt(dr * dr + dg * dg + db * db) > 0.12;
  }

  CharacterRig rigOf(CharacterElement e) => drawnRig(e, 0, rate).$1;
  // How well an arm lies on the drawing: its bone on ink, the sheet just
  // outside it.
  double fit(CharacterRig rig, CharacterLimb limb, {bool upper = true}) {
    var a = rig.root(limb), b = rig.middle(limb), c = rig.end(limb);
    var out = (b.dx - rig.chest.dx).sign;
    var probe = Offset(out * rig.limbWidth * 0.95, 0);
    var on = 0.0, n = 0;
    for (var (from, to, start) in [
      if (upper) (a, b, 0.3),
      (b, c, 0.0),
    ]) {
      for (var t = start; t <= 1.0001; t += 0.1) {
        var q = Offset.lerp(from, to, t)!;
        on += (inked(q) ? 1 : 0) + (inked(q + probe) ? 0 : 1);
        n += 2;
      }
    }
    return n == 0 ? 0 : on / n;
  }

  var pose = front.pose;
  var said = <String>[];
  for (var (limb, upper, fore) in const [
    (CharacterLimb.armL, CharacterBone.upperArmL, CharacterBone.foreArmL),
    (CharacterLimb.armR, CharacterBone.upperArmR, CharacterBone.foreArmR),
  ]) {
    double sweep(CharacterBone bone, double from, double to, bool whole) {
      var best = pose[bone], bestFit = -1.0;
      for (var a = from; a <= to; a += 1) {
        var rig = rigOf(front.copyWith(pose: pose.withAngle(bone, a)));
        var f = fit(rig, limb, upper: whole);
        // Ties go to the angle nearer as it was.
        if (f > bestFit + 1e-6 ||
            (f > bestFit - 1e-6 &&
                (a - pose[bone]).abs() < (best - pose[bone]).abs())) {
          bestFit = f;
          best = a;
        }
      }
      return best;
    }

    pose = pose.withAngle(upper, sweep(upper, -50, 50, true));
    pose = pose.withAngle(fore, sweep(fore, -30, 30, false));
    said.add("${pose[upper].round()}°");
  }

  // The arms as long as the drawn hands reach: where the ink ends, along
  // the forearm on from the wrist.
  var fitted = front.copyWith(pose: pose);
  var rig = rigOf(fitted);
  var reach = <double>[];
  for (var limb in [CharacterLimb.armL, CharacterLimb.armR]) {
    var b = rig.middle(limb), c = rig.end(limb);
    var dir = c - b;
    if (dir.distance == 0) continue;
    dir = dir / dir.distance;
    var tip = 0.0, gap = 0.0;
    for (var k = 0.0; k < rig.handRadius * 6; k += 1) {
      if (inked(c + dir * k)) {
        tip = k;
        gap = 0;
      } else if ((gap += 1) > rig.handRadius) {
        break;
      }
    }
    reach.add(tip);
  }
  var look = fitted.dna.look;
  if (reach.isNotEmpty) {
    var want = reach.reduce((a, b) => a + b) / reach.length;
    // The hand drawn reaches two of its radii past the wrist.
    double over(double v) {
      var r = rigOf(fitted.copyWith(
          dna: fitted.dna.copyWith(look: look.withValue(Look.armLength, v))));
      var b = r.middle(CharacterLimb.armL), c = r.end(CharacterLimb.armL);
      var stretch = (c - b).distance +
          (r.middle(CharacterLimb.armL) - r.root(CharacterLimb.armL)).distance;
      var now = (rig.middle(CharacterLimb.armL) - rig.root(CharacterLimb.armL))
              .distance +
          (rig.end(CharacterLimb.armL) - rig.middle(CharacterLimb.armL))
              .distance;
      return stretch - now - (want - r.handRadius * 2);
    }

    var lo = Look.armLength.min, hi = 1.0;
    if (over(lo) < 0 && over(hi) > 0) {
      for (var i = 0; i < 16; i++) {
        var mid = (lo + hi) / 2;
        if (over(mid) < 0) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      look = look.withValue(Look.armLength, (lo + hi) / 2);
    }
  }
  var now = c.document.elementById(id);
  if (now is! CharacterElement) return "";
  c.beginInteraction();
  c.replaceElement(now.copyWith(
      pose: pose.withTurn(now.pose.turn), dna: now.dna.copyWith(look: look)));
  c.endInteraction();
  return "Arms turned to ${said.join(" and ")}; arm length "
      "${(look[Look.armLength] * 100).round()}.";
}

/// traceReferenceView traces sketch [id]'s reference over the view it is
/// seen from into shapes drawn on it -- as an image trace does: each run
/// of one of its palette's colours on one part of the body outlined and
/// smoothed, on that part, so it moves with it -- in place of its figure
/// there. The figure is stood as the reference first: its pose is where
/// the parts are. One step to undo. Says what it did, or what stopped it.
Future<String> traceReferenceView(CanvasController c, String id) async {
  var e = c.document.elementById(id);
  if (e is! CharacterElement) return "";
  var ref = e.reference;
  if (ref == null) return "Lay a reference under it first: step 1.";
  var pixels = await sheetPixels(ref.assetId);
  e = c.document.elementById(id);
  if (pixels == null || e is! CharacterElement) {
    return "The reference picture could not be read.";
  }
  var rate = math.max(1, c.document.frameRate);
  var frame = c.frame;
  var key = drawnKey(e, frame, rate);
  var sheet = Turnaround.of(e, frame, rate, const []);
  double guide(String label) =>
      sheet.guides.firstWhere((g) => g.label == label).y - e!.y;
  var box = Rect.fromLTWH(0, 0, e.width, e.height);
  var at = ref.laidOver(key, box, guide("Top of head"), guide("Ground"));
  if (at == null) return "The reference has no cut for this view.";
  var (rig, _, _) = drawnRig(e, frame, rate);
  Offset place(Offset q) => CharacterReference.onBox(q, at);
  var palette = [for (var s in e.palette) s.color];
  if (palette.isEmpty) palette = paletteOf(pixels, [at.cut]);
  var regions = traceRegions(
      pixels, at.cut, palette, (q) => _tracedPart(rig, place(q)).index);
  if (regions.isEmpty) return "Nothing was found to trace in that cut.";
  // A shoe is the foot's, all of it: its colours, low on the shin -- above
  // the rig's ankle, where the drawing's is higher -- on the foot too, not
  // cut in two at the ankle and parted as the leg bends.
  var shoe = <int, int>{};
  for (var r in regions) {
    var p = CharacterPart.values[r.part];
    if (p == CharacterPart.footL || p == CharacterPart.footR) {
      shoe[r.colour] = (shoe[r.colour] ?? 0) + r.area;
    }
  }
  var shoeArea = shoe.values.fold(0, (a, b) => a + b);
  bool lowOnShin(TracedRegion r, CharacterLimb limb) {
    var knee = rig.middle(limb).dy, ankle = rig.end(limb).dy;
    return place(r.bounds.center).dy > knee + (ankle - knee) * 0.7;
  }

  regions = [
    for (var r in regions)
      if ((shoe[r.colour] ?? 0) > shoeArea * 0.1 &&
          r.part == CharacterPart.shinL.index &&
          lowOnShin(r, CharacterLimb.legL))
        TracedRegion(
            r.colour, CharacterPart.footL.index, r.rings, r.area, r.bounds)
      else if ((shoe[r.colour] ?? 0) > shoeArea * 0.1 &&
          r.part == CharacterPart.shinR.index &&
          lowOnShin(r, CharacterLimb.legR))
        TracedRegion(
            r.colour, CharacterPart.footR.index, r.rings, r.area, r.bounds)
      else
        r,
  ];
  // A hand hanging against the hips takes an edge of the jeans with it:
  // what is in a leg's own colour is the leg's.
  var legColours = <int, int>{};
  for (var r in regions) {
    if (const {
      CharacterPart.thighL,
      CharacterPart.thighR,
      CharacterPart.shinL,
      CharacterPart.shinR
    }.contains(CharacterPart.values[r.part])) {
      legColours[r.colour] = (legColours[r.colour] ?? 0) + r.area;
    }
  }
  var legArea = legColours.values.fold(0, (a, b) => a + b);
  CharacterPart? legsOwn(TracedRegion r) {
    if (!_armParts.contains(CharacterPart.values[r.part])) return null;
    if ((legColours[r.colour] ?? 0) <= legArea * 0.2) return null;
    return _bodyUnder(rig, place(r.bounds.center));
  }

  regions = [
    for (var r in regions)
      switch (legsOwn(r)) {
        var under? =>
          TracedRegion(r.colour, under.index, r.rings, r.area, r.bounds),
        null => r,
      },
  ];
  // The skin: the colour most of the hands are.
  var handColours = <int, int>{};
  for (var r in regions) {
    var p = CharacterPart.values[r.part];
    if (p == CharacterPart.handL || p == CharacterPart.handR) {
      handColours[r.colour] = (handColours[r.colour] ?? 0) + r.area;
    }
  }
  var tone = handColours.entries
      .fold<MapEntry<int, int>?>(
          null, (a, b) => a == null || b.value > a.value ? b : a)
      ?.key;
  // An arm's colours: mostly found on the arms -- a hand's shading, its
  // outline -- as well as the skin.
  var onArms = <int, int>{}, everywhere = <int, int>{};
  for (var r in regions) {
    everywhere[r.colour] = (everywhere[r.colour] ?? 0) + r.area;
    if (_armParts.contains(CharacterPart.values[r.part])) {
      onArms[r.colour] = (onArms[r.colour] ?? 0) + r.area;
    }
  }
  bool skinLikeColour(int i) {
    if ((onArms[i] ?? 0) > (everywhere[i] ?? 0) * 0.5) return true;
    if (tone == null) return false;
    var a = palette[i], b = palette[tone];
    var dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b;
    return math.sqrt(dr * dr + dg * dg + db * db) < 0.22;
  }

  // An arm drawn wider than the rig's leaves its far edge on the body,
  // and swung away, a third arm painted there: skin on the body, along an
  // arm, is the arm's.
  // A hand resting on a hip leaves itself on the leg the hip is: skin
  // there is the hand's too. (Only skin: the jeans' own shading near the
  // hand, taken as well, flew off with it.)
  CharacterPart? armsOwn(TracedRegion r) {
    var on = CharacterPart.values[r.part];
    var thigh = on == CharacterPart.thighL || on == CharacterPart.thighR;
    if (on != CharacterPart.torso && !thigh) return null;
    if (!skinLikeColour(r.colour)) return null;
    var q = place(r.bounds.center);
    if (q.dy < rig.chest.dy) return null;
    CharacterPart? best;
    var nearest = rig.limbWidth * 1.6;
    for (var (limb, upper, lower, hand) in const [
      (
        CharacterLimb.armL,
        CharacterPart.upperArmL,
        CharacterPart.foreArmL,
        CharacterPart.handL
      ),
      (
        CharacterLimb.armR,
        CharacterPart.upperArmR,
        CharacterPart.foreArmR,
        CharacterPart.handR
      ),
    ]) {
      var wrist = rig.end(limb), elbow = rig.middle(limb);
      var along = wrist - elbow;
      var tip = along.distance == 0
          ? wrist
          : wrist + along / along.distance * rig.handRadius * 2;
      for (var (a, b, part) in [
        (rig.root(limb), elbow, upper),
        (elbow, wrist, lower),
        (wrist, tip, hand),
      ]) {
        var ab = b - a;
        var len = ab.distanceSquared;
        var t = len == 0
            ? 0.0
            : (((q - a).dx * ab.dx + (q - a).dy * ab.dy) / len).clamp(0.0, 1.0);
        var d = (q - (a + ab * t)).distance;
        if (d < nearest) {
          nearest = d;
          best = part;
        }
      }
    }
    return best;
  }

  regions = [
    for (var r in regions)
      switch (armsOwn(r)) {
        var arm? =>
          TracedRegion(r.colour, arm.index, r.rings, r.area, r.bounds),
        null => r,
      },
  ];
  var seam = 0.7 * at.laid.height / at.cut.height;
  var shapes = [
    for (var r in regions) traceShape(r, palette, place, seam: seam)
  ];
  var parts = [for (var r in regions) CharacterPart.values[r.part]];
  var head = rig.headRadii * rig.headScale;
  // The hair: the colour most of the top of the head is.
  var tops = <int, int>{};
  for (var r in regions) {
    if (r.part != CharacterPart.head.index) continue;
    var b = place(r.bounds.center);
    if (b.dy < rig.headCentre.dy - head.height * 0.35) {
      tops[r.colour] = (tops[r.colour] ?? 0) + r.area;
    }
  }
  var hair = tops.entries
      .fold<MapEntry<int, int>?>(
          null, (a, b) => a == null || b.value > a.value ? b : a)
      ?.key;
  // The skin: the colour most of the rest of the head is; and like it,
  // its shades -- a cheek, a shadow -- which are no feature.
  var skins = <int, int>{};
  for (var r in regions) {
    if (r.part == CharacterPart.head.index && r.colour != hair) {
      skins[r.colour] = (skins[r.colour] ?? 0) + r.area;
    }
  }
  var skin = skins.entries
      .fold<MapEntry<int, int>?>(
          null, (a, b) => a == null || b.value > a.value ? b : a)
      ?.key;
  bool skinLike(int i) {
    if (skin == null) return false;
    var a = palette[i], b = palette[skin];
    var dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b;
    return math.sqrt(dr * dr + dg * dg + db * db) < 0.22;
  }

  // Seen from behind there is no face to find.
  var turn = double.tryParse(key.split(",").first) ?? 0;
  var away = (turn % 360 - 180).abs() < 60;
  var layers = <String>[
    for (var r in regions)
      _tracedLayer(r, CharacterPart.values[r.part], rig.headCentre, head, place,
          hair: hair, face: !away, skinLike: skinLike),
  ];
  // Lowest first: legs, the body, arms, hands, the head; on each part its
  // largest first, what lies on them over them.
  var order = [
    for (var (i, p) in parts.indexed) _tracedRank(p) * 1000.0 + i,
  ];

  // What the picture does not show, as a cut-out animator draws it: each
  // part whole under its detail, in its own main colour -- the body under
  // an arm, shown as the arm swings away -- and a limb hidden behind its
  // other, its other's copy behind the body, a little darker.
  var mainOf = <int, Map<int, int>>{};
  for (var r in regions) {
    var m = mainOf[r.part] ??= {};
    m[r.colour] = (m[r.colour] ?? 0) + r.area;
  }
  // Each part as the trace has it, but under an arm the body or the leg it
  // lies over, in that part's own main colour -- the waist a tee's, the hip
  // a jeans' -- so an arm swung away leaves the body whole, not a hole the
  // arm's shape. (Coloured as found beside the arm, pixel by pixel, it was
  // blotched with skin and shadow.)
  bool isArm(CharacterPart p) => _armParts.contains(p);
  int baseOf(Offset q) {
    var p = _tracedPart(rig, place(q));
    if (isArm(p)) return (_bodyUnder(rig, place(q)) ?? p).index;
    var under = partAt(rig, place(q));
    return (under == CharacterPart.torso ? under : p).index;
  }

  var bases = traceRegions(pixels, at.cut, [palette.first], baseOf,
      least: 6, smooth: 0.8);
  for (var (i, b) in bases.indexed) {
    var colours = mainOf[b.part];
    if (colours == null || colours.isEmpty) continue;
    var main = colours.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    var part = CharacterPart.values[b.part];
    // An arm is on top of all else: nothing to fill under it, and its own
    // base -- in a colour it touches, a hand's against jeans -- would
    // edge it.
    if (isArm(part)) continue;
    // A part's own base in its main colour.
    shapes.add(traceShape(
        TracedRegion(main, b.part, b.rings, b.area, b.bounds), palette, place,
        seam: seam));
    parts.add(part);
    layers.add(part == CharacterPart.head
        ? (main == hair ? "hairBack" : "head")
        : _tracedLayer(b, part, rig.headCentre, head, place));
    order.add(_tracedRank(part) * 1000.0 - 500 + i);
  }
  const groups = [
    (
      [CharacterPart.upperArmL, CharacterPart.foreArmL, CharacterPart.handL],
      // Behind everything: the body and both legs -- in front of the hips,
      // which are the legs', it was a third arm.
      -3000.0
    ),
    ([CharacterPart.thighL, CharacterPart.shinL, CharacterPart.footL], -2000.0),
  ];
  for (var (left, behind) in groups) {
    var right = [for (var p in left) p.mirrored];
    var hasL = parts.any(left.contains), hasR = parts.any(right.contains);
    if (hasL == hasR) continue;
    var from = hasL ? left : right;
    var count = shapes.length;
    for (var i = 0; i < count; i++) {
      if (!from.contains(parts[i])) continue;
      var s = shapes[i];
      Color? dim(Color? c) =>
          c == null ? null : Color.lerp(c, const Color(0xFF000000), 0.14);
      shapes.add(s.copyWith(fill: dim(s.fill), stroke: dim(s.stroke)));
      parts.add(parts[i].mirrored);
      layers.add(_tracedLayer(
          regions.first, parts[i].mirrored, rig.headCentre, head, place));
      order.add(behind + order[i] / 1000);
    }
  }
  var placed = shapesOnParts(shapes, rig, keep: parts);
  var drawing = placed.copyWith(
      order: order, layers: layers, hidden: CharacterRegion.values.toSet());
  var next = e.withDrawingAt(key, drawing);
  var wardrobe = [
    for (var g in next.dna.wardrobe)
      g.withDrawingAt(key, CharacterDrawing.empty.copyWith(replaces: true)),
  ];
  c.beginInteraction();
  c.replaceElement(next.copyWith(dna: next.dna.copyWith(wardrobe: wardrobe)));
  c.endInteraction();
  var view = _cutNames[key.split("@").first] ?? "this view";
  return "Traced ${shapes.length} shapes on the ${view.toLowerCase()}, in "
      "${palette.length} colours.";
}

/// _tracedRank is how low part [p] is drawn among a traced view's.
int _tracedRank(CharacterPart p) => switch (p) {
      CharacterPart.thighL ||
      CharacterPart.thighR ||
      CharacterPart.shinL ||
      CharacterPart.shinR =>
        0,
      CharacterPart.footL || CharacterPart.footR => 1,
      CharacterPart.torso => 2,
      CharacterPart.upperArmL ||
      CharacterPart.upperArmR ||
      CharacterPart.foreArmL ||
      CharacterPart.foreArmR =>
        3,
      CharacterPart.handL || CharacterPart.handR => 4,
      CharacterPart.head => 5,
    };

const _armParts = {
  CharacterPart.upperArmL,
  CharacterPart.foreArmL,
  CharacterPart.handL,
  CharacterPart.upperArmR,
  CharacterPart.foreArmR,
  CharacterPart.handR,
};

/// _bodyUnder is the part of the body -- the body itself, or a thigh --
/// [p] lies within, by where its bones are; null where it is clear of
/// both, an arm against the sheet.
CharacterPart? _bodyUnder(CharacterRig rig, Offset p) {
  double toSegment(Offset a, Offset b) {
    var ab = b - a;
    var len = ab.distanceSquared;
    var t = len == 0
        ? 0.0
        : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  if (toSegment(rig.chest, rig.hips) < rig.shoulderHalf * 1.05) {
    return CharacterPart.torso;
  }
  for (var (limb, thigh) in const [
    (CharacterLimb.legL, CharacterPart.thighL),
    (CharacterLimb.legR, CharacterPart.thighR),
  ]) {
    if (toSegment(rig.root(limb), rig.middle(limb)) < rig.legWidth * 0.7) {
      return thigh;
    }
  }
  return null;
}

/// _tracedPart is the part a traced point is on: the part under it, but
/// an arm or a hand rather than the body where it lies along one -- an arm
/// hanging in front of the body, seen from the side, is the arm.
CharacterPart _tracedPart(CharacterRig rig, Offset p) {
  var under = partAt(rig, p);
  // Along a limb, cut where its joints are: above the knee the thigh,
  // below it the shin, below the ankle the foot -- not the bone nearest,
  // which cuts a leg drawn a little off the rig's slantwise.
  for (var (limb, upper, lower, end) in const [
    (
      CharacterLimb.legL,
      CharacterPart.thighL,
      CharacterPart.shinL,
      CharacterPart.footL
    ),
    (
      CharacterLimb.legR,
      CharacterPart.thighR,
      CharacterPart.shinR,
      CharacterPart.footR
    ),
    (
      CharacterLimb.armL,
      CharacterPart.upperArmL,
      CharacterPart.foreArmL,
      CharacterPart.handL
    ),
    (
      CharacterLimb.armR,
      CharacterPart.upperArmR,
      CharacterPart.foreArmR,
      CharacterPart.handR
    ),
  ]) {
    if (under != upper && under != lower && under != end) continue;
    var a = rig.root(limb), b = rig.middle(limb), c = rig.end(limb);
    double along(Offset from, Offset to) {
      var d = to - from;
      var len = d.distanceSquared;
      return len == 0 ? 0 : ((p - from).dx * d.dx + (p - from).dy * d.dy) / len;
    }

    if (along(a, b) < 1) return upper;
    // A leg's foot from a little above the rig's ankle: at the bare ankle
    // over a shoe, not through the shoe -- whose upper went with the shin
    // and its sole with the foot, apart as she stepped.
    var leg = limb == CharacterLimb.legL || limb == CharacterLimb.legR;
    return along(b, c) < (leg ? 0.86 : 1) ? lower : end;
  }
  if (under != CharacterPart.torso) return under;
  double toSegment(Offset a, Offset b) {
    var ab = b - a;
    var len = ab.distanceSquared;
    var t = len == 0
        ? 0.0
        : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  var half = rig.limbWidth / 2;
  for (var (limb, upper, lower) in const [
    (CharacterLimb.armL, CharacterPart.upperArmL, CharacterPart.foreArmL),
    (CharacterLimb.armR, CharacterPart.upperArmR, CharacterPart.foreArmR),
  ]) {
    var a = rig.root(limb), b = rig.middle(limb), c = rig.end(limb);
    if (toSegment(b, c) < half) return lower;
    // The upper arm, below the shoulder: at the shoulder, the body.
    if (toSegment(a, b) < half && (p - a).distance > half * 1.5) return upper;
  }
  return under;
}

/// _tracedLayer is the layer a traced region is drawn as: on the head, the
/// hair in the colour of [hair], the eyes, brows and mouth -- with a
/// [face] to find -- by where on it they are, and the rest the head;
/// elsewhere the part's own layer.
String _tracedLayer(TracedRegion r, CharacterPart part, Offset headCentre,
    Size head, Offset Function(Offset) place,
    {int? hair, bool face = true, bool Function(int)? skinLike}) {
  switch (part) {
    case CharacterPart.head:
      var b =
          Rect.fromPoints(place(r.bounds.topLeft), place(r.bounds.bottomRight));
      var dx = (b.center.dx - headCentre.dx).abs() / math.max(1, head.width);
      var dy = (b.center.dy - headCentre.dy) / math.max(1, head.height);
      var small = b.height < head.height * 0.5 && b.width < head.width * 0.9;
      if (face && small && dx < 0.8) {
        if (r.colour == hair && dy < -0.05 && b.height < head.height * 0.2) {
          return "brows";
        }
        if (r.colour != hair && !(skinLike?.call(r.colour) ?? false)) {
          if (dy >= -0.12 && dy < 0.32) return "eyes";
          if (dy >= 0.32 && dy < 0.9) return "mouth";
        }
      }
      if (r.colour == hair) return "hairBase";
      return "head";
    case CharacterPart.torso:
      return "torso";
    case CharacterPart.upperArmL || CharacterPart.foreArmL:
      return "armL";
    case CharacterPart.upperArmR || CharacterPart.foreArmR:
      return "armR";
    case CharacterPart.handL:
      return "handL";
    case CharacterPart.handR:
      return "handR";
    case CharacterPart.thighL || CharacterPart.shinL:
      return "legL";
    case CharacterPart.thighR || CharacterPart.shinR:
      return "legR";
    case CharacterPart.footL:
      return "footL";
    case CharacterPart.footR:
      return "footR";
  }
}

/// CharacterStudioBar is the Studio's bar, across the whole page: the way
/// back, the character, its workspaces, what it is made of, and Done.
class CharacterStudioBar extends StatelessWidget {
  final CanvasController controller;
  const CharacterStudioBar({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        var colors = ThemeNotifier.of(context).colors;
        var id = controller.studioCharacter;
        var e = id == null ? null : controller.document.elementById(id);
        if (e is! CharacterElement) return const SizedBox.shrink();
        var now = controller.studioWorkspace;
        var drawn = !e.body.inThreeD;
        var name = e.name.isEmpty ? controller.studioDesignName : e.name;
        return Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              border: Border(bottom: BorderSide(color: colors.outlineVariant))),
          child: Row(children: [
            CanvasTextButton(
              key: const ValueKey("studioBack"),
              label: "Canvas",
              icon: Icons.arrow_back,
              onPressed: controller.closeStudio,
            ),
            const SizedBox(width: 10),
            Icon(Icons.person_outline, size: 18, color: colors.primary),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(name.isEmpty ? "Character" : name,
                  key: const ValueKey("studioName"),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (var w in StudioWorkspace.values)
                    if (drawn || !w.drawnOnly)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Material(
                          color: w == now
                              ? colors.secondaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(7),
                          child: InkWell(
                            key: ValueKey("studioWs-${w.name}"),
                            borderRadius: BorderRadius.circular(7),
                            onTap: () => controller.studioWorkspace = w,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(w.icon,
                                        size: 15,
                                        color: w == now
                                            ? colors.onSecondaryContainer
                                            : colors.onSurfaceVariant),
                                    const SizedBox(width: 6),
                                    Text(w.label,
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: w == now
                                                ? colors.onSecondaryContainer
                                                : colors.onSurface)),
                                  ]),
                            ),
                          ),
                        ),
                      ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            CanvasDropdown<BodyKind>(
              key: const ValueKey("studioMadeOf"),
              label: "",
              value:
                  e.body.kind == BodyKind.model ? BodyKind.model : e.body.kind,
              width: 140,
              options: [
                (BodyKind.drawn, "Drawn 2D"),
                (BodyKind.mannequin, "Sculpted 3D"),
                if (e.body.kind == BodyKind.model) (BodyKind.model, "A model"),
              ],
              onChanged: (k) {
                if (k == e.body.kind) return;
                controller.beginInteraction();
                controller
                    .replaceElement(e.copyWith(body: e.body.copyWith(kind: k)));
                controller.endInteraction();
                if (k != BodyKind.drawn &&
                    controller.studioWorkspace.drawnOnly) {
                  controller.studioWorkspace = StudioWorkspace.body;
                }
              },
            ),
            const SizedBox(width: 4),
            IconButton(
              key: const ValueKey("studioUndo"),
              tooltip: "Undo",
              icon: const Icon(Icons.undo, size: 18),
              onPressed: controller.canUndo ? controller.undo : null,
            ),
            IconButton(
              key: const ValueKey("studioRedo"),
              tooltip: "Redo",
              icon: const Icon(Icons.redo, size: 18),
              onPressed: controller.canRedo ? controller.redo : null,
            ),
            const SizedBox(width: 4),
            FilledButton(
              key: const ValueKey("studioClose"),
              onPressed: controller.closeStudio,
              child: const Text("Done"),
            ),
          ]),
        );
      });
}

/// CharacterStudioScreen is the Studio, given the whole page: its bar, the
/// workspace's list down the left where it has one, the character alone on
/// [stage] -- the canvas's own, showing the Studio's document -- and the
/// workspace's settings down the right.
class CharacterStudioScreen extends StatelessWidget {
  final CanvasController controller;
  final Widget stage;

  /// overStage is laid over the top of the stage: the drawing tools' bars.
  final List<Widget> overStage;
  const CharacterStudioScreen(
      {required this.controller,
      required this.stage,
      this.overStage = const [],
      super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return Column(children: [
      CharacterStudioBar(controller: controller),
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              var w = controller.studioWorkspace;
              if (w != StudioWorkspace.start &&
                  w != StudioWorkspace.body &&
                  w != StudioWorkspace.draw &&
                  w != StudioWorkspace.face &&
                  w != StudioWorkspace.motion) {
                return const SizedBox.shrink();
              }
              return Container(
                width: 260,
                decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    border: Border(
                        right: BorderSide(color: colors.outlineVariant))),
                child: CharacterStudioList(controller: controller),
              );
            },
          ),
          Expanded(
            child: Stack(children: [
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, child) => controller.studioDriving &&
                          controller.studioWorkspace == StudioWorkspace.test
                      ? _DriveKeys(controller: controller, child: child!)
                      : child!,
                  child: stage,
                ),
              ),
              Positioned(
                top: 10,
                left: 16,
                right: 16,
                child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _StudioViews(controller: controller),
                  ...overStage,
                ])),
              ),
              // On Face: where it looks, and a line to say.
              Positioned(
                left: 16,
                right: 16,
                bottom: 12,
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    var id = controller.studioCharacter;
                    var e =
                        id == null ? null : controller.document.elementById(id);
                    if (e is! CharacterElement ||
                        controller.studioWorkspace != StudioWorkspace.face ||
                        controller.drawingOn != null) {
                      return const SizedBox.shrink();
                    }
                    return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _LookPad(controller: controller, character: e),
                          const SizedBox(height: 8),
                          _SaySomething(controller: controller),
                        ]);
                  },
                ),
              ),
            ]),
          ),
          Container(
            width: 340,
            decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                border: Border(left: BorderSide(color: colors.outlineVariant))),
            child: CharacterStudioPanel(controller: controller),
          ),
        ]),
      ),
    ]);
  }
}

/// _StudioViews is the row of which way round the character is seen.
class _StudioViews extends StatelessWidget {
  final CanvasController controller;
  const _StudioViews({required this.controller});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        var colors = ThemeNotifier.of(context).colors;
        if (controller.drawingOn != null) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
              color: colors.surfaceContainerHigh.withValues(alpha: 0.92),
              border: Border.all(color: colors.outlineVariant),
              borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var v in StudioView.values)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Material(
                  color: v == controller.studioView
                      ? colors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  child: InkWell(
                    key: ValueKey("studioView-${v.name}"),
                    borderRadius: BorderRadius.circular(7),
                    onTap: () => controller.studioView = v,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      child: Text(v.label,
                          style: TextStyle(
                              fontSize: 11.5,
                              color: v == controller.studioView
                                  ? colors.onPrimary
                                  : colors.onSurface)),
                    ),
                  ),
                ),
              ),
          ]),
        );
      });
}

/// CharacterStudioList is the workspace's list down the left: the library
/// on Start, the parts on Draw.
class CharacterStudioList extends StatelessWidget {
  final CanvasController controller;
  const CharacterStudioList({required this.controller, super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        var id = controller.studioCharacter;
        var e = id == null ? null : controller.document.elementById(id);
        if (e is! CharacterElement) return const SizedBox.shrink();
        void write(CanvasElement next) {
          controller.beginInteraction();
          controller.replaceElement(next, transient: true);
        }

        return ScrollConfiguration(
          behavior: const CanvasNoScrollbar(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
            child: CanvasControlScope(
              maxWidth: 236,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (controller.studioWorkspace == StudioWorkspace.start)
                      _LibraryList(controller: controller, character: e)
                    else if (controller.studioWorkspace == StudioWorkspace.body)
                      _RegionList(controller: controller, character: e)
                    else if (controller.studioWorkspace == StudioWorkspace.face)
                      _FaceParts(controller: controller, character: e)
                    else if (controller.studioWorkspace ==
                        StudioWorkspace.motion)
                      _MotionLibrary(controller: controller, character: e)
                    else
                      characterLayersSection(
                          context,
                          controller,
                          e,
                          write,
                          controller.beginInteraction,
                          controller.endInteraction,
                          tools: false),
                  ]),
            ),
          ),
        );
      });
}

/// _RegionList is the parts of the body, for Body to shape one at a time.
class _RegionList extends StatelessWidget {
  final CanvasController controller;
  final CharacterElement character;
  const _RegionList({required this.controller, required this.character});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var person = character.dna.kind.person;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("PARTS",
          style: TextStyle(
              fontSize: 10,
              letterSpacing: 0.7,
              fontWeight: FontWeight.w700,
              color: colors.onSurfaceVariant)),
      const SizedBox(height: 8),
      for (var g in AppearanceGroup.values)
        if (person ||
            (g != AppearanceGroup.hair && g != AppearanceGroup.facialHair))
          _LibraryRow(
            key: ValueKey("studioRegion-${g.name}"),
            name: g.label,
            note: "",
            picked: controller.studioRegion == g,
            onTap: () => controller.studioRegion = g,
          ),
    ]);
  }
}

/// _FaceParts is the parts of the face, for Face to work on one at a time:
/// each with a mark for each of its states, filled where it is drawn; and
/// what the face does by itself, always.
class _FaceParts extends StatelessWidget {
  final CanvasController controller;
  final CharacterElement character;
  const _FaceParts({required this.controller, required this.character});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var e = character;
    var drawn = !e.body.inThreeD;
    Text heading(String t) => Text(t,
        style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.7,
            fontWeight: FontWeight.w700,
            color: colors.onSurfaceVariant));
    void life(CharacterLife to) {
      controller.beginInteraction();
      controller.replaceElement(e.copyWith(life: to));
      controller.endInteraction();
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      heading("PARTS"),
      const SizedBox(height: 8),
      for (var p in StudioFacePart.values)
        () {
          var chart = drawn && p.chart != null
              ? controller.characterChart(e.id, p.chart!)
              : null;
          var states = p.states;
          var done = [
            for (var (k, _) in states) chart?.drawings.containsKey(k) ?? false
          ];
          var picked = controller.studioFacePart == p;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: picked ? colors.secondaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                key: ValueKey("studioFacePart-${p.name}"),
                borderRadius: BorderRadius.circular(8),
                onTap: () => controller.studioFacePart = p,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(p.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: colors.onSurface))),
                          Text(
                              states.isEmpty
                                  ? "${p.controls.length} controls"
                                  : !drawn
                                      ? "sculpted"
                                      : "${done.where((d) => d).length} of ${states.length}",
                              key: ValueKey("studioFacePartCount-${p.name}"),
                              style: TextStyle(
                                  fontSize: 10.5,
                                  color: colors.onSurfaceVariant)),
                        ]),
                        if (states.isNotEmpty && drawn) ...[
                          const SizedBox(height: 5),
                          Row(children: [
                            for (var (i, d) in done.indexed) ...[
                              if (i > 0) const SizedBox(width: 3),
                              Expanded(
                                child: Container(
                                  height: 5,
                                  decoration: BoxDecoration(
                                      color: d
                                          ? colors.primary
                                          : colors.outlineVariant,
                                      borderRadius: BorderRadius.circular(3)),
                                ),
                              ),
                            ],
                          ]),
                        ],
                      ]),
                ),
              ),
            ),
          );
        }(),
      const SizedBox(height: 14),
      heading("ALWAYS, WITH NO KEYS"),
      const SizedBox(height: 4),
      CanvasToggle(
        key: const ValueKey("studioBlink"),
        label: "Blink",
        value: e.life.blink,
        onChanged: (v) => life(e.life.copyWith(blink: v)),
      ),
      CanvasToggle(
        key: const ValueKey("studioBreathe"),
        label: "Breathe",
        value: e.life.breathe,
        onChanged: (v) => life(e.life.copyWith(breathe: v)),
      ),
      CanvasToggle(
        key: const ValueKey("studioGlance"),
        label: "Glance about",
        value: e.life.glance,
        onChanged: (v) => life(e.life.copyWith(glance: v)),
      ),
    ]);
  }
}

/// _MotionLibrary is the motions and stances to try the character in: one
/// pressed plays on it, round and round, until another is.
class _MotionLibrary extends StatelessWidget {
  final CanvasController controller;
  final CharacterElement character;
  const _MotionLibrary({required this.controller, required this.character});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var e = character;
    var trying = controller.studioTrying;
    Text heading(String t) => Text(t,
        style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.7,
            fontWeight: FontWeight.w700,
            color: colors.onSurfaceVariant));
    String note(MotionKind k) {
      var inGame = [
        for (var m in GameMove.values)
          if (e.gameMotions[m] == k) m.label.toLowerCase(),
      ];
      var tuned =
          !e.feel.isDefault && (k == MotionKind.walk || k == MotionKind.run);
      return [if (tuned) "tuned", if (inGame.isNotEmpty) inGame.first]
          .join(" · ");
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      heading("MOTIONS"),
      const SizedBox(height: 8),
      for (var k in MotionKind.values)
        _LibraryRow(
          key: ValueKey("studioMotion-${k.name}"),
          name: k.label,
          note: note(k),
          icon: Icons.directions_run,
          picked: trying == k.name,
          onTap: () => controller.studioTry(motion: k),
        ),
      const SizedBox(height: 12),
      heading("STANCES"),
      const SizedBox(height: 8),
      for (var p in posePresets)
        _LibraryRow(
          key: ValueKey("studioStance-${p.name}"),
          name: p.name,
          note: "",
          icon: Icons.accessibility_new,
          picked: trying == p.name,
          onTap: () => p == posePresets.first
              ? controller.studioTry()
              : controller.studioTry(pose: p.name),
        ),
    ]);
  }
}

/// _DriveKeys drives the Studio's character with the keyboard, as a game
/// does: left and right walk it -- running with Shift held -- and Space
/// jumps, landing back in whatever the keys still hold.
class _DriveKeys extends StatefulWidget {
  final CanvasController controller;
  final Widget child;
  const _DriveKeys({required this.controller, required this.child});

  @override
  State<_DriveKeys> createState() => _DriveKeysState();
}

class _DriveKeysState extends State<_DriveKeys> {
  final _focus = FocusNode(debugLabel: "studioDrive");
  final Set<LogicalKeyboardKey> _held = {};
  double _facing = 0;
  Timer? _landing;

  @override
  void dispose() {
    _landing?.cancel();
    _focus.dispose();
    super.dispose();
  }

  /// _go is the move the keys held make, on the ground.
  void _go() {
    var left = _held.contains(LogicalKeyboardKey.arrowLeft);
    var right = _held.contains(LogicalKeyboardKey.arrowRight);
    var shift = _held.contains(LogicalKeyboardKey.shiftLeft) ||
        _held.contains(LogicalKeyboardKey.shiftRight);
    if (left != right) _facing = left ? 90 : -90;
    var move = left == right
        ? GameMove.standing
        : shift
            ? GameMove.running
            : GameMove.walking;
    widget.controller.studioDrive(move, facing: _facing);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    var k = event.logicalKey;
    final used = {
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.space,
    };
    if (!used.contains(k)) return KeyEventResult.ignored;
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (event is KeyUpEvent) {
      _held.remove(k);
      if (k != LogicalKeyboardKey.space && _landing == null) _go();
      return KeyEventResult.handled;
    }
    _held.add(k);
    if (k == LogicalKeyboardKey.space) {
      if (_landing != null) return KeyEventResult.handled;
      widget.controller.studioDrive(GameMove.jumping, facing: _facing);
      var e = widget.controller.studioCharacter;
      var c = e == null ? null : widget.controller.document.elementById(e);
      var kind = c is CharacterElement
          ? c.gameMotions[GameMove.jumping]
          : MotionKind.jump;
      _landing =
          Timer(Duration(milliseconds: (kind.seconds * 1000).round()), () {
        _landing = null;
        if (mounted) _go();
      });
    } else if (_landing == null) {
      _go();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _key,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) => _focus.requestFocus(),
        child: Stack(children: [
          Positioned.fill(child: widget.child),
          Positioned(
            left: 16,
            bottom: 12,
            child: ListenableBuilder(
              listenable: _focus,
              builder: (context, _) => Container(
                key: const ValueKey("studioDriveHint"),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh.withValues(alpha: 0.92),
                    border: Border.all(color: colors.outlineVariant),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(
                    _focus.hasFocus
                        ? "Driving: left and right walk, Shift runs, Space jumps"
                        : "Click the stage to drive it",
                    style: TextStyle(fontSize: 11.5, color: colors.onSurface)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// _LookPad is where the character looks, with one press: the eyes, and
/// the head turned and nodded a little after them.
class _LookPad extends StatelessWidget {
  final CanvasController controller;
  final CharacterElement character;
  const _LookPad({required this.controller, required this.character});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var face = character.faceAtFrame(controller.frame);
    var lx = face[FaceControl.lookX], ly = face[FaceControl.lookY];
    void look(int x, int y) {
      var f = face
          .withControl(FaceControl.lookX, x * 0.8)
          .withControl(FaceControl.lookY, -y * 0.7)
          .withControl(FaceControl.turn, -x * 20.0)
          .withControl(FaceControl.nod, y * 8.0);
      controller.beginInteraction();
      controller.replaceElement(controller.characterFaced(character, f));
      controller.endInteraction();
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
          color: colors.surfaceContainerHigh.withValues(alpha: 0.92),
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(10)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text("LOOK",
            style: TextStyle(
                fontSize: 9.5,
                letterSpacing: 0.7,
                fontWeight: FontWeight.w700,
                color: colors.onSurfaceVariant)),
        const SizedBox(height: 4),
        for (var y in const [-1, 0, 1])
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var x in const [-1, 0, 1])
              () {
                var on =
                    (lx - x * 0.8).abs() < 0.05 && (ly + y * 0.7).abs() < 0.05;
                return Padding(
                  padding: const EdgeInsets.all(1.5),
                  child: Material(
                    color: on
                        ? colors.secondaryContainer
                        : colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      key: ValueKey("studioLook-$x-$y"),
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => look(x, y),
                      child: SizedBox(
                        width: 30,
                        height: 26,
                        child: Center(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: on
                                    ? colors.primary
                                    : colors.outlineVariant),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }(),
          ]),
      ]),
    );
  }
}

/// _SaySomething has the character say a line typed in, to see its mouths:
/// each word, and the shapes it is said with.
class _SaySomething extends StatefulWidget {
  final CanvasController controller;
  const _SaySomething({required this.controller});

  @override
  State<_SaySomething> createState() => _SaySomethingState();
}

class _SaySomethingState extends State<_SaySomething> {
  final _line = TextEditingController(text: "Hello! Lovely to meet you.");

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    var c = widget.controller;
    var speaking = c.studioTrying == "say" && c.playing;
    var words =
        _line.text.split(RegExp(r"\s+")).where((w) => w.isNotEmpty).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
          color: colors.surfaceContainerHigh.withValues(alpha: 0.95),
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(10)),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    key: const ValueKey("studioSayLine"),
                    controller: _line,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (t) => c.studioSay(t),
                    style: TextStyle(fontSize: 12.5, color: colors.onSurface),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: "Something to say",
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 9),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CanvasTextButton(
                key: const ValueKey("studioSay"),
                label: speaking ? "Speaking" : "Say it",
                icon: Icons.record_voice_over_outlined,
                primary: true,
                onPressed: words.isEmpty ? null : () => c.studioSay(_line.text),
              ),
            ]),
            if (words.isNotEmpty) ...[
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (var w in words.take(24))
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(w,
                            style: TextStyle(
                                fontSize: 11.5, color: colors.onSurface)),
                        Text(mouthsOfWord(w).map((m) => m.letter).join(" "),
                            style: TextStyle(
                                fontSize: 10, color: colors.onSurfaceVariant)),
                      ]),
                    ),
                ]),
              ),
            ],
          ]),
    );
  }
}

/// _LibraryList is the library's characters: which this is, and the others
/// it could be made as instead.
class _LibraryList extends StatelessWidget {
  final CanvasController controller;
  final CharacterElement character;
  const _LibraryList({required this.controller, required this.character});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return ValueListenableBuilder<int>(
      valueListenable: CharacterLibrary.changed,
      builder: (context, _, __) => FutureBuilder<List<CharacterAsset>>(
        future: CharacterLibrary.list(),
        builder: (context, snap) {
          var all = snap.data ?? const <CharacterAsset>[];
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("YOUR CHARACTERS",
                    style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.7,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurfaceVariant)),
                const SizedBox(height: 8),
                _LibraryRow(
                  key: const ValueKey("studioLibrary-this"),
                  name: character.name.isEmpty
                      ? controller.studioDesignName
                      : character.name,
                  note: "This one",
                  picked: true,
                  onTap: null,
                ),
                for (var a in all)
                  if (a.id != character.characterId)
                    _LibraryRow(
                      key: ValueKey("studioLibrary-${a.id}"),
                      name: a.name.isEmpty ? "Character" : a.name,
                      note: "Make it this",
                      picked: false,
                      onTap: () => controller.studioUseCharacter(a),
                    ),
                if (all.where((a) => a.id != character.characterId).isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        "Characters are kept here when you press Done, to place "
                        "in any scene.",
                        style: TextStyle(
                            fontSize: 11, color: colors.onSurfaceVariant)),
                  ),
              ]);
        },
      ),
    );
  }
}

class _LibraryRow extends StatelessWidget {
  final String name;
  final String note;
  final bool picked;
  final VoidCallback? onTap;
  final IconData icon;
  const _LibraryRow(
      {required this.name,
      required this.note,
      required this.picked,
      required this.onTap,
      this.icon = Icons.person_outline,
      super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: picked ? colors.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              Icon(icon, size: 16, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                  flex: 3,
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12.5, color: colors.onSurface))),
              if (note.isNotEmpty)
                Flexible(
                  flex: 2,
                  child: Text(note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                          fontSize: 10.5, color: colors.onSurfaceVariant)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// CharacterStudioPanel is the workspace's own settings, down the right.
class CharacterStudioPanel extends StatefulWidget {
  final CanvasController controller;
  const CharacterStudioPanel({required this.controller, super.key});

  @override
  State<CharacterStudioPanel> createState() => _CharacterStudioPanelState();
}

class _CharacterStudioPanelState extends State<CharacterStudioPanel> {
  CanvasController get c => widget.controller;
  String _said = "";
  bool _reading = false;

  /// _working is a tool at work -- fitting, tracing -- and _told what the
  /// last one said, by its key.
  bool _working = false;
  final Map<String, String> _told = {};

  Future<void> _run(String key, Future<String> Function() job) async {
    setState(() => _working = true);
    var said = await job();
    if (!mounted) return;
    setState(() {
      _working = false;
      _told[key] = said;
    });
  }

  Widget _toldOf(String key, ColorScheme colors) {
    var t = _told[key] ?? "";
    if (t.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(t,
          key: ValueKey("${key}Says"),
          style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
    );
  }

  Future<void> _choose(Future<String?> Function() pick, String id) async {
    var asset = await pick();
    if (asset == null || !mounted) return;
    setState(() {
      _reading = true;
      _said = "Reading the sheet…";
    });
    var said = await readReference(c, id, asset);
    if (!mounted) return;
    setState(() {
      _reading = false;
      _said = said;
    });
  }

  void _write(CanvasElement next) {
    c.beginInteraction();
    c.replaceElement(next, transient: true);
  }

  void _now(CharacterElement next) {
    c.beginInteraction();
    c.replaceElement(next);
    c.endInteraction();
  }

  /// _sections are the character's own settings sections called [names],
  /// from its settings, in the step that uses them.
  List<Widget> _sections(CharacterElement e, Set<String> names) => [
        for (var w in characterSettings(
            context, c, e, _write, c.beginInteraction, c.endInteraction))
          if (w.key case ValueKey<String>(:var value)
              when names.contains(value.replaceFirst("elementSection-", "")))
            w,
      ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          var colors = ThemeNotifier.of(context).colors;
          var id = c.studioCharacter;
          var e = id == null ? null : c.document.elementById(id);
          if (e is! CharacterElement) return const SizedBox.shrink();
          var w = c.studioWorkspace;
          var drawn = !e.body.inThreeD;
          return ScrollConfiguration(
            behavior: const CanvasNoScrollbar(),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
              child: CanvasControlScope(
                maxWidth: 300,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(w.label,
                          key: const ValueKey("studioWsTitle"),
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: colors.onSurface)),
                      const SizedBox(height: 4),
                      Text(w.says,
                          style: TextStyle(
                              fontSize: 11.5,
                              height: 1.45,
                              color: colors.onSurfaceVariant)),
                      const SizedBox(height: 12),
                      ...switch (w) {
                        StudioWorkspace.start => [
                            // The new characters, drawn in 3D, as they are
                            // built: the new Studio, in this one's place.
                            CanvasTextButton(
                              key: const ValueKey("studioNewCharacters"),
                              label: "Try the new 3D characters",
                              icon: Icons.view_in_ar_outlined,
                              onPressed: c.openStudio3d,
                            ),
                            const SizedBox(height: 12),
                            ..._generate(e, colors),
                            ..._sections(e, {"character"}),
                            if (drawn) ..._reference(e, colors),
                          ],
                        StudioWorkspace.body => [
                            ..._mixAndColour(e, colors),
                            ..._sections(e, {"style"}),
                            AppearanceEditor(
                              key: ValueKey(
                                  "studioRegionEditor-${c.studioRegion.name}"),
                              controller: c,
                              character: e,
                              write: _write,
                              commit: c.endInteraction,
                              only: c.studioRegion,
                            ),
                            if (drawn) ..._proportions(e, colors),
                          ],
                        StudioWorkspace.clothes => [
                            ..._outfits(e, colors),
                            _palette(
                                "Hair",
                                hairColours,
                                e.dna.hair,
                                "studioHair",
                                (col) => _now(e.copyWith(
                                    dna: e.dna.copyWith(hair: col)))),
                            ..._sections(e, {"wardrobe"}),
                          ],
                        StudioWorkspace.draw =>
                          drawn ? _draw(e, colors) : const <Widget>[],
                        StudioWorkspace.rig => [
                            if (drawn) ..._bones(e, colors),
                            _tryIt(),
                            ..._sections(e, {"pose"}),
                            if (drawn) _physics(e) else _weights(),
                          ],
                        StudioWorkspace.face => _face(e, colors),
                        StudioWorkspace.motion => _motion(e),
                        StudioWorkspace.test => [
                            ..._test(e),
                            ..._check(e, colors),
                          ],
                      },
                    ]),
              ),
            ),
          );
        },
      );

  /// _generate makes someone new from what goes together: the curated
  /// palettes, the cast, a costume.
  List<Widget> _generate(CharacterElement e, ColorScheme colors) => [
        CanvasControlGroup(label: "Make someone new", rule: false, children: [
          CanvasTextButton(
            key: const ValueKey("studioGenerate"),
            label: "Generate",
            icon: Icons.auto_awesome,
            primary: true,
            onPressed: () => c.studioGenerate(),
          ),
          const CanvasHint(
              "Two of the cast mixed, a skin, hair and eyes from colours that "
              "go together, a hairstyle and an outfit. Press again for "
              "another; undo for the last."),
        ]),
      ];

  /// _mix is the cast mixed in Body, by their place in the cast, and how
  /// much of each.
  final Map<int, double> _mix = {};

  /// _mixAndColour mixes the cast into the body and face, and picks the
  /// skin and eyes from the curated palettes.
  List<Widget> _mixAndColour(CharacterElement e, ColorScheme colors) {
    var people = [
      for (var (i, m) in characterCast.indexed)
        if (m.dna.kind.person) (i, m),
    ];
    void mix() {
      var parts = [
        for (var MapEntry(:key, :value) in _mix.entries)
          (characterCast[key].dna, value),
      ];
      if (parts.isEmpty) return;
      _now(e.copyWith(dna: mixDna(e.dna, parts)));
    }

    return [
      CanvasControlGroup(label: "Mix from the cast", rule: false, children: [
        SizedBox(
          width: double.infinity,
          child: Wrap(spacing: 5, runSpacing: 5, children: [
            for (var (i, m) in people)
              _Pill(
                key: ValueKey("studioMix-$i"),
                label: m.name,
                on: _mix.containsKey(i),
                onTap: () {
                  setState(() {
                    if (_mix.remove(i) == null) _mix[i] = 0.5;
                  });
                  mix();
                },
              ),
          ]),
        ),
        for (var MapEntry(:key, :value) in _mix.entries)
          CanvasSlider(
            key: ValueKey("studioMixWeight-$key"),
            label: characterCast[key].name,
            value: value,
            onChanged: (v) {
              setState(() => _mix[key] = v);
              mix();
            },
          ),
        const CanvasHint(
            "The body and face of the people picked, mixed by how much of "
            "each: how tall, the build, every shape, the skin and eyes."),
      ]),
      _palette("Skin", skinTones, e.dna.skin, "studioSkin",
          (col) => _now(e.copyWith(dna: e.dna.copyWith(skin: col)))),
      _palette("Eyes", eyeColours, e.dna.eyes, "studioEyes",
          (col) => _now(e.copyWith(dna: e.dna.copyWith(eyes: col)))),
    ];
  }

  /// _palette is a curated row of colours, [now] marked where it is one.
  Widget _palette(String label, List<Swatch> swatches, Color now, String key,
          ValueChanged<Color> pick) =>
      CanvasControlGroup(label: label, rule: false, children: [
        SizedBox(
          width: double.infinity,
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (var (i, sw) in swatches.indexed)
              Tooltip(
                message: sw.name,
                child: InkWell(
                  key: ValueKey("$key-$i"),
                  customBorder: const CircleBorder(),
                  onTap: () => pick(sw.color),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: sw.color,
                      border: Border.all(
                          color: sw.color.toARGB32() == now.toARGB32()
                              ? Theme.of(context).colorScheme.primary
                              : Colors.black26,
                          width:
                              sw.color.toARGB32() == now.toARGB32() ? 2.5 : 1),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ]);

  /// _outfits are the character's own outfits: the clothes it is designed
  /// in, and each kept as a set; picked, its clothes are the ones changed
  /// below. A scene picks which it wears.
  List<Widget> _outfits(CharacterElement e, ColorScheme colors) {
    var now = c.studioOutfit;
    return [
      CanvasControlGroup(label: "Outfits", rule: false, children: [
        SizedBox(
          width: double.infinity,
          child: Wrap(spacing: 5, runSpacing: 5, children: [
            _Pill(
              key: const ValueKey("studioOutfit-"),
              label: "As designed",
              on: now.isEmpty,
              onTap: () => c.studioEditOutfit(""),
            ),
            for (var o in e.outfits)
              _Pill(
                key: ValueKey("studioOutfit-${o.name}"),
                label: o.name,
                on: now == o.name,
                onTap: () => c.studioEditOutfit(o.name),
              ),
          ]),
        ),
        Wrap(spacing: 6, runSpacing: 6, children: [
          CanvasTextButton(
            key: const ValueKey("studioSaveOutfit"),
            label: "Keep these as an outfit",
            icon: Icons.add,
            onPressed: c.studioSaveOutfit,
          ),
          if (now.isNotEmpty)
            CanvasTextButton(
              key: const ValueKey("studioRemoveOutfit"),
              label: "Remove $now",
              icon: Icons.delete_outline,
              onPressed: () => c.studioRemoveOutfit(now),
            ),
        ]),
        const CanvasHint(
            "The clothes below are the outfit picked here. In a scene, the "
            "character's settings pick which outfit it wears."),
      ]),
    ];
  }

  List<Widget> _reference(CharacterElement e, ColorScheme colors) {
    var ref = e.reference;
    return [
      Wrap(spacing: 6, runSpacing: 6, children: [
        CanvasTextButton(
          key: const ValueKey("studioReferencePictures"),
          label: "From your Pictures",
          icon: Icons.photo_library_outlined,
          onPressed: _reading
              ? null
              : () => _choose(() => showRecentPictures(context), e.id),
        ),
        CanvasTextButton(
          key: const ValueKey("studioReferenceFile"),
          label: "From a file",
          icon: Icons.upload_file,
          onPressed: _reading
              ? null
              : () => _choose(() => pickCanvasImage(context), e.id),
        ),
      ]),
      if (_said.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(_said,
            key: const ValueKey("studioReferenceSays"),
            style: TextStyle(fontSize: 11.5, color: colors.onSurface)),
      ],
      if (ref != null) ...[
        const SizedBox(height: 12),
        _SheetPreview(controller: c, reference: ref),
        const SizedBox(height: 10),
        CanvasControlGroup(label: "Cut into", rule: false, children: [
          for (var MapEntry(key: key, value: r) in ref.cuts.entries)
            CanvasDropdown<String>(
              key: ValueKey("studioCut-$key"),
              label: "${r.width.round()} × ${r.height.round()}",
              value: _cutNames.containsKey(key) ? key : "",
              width: 120,
              options: [
                for (var MapEntry(:key, :value) in _cutNames.entries)
                  (key, value),
              ],
              onChanged: (to) {
                var cuts = {...ref.cuts}..remove(key);
                var skulls = {...ref.skulls};
                var skull = skulls.remove(key);
                if (to.isNotEmpty) {
                  cuts[to] = r;
                  if (skull != null) skulls[to] = skull;
                }
                _now(e.copyWith(
                    reference: ref.copyWith(cuts: cuts, skulls: skulls)));
              },
            ),
          CanvasSlider(
            key: const ValueKey("studioReferenceStrength"),
            label: "Strength",
            value: ref.strength,
            onChanged: (v) =>
                _write(e.copyWith(reference: ref.copyWith(strength: v))),
            onCommit: c.endInteraction,
          ),
          CanvasToggle(
            key: const ValueKey("studioReferenceShown"),
            label: "Shown over the views",
            value: ref.shown,
            onChanged: (v) =>
                _now(e.copyWith(reference: ref.copyWith(shown: v))),
          ),
        ]),
        CanvasTextButton(
          label: "Next: the body",
          icon: Icons.arrow_forward,
          primary: true,
          onPressed: () => c.studioWorkspace = StudioWorkspace.body,
        ),
      ],
    ];
  }

  List<Widget> _proportions(CharacterElement e, ColorScheme colors) {
    var heads = e.reference?.heads ?? 0;
    var sheet = Turnaround.of(e, c.frame, math.max(1, c.document.frameRate),
        [for (var v in e.views) (v.key, v.key)]);
    return [
      CanvasControlGroup(label: "Heads tall", rule: false, children: [
        _row(colors, "The reference",
            heads > 0 ? heads.toStringAsFixed(1) : "not measured"),
        _row(colors, "The character", e.dna.headsTall.toStringAsFixed(1)),
        if (heads > 0)
          CanvasTextButton(
            key: const ValueKey("studioFit"),
            label: "Fit the body to the reference",
            icon: Icons.straighten,
            primary: true,
            onPressed: (e.dna.headsTall - heads).abs() < 0.05
                ? null
                : () => fitToReference(c, e.id),
          ),
      ]),
      CanvasControlGroup(
          label: "The lines a turn keeps",
          rule: false,
          children: [
            for (var g in sheet.guides)
              _row(colors, g.label,
                  "${((g.y - e.y) / math.max(1, e.height) * 100).round()}% down"),
            const CanvasHint(
                "Drawn across every view on the canvas: the eyes, the chin, "
                "the shoulders and the knees of each view should sit on "
                "them. The proportions below move them."),
          ]),
      ..._sections(e, {"appearance"}),
    ];
  }

  /// _bones fits the bones to the reference: before tracing, so a drawing
  /// bends at its own elbows.
  List<Widget> _bones(CharacterElement e, ColorScheme colors) => [
        CanvasControlGroup(label: "The bones", rule: false, children: [
          CanvasTextButton(
            key: const ValueKey("studioFitBones"),
            label: "Fit the bones to the drawing",
            icon: Icons.accessibility_new,
            onPressed: _working || e.reference == null
                ? null
                : () =>
                    _run("studioFitBones", () => fitBonesToReference(c, e.id)),
          ),
          _toldOf("studioFitBones", colors),
          CanvasHint(e.reference == null
              ? "Needs a model sheet: lay one under it on Start."
              : "The arms turned and made as long as the front figure's, so "
                  "a drawing on them bends at its own elbows. Before tracing."),
        ]),
      ];

  /// _tryIt tries the character in a stance or moving, to see it bend: not
  /// its design -- see CanvasController.studioTry.
  Widget _tryIt() {
    var trying = c.studioTrying;
    const motions = [
      MotionKind.walk,
      MotionKind.run,
      MotionKind.jump,
      MotionKind.wave,
      MotionKind.clap,
      MotionKind.dance,
      MotionKind.talk,
    ];
    return CanvasControlGroup(label: "Try it", rule: false, children: [
      SizedBox(
        width: double.infinity,
        child: Wrap(spacing: 5, runSpacing: 5, children: [
          for (var p in posePresets.skip(1))
            _Pill(
              key: ValueKey("studioTryPose-${p.name}"),
              label: p.name,
              on: trying == p.name,
              onTap: () => c.studioTry(pose: p.name),
            ),
        ]),
      ),
      const CanvasLineBreak(),
      SizedBox(
        width: double.infinity,
        child: Wrap(spacing: 5, runSpacing: 5, children: [
          for (var m in motions)
            _Pill(
              key: ValueKey("studioTryMotion-${m.name}"),
              label: m.label,
              on: trying == m.name,
              onTap: () => c.studioTry(motion: m),
            ),
        ]),
      ),
      if (trying != null)
        CanvasTextButton(
          key: const ValueKey("studioTryOff"),
          label: "Back to its own pose",
          icon: Icons.undo,
          onPressed: () => c.studioTry(),
        ),
      const CanvasHint(
          "A stance held, or a motion played round and round: to see the "
          "joints bend, the bend shapes and the hair follow. Only tried -- "
          "Done leaves it standing as designed."),
    ]);
  }

  /// _weights shows how much each bone of a sculpted body moves the skin
  /// round it, as a heat map on the body.
  Widget _weights() =>
      CanvasControlGroup(label: "Skin weights", rule: false, children: [
        CanvasDropdown<HumanBone?>(
          key: const ValueKey("studioWeights"),
          label: "Show for",
          value: c.studioWeights,
          width: 200,
          options: [
            (null, "Nothing"),
            for (var b in HumanBone.values)
              if (b != HumanBone.leftEye && b != HumanBone.rightEye)
                (b, _boneName(b)),
          ],
          onChanged: (b) => c.studioWeights = b,
        ),
        const CanvasHint(
            "How much the bone moves each part of the body: blue not at all, "
            "red all the way. Try a pose above to see where the skin bends "
            "with it."),
      ]);

  /// _physics is how the hair follows the character as it moves.
  Widget _physics(CharacterElement e) {
    var p = e.physics;
    void set(HairPhysics to) => _write(e.copyWith(physics: to));
    return CanvasControlGroup(label: "Physics: hair", rule: false, children: [
      CanvasToggle(
        key: const ValueKey("studioHairPhysics"),
        label: "Hair follows through",
        value: p.on,
        onChanged: (v) => _now(e.copyWith(physics: p.copyWith(on: v))),
      ),
      if (p.on) ...[
        CanvasSlider(
          key: const ValueKey("studioHairStiffness"),
          label: "Stiffness",
          value: p.stiffness,
          onChanged: (v) => set(p.copyWith(stiffness: v)),
          onCommit: c.endInteraction,
        ),
        CanvasSlider(
          key: const ValueKey("studioHairWeight"),
          label: "Weight",
          value: p.weight,
          onChanged: (v) => set(p.copyWith(weight: v)),
          onCommit: c.endInteraction,
        ),
        CanvasSlider(
          key: const ValueKey("studioHairBounce"),
          label: "Bounce",
          value: p.bounce,
          onChanged: (v) => set(p.copyWith(bounce: v)),
          onCommit: c.endInteraction,
        ),
        const CanvasHint(
            "The hair swings after the head as it moves and settles, and "
            "stirs a little standing still. Try it moving above to see it. "
            "Drawn hair on the hair layers follows too."),
      ],
    ]);
  }

  List<Widget> _draw(CharacterElement e, ColorScheme colors) => [
        // The tools first, while a part is drawn on: the brush, the pen, the
        // fill (the pencil's Fill closes small gaps), shadow and shine.
        if (c.drawingOn == e.id) ...[
          ...vectorSettings(context, c, drawingTarget(c, e), _write,
              c.beginInteraction, c.endInteraction,
              toolsOnly: true),
        ] else
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
                "Pick a part's pencil below to draw on it, over the reference "
                "on the canvas.",
                key: const ValueKey("studioDrawHint"),
                style: TextStyle(fontSize: 11.5, color: colors.onSurface)),
          ),
        if (e.reference != null && c.drawingOn != e.id)
          CanvasControlGroup(label: "Trace", rule: false, children: [
            CanvasTextButton(
              key: const ValueKey("studioTrace"),
              label: "Trace the reference on this view",
              icon: Icons.gesture,
              primary: true,
              onPressed: _working
                  ? null
                  : () =>
                      _run("studioTrace", () => traceReferenceView(c, e.id)),
            ),
            _toldOf("studioTrace", colors),
            const CanvasHint(
                "Its view drawn as shapes in the palette's colours, each on "
                "the part under it, the body whole under the arms and a "
                "hidden leg or arm drawn behind. Turn to another view and "
                "trace it too; then draw over what the picture was too small "
                "to show."),
          ]),
        if (e.palette.isNotEmpty)
          CanvasControlGroup(
              label: "${e.name.isEmpty ? "The character" : e.name}'s palette",
              rule: false,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (var (i, s) in e.palette.indexed)
                      _SwatchTile(
                        key: ValueKey("studioSwatch-$i"),
                        swatch: s,
                        picked: c.vectorPencilColour == s.color,
                        onPick: () => c.vectorPencilColour = s.color,
                        onChanged: (next) {
                          var palette = [...e.palette]..[i] = next;
                          _now(e.copyWith(palette: palette));
                        },
                      ),
                  ]),
                ),
                const CanvasHint(
                    "Taken from the reference. Pick one to draw in it; the "
                    "pencil and the shapes picked take it."),
              ]),
      ];

  /// _faces are the face's charts: for the eyes, the brows and the mouth,
  /// a drawing for each state they are in -- open, half, shut; each sound
  /// lip sync makes -- drawn on the view seen, and swapped in as the face
  /// is set, as it speaks, as it blinks. A state not drawn yet shows the
  /// layer's own drawing.
  /// _motion is the Motion workspace's panel: the walk and run tuned to
  /// the character, and what a game plays for each thing it does.
  List<Widget> _motion(CharacterElement e) {
    var f = e.feel;
    var trying = c.studioTrying;
    void feel(MotionFeel to) => _write(e.copyWith(feel: to));
    return [
      CanvasControlGroup(
          label: "The walk, for ${c.studioDesignName}",
          rule: false,
          children: [
            for (var (key, label, value, make)
                in <(String, String, double, MotionFeel Function(double))>[
              ("stride", "Stride", f.stride, (v) => f.copyWith(stride: v)),
              ("bounce", "Bounce", f.bounce, (v) => f.copyWith(bounce: v)),
              (
                "armSwing",
                "Arm swing",
                f.armSwing,
                (v) => f.copyWith(armSwing: v)
              ),
              ("pushOff", "Push-off", f.pushOff, (v) => f.copyWith(pushOff: v)),
              ("lean", "Lean", f.lean, (v) => f.copyWith(lean: v)),
            ])
              CanvasSlider(
                key: ValueKey("studioFeel-$key"),
                label: label,
                value: value,
                onChanged: (v) => feel(make(v)),
                onCommit: c.endInteraction,
              ),
            CanvasTextButton(
              key: const ValueKey("studioWatchWalk"),
              label: "Watch it walk",
              icon: Icons.directions_walk,
              primary: trying != MotionKind.walk.name,
              onPressed: () => c.studioTry(motion: MotionKind.walk, facing: 90),
            ),
            CanvasTextButton(
              key: const ValueKey("studioWatchRun"),
              label: "Watch it run",
              icon: Icons.directions_run,
              onPressed: () => c.studioTry(motion: MotionKind.run, facing: 90),
            ),
            CanvasTextButton(
              key: const ValueKey("studioFeelReset"),
              label: "As made",
              icon: Icons.restart_alt,
              onPressed: f.isDefault
                  ? null
                  : () => _now(e.copyWith(feel: MotionFeel.asMade)),
            ),
            const CanvasHint(
                "Its walk and run, everywhere it walks: on the timeline, "
                "walked across a page, in a game. A longer stride carries it "
                "further, so its feet keep to the ground."),
          ]),
      CanvasControlGroup(label: "In a game", rule: false, children: [
        for (var m in GameMove.values)
          CanvasDropdown<MotionKind>(
            key: ValueKey("studioGameMove-${m.name}"),
            label: m.label,
            value: e.gameMotions[m],
            width: 150,
            options: [for (var k in MotionKind.values) (k, k.label)],
            onChanged: (k) =>
                _now(e.copyWith(gameMotions: e.gameMotions.withMotion(m, k))),
          ),
        const CanvasHint(
            "What a game plays as it does each thing. Try them on Test, with "
            "the arrow keys."),
      ]),
      if (trying != null)
        CanvasTextButton(
          key: const ValueKey("studioTryOff"),
          label: "Back to its own pose",
          icon: Icons.undo,
          onPressed: () => c.studioTry(),
        ),
    ];
  }

  /// _test is the Test workspace's playground: motions to play, the arrow
  /// keys to drive it with, and a line to say.
  List<Widget> _test(CharacterElement e) {
    var trying = c.studioTrying;
    return [
      CanvasControlGroup(label: "Play", rule: false, children: [
        SizedBox(
          width: double.infinity,
          child: Wrap(spacing: 5, runSpacing: 5, children: [
            for (var k in const [
              MotionKind.idle,
              MotionKind.walk,
              MotionKind.run,
              MotionKind.jump,
              MotionKind.wave
            ])
              _Pill(
                key: ValueKey("studioPlay-${k.name}"),
                label: k.label,
                on: trying == k.name,
                onTap: () => c.studioTry(motion: k),
              ),
            _Pill(
              key: const ValueKey("studioPlay-turntable"),
              label: "Turntable",
              on: trying == "turntable",
              onTap: () => c.studioTry(turntable: true),
            ),
          ]),
        ),
        if (trying != null)
          CanvasTextButton(
            key: const ValueKey("studioTryOff"),
            label: "Stop",
            icon: Icons.stop,
            onPressed: () => c.studioTry(),
          ),
      ]),
      CanvasControlGroup(label: "Drive it", rule: false, children: [
        CanvasToggle(
          key: const ValueKey("studioDrive"),
          label: "With the arrow keys",
          value: c.studioDriving,
          onChanged: (v) => c.studioDriving = v,
        ),
        const CanvasHint(
            "Left and right walk it, the way a game would; hold Shift to "
            "run, Space jumps. It plays what In a game on Motion says."),
      ]),
      CanvasControlGroup(label: "Say something", rule: false, children: [
        SizedBox(width: double.infinity, child: _SaySomething(controller: c)),
      ]),
    ];
  }

  /// _expressionName is the name a mix of the face is to be saved as.
  String _expressionName = "";

  /// _face is the Face workspace's panel: the part of the face picked on
  /// the left -- its states, drawn or not, and the controls that move it --
  /// and the character's expressions, ready-made and its own.
  List<Widget> _face(CharacterElement e, ColorScheme colors) {
    var face = e.faceAtFrame(c.frame);
    var part = c.studioFacePart;
    var drawn = !e.body.inThreeD;
    var kind = part.chart;
    var chart = drawn && kind != null ? c.characterChart(e.id, kind) : null;
    var now = kind == null ? null : chartKeyOf(kind, face);
    var drawingKind =
        c.drawingOn == e.id ? ChartKind.ofLayer(c.drawingLayer) : null;
    void faceNow(CharacterFace f) => _now(c.characterFaced(e, f));
    bool same(CharacterFace a) => [
          for (var k in FaceControl.values)
            if (k != FaceControl.turn && k != FaceControl.nod)
              (a[k] - face[k]).abs() <= 0.01,
        ].every((b) => b);
    return [
      // Drawing a state: the tools first, and the way out.
      if (drawingKind != null &&
          c.characterChart(e.id, drawingKind) != null) ...[
        ...vectorSettings(context, c, drawingTarget(c, e), _write,
            c.beginInteraction, c.endInteraction,
            toolsOnly: true),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: CanvasTextButton(
            key: const ValueKey("studioChartDone"),
            label: "Done drawing",
            icon: Icons.check,
            onPressed: c.stopDrawingOnCharacter,
          ),
        ),
      ],
      CanvasControlGroup(
          key: ValueKey("studioFacePanel-${part.name}"),
          label: part.label,
          rule: false,
          children: [
            if (kind != null) ...[
              SizedBox(
                width: double.infinity,
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (var (key, label) in part.states)
                    _ChartStateTile(
                      key: ValueKey("studioChartState-${kind.name}-$key"),
                      label: label,
                      drawn: chart?.drawings.containsKey(key) ?? false,
                      now: now == key,
                      drawing: drawingKind == kind && now == key,
                      onTap: () => faceNow(faceForChart(face, kind, key)),
                    ),
                ]),
              ),
              if (chart != null)
                CanvasTextButton(
                  key: const ValueKey("studioDrawState"),
                  label:
                      "Draw ${part.states.firstWhere((s) => s.$1 == now, orElse: () => (
                            "",
                            "this state"
                          )).$2}",
                  icon: Icons.edit,
                  primary: true,
                  onPressed: now == null || !part.states.any((s) => s.$1 == now)
                      ? null
                      : () => c.drawChartState(e.id, kind, now),
                )
              else if (drawn)
                CanvasTextButton(
                  key: ValueKey("studioMakeChart-${kind.name}"),
                  label: "Draw ${kind.label.toLowerCase()} by hand",
                  icon: Icons.grid_view,
                  onPressed: () => c.chartCharacterLayer(e.id, kind),
                ),
              CanvasHint(!drawn
                  ? "Pick one to see it: the sculpted face's own shapes make it."
                  : chart == null
                      ? "Drawn as the character makes them for now. Draw them by "
                          "hand, one state at a time, to make them your own."
                      : "${chart.drawings.length} of ${kind.keys.length} drawn "
                          "on this view. Pick one to see it; one not drawn "
                          "shows the ${kind.layer} as drawn."),
            ],
            for (var k in part.controls)
              CanvasSlider(
                key: ValueKey("studioFaceControl-${k.name}"),
                label: k.label,
                value: face[k].clamp(k.min, k.max).toDouble(),
                min: k.min,
                max: k.max,
                onChanged: (v) =>
                    _write(c.characterFaced(e, face.withControl(k, v))),
                onCommit: c.endInteraction,
              ),
          ]),
      CanvasControlGroup(
          key: const ValueKey("studioExpressions"),
          label: "Expressions",
          rule: false,
          children: [
            SizedBox(
              width: double.infinity,
              child: Wrap(spacing: 5, runSpacing: 5, children: [
                for (var x in expressionPresets)
                  _Pill(
                    key: ValueKey("studioExpression-${x.name}"),
                    label: x.name,
                    on: same(x.face),
                    onTap: () => faceNow(face.feeling(x.face)),
                  ),
                for (var x in e.expressions)
                  _Pill(
                    key: ValueKey("studioOwnExpression-${x.name}"),
                    label: x.name,
                    on: same(x.face),
                    onTap: () => faceNow(face.feeling(x.face)),
                  ),
              ]),
            ),
            CanvasTextField(
              key: const ValueKey("studioExpressionName"),
              label: "Keep this mix as",
              value: _expressionName,
              hint: "Cheeky",
              onChanged: (v) => setState(() => _expressionName = v),
            ),
            CanvasTextButton(
              key: const ValueKey("studioSaveExpression"),
              label: "Keep it",
              icon: Icons.add,
              onPressed: _expressionName.trim().isEmpty
                  ? null
                  : () {
                      c.studioSaveExpression(_expressionName);
                      setState(() => _expressionName = "");
                    },
            ),
            for (var x in e.expressions)
              if (same(x.face))
                CanvasTextButton(
                  key: ValueKey("studioExpressionOff-${x.name}"),
                  label: "Remove ${x.name}",
                  icon: Icons.close,
                  onPressed: () => c.studioRemoveExpression(x.name),
                ),
            const CanvasHint(
                "An expression is a mix of the controls: set them, then keep "
                "the mix under a name. A scene picks from these, and blends "
                "between them on its timeline."),
          ]),
      if (drawn)
        CanvasControlGroup(label: "A starting face", rule: false, children: [
          CanvasTextButton(
            key: const ValueKey("studioStartingFace"),
            label: "Make every state from the drawing",
            icon: Icons.auto_awesome,
            onPressed: c.studioStartingFace,
          ),
          const CanvasHint(
              "The eyes, the brows and every mouth drawn once for each "
              "state, as the character makes them now, on this view: a "
              "drawing of each to change, not one for all. States drawn "
              "already are kept."),
        ]),
    ];
  }

  List<Widget> _check(CharacterElement e, ColorScheme colors) {
    var ref = e.reference;
    var checks = <(String, String, bool)>[
      (
        "A reference",
        ref == null ? "None yet: step 1" : "${ref.cuts.length} cuts",
        ref != null
      ),
      for (var k in _figureKeys)
        (
          "${_cutNames[k]} drawn from it",
          ref?.cutFor(k) == null ? "No cut for it: step 1" : "Cut found",
          ref?.cutFor(k) != null
        ),
      if (ref != null && ref.heads > 0)
        (
          "Heads tall agree",
          "reference ${ref.heads.toStringAsFixed(1)}, character "
              "${e.dna.headsTall.toStringAsFixed(1)}",
          (ref.heads - e.dna.headsTall).abs() < 0.25
        ),
      (
        "A palette",
        e.palette.isEmpty ? "None yet: step 1" : "${e.palette.length} swatches",
        e.palette.isNotEmpty
      ),
      (
        "Drawn on",
        e.drawings.isEmpty
            ? "Nothing drawn yet: step 3"
            : "${e.drawings.length} drawings",
        e.drawings.isNotEmpty
      ),
      for (var k in _figureKeys)
        if (ref?.cutFor(k) != null)
          (
            "${_cutNames[k]} drawn",
            _drawnOn(e, k) ? "Its own drawing" : "Not drawn yet: step 3",
            _drawnOn(e, k)
          ),
      for (var (layer, name) in const [
        ("eyes", "Eye line"),
        ("mouth", "Mouth line")
      ])
        if (studioDrift(e, layer) case var drift?)
          (
            "$name agrees across views",
            drift < 0.015
                ? "Level on every view"
                : "Off by ${(drift * 100).toStringAsFixed(1)}% of the height "
                    "between views",
            drift < 0.015
          ),
      for (var kind in ChartKind.values)
        if (_chartsOf(e, kind) case var charts when charts.isNotEmpty)
          (
            "${kind.label} chart",
            [
              for (var MapEntry(:key, value: chart) in charts.entries)
                "${_cutNames[key] ?? key} ${chart.drawings.length} of "
                    "${kind.keys.length}",
            ].join(", "),
            charts.values.every((ch) => ch.drawings.length == kind.keys.length)
          ),
    ];
    return [
      for (var (name, says, ok) in checks)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      ok ? const Color(0xFF3CCF7A) : const Color(0xFFF2B33D)),
              child: Icon(ok ? Icons.check : Icons.priority_high,
                  size: 11, color: const Color(0xFF101114)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style:
                            TextStyle(fontSize: 12, color: colors.onSurface)),
                    Text(says,
                        style: TextStyle(
                            fontSize: 10.5, color: colors.onSurfaceVariant)),
                  ]),
            ),
          ]),
        ),
    ];
  }

  Widget _row(ColorScheme colors, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 12, color: colors.onSurface))),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface)),
        ]),
      );
}

/// _drawnOn is whether view [panel] of [e] has a drawing of its own.
bool _drawnOn(CharacterElement e, String panel) => e.drawings.entries
    .any((d) => d.key.split("@").first == panel && d.value.shapes.isNotEmpty);

/// _chartsOf are [kind]'s charts on [e], by the view they are drawn on.
Map<String, LayerChart> _chartsOf(CharacterElement e, ChartKind kind) => {
      for (var MapEntry(:key, value: d) in e.drawings.entries)
        if (d.charts[kind.layer] case var chart?) key.split("@").first: chart,
    };

/// studioDrift is how far [layer] -- the eyes, the mouth -- sits from one
/// view to another, as a share of the character's height: where each view
/// with it drawn as its own draws it, standing at rest, the highest and the
/// lowest compared. Null where fewer than two views draw it.
double? studioDrift(CharacterElement e, String layer) {
  var at = <double>[];
  for (var k in _figureKeys) {
    var turn = double.parse(k.split(",").first);
    var turned = e.copyWith(pose: e.pose.withTurn(turn));
    var shapes = drawingProxy(turned, 0, 24, layer: layer).shapes ?? const [];
    if (shapes.isEmpty) continue;
    Rect? r;
    for (var s in shapes) {
      var b = s.path.getBounds();
      r = r?.expandToInclude(b) ?? b;
    }
    at.add(r!.center.dy);
  }
  if (at.length < 2 || e.height <= 0) return null;
  at.sort();
  return (at.last - at.first) / e.height;
}

/// _Pill is a choice that is on or off.
class _Pill extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Pill(
      {required this.label, required this.on, required this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return Material(
      color: on ? colors.secondaryContainer : colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: on ? colors.primary : colors.outlineVariant)),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  color: on ? colors.onSecondaryContainer : colors.onSurface)),
        ),
      ),
    );
  }
}

/// _ChartStateTile is one state of a face chart: named, marked drawn or
/// not, outlined while the face is in it.
class _ChartStateTile extends StatelessWidget {
  final String label;
  final bool drawn;
  final bool now;
  final bool drawing;
  final VoidCallback onTap;
  const _ChartStateTile(
      {required this.label,
      required this.drawn,
      required this.now,
      required this.drawing,
      required this.onTap,
      super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color:
              drawing ? colors.primaryContainer : colors.surfaceContainerHigh,
          border: Border.all(
              color: now ? colors.primary : colors.outlineVariant,
              width: now ? 1.5 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(drawn ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 12,
              color: drawn ? colors.primary : colors.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color:
                      drawing ? colors.onPrimaryContainer : colors.onSurface)),
        ]),
      ),
    );
  }
}

/// _SwatchTile is one of the palette's colours: picked, it is the pencil's;
/// its name and colour changed in place.
class _SwatchTile extends StatelessWidget {
  final Swatch swatch;
  final bool picked;
  final VoidCallback onPick;
  final ValueChanged<Swatch> onChanged;
  const _SwatchTile(
      {required this.swatch,
      required this.picked,
      required this.onPick,
      required this.onChanged,
      super.key});

  @override
  Widget build(BuildContext context) {
    var colors = ThemeNotifier.of(context).colors;
    return SizedBox(
      width: 52,
      child: Column(children: [
        InkWell(
          onTap: onPick,
          customBorder: const CircleBorder(),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: swatch.color,
              border: Border.all(
                  color: picked ? colors.primary : colors.outlineVariant,
                  width: picked ? 2.5 : 1),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(swatch.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9.5, color: colors.onSurfaceVariant)),
      ]),
    );
  }
}

/// _SheetPreview is the reference picture, small, with its cuts drawn on
/// it, each named.
class _SheetPreview extends StatelessWidget {
  final CanvasController controller;
  final CharacterReference reference;
  const _SheetPreview({required this.controller, required this.reference});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller.images,
        builder: (context, _) {
          var picture = controller.images
              .resolve(reference.assetId, const BackgroundRemoval());
          if (picture == null) {
            return const SizedBox(
                height: 80, child: Center(child: Text("Loading…")));
          }
          return AspectRatio(
            aspectRatio: picture.width / math.max(1, picture.height),
            child: CustomPaint(
                key: const ValueKey("studioSheet"),
                painter: _SheetPainter(picture, reference)),
          );
        },
      );
}

class _SheetPainter extends CustomPainter {
  final ui.Image picture;
  final CharacterReference reference;
  _SheetPainter(this.picture, this.reference);

  static const _colours = <String, Color>{
    "0,0": Color(0xFF5AA9FF),
    "90,0": Color(0xFF3CCF7A),
    "180,0": Color(0xFFF2C94C),
    referenceFaces: Color(0xFFC58AF9),
  };

  @override
  void paint(Canvas canvas, Size size) {
    var s = size.width / picture.width;
    canvas.drawImageRect(
        picture,
        Rect.fromLTWH(
            0, 0, picture.width.toDouble(), picture.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium);
    for (var MapEntry(:key, value: r) in reference.cuts.entries) {
      var colour = _colours[key] ?? const Color(0xFFFFFFFF);
      var box = Rect.fromLTWH(r.left * s, r.top * s, r.width * s, r.height * s);
      canvas.drawRect(
          box,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = colour);
      var tp = TextPainter(
          text: TextSpan(
              text: _cutNames[key] ?? key,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: colour,
                  shadows: const [
                    Shadow(blurRadius: 2, color: Color(0xCC000000))
                  ])),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, box.topLeft + const Offset(3, 2));
    }
  }

  @override
  bool shouldRepaint(_SheetPainter old) =>
      old.picture != picture || old.reference != reference;
}
