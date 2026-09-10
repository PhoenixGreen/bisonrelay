import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/element_preset.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
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
    test("includes the football table, ready to be put on a canvas", () {
      var presets = builtinElementPresets;
      var table = presets.firstWhere((p) => p.name == "Football table");
      expect(table.kind, ElementKind.table);
      expect(table.builtIn, isTrue);

      var made = table.build();
      expect(made, isA<TableElement>());
      var rows = (made as TableElement).rows;
      expect(rows.length, greaterThan(10),
          reason: "a league table, with its rows");
      expect(rows.first.length, greaterThan(3), reason: "and its columns");
    });

    test("and each build is its own element", () {
      // Two sharing an id would be one element as far as selection,
      // keyframes and flow links are concerned.
      var table = builtinElementPresets.first;
      expect(table.build().id, isNot(table.build().id));
    });

    test("which cannot be renamed or deleted", () async {
      var store = ElementPresetStore.instance;
      await store.load();
      var table = store.forKind(ElementKind.table).first;
      expect(await store.rename(table, "Mine"), isFalse);
      expect(await store.remove(table), isFalse);
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
      var next = made.withBase(x: here.x, y: here.y).withId(here.id);

      expect(next.id, "t", reason: "the same element, not a second one");
      expect((next as TextElement).text, "The saved design");
      expect(next.x, 120);
      expect(next.y, 240);
      expect(next.bounds.width, 300, reason: "the design's own shape");
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
