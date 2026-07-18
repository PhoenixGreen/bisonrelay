import 'package:bruig/components/confirmation_dialog.dart';
import 'package:bruig/components/info_grid.dart';
import 'package:bruig/components/interactive_avatar.dart';
import 'package:bruig/components/snackbars.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:golib_plugin/util.dart';
import 'package:tuple/tuple.dart';
import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/theme_manager.dart';

class PayStatsScreenTitle extends StatelessWidget {
  const PayStatsScreenTitle({super.key});
  @override
  Widget build(BuildContext context) {
    return const Txt.L("Payment Stats");
  }
}

class PayStatsScreen extends StatefulWidget {
  static String routeName = "/payStats";
  final ClientModel client;
  const PayStatsScreen(this.client, {super.key});

  @override
  State<PayStatsScreen> createState() => _PayStatsScreenState();
}

class _PayStatsScreenState extends State<PayStatsScreen> {
  ClientModel get client => widget.client;
  List<Tuple3<String, String, UserPayStats>> stats = []; // UID,nick,stat
  int selectedIndex = -1;
  List<PayStatsSummary> userStats = [];
  ScrollController userStatsSentCtrl = ScrollController();
  ScrollController userStatsReceivedCtrl = ScrollController();
  int userStatsTotalReceived = 0;
  int userStatsTotalSent = 0;

  void listPayStats() async {
    try {
      var statsMap = await Golib.listPaymentStats();
      var newStats = statsMap.entries
          .map((e) => Tuple3<String, String, UserPayStats>(
              e.key, client.getNick(e.key), e.value))
          .toList();
      newStats.sort((a, b) {
        var ta = a.item3.totalSent + a.item3.totalReceived;
        var tb = b.item3.totalSent + b.item3.totalReceived;
        return tb - ta;
      });
      setState(() {
        stats = newStats;
        if (selectedIndex >= stats.length) {
          selectedIndex = -1;
        }
      });
    } catch (exception) {
      showErrorSnackbar(this, "Unable to list payment stats: $exception");
    }
  }

  void select(int index) async {
    setState(() {
      selectedIndex = index;
    });
    try {
      var newUserStats = await Golib.summarizeUserPayStats(stats[index].item1);
      setState(() {
        userStats = newUserStats;
        userStatsTotalReceived = 0;
        userStatsTotalSent = 0;
        for (int i = 0; i < userStats.length; i++) {
          if (userStats[i].total > 0) {
            userStatsTotalReceived += userStats[i].total;
          } else {
            userStatsTotalSent += userStats[i].total;
          }
        }
      });
    } catch (exception) {
      showErrorSnackbar(this, "Unable to fetch user pay stats: $exception");
    }
  }

  void delete(int index) async {
    var nick = stats[index].item2;
    if (nick == "") {
      nick = stats[index].item1;
    }
    confirmationDialog(context, () async {
      try {
        await Golib.clearPayStats(stats[index].item1);
        listPayStats();
      } catch (exception) {
        showErrorSnackbar(this, "Unable to clear stats: $exception");
      }
    }, "Clear data?", "Really clear data for user $nick?", "Clear", "Cancel");
  }

  @override
  void initState() {
    super.initState();
    listPayStats();
  }

  Widget _summaryCard(String label, int mAtoms) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF9A9A9A), fontSize: 11, letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(formatDCR(milliatomsToDCR(mAtoms)),
              style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                  fontSize: 17,
                  color: Color(0xFFF5F5F5))),
        ],
      ),
    );
  }

  Widget _statRow(int index, int maxSent) {
    final t = stats[index];
    final nick = t.item2.isNotEmpty ? t.item2 : "User fees";
    final sent = t.item3.totalSent;
    final recv = t.item3.totalReceived;
    final sel = index == selectedIndex;
    final frac = maxSent > 0 ? (sent / maxSent).clamp(0.0, 1.0) : 0.0;
    const mono = TextStyle(
        fontFeatures: [FontFeature.tabularFigures()],
        fontSize: 13,
        color: Color(0xFFF5F5F5));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => select(index),
        hoverColor: const Color(0xFF141414),
        child: Container(
          decoration: BoxDecoration(
            color: sel ? const Color(0xFF141A1A) : null,
            border: Border(
              bottom: const BorderSide(color: Color(0xFF1A1A1A), width: 1),
              left: BorderSide(
                  color: sel ? const Color(0xFF2DD8A3) : Colors.transparent,
                  width: 3),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
          child: Row(children: [
            SizedBox(
                width: 20,
                child: Text("${index + 1}",
                    style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()],
                        fontSize: 12,
                        color: Color(0xFF6B6B6B)))),
            const SizedBox(width: 6),
            // Deliberate improvement over the literal exitus1 port: use the
            // real avatar widget (so it inherits the monochrome-avatars
            // setting) instead of an ad-hoc initial-letter circle.
            UserAvatarFromID(client, t.item1, radius: 12, nick: nick),
            const SizedBox(width: 9),
            Expanded(
                child: Text(nick,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFFE6E6E6), fontSize: 13))),
            SizedBox(
              width: 140,
              height: 20,
              child: Stack(children: [
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: frac,
                      child: Container(
                          decoration: BoxDecoration(
                              color: const Color(0xFF12312A),
                              borderRadius: BorderRadius.circular(3))),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(milliatomsToDCR(sent).toStringAsFixed(8),
                        style: mono),
                  ),
                ),
              ]),
            ),
            SizedBox(
              width: 140,
              child: Text(milliatomsToDCR(recv).toStringAsFixed(8),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                      fontSize: 13,
                      color: recv > 0
                          ? const Color(0xFFCED4D2)
                          : const Color(0xFF5A5A5A))),
            ),
            SizedBox(
              width: 34,
              child: IconButton(
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  onPressed: () => delete(index),
                  icon: const Icon(Icons.delete_outline,
                      color: Color(0xFF6B6B6B))),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _redesignedStats(ThemeNotifier theme) {
    int grandSent = 0, grandRecv = 0, maxSent = 1;
    for (final s in stats) {
      grandSent += s.item3.totalSent;
      grandRecv += s.item3.totalReceived;
      if (s.item3.totalSent > maxSent) maxSent = s.item3.totalSent;
    }
    const hdrStyle =
        TextStyle(color: Color(0xFF6B6B6B), fontSize: 11, letterSpacing: 0.5);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(children: [
          Row(children: [
            Expanded(child: _summaryCard("Total sent", grandSent)),
            const SizedBox(width: 10),
            Expanded(child: _summaryCard("Total received", grandRecv)),
          ]),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: const [
              SizedBox(width: 26, child: Text("#", style: hdrStyle)),
              Expanded(child: Text("User", style: hdrStyle)),
              SizedBox(
                  width: 140,
                  child: Text("Sent (DCR)",
                      textAlign: TextAlign.right, style: hdrStyle)),
              SizedBox(
                  width: 140,
                  child: Text("Received (DCR)",
                      textAlign: TextAlign.right, style: hdrStyle)),
              SizedBox(width: 34),
            ]),
          ),
          const SizedBox(height: 6),
          Expanded(
            flex: 5,
            child: ListView.builder(
                itemCount: stats.length,
                padding: EdgeInsets.zero,
                itemBuilder: (context, index) => _statRow(index, maxSent)),
          ),
          const Divider(),
          _userStatsPanel(theme),
        ]),
      )),
    );
  }

  Widget _userStatsPanel(ThemeNotifier theme) => userStats.isNotEmpty
      ? Expanded(
          flex: 2,
          child: Container(
              color: theme.colors.surface,
              child: Row(children: [
                Expanded(
                  flex: 2,
                  child: Column(children: [
                    Row(children: [
                      const Text("Total Sent"),
                      const SizedBox(width: 50),
                      Text(
                          textAlign: TextAlign.right,
                          formatDCR(milliatomsToDCR(userStatsTotalSent))),
                    ]),
                    const Divider(),
                    Expanded(
                        child: SimpleInfoGrid(
                      userStats
                          .map<Tuple2<Widget, Widget>>((e) => Tuple2(
                              e.total < 0 ? Text(e.prefix) : const Empty(),
                              e.total < 0
                                  ? Text(formatDCR(milliatomsToDCR(e.total)))
                                  : const Empty()))
                          .toList(),
                      controller: userStatsSentCtrl,
                    ))
                  ]),
                ),
                Expanded(
                  flex: 2,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Text("Total Received"),
                          const SizedBox(width: 50),
                          Text(
                              textAlign: TextAlign.right,
                              formatDCR(
                                  milliatomsToDCR(userStatsTotalReceived))),
                        ]),
                        const Divider(),
                        Expanded(
                            child: SimpleInfoGrid(
                          userStats
                              .map<Tuple2<Widget, Widget>>((e) => Tuple2(
                                  e.total > 0 ? Text(e.prefix) : const Empty(),
                                  e.total > 0
                                      ? Text(
                                          formatDCR(milliatomsToDCR(e.total)))
                                      : const Empty()))
                              .toList(),
                          controller: userStatsReceivedCtrl,
                        ))
                      ]),
                )
              ])))
      : const Empty();

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    if (theme.areaStyle(ThemeArea.stats).payStatsCardStyle) {
      return _redesignedStats(theme);
    }

    var evenBgColor = theme.colors.surfaceDim;
    var oddBgColor = theme.colors.surfaceBright;
    var evenTxtStyle =
        theme.textStyleFor(context, TextSize.small, TextColor.onSurface);
    var oddTxtStyle =
        theme.textStyleFor(context, TextSize.small, TextColor.onSurface);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        const Row(children: [
          SizedBox(width: 100, child: Txt.S("User")),
          SizedBox(width: 105, child: Txt.S("Sent (atoms)")),
          SizedBox(width: 130, child: Txt.S(" Received (atoms) ")),
        ]),
        const SizedBox(height: 5),
        Expanded(
          flex: 5,
          child: ListView.builder(
              itemCount: stats.length,
              padding: const EdgeInsets.all(0),
              itemBuilder: (context, index) => Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    horizontalTitleGap: 0,
                    minVerticalPadding: 0,
                    contentPadding: const EdgeInsets.all(3),
                    tileColor: index.isEven ? evenBgColor : oddBgColor,
                    selectedColor: index.isEven ? evenBgColor : oddBgColor,
                    onTap: () => select(index),
                    shape: index == selectedIndex
                        ? Border.all(color: theme.colors.primary)
                        : null,
                    title: Row(children: [
                      SizedBox(
                          width: 100,
                          child: Text(
                              stats[index].item2.isNotEmpty
                                  ? stats[index].item2
                                  : "User fees",
                              style: index.isOdd ? oddTxtStyle : evenTxtStyle)),
                      SizedBox(
                          width: 110,
                          child: Text("${stats[index].item3.totalSent}",
                              style: index.isOdd ? oddTxtStyle : evenTxtStyle)),
                      SizedBox(
                          width: 130,
                          child: Text("${stats[index].item3.totalReceived}",
                              style: index.isOdd ? oddTxtStyle : evenTxtStyle)),
                      const Expanded(child: Empty()),
                      IconButton(
                          iconSize: 18,
                          padding: const EdgeInsets.all(0),
                          onPressed: () {
                            delete(index);
                          },
                          icon: const Icon(Icons.delete)),
                    ]),
                  ))),
        ),
        const Divider(),
        _userStatsPanel(theme),
      ]),
    );
  }
}
