import 'dart:math' as math;
import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_styles.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';

// page_style.dart is a whole page in one of the data styles (Ken,
// 2026-11-17, the improvements report's fifth item): the charts and
// tables, and the words around them -- headings in its heading face,
// running words in its body face, small print in its quiet ink -- so one
// click turns an infographic from Editorial to Broadcast. And a page's
// data laid out in a few grids that fill it.

/// textInStyle is [t] in [s] by how big it is against the page's largest
/// words, [largest]: a heading, running words, or small print.
TextElement textInStyle(TextElement t, DataStyle s, double largest) {
  var size = t.textSpec.fontSize;
  var head = size >= largest * 0.6;
  var small = !head && size <= largest * 0.35;
  return t.copyWith(
      textSpec: t.textSpec.copyWith(
          fontFamily: head ? s.headFont : s.bodyFont,
          weight: head ? s.headWeight : t.textSpec.weight,
          color: small ? s.dim : s.ink));
}

/// pageInStyle is a page's [elements] in [s]: every chart and table in it
/// (charts on their own ground where they had one), every text by its
/// size. Anything else is left as it is.
List<CanvasElement> pageInStyle(List<CanvasElement> elements, DataStyle s) {
  var largest = elements
      .whereType<TextElement>()
      .map((t) => t.textSpec.fontSize)
      .fold(0.0, math.max);
  return [
    for (var e in elements)
      switch (e) {
        ChartElement c => chartInStyle(c, s, panel: c.panel.a > 0),
        TableElement t => tableInStyle(t, s),
        TextElement t when largest > 0 => textInStyle(t, s, largest),
        _ => e,
      },
  ];
}

/// PageLayout is how a page's data views are laid out over it.
enum PageLayout {
  rows2("Two a row"),
  rows1("One a row"),
  rows3("Three a row"),
  main("One large, the rest beside it");

  final String label;
  const PageLayout(this.label);
}

/// pageLayoutRects is where [n] views go on a page [page] in [layout]: in
/// [area] (below the page's heading, inside its margins), [gap] apart.
List<Rect> pageLayoutRects(int n, PageLayout layout, Rect area, double gap) {
  if (n <= 0) return const [];
  List<Rect> grid(int cols) {
    cols = math.min(cols, n);
    var rows = (n / cols).ceil();
    var w = (area.width - gap * (cols - 1)) / cols;
    var h = (area.height - gap * (rows - 1)) / rows;
    return [
      for (var i = 0; i < n; i++)
        Rect.fromLTWH(area.left + (i % cols) * (w + gap),
            area.top + (i ~/ cols) * (h + gap), w, h),
    ];
  }

  switch (layout) {
    case PageLayout.rows1:
      return grid(1);
    case PageLayout.rows2:
      return grid(2);
    case PageLayout.rows3:
      return grid(3);
    case PageLayout.main:
      if (n == 1) return [area];
      var mainW = (area.width - gap) * 0.62;
      var side = n - 1;
      var h = (area.height - gap * (side - 1)) / side;
      return [
        Rect.fromLTWH(area.left, area.top, mainW, area.height),
        for (var i = 0; i < side; i++)
          Rect.fromLTWH(area.left + mainW + gap, area.top + i * (h + gap),
              area.width - mainW - gap, h),
      ];
  }
}

/// layoutArea is where a page's data goes: inside margins a twentieth of
/// its width, from [top] (below its heading) down.
Rect layoutArea(Size page, double top) {
  var margin = page.width * 0.05;
  var t = math.max(margin, top);
  return Rect.fromLTRB(margin, t, page.width - margin, page.height - margin);
}
