import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';

// element_samples.dart is one of every kind in the Add menu, for tests that
// should hold of every element: read back as written, survive a hostile
// file, draw, open a panel. A kind with sorts of its own (each synth module,
// each chart type) is here once for each sort.

/// elementSamples are (name, element) pairs: every ElementKind as it is
/// first added, then the sorts.
List<(String, CanvasElement)> elementSamples() {
  var doc = const CanvasDocument(frames: 96, frameRate: 24);
  var base = <(String, CanvasElement)>[
    for (var kind in ElementKind.values) (kind.label, newElement(kind, doc)),
  ];
  var chart = newElement(ElementKind.chart, doc) as ChartElement;
  var synth = newElement(ElementKind.synth, doc) as SynthModuleElement;
  return [
    ...base,
    for (var t in ChartType.values)
      if (t != chart.type) ("Chart: ${t.label}", chart.copyWith(type: t)),
    for (var m in SynthModuleKind.values)
      if (m != synth.module)
        ("Synth module: ${m.label}", SynthModuleElement(synth.base, module: m)),
  ];
}
