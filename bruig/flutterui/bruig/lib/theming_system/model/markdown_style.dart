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

  const MarkdownInk.of(this.role) : literal = null;
  const MarkdownInk.literal(Color this.literal) : role = null;

  static const inherit = MarkdownInk.of(null);
  bool get isInherit => role == null && literal == null;

  Color? resolve(Color Function(MarkdownRole) roleColor) {
    if (literal != null) return literal;
    if (role != null) return roleColor(role!);
    return null;
  }

  String? toJson() => literal != null ? colorToHex(literal!) : role?.name;

  static MarkdownInk fromJson(Object? json) {
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
/// Bundled only. A guide naming a font the device does not have would render
/// differently everywhere it went, which is the whole thing this feature is
/// for avoiding.
enum MarkdownFont {
  inherit("Theme default", null),
  sans("Sans", "Inter"),
  mono("Monospace", "SourceCodePro"),
  serif("Serif", "serif");

  final String label;
  final String? family;
  const MarkdownFont(this.label, this.family);
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
  TextStyle applyTo(TextStyle base, Color Function(MarkdownRole) roleColor) {
    return base.copyWith(
      fontSize: (base.fontSize ?? 14) * scale.clamp(_minScale, _maxScale),
      color: ink.resolve(roleColor) ?? base.color,
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
  final MarkdownInk quoteBarInk;
  final double quoteBarWidth;
  final MarkdownInk quoteBackground;
  final MarkdownInk codeBackground;
  final MarkdownInk ruleInk;
  final double ruleThickness;
  final MarkdownInk tableBorderInk;
  final double tableBorderWidth;
  final MarkdownAlign bodyAlign;
  final ImageRule image;

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
    this.quoteBarInk = MarkdownInk.inherit,
    this.quoteBarWidth = 2,
    this.quoteBackground = MarkdownInk.inherit,
    this.codeBackground = MarkdownInk.inherit,
    this.ruleInk = const MarkdownInk.of(MarkdownRole.outline),
    this.ruleThickness = 1,
    this.tableBorderInk = const MarkdownInk.of(MarkdownRole.outline),
    this.tableBorderWidth = 1,
    this.bodyAlign = MarkdownAlign.inherit,
    this.image = const ImageRule(),
  });
}
