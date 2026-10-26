import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_tile_snapshot_test.dart is a tile's picture: drawn once and kept,
// kept as it was while a control is dragged, and not kept when it was
// drawn with something standing in for what is not ready.

void main() {
  late int drawn;
  late int stood;
  late bool standIn;

  setUp(() {
    drawn = 0;
    stood = 0;
    standIn = false;
    TileSnapshot.stoodIn = () => stood;
  });
  tearDown(() {
    TileSnapshot.holding = () => false;
    TileSnapshot.stoodIn = () => 0;
    TileSnapshot.arrived = null;
  });

  Widget tile(String id) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
            width: 60,
            height: 40,
            child: TileSnapshot(
                id: id,
                slot: "the tile",
                ground: Colors.white,
                paint: (canvas, size) {
                  drawn++;
                  if (standIn) stood++;
                  canvas.drawCircle(size.center(Offset.zero), 10,
                      Paint()..color = Colors.blue);
                })),
      ));

  testWidgets("is drawn once, and again only for something new", (tester) async {
    await tester.pumpWidget(tile("${DateTime.now().microsecondsSinceEpoch}a"));
    expect(drawn, 1);
    await tester.pumpWidget(tile("${DateTime.now().microsecondsSinceEpoch}b"));
    expect(drawn, 2);
  });

  testWidgets("keeps its picture while a control is dragged, then catches up",
      (tester) async {
    var dragging = false;
    TileSnapshot.holding = () => dragging;
    var first = "${DateTime.now().microsecondsSinceEpoch}first";
    await tester.pumpWidget(tile(first));
    expect(drawn, 1);
    dragging = true;
    for (var step = 0; step < 5; step++) {
      await tester.pumpWidget(tile("$first-step$step"));
    }
    expect(drawn, 1, reason: "nothing drawn during the drag");
    dragging = false;
    await tester.pumpWidget(tile("$first-step4"));
    expect(drawn, 2, reason: "drawn as it is once let go");
  });

  testWidgets("drawn with a stand-in, it is drawn again when the real thing comes",
      (tester) async {
    var arrived = ValueNotifier(0);
    TileSnapshot.arrived = arrived;
    var id = "${DateTime.now().microsecondsSinceEpoch}standin";
    standIn = true;
    await tester.pumpWidget(tile(id));
    expect(drawn, 1);
    standIn = false;
    arrived.value++;
    await tester.pump();
    expect(drawn, 2, reason: "drawn again when the body arrived");
    arrived.value++;
    await tester.pump();
    expect(drawn, 2, reason: "and then kept");
  });
}
