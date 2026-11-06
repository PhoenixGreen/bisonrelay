import 'dart:io';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/devices.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/media_clip.dart';
import 'package:bruig/plugin_system/canvas/model/midi_effects.dart';
import 'package:bruig/plugin_system/canvas/model/mix.dart';
import 'package:bruig/plugin_system/canvas/model/saved_preset.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/device_presets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/saved_preset_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_audio_fake.dart';

// canvas_saved_presets_test.dart is a scene or a whole canvas somebody wants
// again.
//
// The thing worth pinning is that a preset is a *copy*: what is saved is what
// was there at the moment of saving, and the scene it came from goes on being
// edited without any of that reaching the preset. The other is the ids --
// what a preset builds is new, or the canvas it is dropped into has two
// scenes it cannot tell apart.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync("canvas-saved-presets");
    CanvasStorage.rootOverride = root.path;
    SavedPresetStore.scenes.forget();
    SavedPresetStore.canvases.forget();
    SavedPresetStore.devices.forget();
  });

  tearDown(() {
    CanvasStorage.rootOverride = null;
    SavedPresetStore.scenes.forget();
    SavedPresetStore.canvases.forget();
    SavedPresetStore.devices.forget();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  CanvasScene sceneWith(String elementId) => CanvasScene(
        id: "s1",
        name: "Opening",
        elements: [
          ShapeElement(ElementBase(id: elementId, width: 10, height: 10),
              fill: const Color(0xFFFF0000)),
        ],
      );

  test("a saved scene comes back after a restart", () async {
    var store = SavedPresetStore.scenes;
    var saved = await store.save("Title card", sceneWith("a").toJson());
    expect(saved, isNotNull);
    expect(store.presets.map((p) => p.name), ["Title card"]);

    // A second session: nothing in memory, everything on disk.
    store.forget();
    await store.load();
    expect(store.presets.map((p) => p.name), ["Title card"]);
    expect(store.presets.single.kind, SavedPresetKind.scene);
  });

  test("and is a copy, not a link back to the scene it came from", () async {
    var scene = sceneWith("a");
    var json = scene.toJson();
    await SavedPresetStore.scenes.save("Title card", json);

    // The document goes on being worked on -- here, by editing the very map
    // that was handed over.
    (json["elements"] as List).clear();
    json["name"] = "Something else";

    SavedPresetStore.scenes.forget();
    await SavedPresetStore.scenes.load();
    var built = SavedPresetStore.scenes.presets.single.buildScene()!;
    expect(built.name, "Opening");
    expect(built.elements.length, 1,
        reason: "what was saved is what was there");
  });

  test("what it builds is new: fresh ids for the scene and its elements",
      () async {
    await SavedPresetStore.scenes.save("Title card", sceneWith("a").toJson());
    var preset = SavedPresetStore.scenes.presets.single;

    var one = preset.buildScene()!;
    var two = preset.buildScene()!;
    expect(one.id, isNot("s1"));
    expect(one.id, isNot(two.id));
    expect(one.elements.single.id, isNot("a"));
    expect(one.elements.single.id, isNot(two.elements.single.id));
  });

  test("a canvas preset holds every scene, and can start a document", () async {
    var document = const CanvasDocument().withScenes([
      const CanvasScene(id: "a", name: "One"),
      const CanvasScene(id: "b", name: "Two"),
    ]);
    await SavedPresetStore.canvases.save("Match report", document.toJson());

    var preset = SavedPresetStore.canvases.presets.single;
    var built = preset.buildDocument()!;
    expect([for (var s in built.allScenes) s.name], ["One", "Two"]);
    expect(built.allScenes.first.id, isNot("a"), reason: "new ids");
    expect(preset.buildScene(), isNull, reason: "it is not a scene");

    // Dropped into a document that is already open, what it is is its scenes.
    expect(preset.buildScenes().length, 2);
  });

  test("renamed and deleted from the list it is in", () async {
    var store = SavedPresetStore.scenes;
    await store.save("Title card", sceneWith("a").toJson());
    var preset = store.presets.single;

    expect(await store.rename(preset, "Opening card"), isTrue);
    expect(store.presets.single.name, "Opening card");

    store.forget();
    await store.load();
    expect(store.presets.single.name, "Opening card",
        reason: "the new name is on disk, not only in the list");

    expect(await store.remove(store.presets.single), isTrue);
    expect(store.presets, isEmpty);

    store.forget();
    await store.load();
    expect(store.presets, isEmpty, reason: "and gone from disk with it");
  });

  test("the two kinds are kept apart", () async {
    await SavedPresetStore.scenes.save("A scene", sceneWith("a").toJson());
    await SavedPresetStore.canvases
        .save("A canvas", const CanvasDocument().toJson());

    SavedPresetStore.scenes.forget();
    SavedPresetStore.canvases.forget();
    SavedPresetStore.devices.forget();
    await SavedPresetStore.scenes.load();
    await SavedPresetStore.canvases.load();

    expect(SavedPresetStore.scenes.presets.map((p) => p.name), ["A scene"]);
    expect(SavedPresetStore.canvases.presets.map((p) => p.name), ["A canvas"]);
  });

  // The prototype's "Save as a preset…": a device, or a whole chain.
  group("sound presets", () {
    test("a device's preset is named afresh, kept, and comes back", () async {
      expect(freshPresetName("Chorus", {"Chorus", "Chorus 2"}), "Chorus 3");
      var store = SavedPresetStore.devices;
      var kept = await store.save("Wide chorus", {
        "devices": [
          const MixDevice(DeviceKind.chorus, id: "d4", values: {"depth": 0.9})
              .toJson()
        ],
        "midi": [const MidiEffect(MidiEffectKind.arpeggiator).toJson()],
      });
      expect(kept, isNotNull);
      store.forget();
      await store.load();
      var back = store.presets.single;
      expect(back.name, "Wide chorus");
      var devices = presetDevices(back.data);
      expect(devices.single.kind, DeviceKind.chorus);
      expect(devices.single.value("depth"), 0.9);
      expect(devices.single.id, "", reason: "an id of its own once added");
      expect(presetMidi(back.data).single.kind, MidiEffectKind.arpeggiator);
    });

    test("used, it goes on the end of a chain with ids of its own", () {
      var c = CanvasController(
          const CanvasDocument(frames: 100, elements: [
            AudioElement(ElementBase(id: "m", name: "Music"),
                clip: MediaClip(
                    playlist: [MediaSource(assetId: "t", length: 8)],
                    timed: true,
                    mix: ChannelMix(
                        devices: [MixDevice(DeviceKind.reverb, id: "d0")]))),
          ]),
          audioEngine: FakeEngine({"t": 8}));
      addTearDown(c.dispose);
      var preset = {
        "devices": [
          const MixDevice(DeviceKind.chorus, id: "d0").toJson(),
          const MixDevice(DeviceKind.delay).toJson(),
        ],
      };
      expect(useDevicePreset(c, "m", preset), isTrue);
      var now = c.devicesOf("m");
      expect(now.map((d) => d.kind),
          [DeviceKind.reverb, DeviceKind.chorus, DeviceKind.delay]);
      expect(now.map((d) => d.id).toSet(), hasLength(3));
      c.undo();
      expect(c.devicesOf("m").length, 1, reason: "one undo step");
      expect(useDevicePreset(c, "m", const {}), isFalse);
    });
  });
}
