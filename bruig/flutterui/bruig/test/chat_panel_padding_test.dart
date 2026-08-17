import 'package:bruig/components/md_elements.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/theming_system/editor/area_editor_context.dart';
import 'package:bruig/theming_system/editor/areas/chat.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// chat_panel_padding_test.dart covers the Chat area's Panel padding reaching
// every message layout.
//
// Reported: Panel padding does nothing on the Default layout, while working
// on the other two. It was gated twice over -- on the layout being non-
// standard, and on "Expand to fill panel" -- because it shipped alongside
// them. It is not one of them: those two decide the width of a *message*,
// this is the room around the whole conversation viewport, and a conversation
// can want breathing room at its edges whatever shape its bubbles are.
//
// The gate also left the editor in a state worth remembering. "Expand to fill
// panel" is only shown on a non-standard layout, but its value survives
// switching back to Default -- so on Default the Panel padding slider still
// appeared, at whatever value it had been given, and moved nothing at all.

/// _RecordingHost stands in for the areas section and writes down which
/// spacing controls the editor asked for.
///
/// The controls come back as blanks: what is being measured is *which* ones a
/// page offers, and building the real ones would drag in the whole settings
/// screen.
class _RecordingHost implements AreaEditorHost {
  AreaStyle style;
  _RecordingHost(this.style);

  final List<String> spacingKeys = [];

  @override
  void setAreaStyle(
          ThemeNotifier theme, AreaStyle Function(AreaStyle) update) =>
      style = update(style);

  @override
  List<Widget> areaSpacing(AreaEditorContext ctx,
      {required String key,
      required String name,
      required double max,
      required double single,
      required SideValues? sides,
      required List<String> slotLabels,
      required ValueChanged<double> onSingle,
      required void Function(SideValues? Function(SideValues?, double))
          updateSides}) {
    spacingKeys.add(key);
    return const [SizedBox.shrink()];
  }

  @override
  Widget areaSlider(
          String key,
          double value,
          String Function(double)? label,
          double min,
          double max,
          int? divisions,
          bool numberField,
          ValueChanged<double> onCommit) =>
      const SizedBox.shrink();

  @override
  Future<String?> copyPickedImage(ThemeNotifier theme,
          {required String suffix,
          required String dialogTitle,
          List<String> extensions = const []}) async =>
      null;

  @override
  Widget areaImagePreview(String? relPath, String? sourceDir,
          {AreaImagePreset? defaultPreset,
          String? assetFallback,
          VoidCallback? onPick}) =>
      const SizedBox.shrink();
}

Future<_RecordingHost> _pumpChatEditor(
    WidgetTester tester, AreaStyle style) async {
  var host = _RecordingHost(style);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeNotifier>(
          create: (c) => ThemeNotifier(doLoad: false)),
      ChangeNotifierProvider<PaymentsModel>(create: (c) => PaymentsModel()),
      ChangeNotifierProvider<MarkdownAreaModel>(
          create: (c) => MarkdownAreaModel("/tmp")),
    ],
    child: Consumer<ThemeNotifier>(
      builder: (context, theme, _) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: chatAreaEditor(AreaEditorContext(
                host,
                theme: theme,
                preset: ThemePreset.seedFor(Brightness.dark),
                area: ThemeArea.chat,
                style: host.style,
              )),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  return host;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group("the editor offers Panel padding in every layout", () {
    testWidgets("including Default, where it used to do nothing",
        (tester) async {
      for (var layout in [
        // Default, both ways it can be recorded: unset, and set explicitly.
        const AreaStyle(),
        const AreaStyle(messageLayoutMode: MessageLayoutMode.standard),
        const AreaStyle(messageLayoutMode: MessageLayoutMode.leftAlign),
        const AreaStyle(messageLayoutMode: MessageLayoutMode.narrow),
      ]) {
        var host = await _pumpChatEditor(tester, layout);
        expect(host.spacingKeys, contains("expandMessagePadding"),
            reason: "${layout.messageLayoutMode}");
      }
    });

    testWidgets("whether or not the message width is expanded", (tester) async {
      for (var expand in [false, true]) {
        var host = await _pumpChatEditor(
            tester, AreaStyle(expandMessageWidth: expand));
        expect(host.spacingKeys, contains("expandMessagePadding"),
            reason: "expandMessageWidth: $expand");
      }
    });
  });

  group("the padding itself", () {
    test("is nothing at all until it is set", () {
      // The chat has always filled the panel edge to edge, and an untouched
      // theme has to keep doing that.
      expect(const AreaStyle().expandMessagePaddings, SideValues.all(0));
      expect(const AreaStyle().toJson().containsKey("expandMessagePadding"),
          isFalse);
    });

    test("does not depend on the layout or on the expand toggle", () {
      // The contract the render path relies on: what comes out of here is the
      // padding, full stop. active_chat.dart applies it as it is given, and
      // the bug was a gate in front of this rather than anything in it.
      for (var layout in MessageLayoutMode.values) {
        for (var expand in [false, true]) {
          var style = AreaStyle(
            messageLayoutMode: layout,
            expandMessageWidth: expand,
            expandMessagePadding: 16,
          );
          expect(style.expandMessagePaddings, SideValues.all(16),
              reason: "$layout / expand: $expand");
        }
      }
    });

    test("splits per side, so each edge can differ", () {
      var style = AreaStyle(
        expandMessagePadding: 8,
        // left, top, right, bottom.
        expandMessagePaddingSides: SideValues([0, 4, 0, 20]),
      );
      expect(style.expandMessagePaddings.top, 4);
      expect(style.expandMessagePaddings.bottom, 20);
    });

    test("round-trips", () {
      var back = AreaStyle.fromJson(
          const AreaStyle(expandMessagePadding: 24).toJson());
      expect(back.expandMessagePadding, 24);
    });
  });
}
