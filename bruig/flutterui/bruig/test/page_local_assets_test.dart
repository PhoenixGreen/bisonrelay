import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bruig/components/feed/markdown_header.dart';
import 'package:bruig/components/feed/page_image.dart';
import 'package:bruig/models/pages.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'png_fixture.dart';

// page_local_assets_test.dart covers a page being shown to the person
// writing it.
//
// A page fetched from a site gets its pictures over the wire, and that is
// the case PageImage was built for. The preview in Writing is the same
// markdown with nowhere to fetch from: it is this site's own page, and the
// pictures are files already on this disk. It used to draw the alt text
// instead -- so the picture was fine, and only the person choosing it could
// not see it, which is the half that matters while writing.

class _FakePages extends PagesModel {
  _FakePages() : super(ResourcesModel(runStream: false));

  final Map<String, Uint8List> files = {};
  final List<String> asked = [];
  Completer<void>? hold;

  @override
  Future<Uint8List> readAsset(String path) async {
    asked.add(path);
    if (hold != null) await hold!.future;
    var have = files[path];
    if (have == null) throw "no such file";
    return have;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final banner = pngOf(40, 20);

  group('reading this site own pictures', () {
    test('a picture is read once, however often it is asked for', () async {
      // Every rebuild asks. Reading the file each time would be the disk hit
      // on every frame of a scroll.
      var pages = _FakePages()..files["assets/banner.png"] = banner;

      expect(pages.localAssetBytes("assets/banner.png"), isNull,
          reason: "not there yet on the first ask");
      await Future<void>.delayed(Duration.zero);
      expect(pages.localAssetBytes("assets/banner.png"), banner);
      pages.localAssetBytes("assets/banner.png");
      pages.localAssetBytes("assets/banner.png");

      expect(pages.asked, ["assets/banner.png"]);
    });

    test('listeners are told when it arrives', () async {
      var pages = _FakePages()..files["assets/banner.png"] = banner;
      var told = 0;
      pages.addListener(() => told++);

      pages.localAssetBytes("assets/banner.png");
      await Future<void>.delayed(Duration.zero);

      expect(told, greaterThan(0),
          reason: "nothing would redraw, so the picture would never appear");
    });

    test('a second ask while the first is still going does not read twice',
        () async {
      var pages = _FakePages()
        ..files["assets/banner.png"] = banner
        ..hold = Completer<void>();

      pages.localAssetBytes("assets/banner.png");
      pages.localAssetBytes("assets/banner.png");
      pages.hold!.complete();
      await Future<void>.delayed(Duration.zero);

      expect(pages.asked, hasLength(1));
    });

    test('a file that is not there is not asked for again', () async {
      // Otherwise a page naming a deleted picture reads the disk forever.
      var pages = _FakePages();

      pages.localAssetBytes("assets/gone.png");
      await Future<void>.delayed(Duration.zero);
      // Nothing, remembered as nothing -- which is what stops the next
      // build asking again.
      expect(pages.localAssetBytes("assets/gone.png"), isEmpty);
      await Future<void>.delayed(Duration.zero);

      expect(pages.asked, hasLength(1));
    });

    test('adding a picture drops what was read under that name', () async {
      // Replacing a banner and seeing the old one is worse than seeing
      // nothing: it looks like the add silently failed.
      var pages = _FakePages()..files["assets/banner.png"] = banner;
      pages.localAssetBytes("assets/banner.png");
      await Future<void>.delayed(Duration.zero);
      expect(pages.localAssetBytes("assets/banner.png"), isNotNull);

      pages.forgetLocalAsset("assets/banner.png");
      expect(pages.localAssetBytes("assets/banner.png"), isNull);
    });
  });

  group('a banner picture', () {
    // A site keeps its pictures as files, so a page names one by path --
    // which is exactly what the Pictures list hands over to paste in. The
    // banner understood only --embed[...]--, so a background set from the
    // site's own pictures drew nothing at all: the file was there, served,
    // and named correctly, and the banner behaved as though the line were
    // blank.
    test('an embed still works', () {
      // The old way has to keep working: a banner in a post carries its own
      // bytes, and there is nowhere to fetch a file from.
      var png = base64Encode(pngOf(4, 4));
      expect(embedImage("--embed[type=image/png,data=$png]--"), isNotNull);
    });

    test('a line naming no picture is not one', () {
      expect(embedImage("Just some words"), isNull);
    });
  });

  group('the preview', () {
    Widget wrap(PagesModel pages, Widget child) =>
        ChangeNotifierProvider<ThemeNotifier>(
            create: (_) => ThemeNotifier(),
            child: ChangeNotifierProvider<PagesModel>.value(
              value: pages,
              child: MaterialApp(home: Scaffold(body: child)),
            ));

    testWidgets('draws a picture of this site rather than its alt text',
        (tester) async {
      var pages = _FakePages()..files["assets/banner.png"] = banner;

      await tester.pumpWidget(wrap(
          pages, const PageImage(path: "assets/banner.png", alt: "A banner")));
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
      expect(find.text("A banner"), findsNothing);
    });

    testWidgets('shows the alt text while the picture is still being read',
        (tester) async {
      // A page whose pictures are on their way is readable, which is why
      // the alt text is what stands in rather than a spinner.
      var pages = _FakePages()
        ..files["assets/banner.png"] = banner
        ..hold = Completer<void>();

      await tester.pumpWidget(wrap(
          pages, const PageImage(path: "assets/banner.png", alt: "A banner")));
      await tester.pump();

      expect(find.text("A banner"), findsOneWidget);
      pages.hold!.complete();
    });

    testWidgets('draws a banner background named by path', (tester) async {
      // The case that was broken. The whole banner is rendered rather than
      // headerPicture called directly, because the bug was not in reading
      // the path -- it was that nothing ever asked.
      var pages = _FakePages()..files["assets/banner.png"] = banner;

      await tester.pumpWidget(wrap(
          pages,
          Builder(
              builder: (context) =>
                  headerPicture(context, "![](assets/banner.png)") == null
                      ? const Text("nothing")
                      : const Text("drew it"))));
      await tester.pumpAndSettle();

      expect(find.text("drew it"), findsOneWidget);
      expect(pages.asked, ["assets/banner.png"]);
    });

    testWidgets('a banner still takes an embed', (tester) async {
      // A banner in a post carries its own bytes; there is nowhere to fetch
      // a file from. Both ways have to keep working.
      var pages = _FakePages();
      var png = base64Encode(pngOf(4, 4));

      await tester.pumpWidget(wrap(
          pages,
          Builder(
              builder: (context) => headerPicture(
                          context, "--embed[type=image/png,data=$png]--") ==
                      null
                  ? const Text("nothing")
                  : const Text("drew it"))));
      await tester.pumpAndSettle();

      expect(find.text("drew it"), findsOneWidget);
      expect(pages.asked, isEmpty, reason: "an embed needs nothing fetched");
    });

    testWidgets('shows the alt text for a picture that is not there',
        (tester) async {
      var pages = _FakePages();

      await tester.pumpWidget(wrap(
          pages, const PageImage(path: "assets/gone.png", alt: "A banner")));
      await tester.pumpAndSettle();

      expect(find.text("A banner"), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });
}
