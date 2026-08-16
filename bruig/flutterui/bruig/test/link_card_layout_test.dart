import 'package:bruig/components/md_elements.dart';
import 'package:bruig/components/feed/feed_render_scope.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/plugin_system/link_previews/link_previews.dart';
import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'dart:convert';

import 'plugin_test_support.dart';
import 'png_fixture.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// link_card_layout_test.dart covers how wide and how tall a Pretty Links
// card is drawn, which is decided in two quite different places: the Feed
// area's "First image display" for a post, and the Chat area's "Image size"
// for a message.

const _url = "https://youtube.com/watch?v=abc";
const _width = 600.0;

/// _card is a link card with its metadata already in hand.
///
/// Seeded rather than fetched: the fetch goes through the client, so an
/// unseeded card only ever shows the plain link it displays while loading --
/// which is not the part with a layout to get wrong.
Widget _card() => const LinkCard(_url);

Future<void> _pump(WidgetTester tester, Widget child,
    {String chatImageSize = "default"}) async {
  // A real thumbnail, because the size of the picture is most of what is
  // being measured -- a card with none collapses that area entirely.
  seedLinkMetadata(
      _url,
      LinkMetadata("A title", "A description", "An author",
          base64Encode(pngOf(64, 36)), ""));
  var theme = ThemeNotifier(doLoad: false);
  if (chatImageSize != "default") theme.setChatImageSize(chatImageSize);
  await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>.value(
    value: theme,
    child: MaterialApp(
      home: Scaffold(
        // Align inside the fixed width, so the card is offered the width
        // rather than forced to it -- which is how a real message and a real
        // post lay their content out. A bare SizedBox hands its child a
        // *tight* width, and under one of those nothing inside can be
        // narrower than the column: the Chat area's Image size would appear
        // to do nothing here while working perfectly in the app.
        body: Center(
          child: SizedBox(
            width: _width,
            child: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// _card_ is the bordered box the card is drawn in.
///
/// Found by its border rather than by position: LinkCard itself fills
/// whatever it is given, and the box inside it is the thing that resizes.
Finder get _cardBox => find.byWidgetPredicate((w) =>
    w is Container &&
    w.decoration is BoxDecoration &&
    (w.decoration as BoxDecoration).border != null);

double _cardWidth(WidgetTester tester) => tester.getSize(_cardBox.first).width;

/// _claimedWidth is how much of the line the card takes up, as opposed to
/// how wide the card itself is drawn. The two are deliberately different in
/// chat -- see the "own line" tests below.
double _claimedWidth(WidgetTester tester) =>
    tester.getSize(find.byType(LinkCard)).width;

/// _thumbHeight is how tall the picture at the top of the card is.
double _thumbHeight(WidgetTester tester) =>
    tester.getSize(find.byType(Image).first).height;

FeedRenderScope _scope(FeedImageLayout layout,
        {double cropHeight = 200, required Widget child}) =>
    FeedRenderScope(
      linksDisabled: false,
      imageLayout: layout,
      cropHeight: cropHeight,
      textLimit: 0,
      stripMarkdown: false,
      child: child,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Reported: link previews stopped running the full width of the feed.
  //
  // The card had been narrowed to keep its thumbnail 16:9 under a height
  // cap, which made it stop short of the column it was in. Cropping is what
  // a height cap means -- the thumbnail is drawn with BoxFit.cover, so a
  // shorter box crops it -- and the card keeps the full width either way.
  group("in a post", () {
    testWidgets("a card runs the full width under every layout",
        (tester) async {
      for (var layout in [
        FeedImageLayout.standard,
        FeedImageLayout.full,
        FeedImageLayout.cropped,
      ]) {
        await _pump(tester, _scope(layout, child: _card()));
        expect(_cardWidth(tester), _width,
            reason: "$layout should not narrow the card");
      }
    });

    testWidgets("a card with no feed scope runs the full width",
        (tester) async {
      await _pump(tester, _card());
      expect(_cardWidth(tester), _width);
    });

    // Uncapped, the thumbnail is the full width at 16:9.
    testWidgets("an uncapped thumbnail is 16:9 of the full width",
        (tester) async {
      await _pump(tester, _scope(FeedImageLayout.full, child: _card()));
      // Inside the card's 1px border, so a shade under the full width.
      expect(_thumbHeight(tester), closeTo(_width * 9 / 16, 3));
    });

    // Cropped cuts the thumbnail's height without touching the card's width.
    testWidgets("cropped shortens the thumbnail, not the card", (tester) async {
      await _pump(tester,
          _scope(FeedImageLayout.cropped, cropHeight: 120, child: _card()));
      expect(_cardWidth(tester), _width);
      expect(_thumbHeight(tester), closeTo(120, 1),
          reason: "the picture is cropped to the height asked for");
    });
  });

  // Reported over three rounds: a card in chat ignored the Chat area's Image
  // size; sizing the card by it left a bare gap down the right of the bubble
  // and let the words sit beside the preview; sizing the picture by it left
  // a gap inside the card instead.
  //
  // What was wanted: the setting is a *maximum*, not a share to draw at. The
  // card fills whatever it is given -- so there is never a gap beside
  // anything -- but never grows past the size a picture in the same message
  // would be allowed.
  group("in a chat message", () {
    testWidgets("a card grows no larger than a picture would be allowed",
        (tester) async {
      for (var (size, share) in [
        ("quarter", 0.25),
        ("third", 1 / 3),
        ("half", 0.5),
        ("twoThirds", 2 / 3),
        ("full", 1.0),
      ]) {
        await _pump(tester, ChatImageWidth(width: _width, child: _card()),
            chatImageSize: size);
        expect(_cardWidth(tester), closeTo(_width * share, 0.5),
            reason: "$size caps the card at $share of the message");
      }
    });

    // Nothing inside the card is a share of it: whatever width the card
    // ends up with, the picture fills it edge to edge.
    testWidgets("the picture fills the card, whatever the card's width",
        (tester) async {
      for (var size in ["default", "quarter", "half", "full"]) {
        await _pump(tester, ChatImageWidth(width: _width, child: _card()),
            chatImageSize: size);
        // Inside the card's 1px border, hence the tolerance.
        expect(tester.getSize(find.byType(Image).first).width,
            closeTo(_cardWidth(tester), 3),
            reason: "at $size the picture should leave no gap beside it");
      }
    });

    // Default has no share to take. A card has no natural size for the
    // 250pt bound to be a bound on, so it stays at the bubble's width --
    // which is what a preview has always been drawn at.
    testWidgets("Default leaves the card at the bubble's width",
        (tester) async {
      await _pump(tester, ChatImageWidth(width: _width, child: _card()));
      expect(_cardWidth(tester), _width);
    });

    // The card takes no more room than it draws. Keeping it off the words'
    // line is the paragraph split's job now (see MarkdownExtension.
    // standalone), not a claim on the width -- a claim made every box the
    // card sat in full width too.
    testWidgets("a card claims no more room than it draws", (tester) async {
      for (var size in ["quarter", "half", "full"]) {
        await _pump(tester, ChatImageWidth(width: _width, child: _card()),
            chatImageSize: size);
        expect(_claimedWidth(tester), closeTo(_cardWidth(tester), 1),
            reason: "at $size the card should claim only its own width");
      }
    });
  });

  // Through the real pipeline rather than on the card alone: how much room a
  // card claims depends on whether there are words beside it, and only the
  // pipeline knows that.
  group("through the markdown pipeline", () {
    /// _pumpMarkdown renders [src] as a chat message would.
    Future<void> pumpMarkdown(WidgetTester tester, String src,
        {String chatImageSize = "half"}) async {
      seedLinkMetadata(
          _url,
          LinkMetadata("A title", "A description", "An author",
              base64Encode(pngOf(64, 36)), ""));

      var mk = MarkdownAreaModel("/tmp");
      mk.setPluginExtensions(
          linkPreviewExtensions(FakePlugins({PluginCapability.linkCard})));

      var theme = ThemeNotifier(doLoad: false);
      theme.setChatImageSize(chatImageSize);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeNotifier>.value(value: theme),
          ChangeNotifierProvider<PaymentsModel>(create: (c) => PaymentsModel()),
          ChangeNotifierProvider<MarkdownAreaModel>.value(value: mk),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: _width,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ChatImageWidth(
                    width: _width,
                    child: MarkdownArea(src, false),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    // Reported: the card was drawn at half but the bubble around it ran the
    // full width of the window.
    //
    // A bubble is as wide as its widest content, and the card was claiming
    // the whole line to keep words off it -- so it claimed the width even
    // when there were no words to keep off. Written on its own it now claims
    // only what it draws, and the bubble fits it.
    testWidgets("a URL written on its own claims only what it draws",
        (tester) async {
      await pumpMarkdown(tester, _url);
      expect(_cardBox, findsWidgets, reason: "the card should have rendered");

      var claimed = tester.getSize(find.byType(MarkdownArea)).width;
      expect(claimed, closeTo(_width / 2, 1),
          reason: "at Half the card is half the message, and the bubble "
              "around it should be that and no more");
      expect(claimed, closeTo(_cardWidth(tester), 1),
          reason: "the bubble fits the card, not the window");
    });

    // The other half of the same rule, and the earlier report: with words
    // beside it the card takes the line, so the words sit above it.
    testWidgets("a message's words sit above its preview, never beside it",
        (tester) async {
      await pumpMarkdown(tester, "Test $_url");
      expect(_cardBox, findsWidgets, reason: "the card should have rendered");
      // textContaining, not text: markdown lays a paragraph out as rich text
      // runs, so the words are a RichText rather than a Text.
      var words = find.textContaining("Test");
      expect(words, findsWidgets);
      expect(tester.getBottomLeft(words.first).dy,
          lessThanOrEqualTo(tester.getTopLeft(_cardBox.first).dy),
          reason: "the words end before the preview begins");
      expect(tester.getTopLeft(_cardBox.first).dx,
          tester.getTopLeft(find.byType(MarkdownArea)).dx,
          reason: "and nothing shares the line with it");
    });

    // Reported: every message but a bare URL still had the bubble running
    // the width of the window.
    //
    // The card used to claim the whole line to push the words off it, and a
    // bubble is as wide as its widest content -- so the claim made the
    // bubble full width too. The card is given a paragraph of its own
    // instead, which breaks the line without claiming anything.
    testWidgets("words beside a URL do not widen the box around it",
        (tester) async {
      await pumpMarkdown(tester, "Test $_url");
      expect(tester.getSize(find.byType(MarkdownArea)).width,
          closeTo(_cardWidth(tester), 1),
          reason: "the bubble fits the card, words above it or not");
    });

    // A card is the same size whatever is written around it. What changes
    // is the bubble, which is as wide as its widest content -- so a message
    // carrying a long line of its own (a relayed message's
    // "date nick - date nick" header, say) is wide because of that line, not
    // because the preview grew.
    testWidgets("the card is the same size whatever text surrounds it",
        (tester) async {
      await pumpMarkdown(tester, _url);
      var bare = _cardWidth(tester);

      await pumpMarkdown(tester, "Test $_url");
      expect(_cardWidth(tester), bare);

      await pumpMarkdown(
          tester, "2026-07-05 18:33:49 PhoenixGreen - Test\n\n$_url");
      expect(_cardWidth(tester), bare,
          reason: "a long line above it does not change the card");
      expect(tester.getSize(find.byType(MarkdownArea)).width, greaterThan(bare),
          reason: "though it does widen the bubble, which fits that line");
    });

    // A URL that is already markup is left where it is: moving it would
    // break the link it belongs to, and it never becomes a card anyway.
    testWidgets("a written-out link is not pulled out of its sentence",
        (tester) async {
      await pumpMarkdown(tester, "See [the site]($_url) for more");
      expect(_cardBox, findsNothing, reason: "a written link is not a card");
      expect(find.textContaining("See"), findsWidgets);
      expect(find.textContaining("for more"), findsWidgets);
    });

    // Code is shown, not linked -- breaking the block apart would stop it
    // being code at all.
    testWidgets("a URL inside a code fence is left alone", (tester) async {
      await pumpMarkdown(tester, "```\ncurl $_url\n```");
      expect(_cardBox, findsNothing);
      expect(find.textContaining("curl"), findsWidgets);
    });
  });
}
