import 'package:bruig/components/md_elements.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// markdown_bullet_test.dart covers the Lists element's check-box settings:
// what actually gets drawn beside a markdown task list.
//
// Widget tests rather than model ones, because the settings reach the page
// through flutter_markdown's checkboxBuilder rather than through the
// stylesheet. A test that only read the guide back would pass with nothing
// wired up at all -- which is exactly how two controls once shipped dead.

const _tasks = "- [x] done\n- [ ] not done\n";

Future<void> _pump(WidgetTester tester, String data,
        {MarkdownStyleGuide? guide}) =>
    tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        ChangeNotifierProvider<PaymentsModel>(create: (c) => PaymentsModel()),
        ChangeNotifierProvider<MarkdownAreaModel>(
            create: (c) => MarkdownAreaModel("/tmp")),
      ],
      child: MaterialApp(
        home: Scaffold(body: MarkdownArea(data, false, guide: guide)),
      ),
    ));

/// _icons is every icon drawn.
Set<IconData> _icons(WidgetTester tester) => {
      for (var i in tester.widgetList<Icon>(find.byType(Icon)))
        if (i.icon != null) i.icon!
    };

MarkdownStyleGuide _guide({
  MarkdownCheckMark checked = MarkdownCheckMark.tick,
  MarkdownCheckMark unchecked = MarkdownCheckMark.empty,
  double size = 16,
}) =>
    builtInGuideFor(defaultGuideId)!.copyWith(
        id: "custom",
        listCheckedMark: checked,
        listUncheckedMark: unchecked,
        listCheckSize: size);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets("a task list is ticked and empty until told otherwise",
      (tester) async {
    await _pump(tester, _tasks);
    await tester.pump();
    expect(_icons(tester), contains(Icons.check));
    expect(_icons(tester), isNot(contains(Icons.close)));
  });

  // One test per mark would be three copies of the same lines; what matters
  // is that each choice reaches the page and that choosing one does not
  // leave the previous mark behind.
  testWidgets("each check mark is what gets drawn", (tester) async {
    for (var mark in MarkdownCheckMark.values) {
      // Both ends set to the same mark, so whatever is on screen is this
      // choice and nothing is left from the other one.
      await _pump(tester, _tasks,
          guide: _guide(checked: mark, unchecked: mark));
      await tester.pump();
      var drawn = _icons(tester);
      if (mark.icon == null) {
        expect(drawn, isEmpty, reason: "Empty leaves the box open");
      } else {
        expect(drawn, contains(mark.icon), reason: "${mark.label} is missing");
      }
      for (var other in MarkdownCheckMark.values) {
        if (other == mark || other.icon == null) continue;
        expect(drawn, isNot(contains(other.icon)),
            reason: "${other.label} should not still be showing");
      }
    }
  });

  // The two ends are set separately, because which mark reads as "done" is a
  // matter of taste -- a cross for something ruled out, say.
  testWidgets("the two ends are set independently", (tester) async {
    await _pump(tester, _tasks,
        guide: _guide(
            checked: MarkdownCheckMark.cross,
            unchecked: MarkdownCheckMark.tick));
    await tester.pump();
    expect(_icons(tester), containsAll([Icons.close, Icons.check]));
  });

  // An ordinary list has no boxes at all -- only `- [ ]` and `- [x]` are
  // tasks.
  testWidgets("a plain list gets no check boxes", (tester) async {
    await _pump(tester, "- one\n- two\n", guide: _guide());
    await tester.pump();
    expect(_icons(tester), isEmpty);
    expect(find.text("•"), findsWidgets, reason: "still an ordinary bullet");
  });

  /// _boxSize is how large the drawn check box actually is.
  Size boxSize(WidgetTester tester) =>
      tester.getSize(find.byType(DecoratedBox).first);

  testWidgets("the size setting reaches the box", (tester) async {
    await _pump(tester, _tasks, guide: _guide(size: 40));
    await tester.pump();
    expect(boxSize(tester), const Size(40, 40));
  });

  // Reported: raising the list indent made the box wider instead of moving
  // the text away from it.
  //
  // flutter_markdown puts the marker in a SizedBox as wide as the indent,
  // and a SizedBox constrains its child tightly -- so the box was stretched
  // to the indent rather than staying the size it was asked for.
  testWidgets("the indent does not stretch the box", (tester) async {
    await _pump(tester, _tasks,
        guide: _guide(size: 16).copyWith(listIndent: 24));
    await tester.pump();
    expect(boxSize(tester), const Size(16, 16));

    await _pump(tester, _tasks,
        guide: _guide(size: 16).copyWith(listIndent: 64));
    await tester.pump();
    expect(boxSize(tester), const Size(16, 16),
        reason: "a wider indent is more space, not a bigger box");
  });

  // Reported: tasks rendered as ordinary bullets.
  //
  // A "loose" list -- one whose items are separated by blank lines -- wraps
  // each item's content in a paragraph, so the checkbox is the paragraph's
  // first child rather than the item's. The renderer looked only at the item,
  // so every box was missed and the list came out as plain bullets. Written
  // with blank lines is exactly what the Formatting & Content buttons
  // produce, so this was the common case rather than an edge one.
  testWidgets("a task list keeps its boxes when its items are spaced apart",
      (tester) async {
    await _pump(tester, "- [x] done\n\n- [ ] not done\n");
    await tester.pump();
    expect(_icons(tester), contains(Icons.check));
    expect(find.text("•"), findsNothing,
        reason: "a spaced-out task list is still a task list");
  });

  testWidgets("a spaced-out plain list still gets bullets", (tester) async {
    await _pump(tester, "- one\n\n- two\n");
    await tester.pump();
    expect(find.text("•"), findsNWidgets(2));
  });

  // Reported: the indent was measured differently for a task list. For
  // bullets and numbers it added space to the *left* of the marker; for a
  // check box it added space between the box and its text, because the box
  // was aligned to the left of the marker column while every other marker
  // effectively sits at the right of it.
  testWidgets(
      "the indent adds space to the left of the box, as it does for "
      "every other marker", (tester) async {
    Future<double> boxLeft(double indent) async {
      await _pump(tester, _tasks,
          guide: _guide(size: 16).copyWith(listIndent: indent));
      await tester.pump();
      return tester.getTopLeft(find.byType(DecoratedBox).first).dx;
    }

    var narrow = await boxLeft(24);
    var wide = await boxLeft(64);
    expect(wide, greaterThan(narrow),
        reason: "a wider indent moves the box right, it does not push the "
            "text away from a box that stays put");
  });

  // Reported: the indent setting appeared to do nothing to a numbered list.
  //
  // The marker sits in a box as wide as the indent and a number is
  // right-aligned in it, so it ended hard against its item and stayed there
  // however wide the indent was -- while a bullet, being centred in the same
  // box, visibly moved away from the text. One setting, two behaviours.
  //
  // Measured on the marker's own box rather than on the glyph: a bullet's
  // box always spans the full indent (the • is centred inside it), so it is
  // only the number that needs room reserved after it.
  testWidgets("the indent opens a gap after a number, not just before it",
      (tester) async {
    Future<double> gapAfterNumber(double indent) async {
      await _pump(tester, "1. item\n",
          guide: builtInGuideFor(defaultGuideId)!
              .copyWith(id: "custom", listIndent: indent));
      await tester.pump();
      var texts = tester.widgetList<RichText>(find.byType(RichText)).toList();
      return tester.getTopLeft(find.byWidget(texts.last)).dx -
          tester.getTopRight(find.byWidget(texts.first)).dx;
    }

    var narrow = await gapAfterNumber(24);
    var wide = await gapAfterNumber(64);
    expect(wide, greaterThan(narrow),
        reason: "a wider indent is more room between the number and the item");
  });

  // Reported: a list of each kind, one after another, did not line up down
  // the page -- the indent behaved differently for each.
  //
  // flutter_markdown centres a bullet in the marker column, right-aligns a
  // number hard against its text, and pads the two of them but not a check
  // box. Three markers, three placements, one setting. They are all set the
  // same way now: hard against the right of the column, held off the text by
  // the same gap.
  testWidgets("a bullet, a number and a box all line up", (tester) async {
    for (var indent in [24.0, 48.0, 64.0]) {
      await _pump(tester, "- item\n\n1. item\n\n- [ ] item\n",
          guide: _guide(size: 16).copyWith(listIndent: indent));
      await tester.pump();

      var runs = tester
          .widgetList<RichText>(find.byType(RichText))
          .where((w) => w.text.toPlainText().trim().isNotEmpty)
          .toList();
      // Marker, item, marker, item, item -- the box is not a text run.
      var bullet = find.byWidget(runs[0]);
      var number = find.byWidget(runs[2]);
      var box = find.byType(DecoratedBox).first;

      expect(tester.getTopRight(number).dx, tester.getTopRight(bullet).dx,
          reason: "a number ends where a bullet does (indent $indent)");
      expect(tester.getTopRight(box).dx, tester.getTopRight(bullet).dx,
          reason: "a box ends where a bullet does (indent $indent)");

      var textLeft = tester.getTopLeft(find.byWidget(runs[1])).dx;
      expect(tester.getTopLeft(find.byWidget(runs[3])).dx, textLeft);
      expect(tester.getTopLeft(find.byWidget(runs[4])).dx, textLeft,
          reason: "every item's text starts in the same place");
    }
  });

  test("the marks survive being saved and read back", () {
    var guide = _guide(
        checked: MarkdownCheckMark.cross,
        unchecked: MarkdownCheckMark.tick,
        size: 24);
    var back = MarkdownStyleGuide.fromJson(guide.toJson());
    expect(back.listCheckedMark, MarkdownCheckMark.cross);
    expect(back.listUncheckedMark, MarkdownCheckMark.tick);
    expect(back.listCheckSize, 24);
  });

  // A guide written before these settings existed carries none of them.
  test("a guide that says nothing means tick and empty box", () {
    var json = _guide(checked: MarkdownCheckMark.cross).toJson()
      ..remove("listCheckedMark")
      ..remove("listUncheckedMark")
      ..remove("listCheckSize");
    var back = MarkdownStyleGuide.fromJson(json);
    expect(back.listCheckedMark, MarkdownCheckMark.tick);
    expect(back.listUncheckedMark, MarkdownCheckMark.empty);
    expect(back.listCheckSize, 16);
  });
}
