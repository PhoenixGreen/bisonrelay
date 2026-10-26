import 'dart:ui';

import 'package:bruig/plugin_system/canvas/model/elements/character_cast.dart';
import 'package:bruig/plugin_system/canvas/model/elements/character_element.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_painter.dart';
import 'package:bruig/plugin_system/canvas/render/character/character_rig.dart';
import 'package:bruig/plugin_system/canvas/render/model/mannequin.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_character_appearance_test.dart is the character's Appearance --
// the body and face as numbers -- and its type: what is kept, that every
// control changes what is drawn, and what a type starts as.

Future<List<int>> _draw(CharacterDna dna, {bool head = false}) async {
  var rec = PictureRecorder();
  var c = Canvas(rec);
  // The whole figure, or the head close up, where a nostril is a pixel.
  var box = head
      ? Rect.fromLTWH(200 - 250 * 0.5, 20, 500, 500 * dna.headsTall * 0.5)
      : const Rect.fromLTWH(60, 20, 180, 400);
  if (head) box = Rect.fromLTWH(150 - box.height / 4, 20, box.height / 2, box.height);
  paintCharacterFigure(c, box, dna, CharacterElement.restPose);
  var img = await rec.endRecording().toImage(300, 440);
  return (await img.toByteData())!.buffer.asUint8List();
}

void main() {
  group("the numbers", () {
    test("only what is set away from rest is kept, within its range", () {
      var a = Appearance.rest
          .withValue(Look.jaw, 0.5)
          .withValue(Look.freckles, -1)
          .withValue(Look.eyeSize, 3);
      expect(a[Look.jaw], 0.5);
      expect(a[Look.freckles], 0, reason: "an amount is never less than none");
      expect(a[Look.eyeSize], 1);
      expect(a.withValue(Look.jaw, 0).values, isNot(contains(Look.jaw)));
      expect(Appearance.fromJson(a.toJson()), a);
    });

    test("a character keeps its look, its highlights and its type", () {
      var dna = CharacterType.woman.dna.copyWith(
          look: CharacterType.woman.dna.look.withValue(Look.nostrils, 0.5),
          hair2: const Color(0xFF123456));
      var back = CharacterDna.fromJson(dna.toJson());
      expect(back.look, dna.look);
      expect(back.hair2, dna.hair2);
      expect(back.type, CharacterType.woman);
      expect(const CharacterDna().toJson().containsKey("look"), isFalse);
    });

    test("a character saved before types is told by its size and species", () {
      expect(characterCast.first.dna.copyWith().kind, CharacterType.man);
      expect(const CharacterDna(headsTall: 4, hairStyle: HairStyle.long).kind,
          CharacterType.girl);
      expect(const CharacterDna(species: Species.dog).kind, CharacterType.dog);
      expect(const CharacterDna(species: Species.monster, wings: WingKind.bat).kind,
          CharacterType.dragon);
    });
  });

  group("types", () {
    test("each is its own type, and draws", () async {
      for (var t in CharacterType.values) {
        expect(t.dna.kind, t);
        expect(await _draw(t.dna), isNotEmpty);
      }
    });

    test("one person made another keeps their colours and clothes", () {
      var woman = CharacterType.woman.dna.copyWith(skin: const Color(0xFF6B4029));
      var girl = CharacterType.girl.becomes(woman);
      expect(girl.kind, CharacterType.girl);
      expect(girl.skin, woman.skin);
      expect(girl.wardrobe, woman.wardrobe);
      expect(girl.headsTall, CharacterType.girl.dna.headsTall);
      var dog = CharacterType.dog.becomes(woman);
      expect(dog.species, Species.dog);
      expect(dog.wardrobe, isEmpty, reason: "a dog starts as a dog");
    });
  });

  group("every control changes what is drawn", () {
    for (var l in Look.values) {
      test("${l.label} (${l.group.label})", () async {
        var man = CharacterType.man.dna;
        // A control that shapes another is tried with that one set.
        if (l.needs case var n?) {
          man = man.copyWith(look: man.look.withValue(n, 0.8));
        }
        var face = l.group != AppearanceGroup.body;
        var plain = await _draw(man, head: face);
        var changed = await _draw(
            man.copyWith(look: man.look.withValue(l, l.oneSided ? 1 : -1)),
            head: face);
        var other = await _draw(
            man.copyWith(look: man.look.withValue(l, 1)),
            head: face);
        expect(changed == plain && other == plain, isFalse,
            reason: "${l.name} draws nothing different");
        expect(other, isNot(plain), reason: "${l.name} at its top");
      });
    }
  });

  group("the body", () {
    var box = const Rect.fromLTWH(0, 0, 200, 400);
    CharacterRig rig(Appearance a) => CharacterRig.of(
        CharacterType.man.dna.copyWith(look: a), CharacterElement.restPose, box);

    test("longer legs keep the feet down and the head up", () {
      var plain = rig(Appearance.rest);
      var long = rig(const Appearance({Look.legLength: 1}));
      expect(long.thigh, greaterThan(plain.thigh));
      expect(long.ankleL.dy, closeTo(plain.ankleL.dy, 0.5));
      expect(long.headCentre.dy, closeTo(plain.headCentre.dy, 0.5));
      expect(long.hips.dy, lessThan(plain.hips.dy));
    });

    test("shoulders, hips and limbs go where they say", () {
      var plain = rig(Appearance.rest);
      expect(rig(const Appearance({Look.shoulders: 1})).shoulderHalf,
          greaterThan(plain.shoulderHalf));
      expect(rig(const Appearance({Look.hips: -1})).hipHalf,
          lessThan(plain.hipHalf));
      expect(rig(const Appearance({Look.armWidth: 1})).limbWidth,
          greaterThan(plain.limbWidth));
      expect(rig(const Appearance({Look.armLength: 1})).upperArm,
          greaterThan(plain.upperArm));
      expect(rig(const Appearance({Look.headWidth: 1})).headRadii.width,
          greaterThan(plain.headRadii.width));
    });

    test("the mannequin is shaped by the same numbers", () {
      var plain = mannequinPieces(rig(Appearance.rest), CharacterType.man.dna,
          CharacterFace.rest);
      var dna = CharacterType.man.dna.copyWith(
          look: const Appearance({Look.belly: 1, Look.beard: 1}));
      var round = mannequinPieces(
          CharacterRig.of(dna, CharacterElement.restPose, box), dna,
          CharacterFace.rest);
      expect(round.length, greaterThan(plain.length), reason: "a beard");
    });
  });

  group("styles", () {
    test("every family has styles, and every style a family", () {
      for (var f in StyleFamily.values) {
        expect(CharacterStyle.inFamily(f), isNotEmpty, reason: f.label);
      }
      expect(StyleFamily.values.expand(CharacterStyle.inFamily).toSet(),
          CharacterStyle.values.toSet());
    });

    test("a style leans the face, on top of the person's own", () {
      var dna = CharacterType.woman.dna;
      var shojo = CharacterStyle.shojo.dnaOf(dna);
      expect(shojo.look[Look.eyeSize],
          closeTo(dna.look[Look.eyeSize] + CharacterStyle.shojo.bias[Look.eyeSize], 1e-9));
      expect(CharacterStyle.chibi.dnaOf(dna).headsTall, lessThanOrEqualTo(2.6));
      expect(CharacterStyle.webtoon.dnaOf(dna).headsTall, greaterThan(dna.headsTall));
    }, skip: false);

    test("every style draws the same person differently", () async {
      var dna = CharacterType.woman.dna;
      var seen = <String, String>{};
      for (var st in CharacterStyle.values) {
        var rec = PictureRecorder();
        paintCharacterFigure(Canvas(rec), const Rect.fromLTWH(20, 20, 200, 400),
            dna, CharacterElement.restPose, style: st);
        var img = await rec.endRecording().toImage(240, 440);
        var bytes = (await img.toByteData())!.buffer.asUint8List();
        var key = Object.hashAll(bytes).toString();
        expect(seen[key], isNull, reason: "${st.label} draws as ${seen[key]}");
        seen[key] = st.label;
      }
    });
  });
}
