import 'dart:io';
import 'dart:ui' as ui;

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/synth_module_element.dart';
import 'package:bruig/plugin_system/canvas/model/instrument.dart';
import 'package:bruig/plugin_system/canvas/model/synth_channels.dart';
import 'package:bruig/plugin_system/canvas/model/synth_patch.dart';
import 'package:bruig/plugin_system/canvas/render/scene_renderer.dart';
import 'package:bruig/plugin_system/canvas/render/synth_module_painter.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_stage.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'canvas_audio_fake.dart';

// canvas_synth_module_test.dart is synth modules on a canvas (Ken,
// 2026-11-14: "separate, placeable canvas elements ... chainable on the
// canvas with patch cables"): kept, patched, played on their speaker's
// channel, put back to the teacher's start, and drawn in both looks -- set
// SYNTH_PNG to a path to have the rack written as a picture.

Future<void> _font(String family, List<String> files) async {
  var loader = FontLoader(family);
  for (var f in files) {
    loader.addFont(File("assets/fonts/$f")
        .readAsBytes()
        .then((b) => ByteData.view(Uint8List.fromList(b).buffer)));
  }
  await loader.load();
}

const page = CanvasDocument(frames: 240);

/// rack is the starting rack on a page, its speaker on channel "ch".
(CanvasDocument, Map<SynthModuleKind, SynthModuleElement>) rack() {
  var ch = newInstrument(page);
  ch = ch.rebase(ch.base.copyWith(id: "ch", visible: false)) as AudioElement;
  var mods = synthRack(page, channel: "ch");
  var doc = page.copyWith(elements: [ch, ...mods]);
  return (synthSynced(doc), {for (var m in mods) m.module: m});
}

InstrumentPart partOf(CanvasDocument doc) =>
    (doc.elementById("ch") as AudioElement).instrument!;

/// of is the module of [kind] in [c]'s document, as it is now.
SynthModuleElement of(CanvasController c, SynthModuleKind kind) =>
    c.document.elements
        .whereType<SynthModuleElement>()
        .firstWhere((e) => e.module == kind);

/// on is panel point [q] of [e], in document space.
Offset on(SynthModuleElement e, Offset q) {
  var (s, at) = synthPanelFit(e.bounds, synthPanelOf(e.module));
  return at + q * s;
}

Widget providers(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        ChangeNotifierProvider<CanvasPreferences>(
            create: (c) => CanvasPreferences()),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

/// staged is [c] on a stage in [tester]: answers where a document point
/// is on the screen.
Future<Offset Function(Offset)> staged(
    WidgetTester tester, CanvasController c) async {
  var key = GlobalKey<CanvasStageState>();
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(providers(SizedBox(
      width: 1600, height: 1000, child: CanvasStage(key: key, controller: c))));
  await tester.pumpAndSettle();
  var page = key.currentState!.pageRect;
  var scale = page.width / c.document.size.width;
  return (doc) => page.topLeft + doc * scale;
}

void main() {
  setUpAll(() async {
    await _font("Inter", ["Inter-Regular.otf", "Inter-ExtraBold.otf"]);
    await _font("RobotoMono", ["RobotoMono-VariableFont_wght.ttf"]);
  });

  test("kept: settings, cables, the start, the lock, the look, the channel",
      () {
    var (doc, m) = rack();
    var osc = m[SynthModuleKind.osc]!
        .withValue("octave", 1)
        .withChoice("wave", "square")
        .copyWith(fixed: true, look: SynthLook.digital);
    var back = elementFromJson(osc.toJson()) as SynthModuleElement;
    expect(back.module, SynthModuleKind.osc);
    expect(back.value("octave"), 1);
    expect(back.choice("wave"), "square");
    expect(back.inputs["pitch"],
        (module: m[SynthModuleKind.keys]!.id, port: "pitch"));
    expect(back.fixed, isTrue);
    expect(back.look, SynthLook.digital);
    expect(back.startValue("octave"), 0, reason: "the start, as it was");
    expect(back.changed, isTrue);
    var speaker =
        elementFromJson(m[SynthModuleKind.out]!.toJson()) as SynthModuleElement;
    expect(speaker.channel, "ch");
    expect(doc.elements.length, 8);
  });

  test("the rack: seven modules, three cables, the start where it begins", () {
    var (_, m) = rack();
    expect(m.length, 7);
    var cables = synthCables(m.values.toList());
    expect({
      for (var c in cables)
        "${c.from.module.name}.${c.out}>${c.into.module.name}.${c.input}"
    }, {
      "keys.pitch>osc.pitch",
      "osc.out>amp.in",
      "amp.out>out.in"
    });
    for (var e in m.values) {
      expect(e.changed, isFalse);
      expect(e.start, isNotNull);
      // Each box the shape of its panel.
      var p = synthPanelOf(e.module);
      expect(e.width / e.height, closeTo(p.size.width / p.size.height, 1e-6));
    }
    // A cable's ends are its jacks: back on the panel, on the jack.
    for (var c in cables) {
      var q = synthToPanel(c.into, c.b)!;
      expect(
          q, offsetMoreOrLessEquals(synthPanelOf(c.into.module).ins[c.input]!));
    }
  });

  test("the speaker's channel plays the patch it hears, and only that", () {
    var (doc, m) = rack();
    var part = partOf(doc);
    expect(part.sound, InstrumentSound.patch);
    expect([
      for (var x in part.patch!.modules) x.kind
    ], [
      SynthModuleKind.keys,
      SynthModuleKind.osc,
      SynthModuleKind.amp,
      SynthModuleKind.out
    ]);
    // A knob on a module patched into nothing: the channel as it was.
    var env = m[SynthModuleKind.env]!;
    var turned = synthSynced(doc.withElement(env.withValue("a", 2)));
    expect(identical(turned.elementById("ch"), doc.elementById("ch")), isTrue);
    // Patched in, it is heard.
    var amp = m[SynthModuleKind.amp]!;
    var gated = synthSynced(doc
        .withElement(env.plugged(
            "gate", (module: m[SynthModuleKind.keys]!.id, port: "gate")))
        .withElement(amp.plugged("gain", (module: env.id, port: "env"))));
    expect(partOf(gated).patch!.byId(env.id), isNotNull);
    // A knob on the oscillator: the channel's patch with it.
    var osc = m[SynthModuleKind.osc]!;
    var tuned = synthSynced(doc.withElement(osc.withValue("octave", -1)));
    expect(partOf(tuned).patch!.byId(osc.id)!.value("octave"), -1);
  });

  test("↺ and Reset all: back to the teacher's start", () {
    var (_, m) = rack();
    var osc = m[SynthModuleKind.osc]!;
    var moved = osc.withValue("level", 0.2).unplugged("pitch");
    expect(moved.changed, isTrue);
    var back = moved.reset();
    expect(back.changed, isFalse);
    expect(back.inputs, isEmpty, reason: "↺ leaves the cables");
    expect(moved.reset(cables: true).inputs["pitch"], isNotNull);
    var set = moved.startHere();
    expect(set.changed, isFalse);
    expect(set.reset(cables: true).inputs, isEmpty);
  });

  test("the keyboard module's keys: a black over the white under it", () {
    var r = const Rect.fromLTWH(0, 0, 160, 64);
    expect(synthKeyAt(r, const Offset(5, 60)), 60);
    expect(synthKeyAt(r, const Offset(20, 10)), 61);
    expect(synthKeyAt(r, const Offset(155, 60)), 72);
    expect(synthKeyAt(r, const Offset(5, 70)), isNull);
  });

  group("in the editor", () {
    test("the Synth chip's rack: one undo; its keyboard plays the speaker",
        () async {
      var engine = FakeEngine({});
      var c = CanvasController(page, audioEngine: engine);
      addTearDown(c.dispose);
      c.addSynthRack();
      var mods = c.document.elements.whereType<SynthModuleElement>().toList();
      expect(mods.length, 7);
      var speaker = mods.firstWhere((e) => e.module == SynthModuleKind.out);
      expect(c.selected?.id, speaker.id);
      var ch = c.synthChannel(speaker)!;
      expect(ch.visible, isFalse);
      expect(ch.instrument!.patch, isNotNull);
      var keys = mods.firstWhere((e) => e.module == SynthModuleKind.keys);
      c.synthKeyDown(keys, 64);
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(c.heldKeys(ch.id), {64});
      expect(engine.notes.last, (ch.id, 64, 100));
      expect(engine.parts.last.patch, isNotNull, reason: "played as patched");
      c.synthKeyUp(keys, 64);
      expect(c.heldKeys(ch.id), isEmpty);
      c.undo();
      expect(c.document.elements, isEmpty);
    });

    test("a keyboard patched to nothing plays nothing; a misfit won't plug",
        () async {
      var engine = FakeEngine({});
      var c = CanvasController(page, audioEngine: engine);
      addTearDown(c.dispose);
      c.addSynthRack();
      SynthModuleElement of(SynthModuleKind k) => c.document.elements
          .whereType<SynthModuleElement>()
          .firstWhere((e) => e.module == k);
      c.unplugSynth(of(SynthModuleKind.osc), "pitch");
      // The oscillator still drones through to the speaker, but the
      // keyboard reaches nothing.
      c.synthKeyDown(of(SynthModuleKind.keys), 60);
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(engine.notes, isEmpty);
      expect(
          c.plugSynth(
              of(SynthModuleKind.lfo), "lfo", of(SynthModuleKind.filter), "in"),
          isFalse);
      expect(
          c.plugSynth(of(SynthModuleKind.keys), "pitch",
              of(SynthModuleKind.osc), "pitch"),
          isTrue);
      c.resetAllSynths();
      expect(of(SynthModuleKind.osc).inputs["pitch"], isNotNull);
      c.lookAllSynths(SynthLook.digital);
      expect(
          c.document.elements
              .whereType<SynthModuleElement>()
              .every((e) => e.look == SynthLook.digital),
          isTrue);
    });
  });

  test("drawn: each look its own panel; cables over the modules", () async {
    var (doc, _) = rack();
    Future<ui.Image> draw(CanvasDocument d) async {
      var rec = ui.PictureRecorder();
      paintCanvasDocument(ui.Canvas(rec), d);
      return rec
          .endRecording()
          .toImage(d.size.width.round(), d.size.height.round());
    }

    var digital = doc.copyWith(elements: [
      for (var e in doc.elements)
        e is SynthModuleElement ? e.copyWith(look: SynthLook.digital) : e
    ]);
    var a = await draw(doc), d = await draw(digital);
    Future<Color> at(ui.Image img, Offset o) async {
      var raw = (await img.toByteData())!;
      var i = (o.dy.round() * img.width + o.dx.round()) * 4;
      return Color.fromARGB(raw.getUint8(i + 3), raw.getUint8(i),
          raw.getUint8(i + 1), raw.getUint8(i + 2));
    }

    // The oscillator's panel, just under its header: light grey analogue,
    // near black digital.
    var osc = doc.elements
        .whereType<SynthModuleElement>()
        .firstWhere((e) => e.module == SynthModuleKind.osc);
    var (s, top) = synthPanelFit(osc.bounds, synthPanelOf(osc.module));
    var probe = top + const Offset(4, 42) * s;
    expect((await at(a, probe)).computeLuminance(), greaterThan(0.5));
    expect((await at(d, probe)).computeLuminance(), lessThan(0.05));
    if (Platform.environment["SYNTH_PNG"] case var path?) {
      for (var (img, name) in [(a, "analogue"), (d, "digital")]) {
        var png = await img.toByteData(format: ui.ImageByteFormat.png);
        File(path.replaceFirst(".png", "_$name.png"))
            .writeAsBytesSync(png!.buffer.asUint8List());
      }
    }
  });

  group("on the stage, pressed without picking first", () {
    testWidgets("a key sounds while held; a knob turns, one undo",
        (tester) async {
      var engine = FakeEngine({});
      var c = CanvasController(page, audioEngine: engine);
      addTearDown(c.dispose);
      c.addSynthRack();
      c.clearSelection();
      var at = await staged(tester, c);
      var keys = of(c, SynthModuleKind.keys);
      var ch = c.synthChannel(of(c, SynthModuleKind.out))!;
      var white = synthPanelOf(SynthModuleKind.keys).keys!;
      var held = await tester
          .startGesture(at(on(keys, Offset(white.left + 3, white.bottom - 4))));
      await tester.pump();
      expect(c.heldKeys(ch.id), {60});
      expect(c.selection, {keys.id});
      await held.up();
      await tester.pump();
      expect(c.heldKeys(ch.id), isEmpty);

      var osc = of(c, SynthModuleKind.osc);
      var level = synthPanelOf(SynthModuleKind.osc).dials[2].center;
      var drag = await tester.startGesture(at(on(osc, level)));
      for (var i = 0; i < 6; i++) {
        await drag.moveBy(const Offset(0, 5));
        await tester.pump();
      }
      await drag.up();
      await tester.pump(const Duration(milliseconds: 400));
      var turned = of(c, SynthModuleKind.osc).value("level");
      expect(turned, lessThan(0.8), reason: "dragged down, turned down");
      expect(engine.patches.last.$2.byId(osc.id)!.value("level"), turned,
          reason: "sent live, for a note held as it turns");
      expect(of(c, SynthModuleKind.osc).base.y, osc.base.y,
          reason: "a knob turned, not the module moved");
      c.undo();
      expect(of(c, SynthModuleKind.osc).value("level"), 0.8,
          reason: "the whole turn one undo");
    });

    testWidgets("an option chosen; a locked module's stay", (tester) async {
      var c = CanvasController(page, audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.addSynthRack();
      var at = await staged(tester, c);
      var osc = of(c, SynthModuleKind.osc);
      var saw = synthPanelOf(SynthModuleKind.osc).options[2].center;
      await tester.tapAt(at(on(osc, saw)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(of(c, SynthModuleKind.osc).choice("wave"), "sawtooth");
      c.setSynth(of(c, SynthModuleKind.osc).copyWith(fixed: true));
      var sine = synthPanelOf(SynthModuleKind.osc).options[0].center;
      await tester.tapAt(at(on(osc, sine)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(of(c, SynthModuleKind.osc).choice("wave"), "sawtooth");
      // The look switch in its header.
      await tester
          .tapAt(at(on(osc, synthPanelOf(SynthModuleKind.osc).look.center)));
      await tester.pump(const Duration(milliseconds: 400));
      expect(of(c, SynthModuleKind.osc).look, SynthLook.digital);
    });

    testWidgets("a cable carried from jack to jack; pulled out; a misfit",
        (tester) async {
      var c = CanvasController(page, audioEngine: FakeEngine({}));
      addTearDown(c.dispose);
      c.addSynthRack();
      var at = await staged(tester, c);
      Future<void> carry(SynthModuleElement a, Offset from,
          SynthModuleElement? b, Offset to) async {
        var g = await tester.startGesture(at(on(a, from)));
        var end =
            b == null ? at(on(a, from)) + const Offset(0, 120) : at(on(b, to));
        for (var i = 1; i <= 5; i++) {
          await g.moveTo(Offset.lerp(at(on(a, from)), end, i / 5)!);
          await tester.pump();
        }
        await g.up();
        await tester.pump(const Duration(milliseconds: 400));
      }

      // The envelope into the amp's gain.
      var env = of(c, SynthModuleKind.env), amp = of(c, SynthModuleKind.amp);
      await carry(env, synthPanelOf(SynthModuleKind.env).outs["env"]!, amp,
          synthPanelOf(SynthModuleKind.amp).ins["gain"]!);
      expect(of(c, SynthModuleKind.amp).inputs["gain"],
          (module: env.id, port: "env"));
      // Pulled out of the oscillator's pitch and let go of: out.
      var osc = of(c, SynthModuleKind.osc);
      await carry(osc, synthPanelOf(SynthModuleKind.osc).ins["pitch"]!, null,
          Offset.zero);
      expect(of(c, SynthModuleKind.osc).inputs["pitch"], isNull);
      // An LFO is not sound: it won't go into the filter's input.
      var lfo = of(c, SynthModuleKind.lfo),
          filter = of(c, SynthModuleKind.filter);
      await carry(lfo, synthPanelOf(SynthModuleKind.lfo).outs["lfo"]!, filter,
          synthPanelOf(SynthModuleKind.filter).ins["in"]!);
      expect(of(c, SynthModuleKind.filter).inputs["in"], isNull);
      // ...but into its cutoff.
      await carry(lfo, synthPanelOf(SynthModuleKind.lfo).outs["lfo"]!, filter,
          synthPanelOf(SynthModuleKind.filter).ins["cutoff"]!);
      expect(of(c, SynthModuleKind.filter).inputs["cutoff"],
          (module: lfo.id, port: "lfo"));
    });
  });

  testWidgets("its settings: a slider, the lock, start, reset all, add",
      (tester) async {
    var c = CanvasController(page, audioEngine: FakeEngine({}));
    addTearDown(c.dispose);
    c.addSynthRack();
    c.selectOnly(of(c, SynthModuleKind.filter).id);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(providers(ListenableBuilder(
      listenable: c,
      builder: (context, _) => SingleChildScrollView(
        child: SizedBox(
          width: 320,
          child: CanvasControlScope(
            maxWidth: 280,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: elementSettings(context, c, c.selected!)),
          ),
        ),
      ),
    )));
    await tester.pump();
    Future<void> press(String key) async {
      var f = find.byKey(ValueKey(key));
      await tester.ensureVisible(f);
      await tester.tap(f);
      await tester.pump(const Duration(milliseconds: 300));
    }

    var slider = find.byKey(const ValueKey("synthKnob_cutoff"));
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(-200, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(of(c, SynthModuleKind.filter).value("cutoff"), lessThan(6000));
    await press("synthLock");
    expect(of(c, SynthModuleKind.filter).fixed, isTrue);
    await press("synthSetStart");
    expect(of(c, SynthModuleKind.filter).changed, isFalse);
    c.setSynth(of(c, SynthModuleKind.filter).withValue("res", 9));
    await tester.pump();
    await press("synthResetAll");
    expect(of(c, SynthModuleKind.filter).value("res"), 1);
    await press("synthAll_digital");
    expect(
        c.document.elements
            .whereType<SynthModuleElement>()
            .every((e) => e.look == SynthLook.digital),
        isTrue);
  });
}
