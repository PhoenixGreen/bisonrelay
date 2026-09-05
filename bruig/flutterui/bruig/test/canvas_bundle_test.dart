import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bruig/plugin_system/canvas/export/canvas_bundle.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// canvas_bundle_test.dart is about a canvas surviving the journey to somebody
// else's machine.
//
// The failure this exists to prevent is quiet: the document travels perfectly
// well on its own, opens, and is missing every photograph -- because the ids
// in it point at a picture store the sender has and the reader does not. So
// what is checked here is not that a zip can be written, but that what comes
// out the far end refers to pictures that are actually there.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp("canvas_bundle_test");
    CanvasStorage.rootOverride = root.path;
  });

  tearDown(() async {
    CanvasStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  /// A tiny PNG, so the store sniffs a real extension onto the id.
  Uint8List png(int seed) => Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
        ...List.filled(40, seed),
      ]);

  CanvasDocument withPictures(List<String> ids) => CanvasDocument(
        title: "Match plan",
        elements: [
          for (var (i, id) in ids.indexed)
            ImageElement(
              ElementBase(id: "e$i", width: 100, height: 100),
              assetId: id,
            ),
        ],
      );

  test("a canvas comes back with its pictures", () async {
    var first = (await CanvasAssets.save(png(1)))!;
    var second = (await CanvasAssets.save(png(2)))!;
    var document = withPictures([first, second]);

    var packed = await packCanvas(document);
    expect(looksLikeBundle(packed), isTrue);

    var back = (await unpackCanvas(packed))!;
    expect(back.document.title, "Match plan");
    expect(back.pictures.keys.toSet(), {first, second});
    expect(back.pictures[first], png(1));

    // The ids in the document still name the pictures in the bundle, which is
    // the whole point -- a bundle whose ids had been renamed on the way
    // through would open to the same grey placeholders as no bundle at all.
    expect(back.document.assetIds, back.pictures.keys.toSet());
  });

  test("the pictures land in the store under the ids the document uses",
      () async {
    var id = (await CanvasAssets.save(png(3)))!;
    var packed = await packCanvas(withPictures([id]));

    // A reader's machine: the same library, with nothing in the store. The
    // sweep takes every picture no saved canvas refers to, and nothing here
    // has been saved.
    await CanvasAssets.sweepUnused();
    expect(await CanvasAssets.load(id), isNull);

    var bundle = (await unpackCanvas(packed))!;
    expect(await storeBundlePictures(bundle), 1);
    expect(await CanvasAssets.load(id), png(3),
        reason: "the element's assetId now finds something");
  });

  test("a plain canvas file still opens", () async {
    // Both forms are saved under .bcanvas on purpose, so whatever opens one
    // has to take either without being told which.
    var document = const CanvasDocument(title: "No pictures here");
    var bytes = utf8.encode(document.encode());
    expect(looksLikeBundle(bytes), isFalse);

    var back = (await unpackCanvas(bytes))!;
    expect(back.document.title, "No pictures here");
    expect(back.pictures, isEmpty);
  });

  test("a canvas with no pictures needs no bundle", () async {
    var packed = await packCanvas(const CanvasDocument(title: "Bare"));
    var back = (await unpackCanvas(packed))!;
    expect(back.pictures, isEmpty);
    expect(back.document.title, "Bare");
  });

  test("a missing picture costs its own element and not the canvas", () async {
    var kept = (await CanvasAssets.save(png(4)))!;
    var document = withPictures([kept, "0123456789abcdef.png"]);

    var back = (await unpackCanvas(await packCanvas(document)))!;
    expect(back.pictures.keys, [kept]);
    expect(back.document.elements.length, 2,
        reason: "the canvas is exported as it stands, holes and all");
  });

  test("neither rubbish nor an empty zip is taken for a canvas", () async {
    expect(await unpackCanvas(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
    expect(await unpackCanvas(utf8.encode("{not json at all")), isNull);
    // A zip with no canvas.json in it: the right shape, the wrong contents.
    var stripped = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0]);
    expect(await unpackCanvas(stripped), isNull);
  });

  test("a bundle cannot write outside the picture store", () async {
    // The name in an archive is text from somebody else's machine. Only the
    // last segment is taken, and CanvasAssets.saveAs checks it again before it
    // becomes a path -- so an entry called "pictures/../../evil" stores
    // nothing rather than something somewhere else.
    var id = (await CanvasAssets.save(png(5)))!;
    var bundle = (await unpackCanvas(await packCanvas(withPictures([id]))))!;

    var hostile = CanvasBundle(bundle.document, {
      "../../evil.png": png(6),
      "/etc/passwd": png(7),
      "..": png(8),
    });
    expect(await storeBundlePictures(hostile), 0);
    expect(await File("${root.path}/evil.png").exists(), isFalse);
  });
}
