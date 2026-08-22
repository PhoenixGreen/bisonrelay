import 'package:bruig/components/feed/markdown_page.dart';
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

  /// color is named, never given -- the same bargain the page background
  /// makes. A panel cannot know whether its reader is in a dark theme, so a
  /// line it names #000000 is a line nobody in one can see.
  final MarkdownRole? color;

  final double? radius;

  const PanelRule({
    this.padding,
    this.margin,
    this.border,
    this.stroke = PanelStroke.solid,
    this.color,
    this.radius,
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

    return PanelRule(
      padding: PageSetup.parseSpace(fields["padding"]),
      margin: PageSetup.parseSpace(fields["margin"]),
      border: _border(fields["border"]),
      stroke: PanelStroke.parse(fields["style"]),
      color: _role(fields["color"]),
      radius: PageSetup.parseLength(fields["radius"], maxPanelRadius,
          allowZero: true),
    );
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
      for (var p in parts) PageSetup.parseLength(p, maxBorderWidth, allowZero: true)
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

  static MarkdownRole? _role(String? value) {
    for (var r in MarkdownRole.values) {
      if (r.name.toLowerCase() == value?.trim().toLowerCase()) return r;
    }
    return null;
  }

  bool get saysAnything =>
      padding != null ||
      margin != null ||
      border != null ||
      color != null ||
      radius != null;

  @override
  bool operator ==(Object other) =>
      other is PanelRule &&
      other.padding == padding &&
      other.margin == margin &&
      other.border == border &&
      other.stroke == stroke &&
      other.color == color &&
      other.radius == radius;

  @override
  int get hashCode =>
      Object.hash(padding, margin, border, stroke, color, radius);
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
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) =>
      MarkdownPanel(
        rule: PanelRule.parse(element.attributes["attrs"]),
        child: MarkdownArea(element.attributes["body"] ?? "", false),
      );
}

/// MarkdownPanel draws the box.
class MarkdownPanel extends StatelessWidget {
  final PanelRule rule;
  final Widget child;
  const MarkdownPanel({required this.rule, required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var color = theme.markdownRoleColor(rule.color ?? MarkdownRole.outline);
    var radius = BorderRadius.circular(rule.radius ?? 0);

    Widget out = child;
    if (rule.padding != null) {
      out = Padding(padding: rule.padding!, child: out);
    }

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
                borderRadius: rule.radius != null ? radius : null,
              ),
              child: out,
            )
          : CustomPaint(
              foregroundPainter: _PanelBorderPainter(
                color: color,
                width: border,
                radius: rule.radius ?? 0,
                dotted: rule.stroke == PanelStroke.dotted,
              ),
              child: Padding(padding: border, child: out),
            );
    }

    if (rule.margin != null) {
      out = Padding(padding: rule.margin!, child: out);
    }
    return out;
  }
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
            Rect.fromLTWH(inset, inset, size.width - width.top,
                size.height - width.top),
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
      _dash(canvas, Path()..moveTo(from.dx, from.dy)..lineTo(to.dx, to.dy),
          thickness);
    }

    side(width.top, Offset(0, width.top / 2),
        Offset(size.width, width.top / 2));
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
