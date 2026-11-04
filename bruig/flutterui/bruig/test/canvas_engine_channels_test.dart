import 'package:bruig/plugin_system/canvas/media/mix/mix_graph.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:flutter_test/flutter_test.dart';

// A channel gone from the canvas is let go of by the mix: its strip no
// longer runs, and set again it starts afresh.

void main() {
  test("a channel removed no longer runs its strip", () {
    var graph = MixGraph();
    graph.setChannel("a", const ChannelMix());
    graph.setChannel("b", const ChannelMix());
    expect(graph.has("a"), isTrue);
    graph.removeChannel("a");
    expect(graph.has("a"), isFalse);
    expect(graph.has("b"), isTrue, reason: "the others carry on");
    graph.setChannel("a", const ChannelMix());
    expect(graph.has("a"), isTrue, reason: "and it can come back");
  });
}
