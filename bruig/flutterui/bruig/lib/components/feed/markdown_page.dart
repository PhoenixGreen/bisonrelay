import 'package:bruig/theming_system/model/markdown_style.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

// markdown_page.dart is how a page says how wide it is, what it sits on, and
// how much room it keeps around itself:
//
//   --page--
//   width: 800
//   background: raised
//   padding: 24
//   margin: 0 auto
//   --/page--
//
// In the page rather than in a panel beside it, because the page bytes are
// the only thing that reaches a reader. A setting kept anywhere else needs
// its own way across -- a second file to fetch, or something baked in at
// publish that the author never sees again -- and both are a way for what is
// written and what is read to come apart. This travels with the thing it
// describes.
//
// The colour is named, never given. See PageSetup.background.

/// pageFields are the settings a page may state. Anything else is left where
/// it was written, so a typo shows up as itself rather than vanishing.
const List<String> pageFields = ["width", "background", "padding", "margin"];

/// maxPageWidth is the widest a page may ask to be.
///
/// Not a limit on design so much as on nonsense: a page asking for 40000
/// gets the window, which is what asking for no limit already does.
const double maxPageWidth = 4000;

/// maxPageSpace is the most room a page may keep around itself, per side.
const double maxPageSpace = 400;

/// PageBackground is what a page sits on.
///
/// A role, not a colour. A page cannot know what its reader's theme looks
/// like -- whether it is dark or light, or what the writing on it will be --
/// so a page naming #ffffff is a page that is blank white with white writing
/// for every reader in a dark theme. Naming a role instead means the reader's
/// own palette answers, and the answer is right in both.
enum PageBackground {
  /// none lets the Pages area's own background show through, which is what a
  /// page that says nothing gets.
  none("None"),

  /// raised is the surface a panel sits on: the content held slightly above
  /// the window behind it.
  raised("Raised"),

  /// quiet is the muted surface -- the same relationship the other way, for
  /// a page that wants to sit back rather than stand out.
  quiet("Quiet");

  final String label;
  const PageBackground(this.label);

  static PageBackground? parse(String value) {
    for (var b in PageBackground.values) {
      if (b.name == value.trim().toLowerCase()) return b;
    }
    return null;
  }
}

/// PageSetup is what a page asked for.
///
/// Every field is optional and every one has a sane nothing: a page that says
/// nothing renders exactly as a page did before any of this existed.
@immutable
class PageSetup {
  /// width is the widest the content column may be, or null for the window.
  ///
  /// The column, not the page. A banner across the top of a narrow column of
  /// writing is the ordinary shape of a site, and a width that also caged the
  /// banner could not make it. Rows marked flush escape it -- the word the
  /// header already uses for exactly this.
  final double? width;

  final PageBackground background;

  /// padding is inside the background, margin is outside it. They look the
  /// same until there is a background, which is why they are set together.
  final EdgeInsets? padding;
  final EdgeInsets? margin;

  const PageSetup({
    this.width,
    this.background = PageBackground.none,
    this.padding,
    this.margin,
  });

  static const none = PageSetup();

  bool get saysAnything =>
      width != null ||
      background != PageBackground.none ||
      padding != null ||
      margin != null;

  static final _open = RegExp(r'^\s*--page--\s*$');
  static final _close = RegExp(r'^\s*--/page--\s*$');
  static final _field = RegExp(r'^\s*(\w+)\s*:\s*(.*)$');

  /// parse reads the block out of a whole page.
  ///
  /// From the text rather than from the parsed document, because what this
  /// describes is the frame the document is drawn inside -- which has to be
  /// known before there is anything to draw. The block itself renders as
  /// nothing; see PageBlockSyntax.
  ///
  /// The first block wins. A page with two is a page whose author is
  /// changing their mind in writing, and picking the first means what is at
  /// the top of the file is what is in force -- which is where anyone would
  /// look for it.
  static PageSetup parse(String markdown) {
    if (!markdown.contains("--page--")) return none;

    var lines = markdown.split("\n");
    var inside = false;
    var fields = <String, String>{};
    for (var line in lines) {
      if (!inside) {
        if (_open.hasMatch(line)) inside = true;
        continue;
      }
      if (_close.hasMatch(line)) break;
      var m = _field.firstMatch(line);
      var key = m?.group(1)?.toLowerCase();
      if (m != null && key != null && pageFields.contains(key)) {
        fields.putIfAbsent(key, () => m.group(2)!.trim());
      }
    }
    if (fields.isEmpty) return none;

    return PageSetup(
      width: _length(fields["width"], maxPageWidth),
      background: PageBackground.parse(fields["background"] ?? "") ??
          PageBackground.none,
      padding: _space(fields["padding"]),
      margin: _space(fields["margin"]),
    );
  }

  /// _length reads one number, ignoring a unit if one was written.
  ///
  /// "800" and "800px" both mean the same thing to anyone typing them, and a
  /// page that rendered full width because of a "px" would be a puzzle.
  static double? _length(String? value, double most) {
    if (value == null) return null;
    var m = RegExp(r'^(\d+(?:\.\d+)?)').firstMatch(value.trim());
    if (m == null) return null;
    var n = double.tryParse(m.group(1)!);
    if (n == null || n <= 0) return null;
    return n > most ? most : n;
  }

  /// _space reads room around something, the way it is written everywhere
  /// else it is written: one number for all four sides, two for down-and-up
  /// then across, four for each side from the top going clockwise.
  static EdgeInsets? _space(String? value) {
    if (value == null) return null;
    var parts = value
        .trim()
        .split(RegExp(r'[\s,]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    var got = [for (var p in parts) _length(p, maxPageSpace)];
    if (got.isEmpty || got.any((v) => v == null)) return null;
    var n = got.cast<double>();
    return switch (n.length) {
      1 => EdgeInsets.all(n[0]),
      2 => EdgeInsets.symmetric(vertical: n[0], horizontal: n[1]),
      3 => EdgeInsets.fromLTRB(n[1], n[0], n[1], n[2]),
      _ => EdgeInsets.fromLTRB(n[3], n[0], n[1], n[2]),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is PageSetup &&
      other.width == width &&
      other.background == background &&
      other.padding == padding &&
      other.margin == margin;

  @override
  int get hashCode => Object.hash(width, background, padding, margin);
}

/// PageBlockSyntax swallows the block so it is not read as writing.
///
/// It draws nothing. What it says is read from the text by PageSetup.parse
/// and applied by PageFrame, which wraps the whole page -- there is nothing
/// to draw in the place the block happens to sit.
class PageBlockSyntax extends md.BlockSyntax {
  static final _open = RegExp(r'^\s*--page--\s*$');
  static final _close = RegExp(r'^\s*--/page--\s*$');

  @override
  RegExp get pattern => _open;

  @override
  md.Node? parse(md.BlockParser parser) {
    parser.advance();
    while (!parser.isDone) {
      var closing = _close.hasMatch(parser.current.content);
      parser.advance();
      if (closing) break;
    }
    // Nothing at all, rather than an element that draws nothing.
    //
    // Emitting one and rendering it as an empty box threw, for a page whose
    // first line is --page-- -- which is where it belongs, so that was every
    // page that used it. A block that contributes nothing to the document
    // should not put anything into the document; then there is no element to
    // be handled wrongly, and nothing to keep in step with the renderer.
    return null;
  }
}

/// PageFrame draws a page inside what it asked for.
///
/// [cap] is the widest the reader will allow whatever the page asked for,
/// and [honourBackground] whether the page may choose one at all. Both come
/// from the reader's own settings: the page knows its design, the reader
/// knows their screen, and neither can answer for the other.
class PageFrame extends StatelessWidget {
  final PageSetup setup;
  final double? cap;
  final bool honourBackground;
  final Widget child;

  const PageFrame({
    required this.setup,
    required this.child,
    this.cap,
    this.honourBackground = true,
    super.key,
  });

  /// _width is what the page gets, which is the narrower of what it asked
  /// for and what the reader allows.
  ///
  /// The narrower, not the reader's, so a reader's cap of 1200 does not
  /// widen a page that wanted 600. A cap is a ceiling, not a measurement.
  @visibleForTesting
  double? get width {
    if (setup.width == null) return cap;
    if (cap == null) return setup.width;
    return setup.width! < cap! ? setup.width : cap;
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var background = honourBackground ? setup.background : PageBackground.none;

    Widget out = child;
    if (setup.padding != null) {
      out = Padding(padding: setup.padding!, child: out);
    }
    if (background != PageBackground.none) {
      out = DecoratedBox(
        decoration: BoxDecoration(color: _colorFor(theme, background)),
        child: out,
      );
    }
    if (width != null) {
      out = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width!),
          child: out,
        ),
      );
    }
    if (setup.margin != null) {
      out = Padding(padding: setup.margin!, child: out);
    }
    return out;
  }

  /// _colorFor asks the reader's theme, which is the only thing that knows.
  ///
  /// Through markdownRoleColor for raised, so a page sits on exactly the
  /// surface a quotation or a card sits on rather than something almost like
  /// it. Nothing here computes a colour: computing one is how a page ends up
  /// with writing it cannot be read against.
  static Color _colorFor(ThemeNotifier theme, PageBackground background) =>
      switch (background) {
        PageBackground.raised =>
          theme.markdownRoleColor(MarkdownRole.raised),
        PageBackground.quiet => theme.surfaceColor(SurfaceColor.surfaceDim),
        PageBackground.none => Colors.transparent,
      };
}
