import 'dart:convert';

import 'package:bruig/components/md_elements.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'png_fixture.dart';

// chat_image_size_test.dart covers the Chat area's Image size actually
// reaching a picture in a message.
//
// Reported: the setting stopped working. It had not: a style guide is how
// *posts* are set, but nothing kept its scope out of chat, and the scope goes
// on as soon as the guide is anything but the untouched Default. So editing
// any guide setting at all -- a list indent, a check box -- switched every
// picture in every message from the Chat area's Image size to the guide's own
// 100%-of-the-column rule.

const _contentWidth = 580.0;

/// _imageWidth renders one picture in a chat message and measures it.
Future<double> _imageWidth(WidgetTester tester, String size,
    {MarkdownStyleGuide? guide}) async {
  var embed = "--embed[type=image/png,data=${base64Encode(pngOf(800, 450))}]--";
  var theme = ThemeNotifier(doLoad: false);
  theme.setChatImageSize(size);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>.value(value: theme),
      ChangeNotifierProvider<PaymentsModel>(create: (c) => PaymentsModel()),
      ChangeNotifierProvider<MarkdownAreaModel>(
          create: (c) => MarkdownAreaModel("/tmp")),
    ],
    child: MaterialApp(
      home: Scaffold(
        // As components/chat/events.dart lays a message out: the bubble
        // offers its content width rather than forcing it, and hands it down
        // through ChatImageWidth.
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: _contentWidth,
            child: Align(
              alignment: Alignment.topLeft,
              child: ChatImageWidth(
                width: _contentWidth,
                child: MarkdownArea(embed, false, guide: guide),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return tester.getSize(find.byType(Image).first).width;
}

/// _editedGuide is a guide with one setting changed -- any change at all is
/// enough to make it no longer the untouched Default.
MarkdownStyleGuide get _editedGuide =>
    builtInGuideFor(defaultGuideId)!.copyWith(id: "custom", listIndent: 40);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets("each size is a share of the message's width", (tester) async {
    expect(
        await _imageWidth(tester, "quarter"), closeTo(_contentWidth * 0.25, 1));
    expect(await _imageWidth(tester, "third"), closeTo(_contentWidth / 3, 1));
    expect(await _imageWidth(tester, "half"), closeTo(_contentWidth * 0.5, 1));
    expect(await _imageWidth(tester, "twoThirds"),
        closeTo(_contentWidth * 2 / 3, 1));
    expect(await _imageWidth(tester, "full"), closeTo(_contentWidth, 5));
  });

  // The regression itself. A style guide belongs to posts; a message has no
  // guide and never asked for one.
  testWidgets("an edited style guide does not take chat's pictures over",
      (tester) async {
    var plain = await _imageWidth(tester, "half");
    var edited = await _imageWidth(tester, "half", guide: _editedGuide);
    expect(edited, plain,
        reason: "editing a guide must not change a picture in a message");
    expect(edited, closeTo(_contentWidth * 0.5, 1),
        reason: "it is still the Chat area's Image size that decides");
  });

  testWidgets("the setting can be changed without rebuilding the message",
      (tester) async {
    expect(await _imageWidth(tester, "full"), closeTo(_contentWidth, 5));
    expect(
        await _imageWidth(tester, "quarter"), closeTo(_contentWidth * 0.25, 1));
  });
}
