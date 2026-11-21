import 'dart:collection';
import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/element_preset.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/presets/builtin_element_presets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/element_preset_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_element_presets_test.dart is a design somebody wants again.
//
// What is pinned: a preset is the element's own JSON, so it carries every
// setting without anything here having to know what the settings are -- and
// what it makes is an ordinary element, with a new id and no place of its
// own, so two elements made from one preset are two elements.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync("canvas-presets");
    CanvasStorage.rootOverride = root.path;
    ElementPresetStore.instance.forget();
  });

  tearDown(() {
    CanvasStorage.rootOverride = null;
    ElementPresetStore.instance.forget();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group("what ships with the app", () {
    test("is a Code panel's examples, each with the page it was made on", () {
      // There was a football league table here once. It carried no page,
      // so it arrived at whatever size it had been saved at -- which is
      // what presets being sized to the canvas they land on was written to
      // fix. What ships now (Ken, 2026-11-15: the Code examples as presets)
      // carries its page, and builds.
      expect(builtinElementPresets, isNotEmpty);
      for (var p in builtinElementPresets) {
        expect(p.kind, ElementKind.code, reason: p.name);
        expect(p.madeOn, isNotNull, reason: p.name);
        expect(p.build().kind, ElementKind.code, reason: p.name);
      }
    });

    test("but a design that did ship would not be the reader's to lose", () {
      // The rule is kept ready rather than written again for the next one.
      var shipped = const ElementPreset(
        id: "x",
        name: "Shipped",
        kind: ElementKind.table,
        element: {},
        builtIn: true,
      );
      expect(shipped.copyWith(name: "Mine").builtIn, isTrue);
    });

    test("and a saved one cannot be confused for one", () async {
      var store = ElementPresetStore.instance;
      await store.load();
      expect([
        for (var p in store.presets)
          if (p.builtIn) p.id
      ], [
        for (var p in builtinElementPresets) p.id
      ], reason: "only what ships is built in");
    });
  });

  group("saving one", () {
    TextElement headline() => TextElement(
          const ElementBase(id: "t", x: 300, y: 400, width: 400, height: 90),
          text: "A headline",
          textSpec: const TextSpec(fontSize: 44, color: Color(0xFF00FF00)),
        );

    test("keeps every setting, because it keeps the element", () async {
      var store = ElementPresetStore.instance;
      var saved = await store.save("My headline", headline());
      expect(saved, isNotNull);

      var made = saved!.build() as TextElement;
      expect(made.text, "A headline");
      expect(made.textSpec.fontSize, 44);
      expect(made.textSpec.color, const Color(0xFF00FF00));
    });

    test("but not where it happened to be", () async {
      // A preset that carried the coordinates it was saved at would land off
      // the page of any canvas smaller than the one it came from.
      var saved =
          await ElementPresetStore.instance.save("Elsewhere", headline());
      expect(saved!.element.containsKey("x"), isFalse);
      expect(saved.element.containsKey("y"), isFalse);
      expect(saved.element.containsKey("id"), isFalse);
    });

    test("and it is there again after a restart", () async {
      var store = ElementPresetStore.instance;
      await store.save("Kept", headline());

      // A second store, reading the same folder from cold.
      store.forget();
      await store.load();
      var mine = store.forKind(ElementKind.text);
      expect(mine.map((p) => p.name), contains("Kept"));
    });

    test("renaming and deleting", () async {
      var store = ElementPresetStore.instance;
      var saved = await store.save("First name", headline());
      expect(await store.rename(saved!, "Second name"), isTrue);

      store.forget();
      await store.load();
      var mine = store.forKind(ElementKind.text).single;
      expect(mine.name, "Second name");

      expect(await store.remove(mine), isTrue);
      store.forget();
      await store.load();
      expect(store.forKind(ElementKind.text), isEmpty);
    });

    test("an empty name is not a name", () async {
      expect(await ElementPresetStore.instance.save("  ", headline()), isNull);
    });
  });

  group("the folder they live in", () {
    test("is hidden from the Files panel", () async {
      await ElementPresetStore.instance.save(
          "Kept",
          TextElement(
            const ElementBase(id: "t", width: 200, height: 60),
            text: "Words",
          ));
      // The listing skips anything beginning with a dot, which is what keeps
      // a folder of presets from looking like a folder of canvases.
      var entries = await CanvasStorage.list("");
      expect(entries.where((e) => e.name.contains("preset")), isEmpty);
    });
  });

  group("using one", () {
    test("replaces the element being edited rather than joining it", () async {
      // Adding put the new design exactly on top of the old one: two
      // elements in the same place, one of them invisible and still there.
      var here = TextElement(
        const ElementBase(id: "t", x: 120, y: 240, width: 400, height: 90),
        text: "What is here now",
      );
      var store = ElementPresetStore.instance;
      var preset = await store.save(
          "A design",
          TextElement(
            const ElementBase(id: "other", x: 0, y: 0, width: 300, height: 200),
            text: "The saved design",
          ));

      // What the settings do with it: the preset's design, in the element's
      // own place and under its own id.
      var made = preset!.build();
      var next = made.rebase(made.base.withTiesOf(here.base));

      expect(next.id, "t", reason: "the same element, not a second one");
      expect((next as TextElement).text, "The saved design");
      expect(next.x, 120);
      expect(next.y, 240);
      expect(next.bounds.width, 300, reason: "the design's own shape");
    });

    /// tied is a base with everything set that ties an element to its place
    /// in one canvas.
    ElementBase tied(String id) => ElementBase(
          id: id,
          name: "Mine",
          x: 120,
          y: 240,
          width: 400,
          height: 90,
          opacity: 0.5,
          locked: true,
          rowColour: 0xFF112233,
          track: ElementTrack([const Keyframe(frame: 4, dx: 9)]),
          layouts: const {
            "square": ElementLayout(x: 1, y: 2, width: 3, height: 4),
          },
          depth: 0.25,
          ownText: true,
          ownDesign: true,
          shared: const {"kind": "text"},
          cue: "cue1",
          cast: "member1",
          dock: "layout1:cellA",
          dockOut: true,
        );

    test("a saved design carries nothing that ties it to its canvas", () async {
      // A Cast link, a Layout cell, a cue and the layouts of the canvas's
      // other page shapes all name things in the canvas it was saved from.
      // Carried, they arrive in another canvas pointing at nothing, or in
      // this one pointing at something of somebody else's.
      var saved = await ElementPresetStore.instance
          .save("Tied", TextElement(tied("t"), text: "Words"));
      var made = saved!.build();
      expect(made.base.cast, "");
      expect(made.base.dock, "");
      expect(made.base.dockOut, isFalse);
      expect(made.base.cue, "");
      expect(made.base.layouts, isEmpty);
      expect(made.base.shared, isNull);
      expect(made.base.ownDesign, isFalse);
      expect(made.base.ownText, isFalse);
      expect(made.base.track, isNull);
      expect((made as TextElement).text, "Words");
    });

    test("and put on an element, leaves that element's own ties alone", () {
      // The design is another element's, ties and all, as an older saved
      // preset still holds them.
      var design = const ElementBase(
        id: "other",
        width: 300,
        height: 200,
        rotation: 30,
        cue: "theirCue",
        cast: "theirMember",
        dock: "theirLayout:cell",
        layouts: {"wide": ElementLayout(x: 9, y: 9, width: 9, height: 9)},
      );
      var own = tied("t");
      var next = design.withTiesOf(own);

      expect(next.width, 300, reason: "the design's shape");
      expect(next.rotation, 30, reason: "and its turn");
      var kept = next.toJson();
      var mine = own.toJson();
      for (var key in _ties) {
        expect(kept[key], mine[key], reason: "its own $key");
      }
    });

    test("every field of an element is known to be design or a tie", () {
      // ElementBase.fromJson asks for each key it reads. One not listed here
      // is a field added since: decide whether a preset should carry it,
      // put it in asDesign and withTiesOf if not, and add it to a list.
      var asked = _Asked();
      ElementBase.fromJson(asked, "");
      expect(asked.keys.toSet().difference({..._ties, ..._design}), isEmpty);
    });
  });

  group("a preset read back", () {
    test("survives being written and read", () {
      var preset = ElementPreset(
        id: "p1",
        name: "A name",
        kind: ElementKind.chart,
        element: const {"kind": "chart", "w": 400.0, "h": 300.0},
      );
      var back = ElementPreset.fromJson(preset.toJson());
      expect(back.id, "p1");
      expect(back.name, "A name");
      expect(back.kind, ElementKind.chart);
      expect(back.element["w"], 400.0);
      expect(back.builtIn, isFalse);
    });
  });
}

/// _ties are the saved keys that are an element's own on its canvas (its
/// identity, its place, and what names or belongs to that canvas), which a
/// preset put on it leaves alone. _design are those a preset brings.
const _ties = {
  "id", "name", "x", "y", "opacity", "visible", "locked", "rowColour",
  "track", "layouts", "depth", "ownText", "ownDesign", "shared", "cue",
  "cast", "dock", "dockOut", "play", "spot", "motion", //
};
const _design = {
  "w", "h", "rot", "skx", "sky", "blend", "aspect", "ax", "ay",
  "anchorLocked", "typeScale", //
};

/// _Asked is a map that holds nothing and remembers each key it is asked for.
class _Asked extends MapBase<String, dynamic> {
  final Set<String> _keys = {};

  @override
  dynamic operator [](Object? key) {
    if (key is String) _keys.add(key);
    return null;
  }

  @override
  void operator []=(String key, dynamic value) {}

  @override
  void clear() {}

  @override
  Iterable<String> get keys => _keys;

  @override
  dynamic remove(Object? key) => null;
}
