import 'package:bruig/components/md_elements.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/theming_system/editor/area_editor_context.dart';
import 'package:bruig/theming_system/editor/areas/buttons.dart';
import 'package:bruig/theming_system/editor/areas/markdown.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// area_editor_test.dart covers the theme editor's per-area settings pages.
//
// What it pins so far is where they open. An area editor is built fresh every
// time the page is come back to -- switching to another area and back is
// enough -- so anything the editor itself remembers, as opposed to anything
// the theme holds, has to outlive its State or it is lost between one edit
// and the next.

/// _FakeHost stands in for the areas section, which owns the controls whose
/// state or layout it rather than the context builds.
///
/// The sliders and spacing controls come back as blanks: what is being
/// measured here is the picker at the top of the page, and building the real
/// ones would drag in the whole settings screen.
class _FakeHost implements AreaEditorHost {
  AreaStyle style = const AreaStyle();

  @override
  void setAreaStyle(
          ThemeNotifier theme, AreaStyle Function(AreaStyle) update) =>
      style = update(style);

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
  List<Widget> areaSpacing(AreaEditorContext ctx,
          {required String key,
          required String name,
          required double max,
          required double single,
          required SideValues? sides,
          required List<String> slotLabels,
          required ValueChanged<double> onSingle,
          required void Function(SideValues? Function(SideValues?, double))
              updateSides}) =>
      const [SizedBox.shrink()];

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

/// _pumpArea builds one area's settings page, the way the settings screen
/// does. Each call builds it afresh, which is exactly the thing under test.
Future<void> _pumpArea(
  WidgetTester tester,
  ThemeArea area,
  List<Widget> Function(AreaEditorContext) editor,
) async {
  var host = _FakeHost();
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
              children: editor(AreaEditorContext(
                host,
                theme: theme,
                preset: ThemePreset.seedFor(Brightness.dark),
                area: area,
                style: host.style,
              )),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// _choose opens the picker labelled [label] and taps the entry [value].
///
/// Found through its label rather than by type: these pages carry several
/// dropdowns and the ones being driven here are typed on enums the editor
/// keeps private, so there is no type to name from out here.
Future<void> _choose(WidgetTester tester, String label, String value) async {
  var picker = find.descendant(
    of: find
        .ancestor(of: find.text("$label: "), matching: find.byType(Row))
        .first,
    matching: find.byWidgetPredicate((w) => w is DropdownButton),
  );
  await tester.tap(picker.first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Reported: choosing an element, going to another page and coming back put
  // the editor on Text and headings again, so the place had to be found
  // before every edit.
  //
  // Both halves are one test on purpose. Where the page opens is remembered
  // for as long as the app is running, so a separate test for the starting
  // element would pass or fail on which order the two were run in.
  testWidgets("the Markdown area opens where it was left", (tester) async {
    await _pumpArea(tester, ThemeArea.markdown, markdownAreaEditor);
    expect(find.text("Text and headings"), findsWidgets,
        reason: "nothing chosen yet, so the first element");

    await _choose(tester, "Element", "Callouts and cards");
    expect(find.text("Callouts and cards"), findsWidgets);

    // Built afresh, exactly as coming back to the page does.
    await _pumpArea(tester, ThemeArea.markdown, markdownAreaEditor);
    expect(find.text("Callouts and cards"), findsWidgets,
        reason: "coming back puts you where you were working");
  });

  // The same defect in the Buttons area, which picks a role the same way.
  testWidgets("the Buttons area opens where it was left", (tester) async {
    await _pumpArea(tester, ThemeArea.buttons, buttonsAreaEditor);
    expect(find.text("Button 1 - Primary"), findsWidgets);

    await _choose(tester, "Button", "Button 3 - Outlined");
    await _pumpArea(tester, ThemeArea.buttons, buttonsAreaEditor);
    expect(find.text("Button 3 - Outlined"), findsWidgets);
  });
}
