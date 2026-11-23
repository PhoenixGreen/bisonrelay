import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/painting.dart' show EdgeInsets;

import 'package:bruig/components/paint_spec.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/colour_map.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';

// box_spec.dart is the frame round something -- its fill, border, corners
// and padding -- which text, pictures, buttons, tables and layouts share.

/// Corners is four corner radii, one number answering for any not given
/// their own. Shared by an element's frame and a rectangle shape so both
/// round alike; a box is almost always even, and saved documents hold one
/// number.
class Corners {
  /// all is every corner not given its own.
  final double all;

  /// tl, tr, br and bl are the overrides, or null.
  final double? tl;
  final double? tr;
  final double? br;
  final double? bl;

  const Corners({this.all = 0, this.tl, this.tr, this.br, this.bl});

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = Corners();

  double get topLeft => tl ?? all;
  double get topRight => tr ?? all;
  double get bottomRight => br ?? all;
  double get bottomLeft => bl ?? all;

  bool get isRounded =>
      topLeft > 0 || topRight > 0 || bottomRight > 0 || bottomLeft > 0;

  /// even is the number all four share, or null where they differ: what the
  /// "all corners" field shows.
  double? get even => topLeft == topRight &&
          topRight == bottomRight &&
          bottomRight == bottomLeft
      ? topLeft
      : null;

  /// withEven sets all four, dropping overrides.
  Corners withEven(double radius) => Corners(all: radius);

  Corners scaledBy(double by) => Corners(
        all: all * by,
        tl: tl == null ? null : tl! * by,
        tr: tr == null ? null : tr! * by,
        br: br == null ? null : br! * by,
        bl: bl == null ? null : bl! * by,
      );

  Corners copyWith(
          {double? all, double? tl, double? tr, double? br, double? bl}) =>
      Corners(
        all: all ?? this.all,
        tl: tl ?? this.tl,
        tr: tr ?? this.tr,
        br: br ?? this.br,
        bl: bl ?? this.bl,
      );

  /// rrect is [rect] with these corners, inset by [by], so a border inside a
  /// fill stays concentric with it.
  RRect rrect(Rect rect, {double by = 0}) => RRect.fromRectAndCorners(
        by == 0 ? rect : rect.deflate(by),
        topLeft: Radius.circular(math.max(0, topLeft - by)),
        topRight: Radius.circular(math.max(0, topRight - by)),
        bottomRight: Radius.circular(math.max(0, bottomRight - by)),
        bottomLeft: Radius.circular(math.max(0, bottomLeft - by)),
      );

  /// inside is [inner], already padded, with corners concentric with these.
  /// Each corner is pulled in by the wider side meeting it, which keeps the
  /// curve in its room when the padding is uneven.
  RRect inside(Rect inner, Room room) => RRect.fromRectAndCorners(
        inner,
        topLeft: Radius.circular(
            math.max(0, topLeft - math.max(room.left, room.top))),
        topRight: Radius.circular(
            math.max(0, topRight - math.max(room.right, room.top))),
        bottomRight: Radius.circular(
            math.max(0, bottomRight - math.max(room.right, room.bottom))),
        bottomLeft: Radius.circular(
            math.max(0, bottomLeft - math.max(room.left, room.bottom))),
      );

  Map<String, dynamic> toJson() => {
        if (all != _defaults.all) "r": all,
        if (tl != null) "tl": tl,
        if (tr != null) "tr": tr,
        if (br != null) "br": br,
        if (bl != null) "bl": bl,
      };

  factory Corners.fromJson(Map<String, dynamic> json) => Corners(
        all: jsonLength(json["r"], _defaults.all),
        tl: json["tl"] == null ? null : jsonLength(json["tl"], 0),
        tr: json["tr"] == null ? null : jsonLength(json["tr"], 0),
        br: json["br"] == null ? null : jsonLength(json["br"], 0),
        bl: json["bl"] == null ? null : jsonLength(json["bl"], 0),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Corners &&
          other.topLeft == topLeft &&
          other.topRight == topRight &&
          other.bottomRight == bottomRight &&
          other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);
}

/// Room is the space kept on four sides, one number answering for any not
/// given its own, as [Corners] is for corners.
class Room {
  final double all;
  final double? l;
  final double? t;
  final double? r;
  final double? b;

  const Room({this.all = 0, this.l, this.t, this.r, this.b});

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = Room();

  double get left => l ?? all;
  double get top => t ?? all;
  double get right => r ?? all;
  double get bottom => b ?? all;

  EdgeInsets get insets => EdgeInsets.fromLTRB(left, top, right, bottom);

  Rect inner(Rect rect) => insets.deflateRect(rect);

  double? get even =>
      left == top && top == right && right == bottom ? left : null;

  Room withEven(double pad) => Room(all: pad);

  Room scaledBy(double by) => Room(
        all: all * by,
        l: l == null ? null : l! * by,
        t: t == null ? null : t! * by,
        r: r == null ? null : r! * by,
        b: b == null ? null : b! * by,
      );

  Room copyWith({double? all, double? l, double? t, double? r, double? b}) =>
      Room(
        all: all ?? this.all,
        l: l ?? this.l,
        t: t ?? this.t,
        r: r ?? this.r,
        b: b ?? this.b,
      );

  Map<String, dynamic> toJson() => {
        "all": all,
        if (l != null) "l": l,
        if (t != null) "t": t,
        if (r != null) "r": r,
        if (b != null) "b": b,
      };

  factory Room.fromJson(Map<String, dynamic> json) => Room(
        all: jsonLength(json["all"], _defaults.all, signed: true),
        l: json["l"] == null ? null : jsonLength(json["l"], 0, signed: true),
        t: json["t"] == null ? null : jsonLength(json["t"], 0, signed: true),
        r: json["r"] == null ? null : jsonLength(json["r"], 0, signed: true),
        b: json["b"] == null ? null : jsonLength(json["b"], 0, signed: true),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Room &&
          other.left == left &&
          other.top == top &&
          other.right == right &&
          other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

/// BoxSpec is the frame round something: fill, border and padding, shared
/// by text, buttons, tables and images.
class BoxSpec {
  final Color fill;

  /// painted is a picture or pattern covering the box instead, cut to its
  /// corners (as TextFill does for letters); off, [fill] draws the box.
  final TextFill painted;
  final double borderWidth;
  final Color borderColor;

  /// fillFade and borderFade are second colours to fade to, or null for flat.
  final GradientSpec? fillFade;
  final GradientSpec? borderFade;

  /// bwL, bwT, bwR and bwB are one side's border width, or null for
  /// [borderWidth] (a rule under a heading, a bar down a quote).
  final double? bwL;
  final double? bwT;
  final double? bwR;
  final double? bwB;

  /// borderRadius is every corner not given its own, and [padding] every
  /// side; padL..radBL are the overrides. Stored flat because BoxSpecs are
  /// consts, and a const constructor cannot build [Corners] and [Room];
  /// [corners] and [pad] hand them back.
  final double borderRadius;
  final double padding;
  final double? padL;
  final double? padT;
  final double? padR;
  final double? padB;
  final double? radTL;
  final double? radTR;
  final double? radBR;
  final double? radBL;

  const BoxSpec({
    this.fill = const Color(0x00000000),
    this.painted = const TextFill(),
    this.borderWidth = 0,
    this.bwL,
    this.bwT,
    this.bwR,
    this.bwB,
    this.borderColor = const Color(0xFFFFFFFF),
    this.fillFade,
    this.borderFade,
    this.borderRadius = 0,
    this.padding = 8,
    this.padL,
    this.padT,
    this.padR,
    this.padB,
    this.radTL,
    this.radTR,
    this.radBR,
    this.radBL,
    this.borderInset = 0,
  });

  /// _defaults is one as made: what a saved one means by leaving a
  /// field out.
  static const _defaults = BoxSpec();

  /// borderInset draws the border that far inside the box's edge, with the
  /// box's own rounding: a plaque's rule inside its frame. Uneven sides are
  /// inset as strips.
  final double borderInset;

  Corners get corners =>
      Corners(all: borderRadius, tl: radTL, tr: radTR, br: radBR, bl: radBL);
  Room get pad => Room(all: padding, l: padL, t: padT, r: padR, b: padB);

  /// borders is the four border widths.
  Room get borders => Room(all: borderWidth, l: bwL, t: bwT, r: bwR, b: bwB);

  /// evenBorder is the width all four sides share, or null: what the "all
  /// sides" field shows, and whether it can be drawn as one rounded rectangle.
  double? get evenBorder => borders.even;

  bool get hasBorder =>
      borderColor.a > 0 &&
      (borders.left > 0 ||
          borders.top > 0 ||
          borders.right > 0 ||
          borders.bottom > 0);

  double get padLeft => pad.left;
  double get padTop => pad.top;
  double get padRight => pad.right;
  double get padBottom => pad.bottom;

  double get topLeft => corners.topLeft;
  double get topRight => corners.topRight;
  double get bottomRight => corners.bottomRight;
  double get bottomLeft => corners.bottomLeft;

  EdgeInsets get insets => pad.insets;

  Rect inner(Rect rect) => pad.inner(rect);

  /// evenPad and evenRadius are the shared value, or null where they differ:
  /// what the "all sides" field shows.
  double? get evenPad => pad.even;

  double? get evenRadius => corners.even;

  bool get isRounded => corners.isRounded;

  RRect rounded(Rect rect, {double by = 0}) => corners.rrect(rect, by: by);

  /// insetRounded is [within], already padded, with concentric corners.
  RRect insetRounded(Rect within) => corners.inside(within, pad);

  /// assetIds is the picture this box is painted with. Every element with a
  /// box must fold it into its own assetIds, or the sweep deletes it.
  Set<String> get assetIds =>
      painted.assetId.isEmpty ? const {} : {painted.assetId};

  /// scaledBy sizes corners, padding and border widths by [by].
  BoxSpec scaledBy(double by) => withCorners(corners.scaledBy(by))
      .withRoom(pad.scaledBy(by))
      .withBorders(borders.scaledBy(by))
      .copyWith(borderInset: borderInset * by);

  /// withCorners and withRoom replace one whole set, overrides and all, not
  /// as copyWith, whose nulls keep the old overrides.
  BoxSpec withCorners(Corners corners) => BoxSpec(
      fill: fill,
      painted: painted,
      borderWidth: borderWidth,
      bwL: bwL,
      bwT: bwT,
      bwR: bwR,
      bwB: bwB,
      borderColor: borderColor,
      fillFade: fillFade,
      borderFade: borderFade,
      borderRadius: corners.all,
      radTL: corners.tl,
      radTR: corners.tr,
      radBR: corners.br,
      radBL: corners.bl,
      padding: padding,
      padL: padL,
      padT: padT,
      padR: padR,
      padB: padB,
      borderInset: borderInset);

  BoxSpec withRoom(Room room) => BoxSpec(
      fill: fill,
      painted: painted,
      borderWidth: borderWidth,
      bwL: bwL,
      bwT: bwT,
      bwR: bwR,
      bwB: bwB,
      borderColor: borderColor,
      fillFade: fillFade,
      borderFade: borderFade,
      borderRadius: borderRadius,
      radTL: radTL,
      radTR: radTR,
      radBR: radBR,
      radBL: radBL,
      padding: room.all,
      padL: room.l,
      padT: room.t,
      padR: room.r,
      padB: room.b,
      borderInset: borderInset);

  /// withBorders replaces all four widths, as [withCorners] does.
  BoxSpec withBorders(Room room) => BoxSpec(
      fill: fill,
      painted: painted,
      borderWidth: room.all,
      bwL: room.l,
      bwT: room.t,
      bwR: room.r,
      bwB: room.b,
      borderColor: borderColor,
      fillFade: fillFade,
      borderFade: borderFade,
      borderRadius: borderRadius,
      radTL: radTL,
      radTR: radTR,
      radBR: radBR,
      radBL: radBL,
      padding: padding,
      padL: padL,
      padT: padT,
      padR: padR,
      padB: padB,
      borderInset: borderInset);

  /// withEvenPad sets all four sides, dropping overrides.
  BoxSpec withEvenPad(double padding) => withRoom(pad.withEven(padding));

  /// withEvenRadius does the same for corners.
  BoxSpec withEvenRadius(double radius) =>
      withCorners(corners.withEven(radius));

  BoxSpec copyWith({
    Color? fill,
    TextFill? painted,
    double? borderWidth,
    double? bwL,
    double? bwT,
    double? bwR,
    double? bwB,
    Color? borderColor,
    GradientSpec? fillFade,
    GradientSpec? borderFade,
    bool flatFill = false,
    bool flatBorder = false,
    double? borderRadius,
    double? padding,
    double? padL,
    double? padT,
    double? padR,
    double? padB,
    double? radTL,
    double? radTR,
    double? radBR,
    double? radBL,
    double? borderInset,
  }) =>
      BoxSpec(
        fill: fill ?? this.fill,
        painted: painted ?? this.painted,
        borderWidth: borderWidth ?? this.borderWidth,
        bwL: bwL ?? this.bwL,
        bwT: bwT ?? this.bwT,
        bwR: bwR ?? this.bwR,
        bwB: bwB ?? this.bwB,
        borderColor: borderColor ?? this.borderColor,
        fillFade: flatFill ? null : (fillFade ?? this.fillFade),
        borderFade: flatBorder ? null : (borderFade ?? this.borderFade),
        borderRadius: borderRadius ?? this.borderRadius,
        padding: padding ?? this.padding,
        padL: padL ?? this.padL,
        padT: padT ?? this.padT,
        padR: padR ?? this.padR,
        padB: padB ?? this.padB,
        radTL: radTL ?? this.radTL,
        radTR: radTR ?? this.radTR,
        radBR: radBR ?? this.radBR,
        radBL: radBL ?? this.radBL,
        borderInset: borderInset ?? this.borderInset,
      );

  /// mapColours maps the fill, the border colour (shown only where there is
  /// a border, as it is saved), both fades, and the picture or pattern it is
  /// painted with (shown only while it is painted).
  BoxSpec mapColours(ColourMap f) {
    var p = ColourPass(f);
    var fill = p(this.fill);
    var painted =
        p.part(this.painted, (x) => x.mapColours(f.shownOnlyIf(x.on)));
    var borderColor = p(this.borderColor, shown: hasBorder);
    var fillFade = p.partOrNone(this.fillFade, (g) => g.mapColours(f));
    var borderFade = p.partOrNone(this.borderFade, (g) => g.mapColours(f));
    if (!p.changed) return this;
    return copyWith(
      fill: fill,
      painted: painted,
      borderColor: borderColor,
      fillFade: fillFade,
      borderFade: borderFade,
    );
  }

  Map<String, dynamic> toJson() => {
        "fill": colorToJson(fill),
        if (painted.on) "painted": painted.toJson(),
        if (fillFade != null) "fillFade": fillFade!.toJson(),
        if (borderFade != null) "borderFade": borderFade!.toJson(),
        if (borderWidth > 0) "bw": borderWidth,
        if (hasBorder) "bc": colorToJson(borderColor),
        // Overrides are written only where set, so an even box saves only
        // its one number.
        if (bwL != null) "bwL": bwL,
        if (bwT != null) "bwT": bwT,
        if (bwR != null) "bwR": bwR,
        if (bwB != null) "bwB": bwB,
        if (borderRadius > 0) "br": borderRadius,
        "pad": padding,
        if (padL != null) "padL": padL,
        if (padT != null) "padT": padT,
        if (padR != null) "padR": padR,
        if (padB != null) "padB": padB,
        if (radTL != null) "rTL": radTL,
        if (radTR != null) "rTR": radTR,
        if (radBR != null) "rBR": radBR,
        if (radBL != null) "rBL": radBL,
        if (borderInset != _defaults.borderInset) "bi": borderInset,
      };

  factory BoxSpec.fromJson(Map<String, dynamic> json) => BoxSpec(
        fill: colorFromJson(json["fill"], _defaults.fill),
        painted: json["painted"] is Map
            ? TextFill.fromJson(
                (json["painted"] as Map).cast<String, dynamic>())
            : const TextFill(),
        fillFade: json["fillFade"] is Map
            ? GradientSpec.fromJson(
                (json["fillFade"] as Map).cast<String, dynamic>())
            : null,
        borderFade: json["borderFade"] is Map
            ? GradientSpec.fromJson(
                (json["borderFade"] as Map).cast<String, dynamic>())
            : null,
        borderWidth: jsonLength(json["bw"], _defaults.borderWidth),
        bwL: json["bwL"] == null ? null : jsonLength(json["bwL"], 0),
        bwT: json["bwT"] == null ? null : jsonLength(json["bwT"], 0),
        bwR: json["bwR"] == null ? null : jsonLength(json["bwR"], 0),
        bwB: json["bwB"] == null ? null : jsonLength(json["bwB"], 0),
        borderColor: colorFromJson(json["bc"]),
        borderRadius: jsonLength(json["br"], _defaults.borderRadius),
        padding: jsonLength(json["pad"], _defaults.padding, signed: true),
        padL: json["padL"] == null
            ? null
            : jsonLength(json["padL"], 0, signed: true),
        padT: json["padT"] == null
            ? null
            : jsonLength(json["padT"], 0, signed: true),
        padR: json["padR"] == null
            ? null
            : jsonLength(json["padR"], 0, signed: true),
        padB: json["padB"] == null
            ? null
            : jsonLength(json["padB"], 0, signed: true),
        radTL: json["rTL"] == null ? null : jsonLength(json["rTL"], 0),
        radTR: json["rTR"] == null ? null : jsonLength(json["rTR"], 0),
        radBR: json["rBR"] == null ? null : jsonLength(json["rBR"], 0),
        radBL: json["rBL"] == null ? null : jsonLength(json["rBL"], 0),
        borderInset: jsonLength(json["bi"], _defaults.borderInset),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoxSpec &&
          other.fill == fill &&
          other.fillFade == fillFade &&
          other.borderFade == borderFade &&
          other.borderWidth == borderWidth &&
          other.bwL == bwL &&
          other.bwT == bwT &&
          other.bwR == bwR &&
          other.bwB == bwB &&
          other.borderColor == borderColor &&
          other.corners == corners &&
          other.pad == pad &&
          other.borderInset == borderInset;

  @override
  int get hashCode => Object.hash(fill, fillFade, borderFade, borderWidth,
      borderColor, corners, pad, borders, borderInset);
}
