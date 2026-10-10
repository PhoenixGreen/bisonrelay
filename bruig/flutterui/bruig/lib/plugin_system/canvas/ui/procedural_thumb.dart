import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/presets/background_looks.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// procedural_thumb.dart is a background drawn small: what a style or a look
// looks like, shown rather than named.

/// ProceduralThumb draws [spec] at the size it is given.
///
/// Drawn rather than kept as a picture: at this size even the slowest style
/// is a millisecond or two, and it only draws again when the spec does --
/// which, for the looks and the style list, is never, since theirs are made
/// once and kept.
class ProceduralThumb extends StatelessWidget {
  final ProceduralSpec spec;
  final double width;
  final double height;
  final double radius;
  const ProceduralThumb(this.spec,
      {this.width = 36, this.height = 20, this.radius = 3, super.key});

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: CustomPaint(
            size: Size(width, height),
            painter: _ThumbPainter(spec),
          ),
        ),
      );
}

class _ThumbPainter extends CustomPainter {
  final ProceduralSpec spec;
  _ThumbPainter(this.spec);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // Drawn as a frame of a fixed size and shrunk, rather than drawn at the
    // size of the thumbnail. Every style sizes itself against the frame, but
    // lines and dots have a least width below which they stop shrinking --
    // so at forty pixels across a circuit board was all pads.
    const across = 320.0;
    var k = size.width / across;
    canvas.save();
    canvas.scale(k);
    // A moment into the movement, for the styles that start from nothing:
    // rain that has not started falling is an empty rectangle.
    paintProcedural(canvas, Rect.fromLTWH(0, 0, across, size.height / k), spec,
        time: 1.5, frameRate: 30);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ThumbPainter old) => !identical(old.spec, spec);
}

/// styleThumbSpec is what a style is shown as in the list of them: its
/// first look, or -- for one that has none -- its defaults.
ProceduralSpec styleThumbSpec(ProceduralStyle style) => _styleThumbs[style] ??=
    (looksFor(style).firstOrNull?.spec ?? ProceduralSpec(style: style));

final Map<ProceduralStyle, ProceduralSpec> _styleThumbs = {};

/// LooksGrid is a style's looks, three to a row, to choose from.
class LooksGrid extends StatelessWidget {
  final ProceduralSpec spec;
  final ValueChanged<BackgroundLook> onPick;
  const LooksGrid({required this.spec, required this.onPick, super.key});

  @override
  Widget build(BuildContext context) {
    var looks = looksFor(spec.style);
    if (looks.isEmpty) return const SizedBox.shrink();
    var chosen = lookMatching(spec);
    var theme = ThemeNotifier.of(context);
    return LayoutBuilder(builder: (context, box) {
      const gap = 6.0, perRow = 3;
      var w = ((box.maxWidth - gap * (perRow - 1)) / perRow).floorToDouble();
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var look in looks)
            SizedBox(
              width: w,
              child: InkWell(
                key: ValueKey("look-${look.name}"),
                borderRadius: BorderRadius.circular(4),
                onTap: () => onPick(look),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(1.5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          width: 1.5,
                          color: identical(look, chosen)
                              ? theme.colors.primary
                              : Colors.transparent,
                        ),
                      ),
                      child: ProceduralThumb(look.spec,
                          width: w - 6, height: (w - 6) * 9 / 16),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 2, top: 2),
                      child: Text(
                        look.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: identical(look, chosen)
                                ? theme.colors.onSurface
                                : theme.colors.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}
