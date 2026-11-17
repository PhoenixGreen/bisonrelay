import 'dart:math' as math;

import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/data_styles.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/render/chart_painter.dart';
import 'package:bruig/plugin_system/canvas/render/table_painter.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// data_style_picker.dart is the Studio's Style row: the element drawn in
// each of the six styles, its own outlined.

class DataStylePicker extends StatelessWidget {
  final CanvasElement element;
  final ValueChanged<DataStyle> onPick;
  const DataStylePicker(
      {required this.element, required this.onPick, super.key});

  String get _current => switch (element) {
        ChartElement c => c.style,
        TableElement t => t.style,
        _ => "",
      };

  @override
  Widget build(BuildContext context) {
    final colors = ThemeNotifier.of(context).colors;
    return LayoutBuilder(builder: (context, box) {
      var perRow = box.maxWidth > 300 ? 3 : 2;
      var w = (box.maxWidth - 6 * (perRow - 1)) / perRow;
      return Wrap(spacing: 6, runSpacing: 6, children: [
        for (var s in dataStyles)
          SizedBox(
            width: w,
            child: Tooltip(
              message: s.note,
              child: Material(
                color: colors.surfaceContainerHigh,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                        color: _current == s.name
                            ? colors.primary
                            : const Color(0x00000000),
                        width: 1.5)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey("dataStyle-${s.name}"),
                  onTap: () => onPick(s),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(children: [
                      AspectRatio(
                        aspectRatio: 1.5,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: CustomPaint(
                              size: Size.infinite,
                              painter: _StyleThumb(element, s)),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: _current == s.name
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: colors.onSurface)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]);
    });
  }
}

/// _StyleThumb draws [e] in [s], fitted, on the style's ground.
class _StyleThumb extends CustomPainter {
  final CanvasElement e;
  final DataStyle s;
  _StyleThumb(this.e, this.s);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = s.ground);
    var w = math.max(1.0, e.width), h = math.max(1.0, e.height);
    var k = math.min((size.width - 6) / w, (size.height - 6) / h);
    canvas.save();
    canvas.translate((size.width - w * k) / 2, (size.height - h * k) / 2);
    canvas.scale(k);
    var rect = Rect.fromLTWH(0, 0, w, h);
    switch (e) {
      case ChartElement c:
        paintChart(canvas, rect, chartInStyle(c, s));
      case TableElement t:
        paintTable(canvas, rect, tableInStyle(t, s));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StyleThumb old) => !identical(old.e, e) || old.s != s;
}
