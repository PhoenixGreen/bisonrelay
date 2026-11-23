import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:bruig/plugin_system/canvas/model/elements/arrival.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/element_loop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';

// canvas_arrival_saved_form_test.dart pins how the three arrivals (an
// element's, a text's, a part of a text's) are written into a saved canvas:
// every setting away from its default, each type at its default, and the
// cutting effect, which is written only where a cutting preset is chosen.
// A canvas saved before must read back to the same thing, so the strings are
// the saved form itself, key order and all; a change to how the arrivals are
// built must leave every one of them alone.

const _loop = ElementLoop(
    preset: LoopPreset.pulse, cycle: 30, strength: 1.5, from: 4, to: 90);
const _effect =
    EffectSpec(pieces: 14, scatter: 0.6, spin: 0.25, stagger: 0.4, seed: 7);
const _draw = TextDrawSpec(
    color: Color(0xFF336699),
    start: TextDrawStart.fadeText,
    padLeft: 3,
    padTop: 4,
    padRight: 5,
    padBottom: 6,
    radius: 2);
const _echo = TextEchoSpec(
    copies: 6, spacing: 1.5, fade: 0.7, shrink: 0.8, resolve: true);

/// _forms is each arrival with what it saves as, and how to read it back.
List<(String, Map<String, dynamic>, Map<String, dynamic> Function(String))>
    _forms() {
  Map<String, dynamic> element(String s) =>
      ElementAnimation.fromJson(jsonDecode(s) as Map<String, dynamic>).toJson();
  Map<String, dynamic> text(String s) =>
      TextAnimation.fromJson(jsonDecode(s) as Map<String, dynamic>).toJson();
  Map<String, dynamic> part(String s) =>
      TextPartAnimation.fromJson(jsonDecode(s) as Map<String, dynamic>)
          .toJson();

  return [
    ("element at its default", const ElementAnimation().toJson(), element),
    (
      "element, every setting",
      const ElementAnimation(
        preset: ElementAnimationPreset.slideLeft,
        exit: ElementAnimationPreset.pop,
        scale: 1.7,
        effect: _effect,
        ease: ChartEase.bounce,
        length: 30,
        loop: _loop,
        direction: AnimationDirection.belowRight,
        strength: 1.4,
        exitDirection: AnimationDirection.above,
        exitStrength: 0.6,
      ).toJson(),
      element
    ),
    (
      "element, cutting",
      const ElementAnimation(
        preset: ElementAnimationPreset.shatter,
        effect: _effect,
        ease: ChartEase.linear,
      ).toJson(),
      element
    ),
    (
      "element, cutting on the way out only",
      const ElementAnimation(
        exit: ElementAnimationPreset.mosaic,
        effect: _effect,
      ).toJson(),
      element
    ),
    ("text at its default", const TextAnimation().toJson(), text),
    (
      "text, every setting",
      const TextAnimation(
        preset: TextAnimationPreset.trailWords,
        exit: TextAnimationPreset.echoBoth,
        exitInOrder: true,
        gap: 0.8,
        scale: 2.5,
        draw: _draw,
        echo: _echo,
        effect: _effect,
        ease: ChartEase.overshoot,
        length: 48,
        flipOrder: true,
        direction: AnimationDirection.aboveLeft,
        strength: 2,
        exitDirection: AnimationDirection.right,
        exitStrength: 0.5,
        loop: _loop,
        piecesInTurn: true,
        piecesGap: 0.25,
      ).toJson(),
      text
    ),
    (
      "text, cutting",
      const TextAnimation(
        preset: TextAnimationPreset.assemble,
        exit: TextAnimationPreset.glitch,
        effect: _effect,
      ).toJson(),
      text
    ),
    ("part at its default", const TextPartAnimation().toJson(), part),
    (
      "part, every setting",
      const TextPartAnimation(
        arrival: TextAnimation(
          preset: TextAnimationPreset.echoWords,
          gap: 0.9,
          scale: 1.3,
          echo: _echo,
          draw: _draw,
          ease: ChartEase.spring,
          effect: _effect,
        ),
        offset: -6,
        length: 18,
        marks: true,
        markOffset: 12,
        markLength: 20,
      ).toJson(),
      part
    ),
    (
      "part, cutting",
      const TextPartAnimation(
        arrival:
            TextAnimation(preset: TextAnimationPreset.shatter, effect: _effect),
      ).toJson(),
      part
    ),
  ];
}

/// _saved is each of [_forms] as a canvas has it on disk.
const _saved = <String, String>{
  "element at its default": r'{"ease":"easeOut"}',
  "element, every setting": r'{"preset":"slideLeft","exit":"pop",'
      r'"scale":1.7,"ease":"bounce","length":30,"loop":{"preset":"pulse",'
      r'"cycle":30,"strength":1.5,"from":4,"to":90},'
      r'"direction":"belowRight","strength":1.4,"exitDirection":"above",'
      r'"exitStrength":0.6}',
  "element, cutting": r'{"preset":"shatter","effect":{"pieces":14,'
      r'"scatter":0.6,"spin":0.25,"stagger":0.4,"seed":7},"ease":"linear"}',
  "element, cutting on the way out only": r'{"exit":"mosaic",'
      r'"effect":{"pieces":14,"scatter":0.6,"spin":0.25,"stagger":0.4,'
      r'"seed":7},"ease":"easeOut"}',
  "text at its default": r'{"preset":"none","gap":0.35,"ease":"easeOut"}',
  "text, every setting": r'{"preset":"trailWords","exit":"echoBoth",'
      r'"exitOrder":true,"gap":0.8,"scale":2.5,"draw":{"color":4281558681,'
      r'"start":"fadeText","l":3.0,"t":4.0,"r":5.0,"b":6.0,"radius":2.0},'
      r'"echo":{"copies":6,"spacing":1.5,"fade":0.7,"shrink":0.8,'
      r'"resolve":true},"ease":"overshoot","length":48,'
      r'"direction":"aboveLeft","strength":2.0,"exitDirection":"right",'
      r'"exitStrength":0.5,"loop":{"preset":"pulse","cycle":30,'
      r'"strength":1.5,"from":4,"to":90},"piecesInTurn":true,'
      r'"piecesGap":0.25}',
  "text, cutting": r'{"preset":"assemble","exit":"glitch","gap":0.35,'
      r'"effect":{"pieces":14,"scatter":0.6,"spin":0.25,"stagger":0.4,'
      r'"seed":7},"ease":"easeOut"}',
  "part at its default": r'{}',
  "part, every setting": r'{"preset":"echoWords","offset":-6,"length":18,'
      r'"gap":0.9,"scale":1.3,"echo":{"copies":6,"spacing":1.5,"fade":0.7,'
      r'"shrink":0.8,"resolve":true},"draw":{"color":4281558681,'
      r'"start":"fadeText","l":3.0,"t":4.0,"r":5.0,"b":6.0,"radius":2.0},'
      r'"ease":"spring","effect":{"pieces":14,"scatter":0.6,"spin":0.25,'
      r'"stagger":0.4,"seed":7},"marks":true,"markOffset":12,'
      r'"markLength":20}',
  "part, cutting": r'{"preset":"shatter","effect":{"pieces":14,'
      r'"scatter":0.6,"spin":0.25,"stagger":0.4,"seed":7}}',
};

void main() {
  test("every arrival has its saved form written down", () {
    expect({for (var (name, _, _) in _forms()) name}, _saved.keys.toSet());
  });
  for (var (name, json, back) in _forms()) {
    test("$name is saved as it was, and reads back to the same", () {
      var written = jsonEncode(json);
      expect(written, _saved[name], reason: "the saved form changed");
      expect(jsonEncode(back(written)), written,
          reason: "reading it back and writing it again changed it");
    });
  }
}
