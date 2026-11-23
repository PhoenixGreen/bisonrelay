import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/motion_devices.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';

// canvas_text_style_link_test.dart is which texts and counters a named
// style's change reaches: those whose type is still the style's, and not
// one whose type was changed by hand.

const _red = Color(0xFFFF0000);
const _heading = TextSpec(fontSize: 30);

TextElement _text(String id, TextSpec spec, {String style = "Heading"}) =>
    TextElement(ElementBase(id: id, width: 400, height: 200),
        text: id, style: style, textSpec: spec);

TextSpec _specOf(CanvasController c, String id) =>
    (c.document.elementById(id) as TextElement).textSpec;

void main() {
  test("a styled text saved and read back still follows its style", () {
    // The style's glow is lifted off the text's type into a look when the
    // canvas is read, and stays in the style's own: the two still match.
    const glowing = TextSpec(fontSize: 30, glowBlur: 6, glowColor: _red);
    var doc = CanvasDocument(
        textStyles: const [NamedTextStyle("Heading", glowing)],
        elements: [_text("t", glowing)]);
    var read = CanvasDocument.fromJson(
        jsonDecode(jsonEncode(doc.toJson())) as Map<String, dynamic>);
    var back = CanvasController(read);
    addTearDown(back.dispose);
    expect(_specOf(back, "t").glowBlur, 0,
        reason: "read as a look on the words");

    back.updateTextStyle("Heading", glowing.copyWith(fontSize: 44));
    expect(_specOf(back, "t").fontSize, 44);
    var glows = (back.document.elementById("t") as TextElement)
        .base
        .motion
        .devices
        .where((d) => d.kind == MotionDeviceKind.glow);
    expect(glows, hasLength(1), reason: "its glow set again, not doubled");
  });

  test("a text painted by hand with a picture is its own", () {
    // Its fill is part of its type, so the style leaves it alone.
    var painted = _heading.copyWith(
        fill: const TextFill(kind: TextFillKind.image, assetId: "p"));
    var c = CanvasController(CanvasDocument(
        textStyles: const [NamedTextStyle("Heading", _heading)],
        elements: [_text("painted", painted), _text("plain", _heading)]));
    addTearDown(c.dispose);
    c.updateTextStyle("Heading", _heading.copyWith(fontSize: 60));
    expect(_specOf(c, "plain").fontSize, 60);
    expect(_specOf(c, "painted").fontSize, 30);
    expect(_specOf(c, "painted").fill.assetId, "p");
  });

  test("replacing a colour everywhere keeps text and style together", () {
    // It changes the named styles as well as the texts, so the next change
    // to the style still reaches the text.
    var c = CanvasController(CanvasDocument(
        textStyles: const [NamedTextStyle("Heading", _heading)],
        elements: [_text("t", _heading)]));
    addTearDown(c.dispose);
    c.replaceColour(const Color(0xFFFFFFFF), _red);
    expect(_specOf(c, "t").color, _red);
    expect(c.textStyles.single.spec.color, _red);
    c.updateTextStyle(
        "Heading", c.textStyles.single.spec.copyWith(weight: 800));
    expect(_specOf(c, "t").weight, 800);
  });

  test("a counter whose figures were changed by hand is left alone", () {
    const figures = TextSpec(fontFamily: "RobotoMono", fontSize: 96);
    CounterElement counter(String id, TextSpec spec) =>
        CounterElement(ElementBase(id: id), from: 0, to: 300)
            .copyWith(numberSpec: spec, numberStyle: "Figures");
    var c = CanvasController(CanvasDocument(textStyles: const [
      NamedTextStyle("Figures", figures)
    ], elements: [
      counter("edited", figures.copyWith(fontSize: 120)),
      counter("follows", figures),
      counter("source", figures.copyWith(color: _red)),
    ]));
    addTearDown(c.dispose);
    CounterElement get(String id) =>
        c.document.elementById(id) as CounterElement;

    c.updateTextStyle("Figures", get("source").numberSpec);
    expect(get("follows").numberSpec.color, _red);
    expect(get("edited").numberSpec.color, const Color(0xFFFFFFFF));
    expect(get("edited").numberSpec.fontSize, 120);
    expect(get("edited").numberStyle, "Figures", reason: "still linked");
  });

  test("a new style is the next Style N free, for texts and counters", () {
    var c = CanvasController(CanvasDocument(textStyles: const [
      NamedTextStyle("Style 2", _heading)
    ], elements: [
      _text("t", _heading, style: ""),
      CounterElement(const ElementBase(id: "n"), from: 0, to: 9),
    ]));
    addTearDown(c.dispose);
    expect(
        c.saveTextStyle(c.document.elementById("t") as TextElement), "Style 3");
    expect(c.saveCounterStyle(c.document.elementById("n") as CounterElement),
        "Style 4");
    expect(
        c.saveTextStyle(c.document.elementById("t") as TextElement,
            name: "Style 2"),
        "Style 5",
        reason: "a name already taken is not used twice");
  });
}
