import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

// kept_pictures.dart is how the picture tests keep what is drawn and compare
// it with what was kept, to the byte. The environment variable a test names
// points at a folder: a state with nothing kept there yet is written (its
// picture as <state>.rgba and <state>.png, and its numbers as <state>.txt
// where it has any); a state already kept is compared, and a difference
// fails saying how many pixels changed and where, leaving what is drawn now
// beside the kept one as <state>.new.png. With the variable unset nothing is
// kept, so a picture test is harmless in the whole suite.

/// imageBytes is [image]'s pixels as raw RGBA and as a PNG. The image is
/// disposed of once read.
Future<(Uint8List raw, Uint8List png)> imageBytes(ui.Image image) async {
  var raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
      .buffer
      .asUint8List();
  var png = (await image.toByteData(format: ui.ImageByteFormat.png))!
      .buffer
      .asUint8List();
  image.dispose();
  return (raw, png);
}

/// keepOrCompare keeps [raw] (with [png] to look at, and [numbers] where
/// given) as [name] in the folder [variable] names, or compares them with
/// what is kept there. [width] is the picture's width in pixels, for saying
/// where a difference is. The picture is compared before the numbers, so a
/// change that moves both says what it drew.
void keepOrCompare(String variable, String name,
    {required Uint8List raw,
    required Uint8List png,
    required int width,
    String? numbers}) {
  var dir = Platform.environment[variable];
  if (dir == null || dir.isEmpty) return;
  Directory(dir).createSync(recursive: true);
  var kept = File("$dir/$name.rgba");
  var keptNumbers = File("$dir/$name.txt");
  if (!kept.existsSync()) {
    kept.writeAsBytesSync(raw);
    File("$dir/$name.png").writeAsBytesSync(png);
    if (numbers != null) keptNumbers.writeAsStringSync(numbers);
    return;
  }
  var fresh = File("$dir/$name.new.png");
  if (fresh.existsSync()) fresh.deleteSync();
  var was = kept.readAsBytesSync();
  if (!_sameBytes(was, raw)) {
    fresh.writeAsBytesSync(png);
    var changed = 0;
    int? left, top, right, bottom;
    for (var i = 0; i < raw.length && i < was.length; i += 4) {
      if (raw[i] == was[i] &&
          raw[i + 1] == was[i + 1] &&
          raw[i + 2] == was[i + 2] &&
          raw[i + 3] == was[i + 3]) {
        continue;
      }
      changed++;
      var x = (i ~/ 4) % width, y = (i ~/ 4) ~/ width;
      left = left == null || x < left ? x : left;
      right = right == null || x > right ? x : right;
      top = top == null || y < top ? y : top;
      bottom = bottom == null || y > bottom ? y : bottom;
    }
    fail("$name: $changed pixels differ, within x $left..$right, "
        "y $top..$bottom (see $name.new.png)");
  }
  if (numbers != null) {
    expect(numbers, keptNumbers.readAsStringSync(), reason: name);
  }
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
