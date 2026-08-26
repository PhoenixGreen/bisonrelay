import 'package:bruig/theming_system/model/button_style.dart';
import 'package:bruig/theming_system/model/area_sides.dart';
import 'package:bruig/theming_system/model/color_hex.dart';
import 'package:flutter/material.dart';

// The rules themselves live next door, and are re-exported so that
// importing the guide still brings everything a guide is made of.
export 'package:bruig/theming_system/model/markdown_rules.dart';

import 'package:bruig/theming_system/model/markdown_rules.dart';

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
  payment("payment", Icons.payments_outlined),
  // A shop's own four. Here rather than in a list of the store's, because
  // this is the closed list a page may name an icon from, and a shop's
  // pages are pages.
  shop("shop", Icons.storefront_outlined),
  cart("cart", Icons.shopping_cart_outlined),
  orders("orders", Icons.receipt_long_outlined),
  admin("admin", Icons.tune);

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
      blockGap: asDouble(json["blockGap"]) ?? 8,
      listItemGap: asDouble(json["listItemGap"]) ?? 8,
      listIndent: asDouble(json["listIndent"]) ?? 24,
      // A guide written before these existed, or by an app that does not
      // have them, means the tick-and-empty-box pair every task list has
      // always been drawn with.
      listCheckedMark: MarkdownCheckMark.values.firstWhere(
          (m) => m.name == json["listCheckedMark"],
          orElse: () => MarkdownCheckMark.tick),
      listUncheckedMark: MarkdownCheckMark.values.firstWhere(
          (m) => m.name == json["listUncheckedMark"],
          orElse: () => MarkdownCheckMark.empty),
      listCheckSize: asDouble(json["listCheckSize"]) ?? 16,
      listCheckInk: MarkdownInk.fromJson(json["listCheckInk"]),
      quoteBarInk: MarkdownInk.fromJson(json["quoteBarInk"]),
      quoteBarWidth: asDouble(json["quoteBarWidth"]) ?? 2,
      quoteBackground: MarkdownInk.fromJson(json["quoteBackground"]),
      quotePadding: asDouble(json["quotePadding"]) ?? 8,
      codeBackground: MarkdownInk.fromJson(json["codeBackground"]),
      codePadding: asDouble(json["codePadding"]),
      codeLineNumbers: json["codeLineNumbers"] == true,
      codeHighlight: json["codeHighlight"] == true,
      ruleInk: MarkdownInk.fromJson(json["ruleInk"]),
      ruleThickness: asDouble(json["ruleThickness"]) ?? 1,
      tableBorderInk: MarkdownInk.fromJson(json["tableBorderInk"]),
      tableBorderWidth: asDouble(json["tableBorderWidth"]) ?? 1,
      tableHeadBackground: MarkdownInk.fromJson(json["tableHeadBackground"]),
      tableStripeInk: MarkdownInk.fromJson(json["tableStripeInk"]),
      tableCellPadding: asDouble(json["tableCellPadding"]) ?? 8,
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
