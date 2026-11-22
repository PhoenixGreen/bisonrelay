import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import 'package:bruig/plugin_system/canvas/storage/canvas_assets.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_library.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_media.dart';
import 'package:bruig/plugin_system/canvas/storage/canvas_storage.dart';
import 'package:bruig/plugin_system/canvas/storage/picture_import.dart';
import 'package:bruig/plugin_system/canvas/ui/picking/image_picking.dart';

import 'support/png_fixture.dart';

// canvas_picture_import_test.dart is the one way a picture or a drawing
// comes into the library, against real files: what it is is read from the
// bytes, not the name; what cannot be kept is refused in words that say
// why; and a script's drawing alone is held to the stricter rule.

const _svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
    '<circle cx="5" cy="5" r="4"/></svg>';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

/// _Picker answers every pick with one file, as a person choosing it would.
class _Picker extends FilePicker {
  final String file;
  _Picker(this.file);

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      FilePickerResult([
        PlatformFile(
            path: file,
            name: path.basename(file),
            size: File(file).lengthSync()),
      ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp("canvas_picture_import");
    CanvasStorage.rootOverride = root.path;
    CanvasLibrary.resetForTest();
  });

  tearDown(() async {
    CanvasStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  test("a PNG is kept as a picture, named and measured", () async {
    var (:asset, :problem) = await importPicture(pngOf(30, 20), name: "Fox");
    expect(problem, isNull);
    expect(asset!.kind, AssetKind.picture);
    expect(asset.name, "Fox");
    expect((asset.width, asset.height), (30, 20));
    expect(await CanvasAssets.exists(asset.id), isTrue);
    expect((await CanvasLibrary.byId(asset.id))?.name, "Fox");
  });

  test("an SVG is a drawing by what it holds, not by its name", () async {
    var drawn = await importPicture(_bytes(_svg), name: "badge.png");
    expect(drawn.asset!.kind, AssetKind.vector);
    expect(await CanvasMedia.existingPath(MediaKind.vector, drawn.asset!.id),
        isNotNull);

    // A picture called a drawing is still a picture...
    var named = await importPicture(pngOf(4, 4), name: "logo.svg");
    expect(named.asset!.kind, AssetKind.picture);
    // ...and where only a drawing will do, it is refused.
    var only =
        await importPicture(pngOf(4, 4), name: "logo.svg", drawingOnly: true);
    expect(only.asset, isNull);
    expect(only.problem, contains("logo.svg is not a drawing"));
    // Text that is no drawing, called one, is no drawing either.
    var text = await importPicture(_bytes("just words"), name: "notes.svg");
    expect(text.asset, isNull);
    expect(await CanvasLibrary.list(kind: AssetKind.vector), hasLength(1));
  });

  test("what is no picture at all is refused, and not as too large", () async {
    var (:asset, :problem) = await importPicture(
        Uint8List.fromList(List.generate(200, (i) => i % 7)),
        name: "Mystery");
    expect(asset, isNull);
    expect(problem, contains("Mystery"));
    expect(problem, contains("not a picture or drawing"));
    expect(problem, isNot(contains("too large")));
    expect(await CanvasLibrary.list(), isEmpty);
  });

  test("a picture and a drawing past their limits are each too large",
      () async {
    var huge = Uint8List(maxAssetBytes + 1)
      ..setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    var picture = await importPicture(huge, name: "Panorama");
    expect(picture.asset, isNull);
    expect(picture.problem, contains("Panorama is too large"));
    expect(picture.problem, contains("${maxAssetBytes >> 20} MB"));

    var drawing = Uint8List(MediaKind.vector.maxBytes + 1)
      ..fillRange(0, MediaKind.vector.maxBytes + 1, 0x20)
      ..setAll(0, utf8.encode("<svg>"));
    var big = await importPicture(drawing, name: "Map");
    expect(big.asset, isNull);
    expect(big.problem, contains("Map is too large"));
    expect(big.problem, contains("${MediaKind.vector.maxBytes >> 20} MB"));
    expect(await CanvasLibrary.list(), isEmpty);
  });

  test("strict refuses scripts, embedded pages and outside links", () async {
    var reaching = [
      '<svg><script>alert(1)</script></svg>',
      '<svg><foreignObject><p>Hi</p></foreignObject></svg>',
      '<svg><image href="https://example.com/x.png"/></svg>',
    ];
    for (var svg in reaching) {
      var held = await importPicture(_bytes(svg), name: "x", strict: true);
      expect(held.asset, isNull, reason: svg);
      expect(held.problem, contains("outside"), reason: svg);
    }
    // A person's file and a stock icon are kept as they come.
    for (var svg in reaching) {
      var kept = await importPicture(_bytes(svg), name: "x");
      expect(kept.asset?.kind, AssetKind.vector, reason: svg);
    }
  });

  test("the credit given is on the asset", () async {
    var (:asset, :problem) = await importPicture(pngOf(8, 8),
        name: "Red fox",
        author: "Ann",
        license: "CC0",
        origin: "https://example.com/fox",
        from: "Example");
    expect(problem, isNull);
    expect(asset!.author, "Ann");
    expect(asset.license, "CC0");
    expect(asset.origin, "https://example.com/fox");
    expect(asset.from, "Example");
    expect((await CanvasLibrary.byId(asset.id))!.credited, isTrue);
  });

  testWidgets("a drawing chosen as a .png file is kept as a drawing",
      (tester) async {
    var file = File(path.join(root.path, "drawing.png"));
    await tester.runAsync(() => file.writeAsString(_svg));
    FilePicker.platform = _Picker(file.path);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    var context = tester.element(find.byType(SizedBox));
    var id = await tester.runAsync(() => pickCanvasImage(context));

    expect(id, endsWith(".svg"));
    var asset = await tester.runAsync(() => CanvasLibrary.byId(id!));
    expect(asset!.kind, AssetKind.vector);
    expect(asset.name, "drawing");
  });
}
