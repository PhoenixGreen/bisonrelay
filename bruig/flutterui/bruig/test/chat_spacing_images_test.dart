import 'package:bruig/components/md_elements.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// chat_spacing_images_test.dart covers the two Chat-area settings that
// decide how much room a conversation takes: the gap between messages, and
// how large a picture in one is drawn.

void main() {
  group('space between messages', () {
    test('an untouched theme keeps the gaps the chat has always had', () {
      const style = AreaStyle();
      expect(style.messageSpacing, isNull);
      expect(style.messageGap, 10);
      expect(style.sameUserMessageGap, 2);
    });

    test('widening the gap keeps a run of messages reading as one group', () {
      const style = AreaStyle(messageSpacing: 30);
      expect(style.messageGap, 30);
      // Still the tighter of the two, at the proportion the built-in pair
      // already stood in -- otherwise opening the conversation up flattens
      // it into an evenly spaced list with no grouping left.
      expect(style.sameUserMessageGap, 6);
      expect(style.sameUserMessageGap, lessThan(style.messageGap));
    });

    test('it can be closed up as well as opened out', () {
      const style = AreaStyle(messageSpacing: 0);
      expect(style.messageGap, 0);
      expect(style.sameUserMessageGap, 0);
    });

    test('it round-trips, and an untouched theme writes nothing', () {
      var back =
          AreaStyle.fromJson(const AreaStyle(messageSpacing: 24).toJson());
      expect(back.messageSpacing, 24);
      expect(const AreaStyle().toJson().containsKey('messageSpacing'), isFalse);
      expect(AreaStyle.fromJson(const AreaStyle().toJson()).messageSpacing,
          isNull);
    });

    test('clearing it goes back to the built-in gap', () {
      var style = const AreaStyle(messageSpacing: 24)
          .copyWith(clearMessageSpacing: true);
      expect(style.messageSpacing, isNull);
      expect(style.messageGap, 10);
    });
  });

  group('image size', () {
    test('Default leaves a picture alone, bounded to 250', () {
      expect(chatImageFraction('default'), isNull);
      // Null width means "draw at your natural size" -- the bound is applied
      // as constraints instead, by chatImageSized.
      expect(chatImageWidth('default', 800), isNull);
    });

    test('every proportional size is a real share of the width', () {
      expect(chatImageWidth('quarter', 800), 200);
      expect(chatImageWidth('third', 900), 300);
      expect(chatImageWidth('half', 800), 400);
      expect(chatImageWidth('twoThirds', 900), 600);
      expect(chatImageWidth('full', 800), 800);
    });

    test('the sizes are offered smallest first', () {
      expect(appImageSizes.keys.toList(),
          ['default', 'quarter', 'third', 'half', 'twoThirds', 'full']);
      expect(appImageSizes['quarter']!.descr, 'Quarter width');
      expect(appImageSizes['third']!.descr, 'Third width');
      expect(appImageSizes['twoThirds']!.descr, 'Two-thirds width');
    });

    test('the offered sizes really do grow in the order they are listed', () {
      var fractions = appImageSizes.keys
          .map(chatImageFraction)
          .whereType<double>()
          .toList();
      expect(fractions, orderedEquals([...fractions]..sort()));
      // And every one but Default resolves to a share, so none of them is
      // silently falling through to the bound.
      expect(fractions, hasLength(appImageSizes.length - 1));
    });

    test('a narrower message means a smaller picture', () {
      // The whole point of the setting following Message layout: the same
      // choice in a narrowed conversation draws a smaller picture, because
      // the share is of the width the message actually has.
      expect(
          chatImageWidth('half', 400), lessThan(chatImageWidth('half', 800)!));
    });

    test('an unbounded width has no share to take', () {
      expect(chatImageWidth('full', double.infinity), isNull);
    });

    // A filling child, so what these measure is the width the wrapper
    // actually hands down rather than the child's own idea of its size.
    const target = Key('picture');

    // Loose constraints, the way a real message bubble hands them down: a
    // tight width would override the Default size's cap and make this
    // harness prove the opposite of what it is asking about.
    Future<double> widthOf(WidgetTester tester, String size) async {
      await tester.pumpWidget(MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: chatImageSized(size, 800, Container(key: target)),
          ),
        ),
      ));
      return tester.getSize(find.byKey(target)).width;
    }

    testWidgets('a proportional size sets a width, not merely a cap',
        (tester) async {
      // The bug this guards: an Image set to contain draws at its natural
      // size whenever that fits, so as a maximum these settings did nothing
      // at all to any picture already smaller than the share.
      expect(await widthOf(tester, 'half'), 400);
      expect(await widthOf(tester, 'quarter'), 200);
      expect(await widthOf(tester, 'full'), 800);
    });

    // The bug the user hit twice: a picture in a message is inline markdown,
    // rendered inside a WidgetSpan, which lays its child out with an
    // unbounded width. Measuring gives infinity, every size falls through to
    // the same bound, and the setting does nothing at all -- so the width has
    // to be handed down instead.
    testWidgets('an unbounded measurement falls back to the handed-down width',
        (tester) async {
      late double seen;
      await tester.pumpWidget(MaterialApp(
        home: ChatImageWidth(
          width: 600,
          child: Builder(builder: (context) {
            // What ImageMd does: prefer the handed-down width over the
            // measured one.
            seen = ChatImageWidth.of(context) ?? double.infinity;
            return const SizedBox.shrink();
          }),
        ),
      ));
      expect(seen, 600);
      expect(chatImageWidth('half', seen), 300);
    });

    testWidgets('with no width handed down it still measures', (tester) async {
      late double? seen;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          seen = ChatImageWidth.of(context);
          return const SizedBox.shrink();
        }),
      ));
      expect(seen, isNull);
    });

    testWidgets('Default caps rather than sizes', (tester) async {
      // Bounded, so a picture under 250 keeps its own size instead of being
      // stretched up to a share of the message.
      expect(await widthOf(tester, 'default'), 250);
    });
  });
}
