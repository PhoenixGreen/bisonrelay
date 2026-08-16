import 'package:bruig/components/feed/feed_render_scope.dart';
import 'package:bruig/plugin_system/link_previews/link_card.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// feed_render_scope_test.dart covers the Feed area's settings reaching the
// things a post contains, rather than only the post itself.
//
// The defect this pins: a quoted post and a Pretty Links card are built by
// markdown builders several layers below whoever read the settings, so they
// ignored every one of them. A feed set to show no links still unfurled link
// cards inside a quoted post, and a feed cropping pictures to 200px still
// drew full-width thumbnails beside them.

FeedRenderScope _scope({
  bool linksDisabled = false,
  FeedImageLayout imageLayout = FeedImageLayout.standard,
  double cropHeight = 200,
  double textLimit = 0,
  bool stripMarkdown = false,
}) =>
    FeedRenderScope(
      linksDisabled: linksDisabled,
      imageLayout: imageLayout,
      cropHeight: cropHeight,
      textLimit: textLimit,
      stripMarkdown: stripMarkdown,
      child: const SizedBox.shrink(),
    );

const _imageEmbed = "--embed[type=image/png,data=aGk=]--";

/// _pump builds one widget with the theme a link card needs to set itself.
Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
    create: (c) => ThemeNotifier(doLoad: false),
    child: MaterialApp(home: Scaffold(body: child)),
  ));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group("what a nested post is cut down to", () {
    test("no links means none in a quoted post either", () {
      var scope = _scope(linksDisabled: true);
      expect(scope.constrain("see [this](https://decred.org) now"),
          "see this now");
      expect(scope.constrain("bare https://decred.org here").trim(),
          "bare  here".trim());
    });

    test("no pictures means none in a quoted post either", () {
      var scope = _scope(imageLayout: FeedImageLayout.none);
      expect(scope.constrain("before $_imageEmbed after"), "before  after");
    });

    test("a text limit cuts a quoted post to the same length", () {
      expect(_scope(textLimit: 5).constrain("abcdefghij"), "abcde…");
      expect(_scope(textLimit: 5).constrain("abc"), "abc",
          reason: "shorter than the limit is left alone");
      expect(_scope().constrain("abcdefghij"), "abcdefghij",
          reason: "0 is no limit at all");
    });
  });

  // Reported: a quoted post showed the raw "--embed[name=...,data=/9j/4AAQ..."
  // tag and a wall of base64 where the picture should have been.
  //
  // An embed carries a whole picture in base64, so it is routinely tens of
  // thousands of characters -- a cut at the limit lands inside one far more
  // often than not, and half an embed no longer parses.
  group("a text limit never cuts an embed in half", () {
    test("the cut moves back to the start of the embed", () {
      var content = "words $_imageEmbed more words";
      // A limit landing inside the embed.
      var cut = limitText(content, 10);
      expect(cut, "words …");
      expect(cut, isNot(contains("--embed[")));
    });

    test("an embed wholly before the cut is kept whole", () {
      var content = "$_imageEmbed and then a good deal of trailing writing";
      var cut = limitText(content, _imageEmbed.length + 10.0);
      expect(cut, startsWith(_imageEmbed));
      expect(cut, endsWith("…"));
    });

    // A post opening with a picture larger than the limit would otherwise cut
    // to nothing at all, which reads as a broken card rather than a short one.
    test("a post opening with an oversized embed keeps it", () {
      var content = "$_imageEmbed trailing writing after the picture";
      var cut = limitText(content, 5);
      expect(cut, startsWith(_imageEmbed));
      expect(cut, isNot(_imageEmbed),
          reason: "the writing after it is what gets cut");
    });

    test("content with no embed is cut exactly at the limit", () {
      expect(limitText("abcdefghij", 4), "abcd…");
    });

    test("a limit of 0 is no limit", () {
      var content = "words $_imageEmbed more";
      expect(limitText(content, 0), content);
    });
  });

  group("how tall a nested picture may be", () {
    test("cropped caps it at the crop height", () {
      expect(
          _scope(imageLayout: FeedImageLayout.cropped, cropHeight: 220)
              .mediaMaxHeight,
          220);
    });

    // Left and Right put the picture in a 140px column beside the text, so
    // anything nested is drawn in that column rather than at full width.
    test("side-by-side caps it at the column", () {
      for (var layout in [FeedImageLayout.left, FeedImageLayout.right]) {
        expect(_scope(imageLayout: layout).mediaMaxHeight, 140);
        expect(_scope(imageLayout: layout).narrow, isTrue);
      }
    });

    test("the layouts that do not constrain height say so", () {
      for (var layout in [
        FeedImageLayout.standard,
        FeedImageLayout.full,
        FeedImageLayout.none
      ]) {
        expect(_scope(imageLayout: layout).mediaMaxHeight, isNull);
        expect(_scope(imageLayout: layout).narrow, isFalse);
      }
    });

    test("only None hides pictures outright", () {
      expect(_scope(imageLayout: FeedImageLayout.none).imagesHidden, isTrue);
      for (var layout in FeedImageLayout.values) {
        if (layout == FeedImageLayout.none) continue;
        expect(_scope(imageLayout: layout).imagesHidden, isFalse);
      }
    });
  });

  // Reported: a post whose media is a quoted post or a link preview ignored
  // "First image display" entirely -- the card sat full width under the
  // writing while a picture in the same feed sat in a column beside it. A
  // card is the post's media, so it is placed like one.
  group("the card a post leads with is its media", () {
    const quote = "--embed[type=quote,from=abc,post=def]--";

    // Stands in for a provider that claims one host and says nothing about
    // the rest of the web -- which is what the one that ships does.
    bool claimsYoutube(String url) =>
        Uri.parse(url).host.endsWith("youtube.com");
    bool claimsAnything(String url) => true;

    test("a quoted post is pulled out to be placed", () {
      var (card, rest) =
          extractFirstCard("before $quote after", claimsLink: claimsAnything);
      expect(card, quote);
      expect(rest, "before  after");
    });

    test("a claimed link is pulled out to be placed", () {
      var (card, rest) = extractFirstCard("see https://youtube.com/x now",
          claimsLink: claimsYoutube);
      expect(card, "https://youtube.com/x");
      expect(rest, "see  now");
    });

    // Reported: a bare zerohedge.com link -- which nothing unfurls, so it
    // renders as ordinary link text -- was laid out as a card, alone in the
    // media column and wrapped over five lines.
    test("an unclaimed link stays in the writing", () {
      const post = "see https://www.zerohedge.com/technology/china now";
      var (card, rest) = extractFirstCard(post, claimsLink: claimsYoutube);
      expect(card, isNull);
      expect(rest, post);
    });

    // With no link-card provider at all, no URL is a card.
    test("a bare link is left alone when nothing will unfurl it", () {
      var (card, rest) = extractFirstCard("see https://decred.org now");
      expect(card, isNull);
      expect(rest, "see https://decred.org now");
    });

    // A post opening with a link nobody unfurls and going on to one somebody
    // does has a card, and it is the second one.
    test("the first claimed link is the card, not simply the first", () {
      var (card, rest) = extractFirstCard(
          "https://zerohedge.com/a and https://youtube.com/b",
          claimsLink: claimsYoutube);
      expect(card, "https://youtube.com/b");
      expect(rest, contains("https://zerohedge.com/a"),
          reason: "the unclaimed one stays in the writing");
    });

    // A quoted post that also carries a URL is placed as the quote it is.
    test("a quoted post wins over a link", () {
      var (card, _) = extractFirstCard("https://youtube.com/x $quote",
          claimsLink: claimsYoutube);
      expect(card, quote);
    });

    test("an ordinary post has no card to place", () {
      var (card, rest) =
          extractFirstCard("just some writing", claimsLink: claimsAnything);
      expect(card, isNull);
      expect(rest, "just some writing");
    });

    // An image embed is not a card -- it is placed by the image path, and
    // pulling it out here as well would place it twice.
    test("an image embed is not a card", () {
      var (card, _) = extractFirstCard(_imageEmbed, claimsLink: claimsAnything);
      expect(card, isNull);
    });

    // Inside the media column the card is itself the media, so what is in it
    // must not be split into columns all over again.
    test("inside the column, nested content stacks instead of splitting", () {
      var media = _scope(imageLayout: FeedImageLayout.left)
          .asMedia(child: const SizedBox.shrink());
      expect(media.narrow, isFalse);
      expect(media.imageLayout, FeedImageLayout.cropped);
      expect(media.mediaMaxHeight, 140,
          reason: "capped to the height the column is");
    });
  });

  // random has to be resolved before it reaches the scope, or a nested card
  // would be constrained by a layout the post around it is not drawn in.
  test("random resolves to the same layout for the same post", () {
    var first = resolveFeedImageLayout(FeedImageLayout.random, "alice", "7");
    var again = resolveFeedImageLayout(FeedImageLayout.random, "alice", "7");
    expect(first, again);
    expect(first, isNot(FeedImageLayout.random));
    expect(first, isNot(FeedImageLayout.none),
        reason: "random never hides the picture it was asked to place");
  });

  test("every other layout resolves to itself", () {
    for (var layout in FeedImageLayout.values) {
      if (layout == FeedImageLayout.random) continue;
      expect(resolveFeedImageLayout(layout, "alice", "7"), layout);
    }
  });

  // A widget test, not a model one: the whole point of the scope is that it
  // reaches a widget built out of sight of whoever set it, so reading the
  // settings back would prove nothing.
  testWidgets("a link card draws nothing where links are off", (tester) async {
    await _pump(
        tester,
        const FeedRenderScope(
          linksDisabled: true,
          imageLayout: FeedImageLayout.standard,
          cropHeight: 200,
          textLimit: 0,
          stripMarkdown: false,
          child: LinkCard("https://decred.org"),
        ));
    expect(find.text("https://decred.org"), findsNothing);
  });

  // Outside the feed there is no scope, and the card is what it always was.
  testWidgets("a link card with no scope is unchanged", (tester) async {
    await _pump(tester, const LinkCard("https://decred.org"));
    expect(find.text("https://decred.org"), findsOneWidget);
  });
}
