import 'package:bruig/plugin_system/canvas/render/synth_module_painter.dart';
import 'package:flutter/widgets.dart';

// carried_synth_cable.dart is the cable drawn from a synth module's jack to
// the pointer while it is being patched. Here and not with the synth's
// painters in render/, which hold no widget types: this is the wrapper the
// stage's widget tree needs round the function that draws a cable.

/// CarriedSynthCable is a synth cable carried from a jack to the pointer,
/// dashed, painted over the stage: [jack] and [at] are document points,
/// drawn at [scale] from [origin]. Nothing is drawn without a jack.
class CarriedSynthCable extends CustomPainter {
  final Offset? jack;
  final Offset at;
  final Color colour;
  final double panelScale, scale;
  final Offset origin;
  const CarriedSynthCable(this.jack, this.at, this.colour, this.panelScale,
      this.scale, this.origin);

  @override
  void paint(Canvas canvas, Size size) {
    var from = jack;
    if (from == null) return;
    paintSynthCable(canvas, from * scale + origin, at * scale + origin, colour,
        panelScale * scale,
        dashed: true);
  }

  @override
  bool shouldRepaint(CarriedSynthCable old) =>
      old.jack != jack ||
      old.at != at ||
      old.colour != colour ||
      old.panelScale != panelScale ||
      old.scale != scale ||
      old.origin != origin;
}
