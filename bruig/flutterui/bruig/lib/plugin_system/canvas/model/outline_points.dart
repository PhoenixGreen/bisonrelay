import 'dart:math' as math;
import 'dart:ui';

// outline_points.dart is the corners of the straight-sided outlines a box
// can be cut to: what a Shape draws (paint_util_shapes.dart) and what a
// Layout's Free cell is (layout_geometry.dart), so a triangle, a diamond, a
// regular polygon and a star are each worked out in one place. Each kind
// keeps its own numbers where they differ (which way a cell's hexagon
// points, how deep its star is cut), passed in, so a saved one draws as it
// did.

/// trianglePoints is [box]'s triangle: its top middle and bottom corners.
List<Offset> trianglePoints(Rect box) =>
    [Offset(box.center.dx, box.top), box.bottomRight, box.bottomLeft];

/// diamondPoints is [box]'s diamond: the middle of each side, from the top
/// round to the left.
List<Offset> diamondPoints(Rect box) => [
      Offset(box.center.dx, box.top),
      Offset(box.right, box.center.dy),
      Offset(box.center.dx, box.bottom),
      Offset(box.left, box.center.dy),
    ];

/// regularPoints is [corners] points round [centre], [rx] across and [ry]
/// down, evenly round from the first at [start] radians (straight up by
/// default); with [inner] below one, every other point is pulled in to that
/// share of the reach, which makes a star of half as many spikes.
List<Offset> regularPoints(Offset centre, double rx, double ry, int corners,
        {double start = -math.pi / 2, double inner = 1}) =>
    [
      for (var i = 0; i < corners; i++)
        () {
          var a = start + i * 2 * math.pi / corners;
          var k = inner != 1 && i.isOdd ? inner : 1.0;
          return Offset(centre.dx + math.cos(a) * rx * k,
              centre.dy + math.sin(a) * ry * k);
        }(),
    ];
