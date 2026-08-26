import 'package:bruig/components/feed/markdown_page.dart';
import 'package:bruig/components/feed/page_image.dart';
import 'package:bruig/components/md_elements.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:bruig/theming_system/model/markdown_style.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

// markdown_panel.dart is a box drawn round a piece of a page:
//
//   --panel[padding=16, border=1, color=outline, radius=8]--
//   Anything at all, including other blocks.
//   --/panel--
//
// Not called --section--, which is taken. A page's reply regions are written
// --section id=reply -- ... --/section--, and are handled by replacing that
// text rather than by rendering it -- in this client and in brclient both.
// The strip is unconditional: every --/section-- in a page is removed before
// it is drawn. A box sharing that closing line would have it taken away from
// underneath, and the failure would look like the box simply not working.
//
// Settings are written in the brackets, the way --grid[3]-- and
// --nav[pills]-- already are, so that everything between the two lines is
// content and there is no question about where the settings stop.
//
// A panel also draws a picture behind itself, at a shape it is told, cropped
// from a corner it is told, and follows a link when it is tapped:
//
//   --panel[image=shopassets/guitar.jpg, ratio=400x400, crop=top,
//           link=product/gtr, align=bottom, fill=raised]--
//
// That is one card of a shop front -- a picture at the same shape as every
// other card's, the writing over it or under it, and the whole of it a link
// to the thing it is selling. Written here rather than as a block of its own
// called --product--, because none of it is about selling: it is a box with a
// picture behind it, which is what a page's banner, a link card and a
// gallery tile are as well.

/// maxBorderWidth is as thick as a line may be drawn.
const double maxBorderWidth = 24;

/// maxPanelRadius is as round as a corner may be.
const double maxPanelRadius = 200;

/// PanelStroke is how a border is drawn.
///
/// Dashed and dotted are drawn rather than described: Flutter's own Border
/// paints solid lines only, so those two are laid out by _PanelBorderPainter.
enum PanelStroke {
  solid("Solid"),
  dashed("Dashed"),
  dotted("Dotted"),
  none("None");

  final String label;
  const PanelStroke(this.label);

  static PanelStroke parse(String? value) {
    for (var s in PanelStroke.values) {
      if (s.name == value?.trim().toLowerCase()) return s;
    }
    return PanelStroke.solid;
  }
}

/// PanelJustify is how wide a panel's content is drawn.
enum PanelJustify {
  /// stretch is the full width of the panel, which is what a block of a
  /// page has always been.
  stretch,
  left,
  center,
  right,
}

/// PanelRule is what one panel asked for.
@immutable
class PanelRule {
  final EdgeInsets? padding;
  final EdgeInsets? margin;

  /// border is the line's thickness, per side, or null for no line.
  ///
  /// Per side because a rule across the top of a block and a card outlined
  /// all round are the same thing asked for differently, and having to write
  /// two blocks to get one line is the sort of thing that ends in a table
  /// being used as a border.
  final EdgeInsets? border;

  final PanelStroke stroke;

  /// color is the line's colour: a named role, or a colour written out.
  ///
  /// A role is the better answer and is what the settings offer first, for
  /// the reason the page background names one: a panel cannot know whether
  /// its reader is in a dark theme, so a line it names #000000 is a line
  /// nobody in one can see. But a shop putting its own border round its own
  /// cards has a particular colour in mind, and refusing to carry it only
  /// meant the border could not be used.
  final MarkdownInk? color;

  /// radius is how round the corners are, per corner.
  ///
  /// Per corner because a picture at the top of a card is rounded at the top
  /// and square at the bottom, where the writing meets it -- one number for
  /// all four makes that impossible to draw, and a card built out of two
  /// boxes to get it is a card with a seam down the middle.
  final BorderRadius? radius;

  /// fill is what the panel is filled with behind its content.
  ///
  /// A named colour or a written one, unlike [color]: a fill is what a
  /// seller's own shop front is coloured with, and a shop with a brand
  /// colour has one particular colour rather than one of eight roles. A role
  /// is still the better answer where there is one, because it follows the
  /// reader's theme -- see MarkdownInk.
  final MarkdownInk? fill;

  /// image is a picture of the site's own drawn behind the panel, written as
  /// the path a Markdown image would be: shopassets/guitar.jpg.
  final String? image;

  /// ratio is the shape the panel is drawn at -- width over height -- or
  /// null to be as tall as what is in it.
  ///
  /// What makes a row of cards line up. Without it a shop front of
  /// photographs at six different shapes is a ragged page, and there is
  /// nothing a seller can do about it short of re-cropping every photograph
  /// they own.
  final double? ratio;

  /// crop is which part of [image] survives being fitted to [ratio].
  ///
  /// A picture cropped to a shape loses something, and which part it loses
  /// is the difference between a photograph of a person and a photograph of
  /// their shoulders.
  final Alignment crop;

  /// align is where the panel's content sits in it, top to bottom, or null
  /// for wherever it falls.
  ///
  /// Read only by a panel that has a height of its own to place anything in
  /// -- one with a [ratio], or one sized by the picture behind it.
  final Alignment? align;

  /// link is what the whole panel opens when it is tapped, or null for one
  /// that is not a link.
  final String? link;

  /// justify is how wide the panel's content is: the full width of the
  /// panel, or only as wide as itself and sitting to one side.
  ///
  /// Read together with [align], which is the same question the other way
  /// up. A plate on a card is the reason both exist: it either runs the
  /// width of the picture or hugs the writing, and the second is only a
  /// choice once it can also be told which side to hug.
  final PanelJustify justify;

  /// text is which side the writing inside the panel sits on, or null for
  /// wherever the reader's guide puts it.
  final WrapAlignment? text;

  const PanelRule({
    this.padding,
    this.margin,
    this.border,
    this.stroke = PanelStroke.solid,
    this.color,
    this.radius,
    this.fill,
    this.image,
    this.ratio,
    this.crop = Alignment.center,
    this.align,
    this.link,
    this.justify = PanelJustify.stretch,
    this.text,
  });

  static const none = PanelRule();

  /// parse reads the settings out of what was written in the brackets.
  ///
  /// A setting it does not know is ignored rather than guessed at, and one
  /// whose value will not read leaves that setting unset rather than the
  /// whole panel. A panel with a typo in its radius is still a panel.
  static PanelRule parse(String? attributes) {
    if (attributes == null || attributes.trim().isEmpty) return none;

    var fields = <String, String>{};
    for (var part in attributes.split(",")) {
      var at = part.indexOf("=");
      if (at == -1) continue;
      var key = part.substring(0, at).trim().toLowerCase();
      fields.putIfAbsent(key, () => part.substring(at + 1).trim());
    }
    if (fields.isEmpty) return none;

    var fill = MarkdownInk.fromJson(fields["fill"]);
    return PanelRule(
      padding: PageSetup.parseSpace(fields["padding"]),
      margin: PageSetup.parseSpace(fields["margin"]),
      border: _border(fields["border"]),
      stroke: PanelStroke.parse(fields["style"]),
      color: _ink(fields["color"]),
      radius: _radius(fields["radius"]),
      fill: fill.isInherit ? null : fill,
      image: _image(fields["image"]),
      ratio: _ratio(fields["ratio"]),
      crop: _crop(fields["crop"]),
      align: _align(fields["align"]),
      link: _link(fields["link"]),
      justify: _justify(fields["justify"]),
      text: _text(fields["text"]),
    );
  }

  /// _radius reads the corners, written the way room around something is:
  /// one number for all four, or four for each corner from the top left
  /// round to the bottom left -- the order CSS writes them in.
  static BorderRadius? _radius(String? value) {
    if (value == null) return null;
    var parts = value
        .trim()
        .split(RegExp(r'[\s,]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    var got = [
      for (var p in parts)
        PageSetup.parseLength(p, maxPanelRadius, allowZero: true)
    ];
    if (got.isEmpty || got.any((v) => v == null)) return null;
    var n = got.cast<double>();
    Radius r(double v) => Radius.circular(v);
    return switch (n.length) {
      1 => BorderRadius.all(r(n[0])),
      2 => BorderRadius.only(
          topLeft: r(n[0]),
          topRight: r(n[1]),
          bottomRight: r(n[0]),
          bottomLeft: r(n[1])),
      3 => BorderRadius.only(
          topLeft: r(n[0]),
          topRight: r(n[1]),
          bottomRight: r(n[2]),
          bottomLeft: r(n[1])),
      _ => BorderRadius.only(
          topLeft: r(n[0]),
          topRight: r(n[1]),
          bottomRight: r(n[2]),
          bottomLeft: r(n[3])),
    };
  }

  static PanelJustify _justify(String? value) =>
      switch (value?.trim().toLowerCase()) {
        "left" || "start" => PanelJustify.left,
        "center" || "centre" || "middle" => PanelJustify.center,
        "right" || "end" => PanelJustify.right,
        _ => PanelJustify.stretch,
      };

  static WrapAlignment? _text(String? value) =>
      switch (value?.trim().toLowerCase()) {
        "left" || "start" => WrapAlignment.start,
        "center" || "centre" || "middle" => WrapAlignment.center,
        "right" || "end" => WrapAlignment.end,
        _ => null,
      };

  /// _image is the picture behind a panel, or null for anything that is not
  /// one of this site's own files.
  ///
  /// A path with no scheme and nothing else. What is drawn behind a panel is
  /// fetched from whoever served the page, exactly as a Markdown image on it
  /// is, and a background that could name a URL would be every page able to
  /// ask its reader's client to fetch from anywhere.
  static String? _image(String? value) {
    var path = value?.trim() ?? "";
    return path.isNotEmpty && isPageAssetPath(path) ? path : null;
  }

  /// _ratio reads a shape, written either as two lengths -- 400x400, 600x400
  /// -- or as the number one divided by the other.
  ///
  /// Two lengths because that is how a seller thinks about it: a picture is
  /// 600 wide and 400 tall. Nothing is drawn at that size -- a card is as
  /// wide as its share of the row -- so it is the shape that is kept.
  static double? _ratio(String? value) {
    var text = value?.trim().toLowerCase() ?? "";
    if (text.isEmpty) return null;

    var at = text.indexOf("x");
    if (at != -1) {
      var w = double.tryParse(text.substring(0, at).trim());
      var h = double.tryParse(text.substring(at + 1).trim());
      if (w == null || h == null || w <= 0 || h <= 0) return null;
      return _boundedRatio(w / h);
    }
    var direct = double.tryParse(text);
    return direct == null || direct <= 0 ? null : _boundedRatio(direct);
  }

  /// _boundedRatio keeps a shape to one a card can be drawn at.
  ///
  /// A panel a hundred times wider than it is tall is a hairline, and one a
  /// hundred times taller is a column the length of the page -- both from a
  /// number somebody typed into a settings field. Clamped rather than
  /// refused, so an extreme shape is drawn as far as it goes.
  static double _boundedRatio(double ratio) => ratio.clamp(1 / 8, 8);

  static Alignment _crop(String? value) =>
      switch (value?.trim().toLowerCase()) {
        "topleft" || "lefttop" => Alignment.topLeft,
        "top" || "topcenter" || "topcentre" => Alignment.topCenter,
        "topright" || "righttop" => Alignment.topRight,
        "left" => Alignment.centerLeft,
        "right" => Alignment.centerRight,
        "bottomleft" => Alignment.bottomLeft,
        "bottom" || "bottomcenter" || "bottomcentre" => Alignment.bottomCenter,
        "bottomright" => Alignment.bottomRight,
        _ => Alignment.center,
      };

  static Alignment? _align(String? value) =>
      switch (value?.trim().toLowerCase()) {
        "top" => Alignment.topCenter,
        "center" || "centre" || "middle" => Alignment.center,
        "bottom" => Alignment.bottomCenter,
        _ => null,
      };

  static String? _link(String? value) {
    var link = value?.trim() ?? "";
    return link.isEmpty ? null : link;
  }

  /// _border reads a line's thickness the same way room around something is
  /// read: one number for all four sides, two, three or four for each.
  ///
  /// The same shape as padding on purpose. Two ways of writing the same
  /// thing in one block is two things to remember.
  static EdgeInsets? _border(String? value) {
    if (value == null) return null;
    var parts = value
        .trim()
        .split(RegExp(r'[\s,]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    var got = [
      for (var p in parts)
        PageSetup.parseLength(p, maxBorderWidth, allowZero: true)
    ];
    if (got.isEmpty || got.any((v) => v == null)) return null;
    var n = got.cast<double>();
    return switch (n.length) {
      1 => EdgeInsets.all(n[0]),
      2 => EdgeInsets.symmetric(vertical: n[0], horizontal: n[1]),
      3 => EdgeInsets.fromLTRB(n[1], n[0], n[1], n[2]),
      _ => EdgeInsets.fromLTRB(n[3], n[0], n[1], n[2]),
    };
  }

  /// _ink reads a colour written as a role's name or as #rrggbb.
  ///
  /// The name is matched without regard to case, which is what the roles
  /// were matched by before they could also be colours. Half of them are
  /// spelled with a capital in the middle -- quoteBar is one -- so lowering
  /// the written value before looking it up silently lost those, and a
  /// border colour that had always worked stopped being read.
  static MarkdownInk? _ink(String? value) {
    var written = value?.trim() ?? "";
    if (written.isEmpty) return null;

    for (var role in MarkdownRole.values) {
      if (role.name.toLowerCase() == written.toLowerCase()) {
        return MarkdownInk.of(role);
      }
    }

    var ink = MarkdownInk.fromJson(written);
    return ink.isInherit ? null : ink;
  }

  bool get saysAnything =>
      padding != null ||
      margin != null ||
      border != null ||
      color != null ||
      radius != null ||
      fill != null ||
      image != null ||
      ratio != null ||
      align != null ||
      link != null;

  @override
  bool operator ==(Object other) =>
      other is PanelRule &&
      other.padding == padding &&
      other.margin == margin &&
      other.border == border &&
      other.stroke == stroke &&
      other.color == color &&
      other.radius == radius &&
      other.fill == fill &&
      other.image == image &&
      other.ratio == ratio &&
      other.crop == crop &&
      other.align == align &&
      other.link == link &&
      other.justify == justify &&
      other.text == text;

  @override
  int get hashCode => Object.hash(padding, margin, border, stroke, color,
      radius, fill, image, ratio, crop, align, link, justify, text);
}

class PanelBlockSyntax extends md.BlockSyntax {
  static final _open = RegExp(r'^\s*--panel(?:\[([^\]]*)\])?--\s*$');
  static final _close = RegExp(r'^\s*--/panel--\s*$');

  @override
  RegExp get pattern => _open;

  @override
  md.Node? parse(md.BlockParser parser) {
    var attributes = _open.firstMatch(parser.current.content)?.group(1);
    parser.advance();

    var lines = <String>[];
    var depth = 1;
    while (!parser.isDone) {
      var at = parser.current.content;
      if (_close.hasMatch(at)) {
        depth--;
        parser.advance();
        if (depth == 0) break;
        lines.add(at);
        continue;
      }
      // A panel inside a panel is an ordinary thing to write -- a card
      // inside a bordered row -- so a closing line has to be matched to the
      // one that opened it rather than to the first one seen.
      if (_open.hasMatch(at)) depth++;
      lines.add(at);
      parser.advance();
    }

    // The content is carried across as the text it was written as and drawn
    // by the renderer itself, which is how every other block here holds its
    // content. It costs a second parse and buys the whole language inside a
    // panel -- including another panel -- rather than whatever subset this
    // block thought to allow.
    var element = md.Element.text("panel", "");
    element.attributes["body"] = lines.join("\n");
    if (attributes != null) element.attributes["attrs"] = attributes;

    // Inside a paragraph, because this renderer treats only a fixed list of
    // tags as blocks and handles anything else as though it were already
    // inside one. A tag of its own arriving at the top level is handled as
    // part of a paragraph that does not exist, which throws. The blocks that
    // already work here come out wrapped this way, so this matches them
    // rather than inventing a second shape.
    return md.Element("p", [element]);
  }
}

class PanelMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var body = element.attributes["body"] ?? "";
    var rule = PanelRule.parse(element.attributes["attrs"]);
    return MarkdownPanel(
      rule: rule,
      // A panel with nothing between its two lines is a panel drawn for what
      // it is rather than for what it holds -- a picture at a fixed shape,
      // which is the picture half of a shop front's card. Rendering the
      // empty string as markdown would be a renderer, and a line of its
      // spacing, drawn for nothing.
      child: body.trim().isEmpty
          ? const SizedBox.shrink()
          : MarkdownArea(body, false, align: rule.text),
    );
  }
}

/// MarkdownPanel draws the box.
class MarkdownPanel extends StatelessWidget {
  final PanelRule rule;
  final Widget child;
  const MarkdownPanel({required this.rule, required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var color = (rule.color == null ? null : theme.markdownInk(rule.color!)) ??
        theme.markdownRoleColor(MarkdownRole.outline);
    var radius = rule.radius ?? BorderRadius.zero;

    Widget out = child;
    if (rule.padding != null) {
      out = Padding(padding: rule.padding!, child: out);
    }

    out = _surface(context, theme, out, radius);

    var border = rule.border;
    if (border != null && rule.stroke != PanelStroke.none) {
      out = rule.stroke == PanelStroke.solid
          ? DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: color, width: border.top),
                  right: BorderSide(color: color, width: border.right),
                  bottom: BorderSide(color: color, width: border.bottom),
                  left: BorderSide(color: color, width: border.left),
                ),
                borderRadius: rule.radius,
              ),
              child: out,
            )
          : CustomPaint(
              foregroundPainter: _PanelBorderPainter(
                color: color,
                width: border,
                // A broken line takes the first corner it is given. Drawing
                // dashes round four different curves is a different piece of
                // geometry, and a border written with four numbers is
                // overwhelmingly a solid one.
                radius: radius.topLeft.x,
                dotted: rule.stroke == PanelStroke.dotted,
              ),
              child: Padding(padding: border, child: out),
            );
    }

    if (rule.link != null) {
      out = _linked(context, out);
    }

    if (rule.margin != null) {
      out = Padding(padding: rule.margin!, child: out);
    }
    return out;
  }

  /// _surface is the panel's own face: the colour it is filled with, the
  /// picture behind it, the shape it is drawn at, and where its content sits
  /// in that shape.
  ///
  /// Inside the border rather than outside it, so a filled panel's line is
  /// drawn round the fill rather than through it, and the corners clip the
  /// picture rather than the picture squaring them off.
  Widget _surface(BuildContext context, ThemeNotifier theme, Widget content,
      BorderRadius radius) {
    var fill = rule.fill == null ? null : theme.markdownInk(rule.fill!);
    var picture = rule.image == null
        ? null
        : pageAssetPicture(context, rule.image!,
            // Cropped only where there is a shape to crop to. Without one
            // the panel is as tall as the picture, so the whole picture is
            // what it is: there is nothing to crop against.
            fit: BoxFit.cover,
            alignment: rule.crop,
            // With no shape given, the picture is what says how large the
            // panel is -- so it has to be the width of it. Left at its own
            // width it sits at one end of a wider box, and the corners,
            // border and fill are drawn round space the picture is not in.
            fillWidth: rule.ratio == null);

    // Nothing behind it, no shape asked for, and nothing to say about where
    // its content sits leaves the plain block a panel was before any of
    // this: no Stack, no clip, nothing measured.
    //
    // Placement is checked here as well as the rest, and that is the whole
    // of one bug. A panel written only to hold its content to one side --
    // which is how a plate that is not the full width of a card is written
    // -- has no fill, no picture and no shape, so it returned before it
    // reached the placing below and the setting did nothing at all.
    var placing = rule.align != null || rule.justify != PanelJustify.stretch;
    if (fill == null && picture == null && rule.ratio == null && !placing) {
      return content;
    }

    // Placed by a Column rather than an Align, so that content asking for
    // the full width gets it. Aligned, a line of writing on a card would sit
    // in the middle of it and wrap at its own length rather than the card's.
    Widget placed = !placing
        ? content
        : Column(
            mainAxisAlignment: switch (rule.align?.y) {
              null => MainAxisAlignment.start,
              < 0 => MainAxisAlignment.start,
              > 0 => MainAxisAlignment.end,
              _ => MainAxisAlignment.center,
            },
            crossAxisAlignment: switch (rule.justify) {
              PanelJustify.stretch => CrossAxisAlignment.stretch,
              PanelJustify.left => CrossAxisAlignment.start,
              PanelJustify.center => CrossAxisAlignment.center,
              PanelJustify.right => CrossAxisAlignment.end,
            },
            children: [content],
          );

    Widget out;
    if (rule.ratio != null) {
      // A shape given is the panel's own: as wide as it is allowed to be and
      // as tall as the shape makes it, with the picture filling that and the
      // content laid over it.
      out = AspectRatio(
        aspectRatio: rule.ratio!,
        child: Stack(fit: StackFit.expand, children: [
          if (picture != null) picture,
          placed,
        ]),
      );
    } else if (picture != null) {
      // No shape, so the picture is what says how tall the panel is: it is
      // the one child of the stack that is measured, and the content is laid
      // over whatever that comes to.
      out = Stack(children: [
        picture,
        Positioned.fill(child: placed),
      ]);
    } else {
      out = placed;
    }

    if (fill != null) {
      out = DecoratedBox(
        decoration: BoxDecoration(color: fill, borderRadius: rule.radius),
        child: out,
      );
    }

    // Clipped last, so both the fill and the picture are cut to the corners
    // the panel asked for.
    return rule.radius == null
        ? out
        : ClipRRect(borderRadius: radius, child: out);
  }

  /// _linked makes the whole panel the link.
  ///
  /// A GestureDetector rather than an InkWell: a panel is drawn wherever a
  /// page is, including places with no Material above it, and an InkWell
  /// without one throws rather than drawing without its ripple.
  Widget _linked(BuildContext context, Widget out) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          // Opaque, so the whole of the panel answers rather than only the
          // parts of it something is drawn on. A card whose picture is a
          // link and whose margins are not is a card that ignores half the
          // taps aimed at it.
          behavior: HitTestBehavior.opaque,
          onTap: () => followMarkdownLink(context, rule.link!),
          child: out,
        ),
      );
}

/// _PanelBorderPainter draws a broken line, which Border cannot.
///
/// Each side is drawn from its own thickness, so a panel asking for one
/// dashed rule down its left -- border=0 0 0 5 -- gets one. Reading a single
/// thickness for all four meant that panel asked for a line 0 thick and got
/// nothing at all, which looked like dashed borders being broken.
///
/// The corners are rounded only when all four sides are there and the same
/// thickness. A radius joins two sides; with one of them missing there is
/// nothing to join, and with the two different thicknesses the join is a
/// shape nobody asked for.
class _PanelBorderPainter extends CustomPainter {
  final Color color;
  final EdgeInsets width;
  final double radius;
  final bool dotted;

  const _PanelBorderPainter({
    required this.color,
    required this.width,
    required this.radius,
    required this.dotted,
  });

  bool get _uniform =>
      width.top > 0 &&
      width.top == width.right &&
      width.top == width.bottom &&
      width.top == width.left;

  @override
  void paint(Canvas canvas, Size size) {
    if (_uniform) {
      var inset = width.top / 2;
      _dash(
        canvas,
        Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(
                inset, inset, size.width - width.top, size.height - width.top),
            Radius.circular(radius),
          )),
        width.top,
      );
      return;
    }

    // Each side on its own. Drawn down the middle of the thickness it was
    // given, the way a border is drawn everywhere else, so a 5 thick rule
    // sits inside the space the padding already left for it.
    void side(double thickness, Offset from, Offset to) {
      if (thickness <= 0) return;
      _dash(
          canvas,
          Path()
            ..moveTo(from.dx, from.dy)
            ..lineTo(to.dx, to.dy),
          thickness);
    }

    side(
        width.top, Offset(0, width.top / 2), Offset(size.width, width.top / 2));
    side(width.bottom, Offset(0, size.height - width.bottom / 2),
        Offset(size.width, size.height - width.bottom / 2));
    side(width.left, Offset(width.left / 2, 0),
        Offset(width.left / 2, size.height));
    side(width.right, Offset(size.width - width.right / 2, 0),
        Offset(size.width - width.right / 2, size.height));
  }

  void _dash(Canvas canvas, Path path, double thickness) {
    var paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = dotted ? StrokeCap.round : StrokeCap.butt
      ..style = PaintingStyle.stroke;

    // A dot is as long as the line is thick, so it comes out round; a dash is
    // several times that, so it reads as a line with gaps rather than as a
    // row of marks.
    var on = dotted ? 0.1 : thickness * 3;
    var off = dotted ? thickness * 2 : thickness * 3;

    for (var metric in path.computeMetrics()) {
      var at = 0.0;
      while (at < metric.length) {
        var end = at + on;
        canvas.drawPath(
            metric.extractPath(at, end > metric.length ? metric.length : end),
            paint);
        at = end + off;
      }
    }
  }

  @override
  bool shouldRepaint(_PanelBorderPainter old) =>
      old.color != color ||
      old.width != width ||
      old.radius != radius ||
      old.dotted != dotted;
}
