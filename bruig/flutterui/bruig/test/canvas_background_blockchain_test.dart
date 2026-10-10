import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_style_params.dart';
import 'package:bruig/plugin_system/canvas/presets/background_looks.dart';
import 'package:bruig/plugin_system/canvas/render/procedural/generators.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/procedural_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// canvas_background_blockchain_test.dart is the Blockchain background: its
// five ways of drawing, the settings it has of its own, and that each of
// them reaches the picture.

const int _w = 192, _h = 108;
const Rect _page = Rect.fromLTWH(0, 0, 192, 108);

const _base = ProceduralSpec(
  style: ProceduralStyle.blockchain,
  background: Color(0xFF000000),
  foreground: Color(0xFFFFFFFF),
  accent: Color(0xFFFF0000),
  vignette: 0,
);

Future<List<int>> _pixels(ProceduralSpec spec, {double time = 0}) async {
  var recorder = ui.PictureRecorder();
  paintProcedural(ui.Canvas(recorder), _page, spec,
      time: time, frameRate: 30);
  var picture = recorder.endRecording();
  var image = await picture.toImage(_w, _h);
  var bytes = (await image.toByteData())!;
  var out = [
    for (var i = 0; i < bytes.lengthInBytes; i += 4) bytes.getUint32(i),
  ];
  image.dispose();
  picture.dispose();
  return out;
}

/// _lit is how many pixels are not the black base.
int _lit(List<int> px) => px.where((p) => (p >> 8) & 0xFFFFFF > 0x080808).length;

void main() {
  group("each way of drawing it", () {
    for (var (mode, name) in [
      (BlockchainMode.chain, "chain"),
      (BlockchainMode.network, "network"),
      (BlockchainMode.ledger, "ledger"),
      (BlockchainMode.merkle, "Merkle tree"),
      (BlockchainMode.field, "block field"),
    ]) {
      testWidgets("the $name draws something, and moves when animated",
          (tester) async {
        var spec = _base
            .withParam("mode", mode.toDouble())
            .copyWith(animated: true);
        late List<int> a, b, again;
        await tester.runAsync(() async {
          a = await _pixels(spec, time: 1);
          b = await _pixels(spec, time: 3.5);
          again = await _pixels(spec, time: 1);
        });
        expect(_lit(a), greaterThan(300));
        expect(a, isNot(b));
        expect(a, again, reason: "the same moment is the same picture");
      });
    }

    testWidgets("the modes are different pictures", (tester) async {
      var pictures = <List<int>>[];
      await tester.runAsync(() async {
        for (var m = 0; m < 5; m++) {
          pictures.add(await _pixels(_base.withParam("mode", m.toDouble())));
        }
      });
      for (var i = 0; i < 5; i++) {
        for (var j = i + 1; j < 5; j++) {
          expect(pictures[i], isNot(pictures[j]), reason: "$i and $j");
        }
      }
    });
  });

  group("its own settings", () {
    test("are saved where they differ from the defaults, and read back", () {
      var spec = _base
          .withParam("mode", BlockchainMode.network.toDouble())
          .withParam("hubs", 0.4)
          .withParam("rows", 3); // the default: not written
      var json = spec.toJson();
      expect(json["params"], {"mode": 1.0, "hubs": 0.4});
      var back = ProceduralSpec.fromJson(json);
      expect(back.choice("mode"), BlockchainMode.network);
      expect(back.p("hubs"), 0.4);
      expect(back.p("rows"), 3);
    });

    test("are held inside what they can be", () {
      var spec = _base.withParam("rows", 40).withParam("mode", 9);
      expect(spec.p("rows"), 8);
      expect(spec.choice("mode"), 4);
    });

    test("left over from another style are not saved", () {
      var spec = _base
          .withParam("hubs", 0.4)
          .copyWith(style: ProceduralStyle.circuit);
      expect(spec.toJson().containsKey("params"), isFalse);
    });

    testWidgets("a cube's depth changes the picture; flat blocks have none",
        (tester) async {
      late List<int> shallow, deep, flatShallow, flatDeep;
      var flat = _base.withParam("blockShape", 1);
      await tester.runAsync(() async {
        shallow = await _pixels(_base.withParam("blockDepth", 0.1));
        deep = await _pixels(_base.withParam("blockDepth", 0.9));
        flatShallow = await _pixels(flat.withParam("blockDepth", 0.1));
        flatDeep = await _pixels(flat.withParam("blockDepth", 0.9));
      });
      expect(shallow, isNot(deep));
      expect(flatShallow, flatDeep);
    });
  });

  group("the settings panel", () {
    Future<ProceduralSpec Function()> pump(
        WidgetTester tester, ProceduralSpec start) async {
      var current = start;
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider(
          create: (_) => ThemeNotifier(doLoad: false),
          child: Scaffold(
            body: SingleChildScrollView(
              child: CanvasControlScope(
                maxWidth: 300,
                child: SizedBox(
                  width: 300,
                  child: StatefulBuilder(
                    builder: (context, setState) => ProceduralSettings(
                      spec: current,
                      onChanged: (s) => setState(() => current = s),
                      onBegin: () {},
                      onCommit: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return () => current;
    }

    testWidgets("shows only what the chosen way of drawing it uses",
        (tester) async {
      var spec = await pump(tester, _base);
      expect(find.byKey(const ValueKey("param-rows")), findsOneWidget);
      expect(find.byKey(const ValueKey("param-blockDepth")), findsOneWidget);
      expect(find.byKey(const ValueKey("param-hubs")), findsNothing);

      await tester.tap(find.byKey(const ValueKey("param-mode")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Network").last);
      await tester.pumpAndSettle();
      expect(spec().choice("mode"), BlockchainMode.network);
      expect(find.byKey(const ValueKey("param-rows")), findsNothing);
      expect(find.byKey(const ValueKey("param-blockDepth")), findsNothing);
      expect(find.byKey(const ValueKey("param-hubs")), findsOneWidget);
    });

    testWidgets("flat blocks are not offered a depth", (tester) async {
      var spec = await pump(tester, _base);
      await tester.tap(find.byKey(const ValueKey("param-blockShape")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Flat").last);
      await tester.pumpAndSettle();
      expect(spec().choice("blockShape"), 1);
      expect(find.byKey(const ValueKey("param-blockDepth")), findsNothing);
    });

    testWidgets("a number typed in reaches the spec", (tester) async {
      var spec = await pump(tester, _base);
      await tester.enterText(
          find.descendant(
              of: find.byKey(const ValueKey("param-rows")),
              matching: find.byType(EditableText)),
          "5");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(spec().p("rows"), 5);
    });

    testWidgets("its looks cover every way of drawing it", (tester) async {
      var modes = {
        for (var l in looksFor(ProceduralStyle.blockchain)) l.spec.choice("mode")
      };
      expect(modes, {0, 1, 2, 3, 4});
    });
  });
}
