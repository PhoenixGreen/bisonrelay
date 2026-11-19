import 'package:bruig/components/share_settings.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:provider/provider.dart';

// share_settings_test.dart is the terms a file is shared in Files on: who
// can fetch it, its cost and its description, set before a canvas is shared
// and changed afterwards from the Shared page (Ken, 2026-11-19).

SharedFileAndShares _file(
        {bool global = true,
        List<String> shares = const [],
        int cost = 0,
        String descr = "",
        String diskPath = "/tmp/a.png"}) =>
    SharedFileAndShares(SharedFile("hash", "fid", "a.png"), cost, 100, global,
        shares, descr, diskPath);

void main() {
  test("the terms a file is shared on now", () {
    var t = ShareSettings.of(_file(
        global: false, shares: ["u1", "u2"], cost: 50000000, descr: "Map"));
    expect(t.everyone, isFalse);
    expect(t.people, ["u1", "u2"]);
    expect(t.cost, 0.5);
    expect(t.description, "Map");
  });

  test("the same terms are not shared again", () {
    var f = _file(global: false, shares: ["u1", "u2"], cost: 50000000);
    var t = ShareSettings.of(f);
    expect(t.sameTermsAs(f), isTrue);
    expect(t.copyWith(people: ["u2", "u1"]).sameTermsAs(f), isTrue,
        reason: "the order people were added in is no change");
    expect(t.copyWith(cost: 0.6).sameTermsAs(f), isFalse);
    expect(t.copyWith(people: ["u1"]).sameTermsAs(f), isFalse);
    expect(t.copyWith(everyone: true).sameTermsAs(f), isFalse);
    expect(t.copyWith(description: "New").sameTermsAs(f), isFalse);
  });

  test("chosen people with nobody chosen reach nobody", () {
    expect(const ShareSettings().reachesAnyone, isTrue);
    expect(const ShareSettings(everyone: false).reachesAnyone, isFalse);
    expect(const ShareSettings(everyone: false, people: ["u"]).reachesAnyone,
        isTrue);
  });

  test("a cost as the box shows it", () {
    expect(costText(0), "");
    expect(costText(0.5), "0.5");
    expect(costText(2), "2");
    expect(costText(0.00000001), "0.00000001");
  });

  testWidgets("the fields say who, what it costs and what it is",
      (tester) async {
    ShareSettings? last;
    await tester.pumpWidget(ChangeNotifierProvider<ThemeNotifier>(
      create: (c) => ThemeNotifier(doLoad: false),
      child: MaterialApp(
        home: Scaffold(
          body: ShareSettingsFields(
            initial: const ShareSettings(cost: 0.25, description: "Map"),
            onChanged: (t) => last = t,
          ),
        ),
      ),
    ));
    expect(find.text("Everyone who lists your files"), findsOneWidget);
    expect(find.text("0.25"), findsOneWidget);
    expect(find.text("Map"), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey("shareWho")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Only people I choose").last);
    await tester.pumpAndSettle();
    expect(last!.everyone, isFalse);
    expect(find.text("Choose at least one person."), findsOneWidget);
    expect(find.byKey(const ValueKey("shareAddPeople")), findsOneWidget);

    await tester.enterText(find.text("0.25"), "1.5");
    expect(last!.cost, 1.5);
    await tester.enterText(
        find.byKey(const ValueKey("shareDescription")), " A map ");
    expect(last!.description, "A map");
    expect(last!.everyone, isFalse, reason: "each change keeps the others");
  });
}
