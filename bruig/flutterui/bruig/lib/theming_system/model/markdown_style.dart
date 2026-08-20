import 'package:bruig/theming_system/model/button_style.dart';
import 'package:bruig/theming_system/model/area_sides.dart';
import 'package:bruig/theming_system/model/color_hex.dart';
import 'package:flutter/material.dart';

// markdown_style.dart is a style guide for a post: how its headings, quotes,
// code, lists and pictures should look.
//
// Local, and only ever local. A post carries the *name* of a guide and never
// the guide itself, so what arrives is a request to use something the reader
// already has -- which is why nothing here can be smuggled in from outside.
// A name that means nothing on this device falls back to the default, and a
// reader who would rather not be styled at all can say so once.
//
// That is also why the vocabulary is closed. Every value below is a choice
// from a fixed set or a bounded number, so a guide cannot express "text the
// same colour as the background" or "eight hundred point type" whatever it
// was built from.

/// MarkdownInk is a colour in a guide.
///
/// A role by preference, which resolves against whatever theme the reader is
/// using -- so one guide reads correctly in a light theme and a dark one
/// without being written twice. The literal is an escape hatch for someone
/// who means a particular colour and accepts that it is their own lookout in
/// the other theme.
class MarkdownInk {
  final MarkdownRole? role;
  final Color? literal;

  /// paletteIndex is the palette slot [literal] was picked from.
  ///
  /// Kept beside the colour, not instead of it, for the reason every other
  /// colour in the editor keeps both: the index is what makes the choice
  /// follow the palette when that is edited, and the colour is what it falls
  /// back to when the palette has since grown shorter.
  final int? paletteIndex;

  const MarkdownInk.of(this.role)
      : literal = null,
        paletteIndex = null;
  const MarkdownInk.literal(Color this.literal, {this.paletteIndex})
      : role = null;

  static const inherit = MarkdownInk.of(null);
  bool get isInherit => role == null && literal == null;

  /// resolve turns this into a colour.
  ///
  /// [paletteColor] looks a slot up in the live palette; without it the
  /// stored colour is used, which is what the model's own tests do.
  Color? resolve(Color Function(MarkdownRole) roleColor,
      {Color? Function(int)? paletteColor}) {
    if (paletteIndex != null && paletteColor != null) {
      var live = paletteColor(paletteIndex!);
      if (live != null) return live;
    }
    if (literal != null) return literal;
    if (role != null) return roleColor(role!);
    return null;
  }

  Object? toJson() {
    if (literal == null) return role?.name;
    return paletteIndex == null
        ? colorToHex(literal!)
        : {"color": colorToHex(literal!), "slot": paletteIndex};
  }

  static MarkdownInk fromJson(Object? json) {
    if (json is Map) {
      var hex = json["color"];
      var slot = json["slot"];
      if (hex is String) {
        try {
          return MarkdownInk.literal(colorFromHex(hex),
              paletteIndex: slot is num ? slot.toInt() : null);
        } catch (_) {
          return inherit;
        }
      }
      return inherit;
    }
    if (json is! String || json.isEmpty) return inherit;
    if (json.startsWith("#")) {
      // The shared codec throws on anything that is not hex, and this is
      // reading a file the user can edit.
      try {
        return MarkdownInk.literal(colorFromHex(json));
      } catch (_) {
        return inherit;
      }
    }
    for (var role in MarkdownRole.values) {
      if (role.name == json) return MarkdownInk.of(role);
    }
    return inherit;
  }
}

/// MarkdownRole is the small set of colours a guide can name.
///
/// Deliberately far shorter than the theme's own token list. These are the
/// distinctions a piece of writing actually makes -- ordinary text, quieter
/// text, something picked out -- and a dropdown of forty Material tokens
/// would be a worse way to choose between them.
enum MarkdownRole {
  text("Text"),
  muted("Muted text"),
  accent("Accent"),
  link("Link"),
  quote("Quote text"),
  quoteBar("Quote bar"),
  raised("Raised background"),
  outline("Lines and borders");

  final String label;
  const MarkdownRole(this.label);
}

/// MarkdownFont is which of the bundled families to set text in.
///
/// Bundled only, and this list is exactly what pubspec.yaml ships: Inter and
/// RobotoMono. A guide naming anything else renders differently on every
/// device, which is the whole thing this feature is for avoiding -- and it
/// does it silently, since a missing family falls back rather than failing.
///
/// The first version of this list did precisely that. It offered
/// "SourceCodePro" and "serif", neither of which is bundled, so choosing
/// either changed nothing and the setting looked broken. Adding a face means
/// adding a font file, which is what PT Serif is -- all four of Regular,
/// Bold, Italic and Bold Italic, because a family missing a weight does not
/// synthesise it: Flutter picks the nearest one it has, and bold headings in
/// a family with no bold simply come out regular.
enum MarkdownFont {
  inherit("Theme default", null),
  sans("Sans", "Inter"),
  serif("Serif", "PTSerif"),
  mono("Monospace", "RobotoMono");

  final String label;
  final String? family;
  const MarkdownFont(this.label, this.family);
}

/// MarkdownTableFit is how a table divides its width between its columns.
///
/// Two answers, because they are the two a writer actually wants: every
/// column the same, or every column as wide as what is in it. Anything finer
/// -- this column 30%, that one 70% -- would have to be said in the post
/// rather than in a guide, and a guide is about how posts look, not about
/// what one particular table says.
enum MarkdownTableFit {
  equal("Equal width"),
  fitContent("Fit the contents");

  final String label;
  const MarkdownTableFit(this.label);
}

/// MarkdownCheckMark is what goes inside a task list's box.
///
/// Markdown has task lists -- `- [ ]` for an open item and `- [x]` for a done
/// one -- and this is how the two are drawn. Both ends are settable, because
/// which mark reads as "done" is genuinely a matter of taste: a tick for work
/// finished, a cross for something ruled out.
///
/// Drawn as a box with a mark in it rather than as a character, so it does
/// not depend on the reader's font having ☑ and ☒ -- a guide travels, and a
/// glyph that is a box on one machine and a blank rectangle on another is not
/// a setting anybody can rely on.
enum MarkdownCheckMark {
  empty("Empty", null),
  cross("Cross", Icons.close),
  tick("Tick", Icons.check);

  /// label is what the settings show, and [icon] what goes in the box --
  /// null for a box left open.
  final String label;
  final IconData? icon;
  const MarkdownCheckMark(this.label, this.icon);
}

/// MarkdownAlign is how a block sits across the column.
enum MarkdownAlign { inherit, left, center, right }

/// TextRule is one element's text: everything a TextStyle can carry, in the
/// bounded form a guide is allowed to say it.
class TextRule {
  /// scale multiplies the theme's own size for this element rather than
  /// replacing it. A guide written against a 14-point body still reads
  /// correctly for someone who has set their text larger.
  final double scale;
  final MarkdownInk ink;
  final MarkdownFont font;
  final bool? bold;
  final bool? italic;

  /// lineHeight is a multiple of the font size, or null to leave it alone.
  /// The single largest lever on whether a long post is comfortable.
  final double? lineHeight;
  final double? letterSpacing;
  final bool? underline;

  const TextRule({
    this.scale = 1.0,
    this.ink = MarkdownInk.inherit,
    this.font = MarkdownFont.inherit,
    this.bold,
    this.italic,
    this.lineHeight,
    this.letterSpacing,
    this.underline,
  });

  TextRule copyWith({
    double? scale,
    MarkdownInk? ink,
    MarkdownFont? font,
    bool? bold,
    bool? italic,
    double? lineHeight,
    double? letterSpacing,
    bool? underline,
  }) =>
      TextRule(
        scale: scale ?? this.scale,
        ink: ink ?? this.ink,
        font: font ?? this.font,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        lineHeight: lineHeight ?? this.lineHeight,
        letterSpacing: letterSpacing ?? this.letterSpacing,
        underline: underline ?? this.underline,
      );

  /// applyTo folds this rule onto the theme's own style for the element.
  ///
  /// Onto rather than instead of: anything the guide says nothing about is
  /// left as the reader's theme had it.
  TextStyle applyTo(TextStyle base, Color Function(MarkdownRole) roleColor,
      {Color? Function(int)? paletteColor}) {
    // Resolved once and used for the underline as well as the text.
    //
    // An underline with no colour of its own is drawn in whatever
    // decorationColor the style carries, and Material's own text styles set
    // that to the body colour. flutter_markdown builds a link's style by
    // merging the `a` style onto the paragraph's, so a link that named a
    // colour got that colour for its letters and the body's for the line
    // under them -- an underline in a visibly different colour from the text
    // it underlines.
    var color =
        ink.resolve(roleColor, paletteColor: paletteColor) ?? base.color;
    return base.copyWith(
      // A rule that asks for no change in size, applied to a style that
      // names none, states none either -- so an inline run left at 100%
      // stays whatever the text around it is. Anything else would give a
      // bold word inside a heading a size of its own.
      fontSize: base.fontSize == null && scale == 1.0
          ? null
          : (base.fontSize ?? 14) * scale.clamp(_minScale, _maxScale),
      color: color,
      decorationColor: color,
      fontFamily: font.family ?? base.fontFamily,
      fontWeight: bold == null
          ? base.fontWeight
          : (bold! ? FontWeight.w700 : FontWeight.w400),
      fontStyle: italic == null
          ? base.fontStyle
          : (italic! ? FontStyle.italic : FontStyle.normal),
      height: lineHeight?.clamp(_minLineHeight, _maxLineHeight) ?? base.height,
      letterSpacing: letterSpacing?.clamp(-1.0, 4.0) ?? base.letterSpacing,
      decoration: underline == null
          ? base.decoration
          : (underline! ? TextDecoration.underline : TextDecoration.none),
    );
  }

  Map<String, Object?> toJson() => {
        if (scale != 1.0) "scale": scale,
        if (!ink.isInherit) "ink": ink.toJson(),
        if (font != MarkdownFont.inherit) "font": font.name,
        if (bold != null) "bold": bold,
        if (italic != null) "italic": italic,
        if (lineHeight != null) "lineHeight": lineHeight,
        if (letterSpacing != null) "letterSpacing": letterSpacing,
        if (underline != null) "underline": underline,
      };

  static TextRule fromJson(Map<String, Object?> json) => TextRule(
        scale: _asDouble(json["scale"]) ?? 1.0,
        ink: MarkdownInk.fromJson(json["ink"]),
        font: MarkdownFont.values.firstWhere((f) => f.name == json["font"],
            orElse: () => MarkdownFont.inherit),
        bold: json["bold"] as bool?,
        italic: json["italic"] as bool?,
        lineHeight: _asDouble(json["lineHeight"]),
        letterSpacing: _asDouble(json["letterSpacing"]),
        underline: json["underline"] as bool?,
      );
}

/// The bounds every number in a guide is held to.
///
/// These are what stop a guide being a way to shout or to hide. Text cannot
/// be scaled to nothing or to a size that pushes the rest of a conversation
/// off the screen, and a line cannot be crushed to overlap the one above it.
const _minScale = 0.6;
const _maxScale = 3.0;
const _minLineHeight = 0.9;
const _maxLineHeight = 3.0;

double? _asDouble(Object? v) => v is num ? v.toDouble() : null;

/// ImageRule is how an embedded picture is drawn.
///
/// Not part of MarkdownStyleSheet, which has nothing to say about pictures --
/// its `img` entry styles the alt text. These are read by the embed builder
/// this app supplies itself.
class ImageRule {
  /// widthPercent of the column, 10 to 100.
  final double widthPercent;
  final double cornerRadius;
  final double borderWidth;
  final MarkdownInk borderInk;
  final MarkdownAlign align;

  /// gap above and below, in logical pixels.
  final double gap;

  const ImageRule({
    this.widthPercent = 100,
    this.cornerRadius = 0,
    this.borderWidth = 0,
    this.borderInk = const MarkdownInk.of(MarkdownRole.outline),
    this.align = MarkdownAlign.left,
    this.gap = 8,
  });

  ImageRule copyWith({
    double? widthPercent,
    double? cornerRadius,
    double? borderWidth,
    MarkdownInk? borderInk,
    MarkdownAlign? align,
    double? gap,
  }) =>
      ImageRule(
        widthPercent: widthPercent ?? this.widthPercent,
        cornerRadius: cornerRadius ?? this.cornerRadius,
        borderWidth: borderWidth ?? this.borderWidth,
        borderInk: borderInk ?? this.borderInk,
        align: align ?? this.align,
        gap: gap ?? this.gap,
      );

  double get boundedWidth => widthPercent.clamp(10, 100);
  double get boundedRadius => cornerRadius.clamp(0, 48);
  double get boundedBorder => borderWidth.clamp(0, 8);

  // Compared by value, not by identity.
  //
  // MarkdownArea decides whether a piece of markdown needs a guide at all by
  // asking whether the rules differ from the plain ones, and chat relies on
  // the answer being no. Without this, two ImageRules holding identical
  // numbers were never equal -- and AreaStyle.markdownGuide rebuilds the
  // rule every time it is read, so the answer was always "different" and
  // chat was quietly being drawn with a post's picture rules.
  @override
  bool operator ==(Object other) =>
      other is ImageRule &&
      other.widthPercent == widthPercent &&
      other.cornerRadius == cornerRadius &&
      other.borderWidth == borderWidth &&
      other.borderInk.toJson() == borderInk.toJson() &&
      other.align == align &&
      other.gap == gap;

  @override
  int get hashCode =>
      Object.hash(widthPercent, cornerRadius, borderWidth, align, gap);

  Map<String, Object?> toJson() => {
        "widthPercent": widthPercent,
        "cornerRadius": cornerRadius,
        "borderWidth": borderWidth,
        if (!borderInk.isInherit) "borderInk": borderInk.toJson(),
        "align": align.name,
        "gap": gap,
      };

  static ImageRule fromJson(Map<String, Object?> json) => ImageRule(
        widthPercent: _asDouble(json["widthPercent"]) ?? 100,
        cornerRadius: _asDouble(json["cornerRadius"]) ?? 0,
        borderWidth: _asDouble(json["borderWidth"]) ?? 0,
        borderInk: MarkdownInk.fromJson(json["borderInk"]),
        align: MarkdownAlign.values.firstWhere((a) => a.name == json["align"],
            orElse: () => MarkdownAlign.left),
        gap: _asDouble(json["gap"]) ?? 8,
      );
}

/// ColumnRule is how a run of columns is laid out.
///
/// Markdown has no columns of its own, so they are a block syntax this app
/// adds -- see ColumnsBlockSyntax. What a guide gets to say about them is the
/// space between them and the width below which they stop being columns at
/// all, which are the only two decisions that are about the page rather than
/// about the writing.
class ColumnRule {
  /// gap is the space between one column and the next.
  final double gap;

  /// stackBelow is the narrowest a column may be before the run gives up and
  /// stacks them one above another.
  ///
  /// Not optional and not a screen size: the same post is read in a window a
  /// third the width of somebody else's, and three columns of nine
  /// characters each is not a layout. Below this width they become what they
  /// would have been without the markup, which is the one reading that is
  /// always legible.
  final double stackBelow;

  /// The box the run of columns is drawn in: space inside it, space around
  /// it, and the line between the two.
  ///
  /// Around the run as a whole, not around each column. A border on every
  /// column is a row of boxes; a border round the outside is a block with
  /// columns in it, which is what columns are. What separates one column
  /// from the next is [dividerWidth], and it is deliberately a different
  /// setting -- a rule down the middle usually reads better when it is not
  /// the same weight as the frame, and most of the time there is no frame at
  /// all.
  ///
  /// Each is a single figure with an optional per-side split beside it,
  /// which is the form every other spacing setting in the theme editor
  /// takes. Null means "not split", so a guide that never touched the four
  /// is stored as small as it was before they existed.
  final double padding;
  final SideValues? paddingSides;
  final double margin;
  final SideValues? marginSides;
  final double borderWidth;
  final SideValues? borderWidthSides;
  final MarkdownInk borderInk;
  final double radius;
  final SideValues? radiusSides;

  /// dividerWidth is the rule drawn down the middle of the gap between one
  /// column and the next, or zero for none.
  ///
  /// One line between each pair, not a border on each column: two adjacent
  /// borders make a double line with a channel down the middle of it, which
  /// is the thing that looked wrong.
  final double dividerWidth;
  final MarkdownInk dividerInk;

  const ColumnRule({
    this.gap = 16,
    this.stackBelow = 220,
    this.padding = 0,
    this.paddingSides,
    this.margin = 0,
    this.marginSides,
    this.borderWidth = 0,
    this.borderWidthSides,
    this.borderInk = const MarkdownInk.of(MarkdownRole.outline),
    this.radius = 0,
    this.radiusSides,
    this.dividerWidth = 0,
    this.dividerInk = const MarkdownInk.of(MarkdownRole.outline),
  });

  double get boundedGap => gap.clamp(0, 64);
  double get boundedStackBelow => stackBelow.clamp(80, 480);

  /// The four resolved values for each setting: the split when there is one,
  /// otherwise the single figure all round.
  SideValues get paddings =>
      paddingSides ?? SideValues.all(padding.clamp(0, 64));
  SideValues get margins => marginSides ?? SideValues.all(margin.clamp(0, 64));
  SideValues get borderWidths =>
      borderWidthSides ?? SideValues.all(borderWidth.clamp(0, 12));
  SideValues get radii => radiusSides ?? SideValues.all(radius.clamp(0, 48));
  double get boundedDivider => dividerWidth.clamp(0, 12);

  ColumnRule copyWith({
    double? gap,
    double? stackBelow,
    double? padding,
    SideValues? paddingSides,
    bool clearPaddingSides = false,
    double? margin,
    SideValues? marginSides,
    bool clearMarginSides = false,
    double? borderWidth,
    SideValues? borderWidthSides,
    bool clearBorderWidthSides = false,
    MarkdownInk? borderInk,
    double? radius,
    SideValues? radiusSides,
    bool clearRadiusSides = false,
    double? dividerWidth,
    MarkdownInk? dividerInk,
  }) =>
      ColumnRule(
        gap: gap ?? this.gap,
        stackBelow: stackBelow ?? this.stackBelow,
        padding: padding ?? this.padding,
        paddingSides:
            clearPaddingSides ? null : (paddingSides ?? this.paddingSides),
        margin: margin ?? this.margin,
        marginSides:
            clearMarginSides ? null : (marginSides ?? this.marginSides),
        borderWidth: borderWidth ?? this.borderWidth,
        borderWidthSides: clearBorderWidthSides
            ? null
            : (borderWidthSides ?? this.borderWidthSides),
        borderInk: borderInk ?? this.borderInk,
        radius: radius ?? this.radius,
        radiusSides:
            clearRadiusSides ? null : (radiusSides ?? this.radiusSides),
        dividerWidth: dividerWidth ?? this.dividerWidth,
        dividerInk: dividerInk ?? this.dividerInk,
      );

  Map<String, Object?> toJson() => {
        "gap": gap,
        "stackBelow": stackBelow,
        if (padding != 0) "padding": padding,
        if (paddingSides != null) "paddingSides": paddingSides!.toJson(),
        if (margin != 0) "margin": margin,
        if (marginSides != null) "marginSides": marginSides!.toJson(),
        if (borderWidth != 0) "borderWidth": borderWidth,
        if (borderWidthSides != null)
          "borderWidthSides": borderWidthSides!.toJson(),
        if (!borderInk.isInherit) "borderInk": borderInk.toJson(),
        if (radius != 0) "radius": radius,
        if (radiusSides != null) "radiusSides": radiusSides!.toJson(),
        if (dividerWidth != 0) "dividerWidth": dividerWidth,
        if (!dividerInk.isInherit) "dividerInk": dividerInk.toJson(),
      };

  static ColumnRule fromJson(Map<String, Object?> json) => ColumnRule(
        gap: _asDouble(json["gap"]) ?? 16,
        stackBelow: _asDouble(json["stackBelow"]) ?? 220,
        padding: _asDouble(json["padding"]) ?? 0,
        paddingSides: SideValues.fromJson(json["paddingSides"]),
        margin: _asDouble(json["margin"]) ?? 0,
        marginSides: SideValues.fromJson(json["marginSides"]),
        borderWidth: _asDouble(json["borderWidth"]) ?? 0,
        borderWidthSides: SideValues.fromJson(json["borderWidthSides"]),
        borderInk: json.containsKey("borderInk")
            ? MarkdownInk.fromJson(json["borderInk"])
            : const MarkdownInk.of(MarkdownRole.outline),
        radius: _asDouble(json["radius"]) ?? 0,
        radiusSides: SideValues.fromJson(json["radiusSides"]),
        dividerWidth: _asDouble(json["dividerWidth"]) ?? 0,
        dividerInk: json.containsKey("dividerInk")
            ? MarkdownInk.fromJson(json["dividerInk"])
            : const MarkdownInk.of(MarkdownRole.outline),
      );

  @override
  bool operator ==(Object other) =>
      other is ColumnRule &&
      other.gap == gap &&
      other.stackBelow == stackBelow &&
      other.padding == padding &&
      other.paddingSides == paddingSides &&
      other.margin == margin &&
      other.marginSides == marginSides &&
      other.borderWidth == borderWidth &&
      other.borderWidthSides == borderWidthSides &&
      other.borderInk.toJson() == borderInk.toJson() &&
      other.radius == radius &&
      other.radiusSides == radiusSides &&
      other.dividerWidth == dividerWidth &&
      other.dividerInk.toJson() == dividerInk.toJson();

  @override
  int get hashCode => Object.hash(
      gap,
      stackBelow,
      padding,
      paddingSides,
      margin,
      marginSides,
      borderWidth,
      borderWidthSides,
      radius,
      radiusSides,
      dividerWidth);
}

/// MarkdownCardIcon is the icon a card may carry.
///
/// A closed list, like every other choice a guide or a post can make. A post
/// naming an icon is naming something the reader's app has to already have,
/// and "whatever Material calls this string" is not that: a name that means
/// nothing renders as an empty box on some builds and a different picture on
/// others. These are chosen for the things a callout is usually for.
enum MarkdownCardIcon {
  info("info", Icons.info_outline),
  note("note", Icons.push_pin_outlined),
  tip("tip", Icons.lightbulb_outline),
  warning("warning", Icons.warning_amber_outlined),
  danger("danger", Icons.report_gmailerrorred_outlined),
  success("success", Icons.check_circle_outline),
  question("question", Icons.help_outline),
  announce("announce", Icons.campaign_outlined),
  mail("mail", Icons.mail_outline),
  star("star", Icons.star_outline),
  heart("heart", Icons.favorite_border),
  calendar("calendar", Icons.calendar_today_outlined),
  clock("clock", Icons.schedule_outlined),
  link("link", Icons.link),
  download("download", Icons.download_outlined),
  payment("payment", Icons.payments_outlined);

  /// name is what a post writes, and [icon] what it is drawn as.
  final String label;
  final IconData icon;
  const MarkdownCardIcon(this.label, this.icon);

  /// named returns the icon a post asked for, or null when it asked for
  /// something this app does not have -- in which case the card is drawn
  /// without one rather than with a guess.
  static MarkdownCardIcon? named(String name) {
    var wanted = name.trim().toLowerCase();
    for (var i in values) {
      if (i.label == wanted) return i;
    }
    return null;
  }
}

/// GridRule is how a gallery is laid out -- see GridBlockSyntax.
///
/// Deliberately its own rule rather than borrowing ColumnRule. The two look
/// alike and are not: a run of columns is one piece of writing shared out,
/// where the gap is a reading gutter, while a gallery is separate pictures
/// side by side, where the gap is the space between two things. Setting one
/// should not move the other.
///
/// Only the decisions that are about the page rather than the writing: how
/// far apart the cells sit, how many across when the writer did not say, and
/// the width below which side-by-side stops being a layout.
class GridRule {
  /// gap is the space between one cell and the next, across and down.
  final double gap;

  /// columns is how many across a bare --grid-- is, when the writer did not
  /// write --grid[n]--.
  final int columns;

  /// stackBelow is the narrowest a cell may be before the gallery gives up
  /// and stacks the pictures one above another.
  ///
  /// The same reasoning as ColumnRule.stackBelow: the same page is read in a
  /// window a third the width of somebody else's, and four pictures across
  /// at thumbnail size is not a gallery.
  final double stackBelow;

  const GridRule({
    this.gap = 12,
    this.columns = 2,
    this.stackBelow = 180,
  });

  /// boundedGap keeps a guide from setting a gap that swallows the page.
  double get boundedGap => gap.clamp(0, 96);

  /// boundedColumns keeps the default inside what GridBlockSyntax accepts.
  int get boundedColumns => columns.clamp(1, 4);

  double get boundedStackBelow => stackBelow.clamp(0, 600);

  GridRule copyWith({double? gap, int? columns, double? stackBelow}) =>
      GridRule(
        gap: gap ?? this.gap,
        columns: columns ?? this.columns,
        stackBelow: stackBelow ?? this.stackBelow,
      );

  Map<String, Object?> toJson() => {
        "gap": gap,
        "columns": columns,
        "stackBelow": stackBelow,
      };

  static GridRule fromJson(Map<String, Object?> json) => GridRule(
        gap: (json["gap"] as num?)?.toDouble() ?? 12,
        columns: (json["columns"] as num?)?.toInt() ?? 2,
        stackBelow: (json["stackBelow"] as num?)?.toDouble() ?? 180,
      );

  @override
  int get hashCode => Object.hash(gap, columns, stackBelow);

  @override
  bool operator ==(Object other) =>
      other is GridRule &&
      other.gap == gap &&
      other.columns == columns &&
      other.stackBelow == stackBelow;
}

/// HeaderRule is how a page's banner is drawn -- see HeaderBlockSyntax.
///
/// Only what is about the page rather than the writing: how tall a banner is
/// when the writer did not say, how far its contents sit from its edges, how
/// rounded it is, and how much the picture behind is muted so writing on top
/// stays readable.
class HeaderRule {
  /// height is the tallest a header is when the writer did not say.
  final double height;

  /// padding is the space between the banner's edge and what is in it.
  final double padding;
  final double radius;

  /// gap separates the rows inside a banner -- the bar from the title, the
  /// title from the description.
  final double gap;

  /// scrim is how much of the surface colour is laid over the picture, from
  /// 0 for none to 1 for opaque.
  ///
  /// A background chosen for how it looks is rarely chosen for how legible
  /// white text is on it, and the writer cannot know what colour the reader
  /// reads in. This is the reader's answer to that.
  final double scrim;

  const HeaderRule({
    this.height = 220,
    this.padding = 20,
    this.radius = 8,
    this.gap = 12,
    this.scrim = 0.35,
  });

  double get boundedHeight => height.clamp(40, 600);
  double get boundedPadding => padding.clamp(0, 64);
  double get boundedRadius => radius.clamp(0, 48);
  double get boundedGap => gap.clamp(0, 48);

  HeaderRule copyWith({
    double? height,
    double? padding,
    double? radius,
    double? gap,
    double? scrim,
  }) =>
      HeaderRule(
        height: height ?? this.height,
        padding: padding ?? this.padding,
        radius: radius ?? this.radius,
        gap: gap ?? this.gap,
        scrim: scrim ?? this.scrim,
      );

  Map<String, Object?> toJson() => {
        "height": height,
        "padding": padding,
        "radius": radius,
        "gap": gap,
        "scrim": scrim,
      };

  static HeaderRule fromJson(Map<String, Object?> json) => HeaderRule(
        height: (json["height"] as num?)?.toDouble() ?? 220,
        padding: (json["padding"] as num?)?.toDouble() ?? 20,
        radius: (json["radius"] as num?)?.toDouble() ?? 8,
        gap: (json["gap"] as num?)?.toDouble() ?? 12,
        scrim: (json["scrim"] as num?)?.toDouble() ?? 0.35,
      );

  @override
  int get hashCode => Object.hash(height, padding, radius, gap, scrim);

  @override
  bool operator ==(Object other) =>
      other is HeaderRule && other.toJson().toString() == toJson().toString();
}

/// NavRule is how a bar of links is drawn -- see NavBlockSyntax.
///
/// The look is the reader's, the shape is the writer's: --nav[pills]-- says
/// what kind of bar it is, and this says what that kind looks like here.
class NavRule {
  final double gap;

  /// padding is inside each link, which is what gives a pill or a box its
  /// size. Zero for a plain bar, where the links are just words.
  final double padding;
  final double radius;

  /// borderWidth is the line around a boxed link, or under an underlined
  /// one.
  final double borderWidth;
  final MarkdownInk ink;

  const NavRule({
    this.gap = 14,
    this.padding = 8,
    this.radius = 6,
    this.borderWidth = 1,
    this.ink = const MarkdownInk.of(MarkdownRole.link),
  });

  double get boundedGap => gap.clamp(0, 48);
  double get boundedPadding => padding.clamp(0, 32);
  double get boundedRadius => radius.clamp(0, 32);
  double get boundedBorder => borderWidth.clamp(0, 8);

  NavRule copyWith({
    double? gap,
    double? padding,
    double? radius,
    double? borderWidth,
    MarkdownInk? ink,
  }) =>
      NavRule(
        gap: gap ?? this.gap,
        padding: padding ?? this.padding,
        radius: radius ?? this.radius,
        borderWidth: borderWidth ?? this.borderWidth,
        ink: ink ?? this.ink,
      );

  Map<String, Object?> toJson() => {
        "gap": gap,
        "padding": padding,
        "radius": radius,
        "borderWidth": borderWidth,
        "ink": ink.toJson(),
      };

  static NavRule fromJson(Map<String, Object?> json) => NavRule(
        gap: (json["gap"] as num?)?.toDouble() ?? 14,
        padding: (json["padding"] as num?)?.toDouble() ?? 8,
        radius: (json["radius"] as num?)?.toDouble() ?? 6,
        borderWidth: (json["borderWidth"] as num?)?.toDouble() ?? 1,
        ink: json["ink"] is Map<String, Object?>
            ? MarkdownInk.fromJson(json["ink"] as Map<String, Object?>)
            : const MarkdownInk.of(MarkdownRole.link),
      );

  @override
  int get hashCode => Object.hash(gap, padding, radius, borderWidth, ink);

  @override
  bool operator ==(Object other) =>
      other is NavRule && other.toJson().toString() == toJson().toString();
}

/// CardRule is how a callout or a card is drawn.
///
/// A callout and a card are the same thing with a different amount filled in:
/// a title, some text, an icon and a button, any of which may be left out. So
/// there is one set of rules for both rather than two that would drift apart.
class CardRule {
  /// gap is the space between one card and the next in a grid of them.
  final double gap;

  final double padding;
  final SideValues? paddingSides;
  final MarkdownInk background;
  final double borderWidth;
  final MarkdownInk borderInk;
  final double radius;

  /// iconSize is the icon itself; iconBackground is the disc behind it, or
  /// inherit for no disc at all.
  final double iconSize;
  final MarkdownInk iconInk;
  final MarkdownInk iconBackground;

  final TextRule title;
  final TextRule text;

  /// button is which of the app's five button designs a card's button is
  /// drawn as -- see ButtonRole and the Buttons theme area.
  ///
  /// A choice rather than its own set of colours: a card sits in a post, in
  /// the same app as every other button, and a button that looked like
  /// nothing else in it would read as part of the writing rather than as
  /// something to press. Plain is the default because that is the button
  /// this was hardcoded to before it could be chosen.
  final ButtonRole button;

  const CardRule({
    this.gap = 16,
    this.padding = 16,
    this.paddingSides,
    this.background = const MarkdownInk.of(MarkdownRole.raised),
    this.borderWidth = 0,
    this.borderInk = const MarkdownInk.of(MarkdownRole.outline),
    this.radius = 12,
    this.iconSize = 28,
    this.iconInk = const MarkdownInk.of(MarkdownRole.accent),
    this.iconBackground = MarkdownInk.inherit,
    this.title = const TextRule(scale: 1.3, bold: true),
    this.text = const TextRule(ink: MarkdownInk.of(MarkdownRole.muted)),
    this.button = ButtonRole.plain,
  });

  double get boundedGap => gap.clamp(0, 64);
  double get boundedRadius => radius.clamp(0, 48);
  double get boundedBorder => borderWidth.clamp(0, 12);
  double get boundedIconSize => iconSize.clamp(12, 96);
  SideValues get paddings =>
      paddingSides ?? SideValues.all(padding.clamp(0, 64));

  CardRule copyWith({
    double? gap,
    double? padding,
    SideValues? paddingSides,
    bool clearPaddingSides = false,
    MarkdownInk? background,
    double? borderWidth,
    MarkdownInk? borderInk,
    double? radius,
    double? iconSize,
    MarkdownInk? iconInk,
    MarkdownInk? iconBackground,
    TextRule? title,
    TextRule? text,
    ButtonRole? button,
  }) =>
      CardRule(
        gap: gap ?? this.gap,
        padding: padding ?? this.padding,
        paddingSides:
            clearPaddingSides ? null : (paddingSides ?? this.paddingSides),
        background: background ?? this.background,
        borderWidth: borderWidth ?? this.borderWidth,
        borderInk: borderInk ?? this.borderInk,
        radius: radius ?? this.radius,
        iconSize: iconSize ?? this.iconSize,
        iconInk: iconInk ?? this.iconInk,
        iconBackground: iconBackground ?? this.iconBackground,
        title: title ?? this.title,
        text: text ?? this.text,
        button: button ?? this.button,
      );

  Map<String, Object?> toJson() => {
        "gap": gap,
        "padding": padding,
        if (paddingSides != null) "paddingSides": paddingSides!.toJson(),
        if (!background.isInherit) "background": background.toJson(),
        "borderWidth": borderWidth,
        if (!borderInk.isInherit) "borderInk": borderInk.toJson(),
        "radius": radius,
        "iconSize": iconSize,
        if (!iconInk.isInherit) "iconInk": iconInk.toJson(),
        if (!iconBackground.isInherit)
          "iconBackground": iconBackground.toJson(),
        "title": title.toJson(),
        "text": text.toJson(),
        if (button != ButtonRole.plain) "button": button.name,
      };

  static CardRule fromJson(Map<String, Object?> json) {
    TextRule rule(String key, TextRule fallback) {
      var v = json[key];
      return v is Map<String, Object?> ? TextRule.fromJson(v) : fallback;
    }

    return CardRule(
      gap: _asDouble(json["gap"]) ?? 16,
      padding: _asDouble(json["padding"]) ?? 16,
      paddingSides: SideValues.fromJson(json["paddingSides"]),
      background: json.containsKey("background")
          ? MarkdownInk.fromJson(json["background"])
          : const MarkdownInk.of(MarkdownRole.raised),
      borderWidth: _asDouble(json["borderWidth"]) ?? 0,
      borderInk: json.containsKey("borderInk")
          ? MarkdownInk.fromJson(json["borderInk"])
          : const MarkdownInk.of(MarkdownRole.outline),
      radius: _asDouble(json["radius"]) ?? 12,
      iconSize: _asDouble(json["iconSize"]) ?? 28,
      iconInk: json.containsKey("iconInk")
          ? MarkdownInk.fromJson(json["iconInk"])
          : const MarkdownInk.of(MarkdownRole.accent),
      iconBackground: MarkdownInk.fromJson(json["iconBackground"]),
      title: rule("title", const TextRule(scale: 1.3, bold: true)),
      text:
          rule("text", const TextRule(ink: MarkdownInk.of(MarkdownRole.muted))),
      button: ButtonRole.values.firstWhere((r) => r.name == json["button"],
          orElse: () => ButtonRole.plain),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CardRule && other.toJson().toString() == toJson().toString();

  @override
  int get hashCode => toJson().toString().hashCode;
}

/// MarkdownStyleGuide is one named set of rules.
///
/// Every field has a default that is "leave the theme alone", so the guide
/// that changes nothing is the empty one -- which is what "Default" is.
class MarkdownStyleGuide {
  /// id is what a post refers to and what a guide is stored under.
  ///
  /// Separate from [name] so a guide can be renamed without every post that
  /// mentions it losing its styling. Built-ins use a fixed id; a guide the
  /// user makes gets a generated one.
  final String id;
  final String name;

  /// builtIn guides ship with the app, cannot be edited or deleted, and are
  /// the ones a post can rely on: every device has them, so a post that
  /// names one looks the same wherever it is read. A guide somebody made
  /// themselves travels no further than their own machine.
  final bool builtIn;

  final TextRule body;
  final List<TextRule> headings; // Six, h1 first.
  final TextRule link;
  final TextRule strong;
  final TextRule emphasis;
  final TextRule quote;
  final TextRule code;
  final TextRule listBullet;
  final TextRule tableHead;
  final TextRule tableBody;

  /// blockGap is the space between paragraphs, and after headings, quotes
  /// and lists. After the line height, the thing that most decides whether
  /// a post reads as an article or as a chat message.
  final double blockGap;

  /// listItemGap is the space between items in a list.
  ///
  /// Separate from [blockGap] because flutter_markdown spaces list items
  /// with the same figure it uses between paragraphs, and the two want
  /// different numbers: prose reads better with a clear gap between
  /// paragraphs, and a list with that same gap between every bullet falls
  /// apart into unrelated lines. Reported on Article, where the paragraph
  /// spacing that made the prose read well made the lists too airy.
  final double listItemGap;
  final double listIndent;

  /// listCheckedMark and listUncheckedMark are what a task list's boxes get
  /// -- `- [x]` and `- [ ]` respectively.
  final MarkdownCheckMark listCheckedMark;
  final MarkdownCheckMark listUncheckedMark;

  /// listCheckSize is how large the box is drawn, and listCheckInk what it
  /// and the mark in it are drawn in.
  final double listCheckSize;
  final MarkdownInk listCheckInk;
  final MarkdownInk quoteBarInk;
  final double quoteBarWidth;
  final MarkdownInk quoteBackground;

  /// quotePadding is the space between a quotation's bar and its text, and
  /// around the rest of it. The bar and the words sat hard against each
  /// other without it.
  final double quotePadding;
  final MarkdownInk codeBackground;

  /// codePadding is the space between a fenced block's edge and the code in
  /// it. Null leaves the built-in 8.
  final double? codePadding;

  /// codeLineNumbers draws a numbered gutter down the left of a fenced
  /// block. Off by default: most posts are not about a particular line.
  final bool codeLineNumbers;

  /// codeHighlight colours strings, numbers, comments and keywords in a
  /// fenced block.
  ///
  /// Off by default, and deliberately language-agnostic when on -- a fenced
  /// block arrives here as text, with whatever language was written after
  /// the backticks left behind by the parser, so there is nothing to select
  /// a grammar with. See markdownHighlight.
  final bool codeHighlight;
  final MarkdownInk ruleInk;
  final double ruleThickness;
  final MarkdownInk tableBorderInk;
  final double tableBorderWidth;

  /// tableHeadBackground is what the header row is drawn on, and
  /// tableStripeInk what every other body row is drawn on -- the two things
  /// that make a table readable across rather than only down.
  final MarkdownInk tableHeadBackground;
  final MarkdownInk tableStripeInk;

  /// tableCellPadding is the space between a cell's edge and what is in it.
  final double tableCellPadding;

  /// tableFit is how the width is divided between the columns.
  final MarkdownTableFit tableFit;
  final MarkdownAlign bodyAlign;
  final ImageRule image;

  /// columns is how a run of columns is laid out -- see ColumnRule.
  final ColumnRule columns;

  /// cards is how a callout or a card is drawn -- see CardRule.
  final CardRule cards;

  /// grid is how a gallery is laid out -- see GridRule.
  final GridRule grid;

  /// header is how a page's banner is drawn -- see HeaderRule.
  final HeaderRule header;

  /// nav is how a bar of links is drawn -- see NavRule.
  final NavRule nav;

  /// copyWith returns this guide with some rules changed.
  ///
  /// Editing a built-in is not possible, and this is where that is made
  /// true: any change to one produces a guide of the reader's own, with a
  /// fresh id and a name saying what it came from. The built-ins are what a
  /// published post can rely on, so they have to be the same everywhere --
  /// a "Article" that had been quietly edited on one machine would make a
  /// post naming it mean something different there.
  MarkdownStyleGuide copyWith({
    String? id,
    String? name,
    TextRule? body,
    List<TextRule>? headings,
    TextRule? link,
    TextRule? strong,
    TextRule? emphasis,
    TextRule? quote,
    TextRule? code,
    TextRule? listBullet,
    TextRule? tableHead,
    TextRule? tableBody,
    double? blockGap,
    double? listItemGap,
    double? listIndent,
    MarkdownCheckMark? listCheckedMark,
    MarkdownCheckMark? listUncheckedMark,
    double? listCheckSize,
    MarkdownInk? listCheckInk,
    MarkdownInk? quoteBarInk,
    double? quoteBarWidth,
    MarkdownInk? quoteBackground,
    double? quotePadding,
    MarkdownInk? codeBackground,
    double? codePadding,
    bool? codeLineNumbers,
    bool? codeHighlight,
    MarkdownInk? ruleInk,
    double? ruleThickness,
    MarkdownInk? tableBorderInk,
    double? tableBorderWidth,
    MarkdownInk? tableHeadBackground,
    MarkdownInk? tableStripeInk,
    double? tableCellPadding,
    MarkdownTableFit? tableFit,
    MarkdownAlign? bodyAlign,
    ImageRule? image,
    ColumnRule? columns,
    CardRule? cards,
    GridRule? grid,
    HeaderRule? header,
    NavRule? nav,
  }) =>
      MarkdownStyleGuide(
        id: id ?? this.id,
        name: name ?? this.name,
        builtIn: id == null && name == null ? builtIn : false,
        body: body ?? this.body,
        headings: headings ?? this.headings,
        link: link ?? this.link,
        strong: strong ?? this.strong,
        emphasis: emphasis ?? this.emphasis,
        quote: quote ?? this.quote,
        code: code ?? this.code,
        listBullet: listBullet ?? this.listBullet,
        tableHead: tableHead ?? this.tableHead,
        tableBody: tableBody ?? this.tableBody,
        blockGap: blockGap ?? this.blockGap,
        listItemGap: listItemGap ?? this.listItemGap,
        listIndent: listIndent ?? this.listIndent,
        listCheckedMark: listCheckedMark ?? this.listCheckedMark,
        listUncheckedMark: listUncheckedMark ?? this.listUncheckedMark,
        listCheckSize: listCheckSize ?? this.listCheckSize,
        listCheckInk: listCheckInk ?? this.listCheckInk,
        quoteBarInk: quoteBarInk ?? this.quoteBarInk,
        quoteBarWidth: quoteBarWidth ?? this.quoteBarWidth,
        quoteBackground: quoteBackground ?? this.quoteBackground,
        quotePadding: quotePadding ?? this.quotePadding,
        codeBackground: codeBackground ?? this.codeBackground,
        codePadding: codePadding ?? this.codePadding,
        codeLineNumbers: codeLineNumbers ?? this.codeLineNumbers,
        codeHighlight: codeHighlight ?? this.codeHighlight,
        ruleInk: ruleInk ?? this.ruleInk,
        ruleThickness: ruleThickness ?? this.ruleThickness,
        tableBorderInk: tableBorderInk ?? this.tableBorderInk,
        tableBorderWidth: tableBorderWidth ?? this.tableBorderWidth,
        tableHeadBackground: tableHeadBackground ?? this.tableHeadBackground,
        tableStripeInk: tableStripeInk ?? this.tableStripeInk,
        tableCellPadding: tableCellPadding ?? this.tableCellPadding,
        tableFit: tableFit ?? this.tableFit,
        bodyAlign: bodyAlign ?? this.bodyAlign,
        image: image ?? this.image,
        columns: columns ?? this.columns,
        cards: cards ?? this.cards,
        grid: grid ?? this.grid,
        header: header ?? this.header,
        nav: nav ?? this.nav,
      );

  /// forked is this guide as the beginning of one of the reader's own.
  ///
  /// Called the moment a built-in is edited, so the built-in itself is never
  /// changed and the edit is not lost either.
  MarkdownStyleGuide forked(String newId) =>
      copyWith(id: newId, name: "$name (edited)");

  Map<String, Object?> toJson() => {
        "id": id,
        "name": name,
        "body": body.toJson(),
        "headings": [for (var h in headings) h.toJson()],
        "link": link.toJson(),
        "strong": strong.toJson(),
        "emphasis": emphasis.toJson(),
        "quote": quote.toJson(),
        "code": code.toJson(),
        "listBullet": listBullet.toJson(),
        "tableHead": tableHead.toJson(),
        "tableBody": tableBody.toJson(),
        "blockGap": blockGap,
        "listItemGap": listItemGap,
        "listIndent": listIndent,
        "listCheckedMark": listCheckedMark.name,
        "listUncheckedMark": listUncheckedMark.name,
        "listCheckSize": listCheckSize,
        "listCheckInk": listCheckInk.toJson(),
        if (!quoteBarInk.isInherit) "quoteBarInk": quoteBarInk.toJson(),
        "quoteBarWidth": quoteBarWidth,
        if (!quoteBackground.isInherit)
          "quoteBackground": quoteBackground.toJson(),
        "quotePadding": quotePadding,
        if (!codeBackground.isInherit)
          "codeBackground": codeBackground.toJson(),
        if (codePadding != null) "codePadding": codePadding,
        if (codeLineNumbers) "codeLineNumbers": codeLineNumbers,
        if (codeHighlight) "codeHighlight": codeHighlight,
        if (!ruleInk.isInherit) "ruleInk": ruleInk.toJson(),
        "ruleThickness": ruleThickness,
        if (!tableBorderInk.isInherit)
          "tableBorderInk": tableBorderInk.toJson(),
        "tableBorderWidth": tableBorderWidth,
        if (!tableHeadBackground.isInherit)
          "tableHeadBackground": tableHeadBackground.toJson(),
        if (!tableStripeInk.isInherit)
          "tableStripeInk": tableStripeInk.toJson(),
        "tableCellPadding": tableCellPadding,
        "tableFit": tableFit.name,
        "bodyAlign": bodyAlign.name,
        "image": image.toJson(),
        "columns": columns.toJson(),
        "cards": cards.toJson(),
        "grid": grid.toJson(),
        "header": header.toJson(),
        "nav": nav.toJson(),
      };

  static MarkdownStyleGuide fromJson(Map<String, Object?> json) {
    TextRule rule(String key) {
      var v = json[key];
      return v is Map<String, Object?>
          ? TextRule.fromJson(v)
          : const TextRule();
    }

    var heads = json["headings"];
    return MarkdownStyleGuide(
      id: json["id"] as String? ?? "",
      name: json["name"] as String? ?? "Untitled",
      body: rule("body"),
      headings: heads is List && heads.length == 6
          ? [
              for (var h in heads)
                h is Map<String, Object?>
                    ? TextRule.fromJson(h)
                    : const TextRule()
            ]
          : const [
              TextRule(),
              TextRule(),
              TextRule(),
              TextRule(),
              TextRule(),
              TextRule(),
            ],
      link: rule("link"),
      strong: rule("strong"),
      emphasis: rule("emphasis"),
      quote: rule("quote"),
      code: rule("code"),
      listBullet: rule("listBullet"),
      tableHead: rule("tableHead"),
      tableBody: rule("tableBody"),
      blockGap: _asDouble(json["blockGap"]) ?? 8,
      listItemGap: _asDouble(json["listItemGap"]) ?? 8,
      listIndent: _asDouble(json["listIndent"]) ?? 24,
      // A guide written before these existed, or by an app that does not
      // have them, means the tick-and-empty-box pair every task list has
      // always been drawn with.
      listCheckedMark: MarkdownCheckMark.values.firstWhere(
          (m) => m.name == json["listCheckedMark"],
          orElse: () => MarkdownCheckMark.tick),
      listUncheckedMark: MarkdownCheckMark.values.firstWhere(
          (m) => m.name == json["listUncheckedMark"],
          orElse: () => MarkdownCheckMark.empty),
      listCheckSize: _asDouble(json["listCheckSize"]) ?? 16,
      listCheckInk: MarkdownInk.fromJson(json["listCheckInk"]),
      quoteBarInk: MarkdownInk.fromJson(json["quoteBarInk"]),
      quoteBarWidth: _asDouble(json["quoteBarWidth"]) ?? 2,
      quoteBackground: MarkdownInk.fromJson(json["quoteBackground"]),
      quotePadding: _asDouble(json["quotePadding"]) ?? 8,
      codeBackground: MarkdownInk.fromJson(json["codeBackground"]),
      codePadding: _asDouble(json["codePadding"]),
      codeLineNumbers: json["codeLineNumbers"] == true,
      codeHighlight: json["codeHighlight"] == true,
      ruleInk: MarkdownInk.fromJson(json["ruleInk"]),
      ruleThickness: _asDouble(json["ruleThickness"]) ?? 1,
      tableBorderInk: MarkdownInk.fromJson(json["tableBorderInk"]),
      tableBorderWidth: _asDouble(json["tableBorderWidth"]) ?? 1,
      tableHeadBackground: MarkdownInk.fromJson(json["tableHeadBackground"]),
      tableStripeInk: MarkdownInk.fromJson(json["tableStripeInk"]),
      tableCellPadding: _asDouble(json["tableCellPadding"]) ?? 8,
      tableFit: MarkdownTableFit.values.firstWhere(
          (f) => f.name == json["tableFit"],
          orElse: () => MarkdownTableFit.equal),
      bodyAlign: MarkdownAlign.values.firstWhere(
          (a) => a.name == json["bodyAlign"],
          orElse: () => MarkdownAlign.inherit),
      image: json["image"] is Map<String, Object?>
          ? ImageRule.fromJson(json["image"] as Map<String, Object?>)
          : const ImageRule(),
      columns: json["columns"] is Map<String, Object?>
          ? ColumnRule.fromJson(json["columns"] as Map<String, Object?>)
          : const ColumnRule(),
      header: json["header"] is Map<String, Object?>
          ? HeaderRule.fromJson(json["header"] as Map<String, Object?>)
          : const HeaderRule(),
      nav: json["nav"] is Map<String, Object?>
          ? NavRule.fromJson(json["nav"] as Map<String, Object?>)
          : const NavRule(),
      grid: json["grid"] is Map<String, Object?>
          ? GridRule.fromJson(json["grid"] as Map<String, Object?>)
          : const GridRule(),
      cards: json["cards"] is Map<String, Object?>
          ? CardRule.fromJson(json["cards"] as Map<String, Object?>)
          : const CardRule(),
    );
  }

  const MarkdownStyleGuide({
    required this.id,
    required this.name,
    this.builtIn = false,
    this.body = const TextRule(),
    this.headings = const [
      TextRule(),
      TextRule(),
      TextRule(),
      TextRule(),
      TextRule(),
      TextRule(),
    ],
    this.link = const TextRule(),
    this.strong = const TextRule(),
    this.emphasis = const TextRule(),
    this.quote = const TextRule(),
    this.code = const TextRule(),
    this.listBullet = const TextRule(),
    this.tableHead = const TextRule(),
    this.tableBody = const TextRule(),
    this.blockGap = 8,
    this.listItemGap = 8,
    this.listIndent = 24,
    this.listCheckedMark = MarkdownCheckMark.tick,
    this.listUncheckedMark = MarkdownCheckMark.empty,
    this.listCheckSize = 16,
    this.listCheckInk = MarkdownInk.inherit,
    this.quoteBarInk = MarkdownInk.inherit,
    this.quoteBarWidth = 2,
    this.quoteBackground = MarkdownInk.inherit,
    this.quotePadding = 8,
    this.codeBackground = MarkdownInk.inherit,
    this.codePadding,
    this.codeLineNumbers = false,
    this.codeHighlight = false,
    this.ruleInk = const MarkdownInk.of(MarkdownRole.outline),
    this.ruleThickness = 1,
    this.tableBorderInk = const MarkdownInk.of(MarkdownRole.outline),
    this.tableBorderWidth = 1,
    this.tableHeadBackground = MarkdownInk.inherit,
    this.tableStripeInk = MarkdownInk.inherit,
    this.tableCellPadding = 8,
    this.tableFit = MarkdownTableFit.equal,
    this.bodyAlign = MarkdownAlign.inherit,
    this.image = const ImageRule(),
    this.columns = const ColumnRule(),
    this.cards = const CardRule(),
    this.grid = const GridRule(),
    this.header = const HeaderRule(),
    this.nav = const NavRule(),
  });
}
