import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_item.dart';
import 'package:bruig/plugin_system/canvas/model/procedural_spec.dart';
import 'package:bruig/plugin_system/canvas/model/text_spec.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_parts.dart';
import 'package:bruig/plugin_system/canvas/model/text_document.dart';
import 'package:bruig/plugin_system/canvas/model/elements/text_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_estimate.dart';
import 'dart:math' as math;
import 'package:bruig/storage_manager.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_numbers.dart';
import 'package:bruig/plugin_system/canvas/model/chart_interval.dart';
import 'package:bruig/models/snackbar.dart';
import 'dart:io';
import 'dart:convert';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/canvas_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_animation.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_scene.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/model/elements/image_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/path_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/shape_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/player_element.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/model/elements/chart_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/counter_element.dart';
import 'package:bruig/plugin_system/canvas/model/elements/table_element.dart';
import 'package:bruig/plugin_system/canvas/ui/chart_data_editor.dart';
import 'package:bruig/plugin_system/canvas/ui/table_data_editor.dart';
import 'package:bruig/plugin_system/canvas/model/data_presets.dart';
import 'package:bruig/plugin_system/canvas/model/data_source.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/guides_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_settings_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_timeline.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/element_settings_pane.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/components/panel_stack.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/presets_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/canvas_sidebar.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/layers_panel.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// canvas_editor_test.dart builds the controls and uses them.
//
// The point of testing them as widgets rather than testing the controller is
// that a control which is drawn but wired to nothing passes every model test
// there is. The settings band and the timeline are almost entirely wiring, so
// wiring is what these check: tap the thing, look at the document.

void main() {
  var published = 0;
  setUp(() => published = 0);

  Future<void> pump(WidgetTester tester, Widget child,
      {CanvasPreferences? prefs}) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false)),
        // Pressing Refresh says what came back, and says it through this.
        ChangeNotifierProvider<SnackBarModel>(create: (c) => SnackBarModel()),
        // Always provided, not only when a test brought its own. A table's
        // Data section reads whether fetching is allowed, and the app always
        // has these -- a settings panel that worked in the app and threw in a
        // test would be a test harness lying about the app.
        prefs == null
            ? ChangeNotifierProvider<CanvasPreferences>(
                create: (c) => CanvasPreferences())
            : ChangeNotifierProvider<CanvasPreferences>.value(value: prefs),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    ));
    await tester.pumpAndSettle();
  }

  group("the settings band", () {
    /// bar builds the band. Every test needs the two canvas-settings
    /// parameters, and none of them cares what they are, because the panel
    /// those drive is a separate widget the screen floats over the canvas.
    Widget bar(CanvasController controller,
            {bool open = false,
            VoidCallback? toggle,
            VoidCallback? showSidebar}) =>
        CanvasSettingsBar(
          controller: controller,
          onPublish: () => published++,
          canvasSettingsOpen: open,
          onToggleCanvasSettings: toggle ?? () {},
          guidesOpen: false,
          onToggleGuides: () {},
          timelineOpen: true,
          onToggleTimeline: () {},
          onShowSidebar: showSidebar,
        );

    testWidgets("is one line, open or closed", (tester) async {
      // The whole point of splitting the panel out. As a second row inside the
      // band, opening the canvas settings pushed the canvas down -- the design
      // jumped and the zoom changed under whatever was being looked at.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);

      tester.view.physicalSize = const Size(700, 900);
      await pump(tester, bar(controller));
      var closed = tester.getSize(find.byType(CanvasSettingsBar)).height;

      await pump(tester, bar(controller, open: true));
      expect(tester.getSize(find.byType(CanvasSettingsBar)).height, closed,
          reason: "opening the settings must not change the band's height");
      expect(closed, lessThan(50), reason: "one line, always");
      expect(tester.takeException(), isNull);
    });

    testWidgets("the canvas settings button reports its state", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);

      var toggled = 0;
      await pump(tester, bar(controller, toggle: () => toggled++));
      await tester.tap(find.byTooltip("Canvas settings"));
      await tester.pumpAndSettle();
      expect(toggled, 1);
    });

    testWidgets("carries no element settings until they are asked for",
        (tester) async {
      // The band is one line unless the button has been pressed, and selecting
      // something is not pressing the button. A line that appears because an
      // element was selected is a line that has to be dismissed again after
      // every selection.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.text, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);

      await pump(tester, bar(controller));
      var oneLine = tester.getSize(find.byType(CanvasSettingsBar)).height;

      controller.selectOnly(element.id);
      await tester.pumpAndSettle();

      expect(find.byTooltip("Try the next variation"), findsNothing);
      expect(tester.getSize(find.byType(CanvasSettingsBar)).height, oneLine,
          reason: "selecting something does not open the second line");
    });

    testWidgets("the band no longer carries the element settings",
        (tester) async {
      // They were a second line here as well as in both sidebar tabs, because
      // the things they belong with were in different tabs and each place kept
      // a copy to shorten the journey. Adding, the layers and the settings are
      // one column now -- see CanvasDesignPanel -- so the band is back to
      // being about the canvas rather than about what is on it.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.text, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);

      await pump(tester, bar(controller));
      expect(find.byIcon(Icons.format_paint_outlined), findsNothing);
      expect(find.text("Opacity"), findsNothing);
    });

    testWidgets("offers both frame buttons", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, bar(controller));

      expect(controller.fit, CanvasFit.whole);
      await tester.tap(find.byTooltip(
          "${CanvasFit.width.label} — the canvas scrolls if it is taller "
          "than the window"));
      await tester.pumpAndSettle();
      expect(controller.fit, CanvasFit.width);

      await tester.tap(find.byTooltip(CanvasFit.whole.label));
      await tester.pumpAndSettle();
      expect(controller.fit, CanvasFit.whole);
    });

    testWidgets("turns the editing helpers off", (tester) async {
      // A pitch of twenty-two dots with a box and eight handles over one of
      // them is a picture of an editor, not a picture of a formation.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, bar(controller));

      expect(controller.showHelpers, isTrue, reason: "on by default");
      await tester.tap(find.byTooltip("Hide the selection box and handles"));
      await tester.pumpAndSettle();
      expect(controller.showHelpers, isFalse);

      await tester.tap(find.byTooltip("Show the selection box and handles"));
      await tester.pumpAndSettle();
      expect(controller.showHelpers, isTrue);
    });

    testWidgets("offers the two tools", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, bar(controller));

      await tester.tap(find.byTooltip(
          "${CanvasTool.pan.label} — ${CanvasTool.pan.description}"));
      await tester.pumpAndSettle();
      expect(controller.tool, CanvasTool.pan);

      await tester.tap(find.byTooltip(
          "${CanvasTool.select.label} — ${CanvasTool.select.description}"));
      await tester.pumpAndSettle();
      expect(controller.tool, CanvasTool.select);
    });

    testWidgets("hides and restores the sidebar", (tester) async {
      // The same pair of controls the Writing page has. A hidden sidebar with
      // no way back is a trap, so the restore control lives in the band, where
      // everything else on the page already is.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);

      var hidden = 0;
      await pump(
          tester,
          CanvasSidebarShell(
            panel: CanvasPanel.files,
            onPanelChanged: (_) {},
            onHide: () => hidden++,
            child: const SizedBox(),
          ));
      await tester.tap(find.byTooltip("Hide the sidebar"));
      await tester.pumpAndSettle();
      expect(hidden, 1);

      // While it is showing, the band carries no restore control.
      await pump(tester, bar(controller));
      expect(find.byTooltip("Show the sidebar"), findsNothing);

      var shown = 0;
      await pump(tester, bar(controller, showSidebar: () => shown++));
      await tester.tap(find.byTooltip("Show the sidebar"));
      await tester.pumpAndSettle();
      expect(shown, 1);
    });

    testWidgets("publish, undo and redo are pinned to the band",
        (tester) async {
      // They used to float over the top-right corner of the canvas, on top of
      // the design. Publish is an icon now, so the tooltip is what names it.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, bar(controller));

      expect(find.byTooltip("Undo"), findsOneWidget);
      expect(find.byTooltip("Redo"), findsOneWidget);

      await tester.tap(find.byTooltip("Publish this canvas"));
      await tester.pumpAndSettle();
      expect(published, 1);
    });
  });

  group("the canvas settings panel", () {
    testWidgets("changes the canvas width", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasSettingsPanel(controller: controller));

      var field = find.byKey(const ValueKey("canvasWidth"));
      expect(field, findsOneWidget);
      expect(find.descendant(of: field, matching: find.text("1280")),
          findsOneWidget,
          reason: "it should show the current width");

      await tester.enterText(field, "800");
      await tester.pump();
      // The width published at. The design keeps the space it was laid out
      // in and is scaled on the way out -- see CanvasSize.
      expect(controller.document.size.exportWidth, 800);
      // The height follows the ratio rather than being edited separately.
      expect(controller.document.size.exportHeight, 450);
      expect(controller.document.size.width, 1280,
          reason: "nothing in the design has moved");
    });

    testWidgets("changes the ratio", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasSettingsPanel(controller: controller));

      await tester.tap(find.text("16:9").first);
      await tester.pumpAndSettle();
      await tester.tap(find.text("1:1").last);
      await tester.pumpAndSettle();

      expect(controller.document.size.ratio, CanvasRatio.square);
      expect(controller.document.size.height, controller.document.size.width);
    });

    testWidgets("shows what publishing will cost", (tester) async {
      // Moved here from a chip floating over the bottom-left corner of the
      // canvas. It belongs with the two settings that decide it.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasSettingsPanel(controller: controller));

      expect(find.text("ESTIMATED SIZE"), findsOneWidget);
      expect(find.text("PNG"), findsOneWidget,
          reason: "a size with no format beside it is a number without a "
              "question");

      // A still is offered the still formats and an animation the moving
      // ones: a GIF of a still is a still, and a PNG of an animation is one
      // frame of it.
      controller.apply(controller.document.copyWith(frames: 24));
      await tester.pumpAndSettle();
      expect(find.text("GIF"), findsOneWidget);
      expect(find.text("PNG"), findsNothing);
    });

    testWidgets("and the estimate is for the file it will be", (tester) async {
      // The same canvas is four hundred kilobytes as a PNG and forty as a
      // JPEG at 85, so the format and the quality are settings.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasSettingsPanel(controller: controller));

      String shown() => tester
          .widgetList<Text>(find.descendant(
              of: find.ancestor(
                  of: find.text("ESTIMATED SIZE"),
                  matching: find.byType(CanvasControlGroup)),
              matching: find.byType(Text)))
          .map((t) => t.data ?? "")
          .firstWhere((t) => t.contains("B"), orElse: () => "");

      var asPng = shown();
      expect(find.text("Quality"), findsNothing,
          reason: "PNG packs harder or less hard and never looks different");

      await tester.tap(find.byKey(const ValueKey("estimateAs")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("JPEG").last);
      await tester.pumpAndSettle();

      expect(controller.document.estimate.format, EstimateAs.jpeg);
      expect(find.text("Quality"), findsOneWidget);
      expect(shown(), isNot(asPng), reason: "a JPEG is not a PNG: $asPng");
    });

    testWidgets("the frame rate is chosen by name or typed", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasSettingsPanel(controller: controller));

      await tester.tap(find.byKey(const ValueKey("canvasRatePreset")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("30 fps").last);
      await tester.pumpAndSettle();
      expect(controller.document.frameRate, 30);

      // And anything else in the box beside it, which then says Custom rather
      // than borrowing a name that would be untrue.
      await tester.enterText(find.byKey(const ValueKey("canvasRate")), "25");
      await tester.pumpAndSettle();
      expect(controller.document.frameRate, 25);
      expect(find.text("Custom · 25"), findsOneWidget);
    });

    testWidgets("and follows the shape until somebody chooses one",
        (tester) async {
      // A page has no frames to have a rate between; a screen that moves
      // wants film's twenty-four.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasSettingsPanel(controller: controller));
      expect(controller.document.frameRate, 24);

      await tester.tap(find.byKey(const ValueKey("canvasRatio")));
      await tester.pumpAndSettle();
      await tester.tap(find.text(CanvasRatio.a4.label).last);
      await tester.pumpAndSettle();
      expect(controller.document.frameRate, 1, reason: "a page is a still");

      // But a rate somebody has chosen is theirs, and changing the shape does
      // not overrule it.
      await tester.enterText(find.byKey(const ValueKey("canvasRate")), "12");
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("canvasRatio")));
      await tester.pumpAndSettle();
      await tester.tap(find.text(CanvasRatio.wide.label).last);
      await tester.pumpAndSettle();
      expect(controller.document.frameRate, 12);
    });

    testWidgets("a size can be chosen by the name people use for it",
        (tester) async {
      // Nobody remembers that 1080p is 1920 across, and everybody knows what
      // 1080p is.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasSettingsPanel(controller: controller));

      await tester.tap(find.byKey(const ValueKey("canvasWidthPreset")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("1080p · 1920").last);
      await tester.pumpAndSettle();

      var size = controller.document.size;
      expect([size.exportWidth, size.exportHeight], [1920, 1080],
          reason: "which is what 1080p means");

      // A size that is not one of the named ones says so rather than
      // borrowing a name that would be untrue. The pixels are on the readout
      // beside it.
      controller.apply(controller.document.copyWith(
          size: controller.document.size.copyWith(exportWidth: 1337)));
      await tester.pumpAndSettle();
      expect(find.text("Custom"), findsWidgets);
      expect(find.text("1337 × 752"), findsOneWidget,
          reason: "said once, on the readout");
    });

    testWidgets("and the sizes offered are the ones that shape has",
        (tester) async {
      // A width on its own names nothing: 1920 across is 1080p at sixteen by
      // nine, and on an A4 page it is 1920 by 2716, which is not 1080p and is
      // not any other name either. Offering every width for every shape was
      // offering names that were not true.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasSettingsPanel(controller: controller));

      await tester.tap(find.byKey(const ValueKey("canvasWidthPreset")));
      await tester.pumpAndSettle();
      expect(find.text("1080p · 1920"), findsWidgets);
      expect(find.text("A4 at 150dpi · 1240"), findsNothing,
          reason: "a sheet of paper is not sixteen by nine");
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButton<CanvasRatio>));
      await tester.pumpAndSettle();
      await tester.tap(find.text("A4 · A3 · A5").last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey("canvasWidthPreset")));
      await tester.pumpAndSettle();
      expect(find.text("A4 at 150dpi · 1240"), findsWidgets);
      expect(find.text("1080p · 1920"), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    });

    testWidgets("the size can grow the page instead of the resolution",
        (tester) async {
      // The other half of the answer: sometimes what somebody wants is a
      // bigger sheet rather than a sharper one, and that is what this did
      // before there was a choice.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasSettingsPanel(controller: controller));

      await tester.enterText(find.byKey(const ValueKey("canvasWidth")), "2560");
      await tester.pump();
      expect(controller.document.size.width, 1280,
          reason: "a resolution: the design is where it was");

      // At the end of the line, after the size and the cost: it is set once
      // and left, rather than sitting between the ratio and the width.
      var scaling = find.byKey(const ValueKey("canvasScalesDesign"));
      // The line scrolls sideways, and it grew when the frame rate joined it.
      await tester.ensureVisible(scaling);
      await tester.pumpAndSettle();
      expect(tester.getRect(scaling).left,
          greaterThan(tester.getRect(find.text("ESTIMATED SIZE")).left));

      await tester.tap(scaling);
      await tester.pumpAndSettle();
      expect(controller.document.size.width, 2560,
          reason: "a page: the design space grew with it");
      expect(controller.document.size.exportScale, 1);
    });

    testWidgets("a shape with no named sizes shows no list", (tester) async {
      // A custom ratio has nothing to name, and the width box beside the list
      // is the answer for every shape nobody has a word for.
      var controller = CanvasController(const CanvasDocument(
          size: CanvasSize(ratio: CanvasRatio.custom, customRatio: 2.3)));
      addTearDown(controller.dispose);
      await pump(tester, CanvasSettingsPanel(controller: controller));

      expect(find.byKey(const ValueKey("canvasWidthPreset")), findsNothing);
      expect(find.byKey(const ValueKey("canvasWidth")), findsOneWidget);
    });

    testWidgets("and paper is a ratio like any other", (tester) async {
      // A3, A4 and A5 are the same shape -- halving an A-size folds it in
      // half -- so they are one ratio, and what tells them apart is a width.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasSettingsPanel(controller: controller));

      await tester.tap(find.byType(DropdownButton<CanvasRatio>));
      await tester.pumpAndSettle();
      await tester.tap(find.text("A4 · A3 · A5").last);
      await tester.pumpAndSettle();

      var size = controller.document.size;
      expect(size.ratio, CanvasRatio.a4);
      expect(size.height / size.width, closeTo(297 / 210, 0.01),
          reason: "taller than it is wide, in the paper proportion");
    });

    testWidgets("does not overflow a narrow window", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(700, 900);
      await pump(tester, CanvasSettingsPanel(controller: controller));
      expect(tester.takeException(), isNull);
    });

    testWidgets("typing a width is one undo step", (tester) async {
      // The panel writes transient edits and commits when the control is let
      // go. Without that, typing a four-digit width would be four undo steps.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasSettingsPanel(controller: controller));

      var field = find.byKey(const ValueKey("canvasWidth"));
      await tester.enterText(field, "900");
      await tester.pump();
      await tester.enterText(field, "901");
      await tester.pump();
      controller.endInteraction();

      expect(controller.canUndo, isTrue,
          reason: "a change made through the panel must be undoable at all");
      controller.undo();
      expect(controller.document.size.width, 1280,
          reason: "the whole typed edit is one step, not two");
    });
  });

  group("the design elements panel", () {
    testWidgets("offers every kind, and adding one selects it", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasElementsPanel(controller: controller));

      for (var kind in ElementKind.values) {
        expect(find.text(kind.label), findsWidgets, reason: kind.name);
      }

      await tester.tap(find.text("Chart").first);
      await tester.pumpAndSettle();

      expect(controller.document.elements.length, 1);
      expect(controller.document.elements.single.kind, ElementKind.chart);
      expect(controller.selection, {controller.document.elements.single.id});
    });

    testWidgets("a new element lands inside the canvas", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasElementsPanel(controller: controller));

      await tester.tap(find.text("Text").first);
      await tester.pumpAndSettle();

      var element = controller.document.elements.single;
      var page = controller.document.size.rect;
      expect(page.contains(element.center), isTrue,
          reason: "a new element must be somewhere the reader can see it");
      expect(element.width, greaterThan(0));
      expect(element.height, greaterThan(0));
    });

    testWidgets("is the grid and nothing else", (tester) async {
      // It carried the layer list once and the settings after that, both
      // because the three were in different tabs and each kept a copy of its
      // neighbour. They share a column now, so this is one thing again.
      var document = const CanvasDocument();
      var controller = CanvasController(
          document.addElement(newElement(ElementKind.text, document)));
      addTearDown(controller.dispose);
      await pump(tester, CanvasElementsPanel(controller: controller));

      expect(find.byType(CanvasLayerRow), findsNothing);
      expect(find.text("Opacity"), findsNothing);
    });
  });

  group("the layers panel", () {
    testWidgets("the layer list reorders, hides and locks", (tester) async {
      // A handful of plain elements rather than a preset: the football preset
      // is two team elements now, and swapping two of anything cannot show
      // that a reorder left the rest of the stack alone.
      var document = const CanvasDocument();
      for (var kind in [
        ElementKind.shape,
        ElementKind.text,
        ElementKind.line,
        ElementKind.shape,
      ]) {
        document = document.addElement(newElement(kind, document));
      }
      var controller = CanvasController(document);
      addTearDown(controller.dispose);
      await pump(tester, CanvasDesignPanel(controller: controller));

      var first = controller.document.elements.first;

      await tester.tap(find.byTooltip("Hide").first);
      await tester.pumpAndSettle();
      expect(controller.document.elements.any((e) => !e.visible), isTrue);

      await tester.tap(find.byTooltip("Lock").first);
      await tester.pumpAndSettle();
      expect(controller.document.elements.any((e) => e.locked), isTrue);

      // The list is drawn front-to-back, so its first row is the last element.
      // "Move back" on it must actually change the paint order.
      var before = controller.document.elements.last.id;
      await tester.tap(find.byTooltip("Move back").first);
      await tester.pumpAndSettle();
      expect(controller.document.elements.last.id, isNot(before));
      expect(controller.document.elements.first.id, first.id);
    });

    testWidgets("shows the selected element's settings below the list",
        (tester) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.text, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      await pump(tester, CanvasDesignPanel(controller: controller));

      // Nothing selected: the list, and no settings under it.
      expect(find.text("Fit to box"), findsNothing);

      controller.selectOnly(element.id);
      await tester.pumpAndSettle();
      expect(find.text("Fit to box"), findsWidgets);
    });

    testWidgets("the background is the bottom layer, and selectable",
        (tester) async {
      // It is not an element, so it cannot be reordered into the middle of
      // them -- it is painted before all of them. Showing it in the list is
      // what makes it findable at all; it used to be reachable only by
      // deselecting everything and noticing the band had changed.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.text, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      await pump(tester, CanvasDesignPanel(controller: controller));

      var background = find.byType(CanvasBackgroundLayerRow);
      expect(background, findsOneWidget);
      expect(tester.getCenter(background).dy,
          greaterThan(tester.getCenter(find.byType(CanvasLayerRow).first).dy),
          reason: "the background sits below every element");

      await tester.tap(background);
      await tester.pumpAndSettle();
      expect(controller.backgroundSelected, isTrue);
      expect(controller.selection, isEmpty,
          reason: "selecting the background deselects elements");

      // Its settings are what the panel now shows.
      expect(find.byTooltip("Try the next variation"), findsOneWidget);
      var seed = controller.document.background.spec.seed;
      await tester.tap(find.byTooltip("Try the next variation"));
      await tester.pumpAndSettle();
      expect(controller.document.background.spec.seed, isNot(seed));
    });

    testWidgets("selecting an element deselects the background",
        (tester) async {
      // The two are exclusive: both mean "this is what the settings below the
      // list are about", and there is only one of those.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.text, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);

      controller.selectBackground();
      expect(controller.backgroundSelected, isTrue);

      controller.selectOnly(element.id);
      expect(controller.backgroundSelected, isFalse);
      expect(controller.selection, {element.id});

      controller.selectBackground();
      controller.clearSelection();
      expect(controller.backgroundSelected, isFalse);
    });

    testWidgets("a panel's top edge resizes the one above it", (tester) async {
      // The grip is the header's own top edge rather than a bar of its own: a
      // bar between two panels is a row of pixels that does nothing but be
      // dragged, in a column where every row is wanted for something.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false),
            child: SizedBox(
              width: 280,
              height: 600,
              child: CanvasDesignPanel(controller: controller),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      var before = tester.getSize(find.byType(CanvasLayersPanel)).height;

      // The line between Layers and the settings. Dragging it down gives
      // Layers the room. Taken between two panels that are both open: a shut
      // one is its own header and has no room to give.
      var grip = find
          .byWidgetPredicate((w) =>
              w is MouseRegion && w.cursor == SystemMouseCursors.resizeUpDown)
          .last;
      await tester.drag(grip, const Offset(0, 60));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(CanvasLayersPanel)).height,
          greaterThan(before));
    });

    testWidgets("the stacked settings fit a narrow sidebar", (tester) async {
      // The same controls as the band above the canvas, laid out stacked. A
      // control sized past its parent overflows rather than shrinking, and the
      // chart's data box asks for 260 -- so without the scope's width cap this
      // is a wall of stripes. A chart is the widest element there is.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.chart, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeNotifier>(
                  create: (c) => ThemeNotifier(doLoad: false)),
              // A chart has a data source of its own now, and the panel that
              // fills it in asks whether fetching is allowed.
              ChangeNotifierProvider<CanvasPreferences>(
                  create: (c) => CanvasPreferences()),
            ],
            child: SizedBox(
              width: 260,
              height: 800,
              child: CanvasDesignPanel(controller: controller),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: "the settings column must not overflow the sidebar");
    });
  });

  group("a team's settings", () {
    /// panel pumps the Layers sidebar with a team selected, which is where an
    /// element's settings live.
    Future<CanvasController> panel(WidgetTester tester,
        {TeamElement? team}) async {
      var document = const CanvasDocument(size: CanvasSize(width: 1000));
      var element = (team ??
          TeamElement(
            ElementBase(id: newElementId(), width: 400, height: 300),
          ).withFormation(TeamFormation.f442)) as CanvasElement;
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasDesignPanel(controller: controller));
      return controller;
    }

    TeamElement teamIn(CanvasController c) =>
        c.document.elements.whereType<TeamElement>().single;

    testWidgets("one element is the whole team", (tester) async {
      var controller = await panel(tester);
      expect(teamIn(controller).players.length, 11,
          reason: "ten outfield players and a goalkeeper");
      // The panel header names the element now, so the first group no longer
      // captions itself with the same word.
      expect(find.text("TEAM SETTINGS"), findsOneWidget);
      expect(find.text("PLAYERS"), findsOneWidget);
    });

    testWidgets("choosing a formation moves everybody", (tester) async {
      var controller = await panel(tester);
      var before = [for (var p in teamIn(controller).players) (p.dx, p.dy)];

      // Scrolled to first: every element carries a Presets line at the top
      // of its settings now, so what is below it starts lower down.
      await tester.ensureVisible(find.text("4-4-2").first);
      await tester.pumpAndSettle();
      await tester.tap(find.text("4-4-2").first);
      await tester.pumpAndSettle();
      await tester.tap(find.text("4-3-3").last);
      await tester.pumpAndSettle();

      var after = teamIn(controller);
      expect(after.formation, TeamFormation.f433);
      expect([for (var p in after.players) (p.dx, p.dy)], isNot(before));
      expect(after.players.length, 11);
    });

    testWidgets("the squad list opens and edits one player", (tester) async {
      // Behind an expander because eleven rows of four fields is more than
      // every other element's settings put together.
      var controller = await panel(tester);
      var id = teamIn(controller).id;

      expect(find.byKey(ValueKey("name-0-$id")), findsNothing);
      // Scrolled to first: the squad list is below the fold in a panel this
      // tall, and a tap at a point outside the viewport hits nothing.
      await tester.ensureVisible(find.text("PLAYERS"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("PLAYERS"));
      await tester.pumpAndSettle();

      // The goalkeeper is the first row, and is labelled as such.
      expect(find.text("GK"), findsOneWidget);

      await tester.enterText(find.byKey(ValueKey("name-0-$id")), "Banks");
      await tester.pump();
      expect(teamIn(controller).players.first.name, "Banks");

      await tester.enterText(find.byKey(ValueKey("num-0-$id")), "01");
      await tester.pump();
      expect(teamIn(controller).players.first.number, "01",
          reason: "a squad number is written, not counted");
    });

    testWidgets("a player's coordinates are the canvas's, not the box's",
        (tester) async {
      var team = TeamElement(
        ElementBase(id: newElementId(), x: 100, y: 50, width: 400, height: 300),
      ).withFormation(TeamFormation.f442);
      var controller = await panel(tester, team: team);
      var id = teamIn(controller).id;

      // Scrolled to first: the squad list is below the fold in a panel this
      // tall, and a tap at a point outside the viewport hits nothing.
      await tester.ensureVisible(find.text("PLAYERS"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("PLAYERS"));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(ValueKey("x-0-$id")), "260");
      await tester.pump();
      var keeper = teamIn(controller).players.first;
      expect(teamIn(controller).centreOf(keeper).dx, closeTo(260, 0.5),
          reason: "typed as a canvas coordinate, stored as a fraction");
      expect(keeper.dx, closeTo((260 - 100) / 400, 0.001));
    });

    testWidgets("lock, hide and reorder work per player", (tester) async {
      var controller = await panel(tester);
      // Scrolled to first: the squad list is below the fold in a panel this
      // tall, and a tap at a point outside the viewport hits nothing.
      await tester.ensureVisible(find.text("PLAYERS"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("PLAYERS"));
      await tester.pumpAndSettle();

      /// press taps a control inside one player's row.
      ///
      /// Scoped to the row rather than found by tooltip alone, because the
      /// element's own Lock and Hide sit above the squad list with exactly the
      /// same tooltips -- so `.first` locks the whole team instead of the
      /// goalkeeper. And scrolled into view first: eleven rows of four fields
      /// is taller than the settings column, so most of the squad is below the
      /// fold and a tap at its computed position lands outside the viewport.
      Future<void> press(int index, String tooltip) async {
        var finder = find.descendant(
          of: find.byKey(ValueKey("player-$index-${teamIn(controller).id}")),
          matching: find.byTooltip(tooltip),
        );
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await press(0, "Lock in place");
      expect(teamIn(controller).players.first.locked, isTrue);
      expect(teamIn(controller).locked, isFalse,
          reason: "locking a player must not lock the whole team");

      await press(0, "Hide");
      expect(teamIn(controller).players.first.hidden, isTrue);

      var second = teamIn(controller).players[1].number;
      await press(0, "Bring forward");
      expect(teamIn(controller).players[0].number, second,
          reason: "the keeper moved up one, so the next player is now first");
    });

    testWidgets("the dot's width and height are locked together",
        (tester) async {
      // A player marker is a circle, and an oval is almost always somebody
      // having dragged one field without meaning to.
      var controller = await panel(tester);
      expect(teamIn(controller).lockDotAspect, isTrue);

      await tester.enterText(find.byKey(const ValueKey("teamDotWidth")), "60");
      await tester.pump();
      expect(teamIn(controller).dotWidth, 60);
      expect(teamIn(controller).dotHeight, 60);

      // Scrolled to first: a team has more settings than fit in the panel,
      // and a tap on something below the fold lands on whatever is there.
      var lock = find.byTooltip("Width and height move together");
      await tester.ensureVisible(lock);
      await tester.pumpAndSettle();
      await tester.tap(lock);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey("teamDotHeight")), "20");
      await tester.pump();
      expect(teamIn(controller).dotWidth, 60, reason: "now independent");
      expect(teamIn(controller).dotHeight, 20);
    });

    testWidgets("numbers and names share one set of type controls",
        (tester) async {
      // They were two identical panels, and the two drifted -- a team's names
      // ended up in a different face from its numbers.
      var controller = await panel(tester);
      expect(find.text("NUMBERS AND NAMES"), findsOneWidget);
      expect(teamIn(controller).labelSpec.fontSize, isNotNull);
    });
  });

  group("the timeline", () {
    testWidgets("the master canvas's length is a reading, not a field",
        (tester) async {
      // It is as long as the scenes it covers, worked out rather than kept.
      // As a field it took a number and put the old one back, which reads as
      // the field being broken -- reported as "when I change this it reverts
      // to 3600", alongside the real bug: the run was being clamped to the
      // limit on one scene, so six scenes of 720 came to 3600 and playing the
      // whole document stopped in the middle of the sixth.
      var controller = CanvasController(const CanvasDocument().withScenes([
        for (var i = 0; i < 6; i++)
          CanvasScene(id: "s$i", frames: 720, elements: const []),
      ]).copyWith(
        master: const CanvasScene(id: "m", name: "Master"),
        masterOn: true,
        onMaster: true,
      ));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      expect(find.byKey(const ValueKey("canvasFrames")), findsNothing,
          reason: "nothing to type into");
      expect(
          find.descendant(
              of: find.byKey(const ValueKey("canvasFramesMaster")),
              matching: find.text("4320")),
          findsOneWidget,
          reason: "six scenes of seven hundred and twenty");
    });

    testWidgets("adds and removes a keyframe for the selected element",
        (tester) async {
      var document = const CanvasDocument(frames: 20);
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      controller.frame = 7;

      await pump(tester, CanvasTimeline(controller: controller));

      await tester
          .tap(find.byTooltip("Add a keyframe for ${element.name} here"));
      await tester.pumpAndSettle();

      var track = controller.document.elements.single.track;
      expect(track, isNotNull);
      expect(track!.keyAt(7), isNotNull);

      // The tooltip names what it belongs to, since the same button also
      // edits a focused player's keyframes.
      await tester
          .tap(find.byTooltip("Remove this keyframe from ${element.name}"));
      await tester.pumpAndSettle();
      // The track goes entirely rather than being left empty, so a saved file
      // carries no dead animation.
      expect(controller.document.elements.single.track, isNull);
    });

    testWidgets("says what to do when nothing is selected", (tester) async {
      var controller = CanvasController(const CanvasDocument(frames: 10));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      // On the disclosure itself, since with nothing selected there is
      // nothing to open it for.
      expect(
          find.byTooltip(
              "Select an element, or click a player, to give it a keyframe"),
          findsOneWidget);
    });

    testWidgets("changes the frame count and the frame rate", (tester) async {
      // Both moved here from the settings band: they describe the strip they
      // now sit on.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      expect(find.text("Still"), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey("canvasFrames")), "24");
      await tester.pump();
      expect(controller.document.frames, 24);
      expect(find.text("Still"), findsNothing);

      await tester.enterText(
          find.byKey(const ValueKey("canvasFrameRate")), "30");
      await tester.pump();
      expect(controller.document.frameRate, 30);
      expect(find.text("0.8s"), findsOneWidget);
    });

    testWidgets("the playhead and the length are one editable control",
        (tester) async {
      // They were a readout and a separate Frames field a few pixels apart,
      // saying the same number twice -- and the field was too narrow for four
      // digits, so a long document showed "10000" clipped to "1000".
      var controller = CanvasController(const CanvasDocument(frames: 40));
      addTearDown(controller.dispose);
      controller.frame = 12;
      await pump(tester, CanvasTimeline(controller: controller));

      var playhead = find.byKey(const ValueKey("canvasFrame"));
      var length = find.byKey(const ValueKey("canvasFrames"));
      // One-based on screen: the first frame is frame 1 to everybody except a
      // computer.
      expect(find.descendant(of: playhead, matching: find.text("13")),
          findsOneWidget);
      expect(find.descendant(of: length, matching: find.text("40")),
          findsOneWidget);

      await tester.enterText(playhead, "25");
      await tester.pump();
      expect(controller.frame, 24);

      await tester.enterText(length, "600");
      await tester.pump();
      expect(controller.document.frames, 600);
    });

    testWidgets("a long document's numbers still fit", (tester) async {
      var controller =
          CanvasController(const CanvasDocument(frames: maxFrameCount));
      addTearDown(controller.dispose);
      controller.frame = maxFrameCount - 1;
      await pump(tester, CanvasTimeline(controller: controller));

      expect(tester.takeException(), isNull);
      var length = find.byKey(const ValueKey("canvasFrames"));
      expect(find.descendant(of: length, matching: find.text("$maxFrameCount")),
          findsOneWidget);
      // One line: the control plus its caption. Two would be a caption and
      // two rows of field.
      expect(tester.getSize(length).height,
          lessThan(controlHeight + controlLabelHeight + 4));
    });

    testWidgets("typing in a field keeps its own arrow keys and space bar",
        (tester) async {
      // The transport's Focus sits below the app's text-editing shortcuts, so
      // its handler ran first: an arrow pressed while typing a frame number
      // scrubbed the timeline instead of moving the caret, and a space started
      // playback instead of typing.
      var controller = CanvasController(const CanvasDocument(frames: 40));
      addTearDown(controller.dispose);
      controller.frame = 12;
      await pump(tester, CanvasTimeline(controller: controller));

      await tester.tap(find.byKey(const ValueKey("canvasFrameRate")));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(controller.frame, 12, reason: "the playhead did not move");
      expect(controller.playing, isFalse, reason: "and nothing started");
    });

    testWidgets("steps the playhead", (tester) async {
      var controller = CanvasController(const CanvasDocument(frames: 10));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      expect(
          find.descendant(
              of: find.byKey(const ValueKey("canvasFrame")),
              matching: find.text("1")),
          findsOneWidget);
      await tester.tap(find.byTooltip("Next frame"));
      await tester.pumpAndSettle();
      expect(controller.frame, 1);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey("canvasFrame")),
              matching: find.text("2")),
          findsOneWidget);

      // Clamped rather than wrapping or running past the end.
      await tester.tap(find.byTooltip("Previous frame"));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip("Previous frame"));
      await tester.pumpAndSettle();
      expect(controller.frame, 0);
    });

    testWidgets(
        "the transport row does not move when the playhead lands on a "
        "keyframe", (tester) async {
      // The reported problem: the pose controls sat on the transport row and
      // appeared as the playhead crossed a keyframe, so the row changed width
      // under the pointer and the play buttons moved while scrubbing.
      var document = const CanvasDocument(frames: 20);
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasTimeline(controller: controller));

      var playAt = tester.getTopLeft(find.byTooltip("Play this scene"));
      controller.setKeyframe(element.id, const Keyframe(frame: 0));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.byTooltip("Play this scene")), playAt,
          reason: "landing on a keyframe must not move the transport");
      expect(find.text("Easing"), findsNothing,
          reason: "the pose controls are behind the disclosure");
      // The two keyframe buttons stay on this row -- they are pressed
      // constantly while animating and neither changes width, so neither can
      // shift it.
      expect(find.byTooltip("Remove this keyframe from ${element.name}"),
          findsOneWidget);
      expect(
          find.byTooltip(
              "Auto-keyframe: record a keyframe whenever something moves"),
          findsOneWidget);
    });

    testWidgets("the pose bar floats rather than resizing the strip",
        (tester) async {
      // Opening it must not change the timeline's height: the strip is at the
      // bottom of the screen, so a taller one takes height from the canvas
      // area and re-fits the canvas -- opening a panel moved the design.
      var document = const CanvasDocument(frames: 20);
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      controller.setKeyframe(element.id, const Keyframe(frame: 0));

      var open = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<ThemeNotifier>(
            create: (c) => ThemeNotifier(doLoad: false),
            child: StatefulBuilder(
              builder: (context, setState) => Column(children: [
                const Spacer(),
                CanvasTimeline(
                  controller: controller,
                  keyframesOpen: open,
                  onToggleKeyframes: () => setState(() => open = !open),
                ),
              ]),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      var closed = tester.getSize(find.byType(CanvasTimeline)).height;
      await tester.tap(find.byTooltip("Keyframe settings for ${element.name}"));
      await tester.pumpAndSettle();

      expect(open, isTrue);
      expect(tester.getSize(find.byType(CanvasTimeline)).height, closed,
          reason: "the strip is exactly as tall as it was");
      expect(find.text("Easing"), findsNothing,
          reason: "the controls are in the floating bar, not in the strip");
    });

    testWidgets("the pose bar carries the keyframe's controls", (tester) async {
      var document = const CanvasDocument(frames: 20);
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasKeyframeBar(controller: controller));

      // Opened on a frame with no keyframe it would otherwise be blank, which
      // reads as broken rather than as empty.
      expect(find.textContaining("No keyframe on this frame"), findsOneWidget);

      controller.setKeyframe(element.id, const Keyframe(frame: 0));
      await tester.pumpAndSettle();
      expect(find.text("Easing"), findsOneWidget);

      await tester.tap(find.text("Linear").first);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Ease in-out").last);
      await tester.pumpAndSettle();
      expect(controller.document.elements.single.track!.keyAt(0)!.easing,
          KeyframeEasing.easeInOut);
    });

    testWidgets("auto-keyframe can be turned on from the transport",
        (tester) async {
      var controller = CanvasController(const CanvasDocument(frames: 24));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      expect(controller.autoKeyframe, isFalse, reason: "off by default");
      await tester.tap(find.byTooltip(
          "Auto-keyframe: record a keyframe whenever something moves"));
      await tester.pumpAndSettle();
      expect(controller.autoKeyframe, isTrue);
    });

    testWidgets("keyframes follow the focused player", (tester) async {
      // A player has no id and cannot be selected, so the focused player is
      // the only thing that says the controls are about them rather than about
      // the team they are in.
      var team = TeamElement(
        ElementBase(id: newElementId(), width: 400, height: 300),
      ).withFormation(TeamFormation.f442);
      var controller =
          CanvasController(const CanvasDocument(frames: 24).addElement(team));
      addTearDown(controller.dispose);
      controller.selectOnly(team.id);
      controller.frame = 6;
      await pump(tester, CanvasTimeline(controller: controller));

      controller.focusedPlayer = 4;
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip("Add a keyframe for #5 (Team) here"));
      await tester.pumpAndSettle();

      var after = controller.document.elements.whereType<TeamElement>().single;
      expect(after.players[4].track?.keyAt(6), isNotNull);
      expect(after.track, isNull,
          reason: "the team itself did not get the keyframe");
    });

    testWidgets("adds a timeline marker and lets it be removed",
        (tester) async {
      var controller = CanvasController(const CanvasDocument(frames: 30));
      addTearDown(controller.dispose);
      controller.frame = 12;
      await pump(tester, CanvasTimeline(controller: controller));

      await tester.tap(find
          .byTooltip("Loop back — Jump back to the target frame and carry on"));
      await tester.pumpAndSettle();

      expect(controller.document.actions.single.frame, 12);
      expect(find.text("To frame"), findsOneWidget);

      await tester.tap(find.byTooltip("Remove this marker"));
      await tester.pumpAndSettle();
      expect(controller.document.actions, isEmpty);
    });
  });

  group("what the editor remembers between visits", () {
    test("the timeline is off to begin with, and then what it was left as", () {
      // Most canvases are still designs, and a strip of animation controls
      // under one is room taken from the page. Somebody who does animate
      // turns it on once rather than on every visit.
      SharedPreferences.setMockInitialValues({});
      var prefs = CanvasPreferences();
      addTearDown(prefs.dispose);
      expect(prefs.timeline, isFalse);

      prefs.timeline = true;
      var later = CanvasPreferences();
      addTearDown(later.dispose);
      expect(later.timeline, isFalse, reason: "until it has read the disk");
    });

    test("and whether the bar carries the grid switches", () {
      SharedPreferences.setMockInitialValues({});
      var prefs = CanvasPreferences();
      addTearDown(prefs.dispose);
      expect(prefs.markSwitches, isTrue,
          reason: "there until somebody says otherwise");
      prefs.markSwitches = false;
      expect(prefs.markSwitches, isFalse);
    });
  });

  group("the settings section", () {
    testWidgets("turns Canvas on and off", (tester) async {
      var prefs = CanvasPreferences();
      addTearDown(prefs.dispose);

      await pump(tester, const CanvasSettingsSection(), prefs: prefs);

      // Off by default: a whole page and a nav item has to be asked for.
      expect(prefs.enabled, isFalse);
      expect(find.text("Canvas"), findsOneWidget);

      // The first switch is the feature's own. A second appears under it once
      // Canvas is on -- see the fetching test below -- so this one is taken by
      // position rather than by being the only one there is.
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(prefs.enabled, isTrue);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(prefs.enabled, isFalse);
    });

    testWidgets("fetching is off, and is only offered once Canvas is on",
        (tester) async {
      // Two decisions, and the second is not about a canvas at all: it is
      // about whether this app may open a connection of its own, which
      // nothing else in its interface does. So it is off, it is a switch
      // rather than a default, and it says what the cost is.
      var prefs = CanvasPreferences();
      addTearDown(prefs.dispose);
      await pump(tester, const CanvasSettingsSection(), prefs: prefs);

      expect(prefs.allowFetching, isFalse);
      expect(find.text("Let a canvas fetch data"), findsNothing,
          reason: "nothing to decide while the feature is off");

      prefs.enabled = true;
      await tester.pumpAndSettle();
      expect(find.text("Let a canvas fetch data"), findsOneWidget);
      expect(
          find.textContaining("does not go through the proxy"), findsOneWidget,
          reason: "the reason it is off is the reason it is a decision");

      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      expect(prefs.allowFetching, isTrue);
    });
  });

  group("the clipboard", () {
    test("copy and paste makes a separate element", () {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);

      controller.copySelected();
      expect(controller.canPaste, isTrue);
      controller.paste();

      expect(controller.document.elements.length, 2);
      var pasted = controller.document.elements.last;
      expect(pasted.id, isNot(element.id),
          reason: "a new element, not an alias");
      // Offset, because a copy landing exactly on its original is
      // indistinguishable from nothing having happened.
      expect(pasted.x, greaterThan(element.x));
      expect(controller.selection, {pasted.id},
          reason: "what was pasted is what is selected");
    });

    test("pasting twice makes two copies, each visible", () {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      controller.copySelected();
      controller.paste();
      controller.paste();

      var xs = controller.document.elements.map((e) => e.x).toSet();
      expect(controller.document.elements.length, 3);
      expect(xs.length, 2,
          reason: "both copies are off the original; they may share a place");
    });

    test("cut copies before it deletes", () {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.text, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);

      controller.cutSelected();
      expect(controller.document.elements, isEmpty);

      controller.paste();
      expect(controller.document.elements.length, 1);
      expect(controller.document.elements.single.kind, ElementKind.text);
    });

    test("the clipboard survives the page being left", () {
      // Static, for the same reason the session is a provider: leaving Canvas
      // for a chat and coming back must not lose what was copied.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var first = CanvasController(document.addElement(element));
      first.selectOnly(element.id);
      first.copySelected();
      first.dispose();

      var second = CanvasController(const CanvasDocument());
      addTearDown(second.dispose);
      expect(second.canPaste, isTrue);
      second.paste();
      expect(second.document.elements.length, 1);
    });
  });

  group("autosave", () {
    test("does nothing until the document has been saved once", () {
      // Otherwise there is nowhere to write to, and inventing a filename would
      // leave documents in the library nobody asked to keep -- somebody who
      // opens a preset, plays with it and walks away should find nothing new.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      expect(controller.name, isNull);

      controller.apply(controller.document.copyWith(frames: 12));
      expect(controller.dirty, isTrue);
      // scheduleAutosave is called by apply; with no name it must arm nothing.
      controller.scheduleAutosave();
      expect(controller.name, isNull,
          reason: "and it certainly must not invent one");
    });
  });

  group("the session", () {
    test("outlives the page, and only restores on its first open", () {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      expect(controller.opened, isFalse,
          reason: "the first visit restores the last saved file");

      controller.markOpened();
      expect(controller.opened, isTrue,
          reason: "every visit after that keeps the work in progress");
    });
  });

  group("a path on the timeline", () {
    (CanvasController, PathElement) withPath() {
      var path = PathElement(
        const ElementBase(id: "p", x: 0, y: 0, width: 200, height: 200),
        nodes: const [
          PathNode(x: 0, y: 0, frame: 0),
          PathNode(x: 0.5, y: 0.5, frame: 10),
          PathNode(x: 1, y: 1, frame: 20),
        ],
      );
      var controller =
          CanvasController(const CanvasDocument(frames: 30).addElement(path));
      controller.selectOnly("p");
      return (controller, path);
    }

    testWidgets("the strip is about its points, not its (empty) track",
        (tester) async {
      // A path's own track is empty -- what moves is the follower -- so
      // without this a selected path showed a bare strip, and the one thing
      // worth retiming from the timeline could not be reached from it.
      var (controller, _) = withPath();
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      controller.frame = 10;
      await tester.pumpAndSettle();
      expect(find.byTooltip("Remove this keyframe from Path"), findsOneWidget,
          reason: "frame 10 has a point on it");

      controller.frame = 11;
      await tester.pumpAndSettle();
      expect(find.byTooltip("Add a keyframe for Path here"), findsOneWidget);
    });

    testWidgets("the diamond adds and removes a point", (tester) async {
      var (controller, _) = withPath();
      addTearDown(controller.dispose);
      controller.frame = 15;
      await pump(tester, CanvasTimeline(controller: controller));

      // The pose bar is a message for a path: easing, fade, scale and turn all
      // belong to the follower rather than to the point, so offering them here
      // would be four controls that quietly do nothing.
      await pump(tester, CanvasKeyframeBar(controller: controller));
      expect(find.textContaining("No point on this frame"), findsOneWidget);

      await pump(tester, CanvasTimeline(controller: controller));
      await tester.tap(find.byTooltip("Add a keyframe for Path here"));
      await tester.pumpAndSettle();

      var after = controller.document.elements.single as PathElement;
      expect(after.nodes.length, 4);
      expect(after.nodes.map((n) => n.frame).toList(), [0, 10, 15, 20]);

      await tester.tap(find.byTooltip("Remove this keyframe from Path"));
      await tester.pumpAndSettle();
      expect(
          (controller.document.elements.single as PathElement).nodes.length, 3);
    });

    testWidgets("a point drags along the strip to retime it", (tester) async {
      var (controller, _) = withPath();
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      // The ruler is the strip's own CustomPaint, and the marks sit at
      // _rulerHeight + 14 down it -- see _keyframeAt, which is what this is
      // exercising.
      var ruler = find
          .descendant(
              of: find.byType(CanvasTimeline),
              matching: find.byType(CustomPaint))
          .last;
      var box = tester.getRect(ruler);
      // The same mapping _xFor uses, so the drag starts exactly on the mark.
      double xFor(int frame) => box.left + (frame + 0.5) / 30 * box.width;

      await tester.dragFrom(
        Offset(xFor(10), box.top + 22 + 14),
        Offset(xFor(15) - xFor(10), 0),
      );
      await tester.pumpAndSettle();

      var after = controller.document.elements.single as PathElement;
      expect(after.nodes[1].frame, greaterThan(10),
          reason: "the middle point moved later");
      expect(after.nodes[1].frame, lessThanOrEqualTo(20),
          reason: "clamped by its neighbour rather than reordering the curve");
      expect(after.nodes[0].frame, 0, reason: "the others stayed put");
      expect(after.nodes[2].frame, 20);
    });

    testWidgets("the bar between a pair drags both ends", (tester) async {
      // A chart's entrance is two keyframes that mean nothing apart, so they
      // are joined on the strip and the bar moves both. Dragging either mark
      // still changes the length -- that is the next test.
      var document = const CanvasDocument(frames: 30, frameRate: 12);
      var chart = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        data: ChartData.parse("Cat\tA\nx\t10"),
      );
      var controller = CanvasController(document.addElement(chart));
      addTearDown(controller.dispose);
      controller.selectOnly("c");
      controller.frame = 4;
      controller.applyChartAnimation(
          controller.document.elementById("c") as ChartElement,
          ChartAnimationPreset.grow);

      await pump(tester, CanvasTimeline(controller: controller));
      var before = bandsIn(controller.document.elementById("c")!.track).single;

      var ruler = find
          .descendant(
              of: find.byType(CanvasTimeline),
              matching: find.byType(CustomPaint))
          .last;
      var box = tester.getRect(ruler);
      var frames = controller.document.frames;
      double xFor(int frame) => box.left + (frame + 0.5) / frames * box.width;

      // From the middle of the bar, which is the part that is neither end.
      var middle = (before.from + before.to) ~/ 2;
      await tester.dragFrom(
        Offset(xFor(middle), box.top + 22 + 14),
        Offset(xFor(middle - 3) - xFor(middle), 0),
      );
      await tester.pumpAndSettle();

      var after = bandsIn(controller.document.elementById("c")!.track).single;
      expect(after.from, lessThan(before.from), reason: "it moved earlier");
      expect(after.length, before.length,
          reason: "and kept its length, which is what a pair is for");
    });

    testWidgets("and an end still drags on its own, to change the length",
        (tester) async {
      var document = const CanvasDocument(frames: 30, frameRate: 12);
      var chart = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        data: ChartData.parse("Cat\tA\nx\t10"),
      );
      var controller = CanvasController(document.addElement(chart));
      addTearDown(controller.dispose);
      controller.selectOnly("c");
      controller.frame = 0;
      controller.applyChartAnimation(
          controller.document.elementById("c") as ChartElement,
          ChartAnimationPreset.grow);

      await pump(tester, CanvasTimeline(controller: controller));
      var before = bandsIn(controller.document.elementById("c")!.track).single;

      var ruler = find
          .descendant(
              of: find.byType(CanvasTimeline),
              matching: find.byType(CustomPaint))
          .last;
      var box = tester.getRect(ruler);
      var frames = controller.document.frames;
      double xFor(int frame) => box.left + (frame + 0.5) / frames * box.width;

      await tester.dragFrom(
        Offset(xFor(before.to), box.top + 22 + 14),
        Offset(xFor(before.to - 5) - xFor(before.to), 0),
      );
      await tester.pumpAndSettle();

      var after = bandsIn(controller.document.elementById("c")!.track).single;
      expect(after.from, before.from, reason: "the other end stayed put");
      expect(after.length, lessThan(before.length),
          reason: "so the animation is shorter");
    });

    testWidgets("a drag away from the marks still scrubs", (tester) async {
      var (controller, _) = withPath();
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      var ruler = find
          .descendant(
              of: find.byType(CanvasTimeline),
              matching: find.byType(CustomPaint))
          .last;
      var box = tester.getRect(ruler);

      // On the ruler's numbers, above the keyframe row: that is where the
      // playhead is grabbed, and a drag starting there scrubs even if it
      // happens to begin above a mark.
      await tester.dragFrom(
          Offset(box.left + 12, box.top + 4), const Offset(200, 0));
      await tester.pumpAndSettle();

      expect(controller.frame, greaterThan(0));
      var after = controller.document.elements.single as PathElement;
      expect(after.nodes.map((n) => n.frame).toList(), [0, 10, 20],
          reason: "nothing was retimed");
    });
  });

  group("clearing keyframes", () {
    /// pitch is a team with a run on one player, plus a shape with its own
    /// animation -- two channels, so "this one" and "all of them" can be told
    /// apart.
    (CanvasController, TeamElement, CanvasElement) pitch() {
      var team = TeamElement(
        const ElementBase(id: "t", x: 0, y: 0, width: 400, height: 300),
      ).withFormation(TeamFormation.f442);
      var shape =
          ShapeElement(const ElementBase(id: "s", width: 40, height: 40));
      var controller = CanvasController(
          const CanvasDocument(frames: 30).addElement(team).addElement(shape));

      controller.setPlayerKeyframe("t", 6, const Keyframe(frame: 0));
      controller.setPlayerKeyframe("t", 6, const Keyframe(frame: 12, dx: 50));
      controller.setPlayerKeyframe("t", 2, const Keyframe(frame: 4, dy: 20));
      controller.setKeyframe("s", const Keyframe(frame: 8, dx: 30));
      return (controller, team, shape);
    }

    TeamElement teamOf(CanvasController c) =>
        c.document.elements.whereType<TeamElement>().single;

    testWidgets("clear channel takes one player's run and nobody else's",
        (tester) async {
      var (controller, team, _) = pitch();
      addTearDown(controller.dispose);
      controller.selectOnly("t");
      controller.focusedPlayer = 6;
      await pump(tester, CanvasTimeline(controller: controller));

      await tester
          .tap(find.byTooltip("Clear every keyframe on #7 (${team.name})"));
      await tester.pumpAndSettle();

      expect(teamOf(controller).players[6].track, isNull);
      expect(teamOf(controller).players[2].track, isNotNull,
          reason: "the other player kept his");
      expect(controller.document.elementById("s")!.track, isNotNull,
          reason: "and so did the shape");
    });

    testWidgets("clear channel works on a plain element too", (tester) async {
      var (controller, _, shape) = pitch();
      addTearDown(controller.dispose);
      controller.selectOnly(shape.id);
      await pump(tester, CanvasTimeline(controller: controller));

      await tester.tap(find.byTooltip("Clear every keyframe on ${shape.name}"));
      await tester.pumpAndSettle();

      expect(controller.document.elementById("s")!.track, isNull);
      expect(teamOf(controller).players[6].track, isNotNull);
    });

    testWidgets("clear all empties every channel at once", (tester) async {
      var (controller, _, _) = pitch();
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      expect(controller.document.hasKeyframes, isTrue);
      await tester
          .tap(find.byTooltip("Clear every keyframe in the whole canvas"));
      await tester.pumpAndSettle();

      expect(controller.document.hasKeyframes, isFalse);
      expect(teamOf(controller).players[6].track, isNull);
      expect(teamOf(controller).players[2].track, isNull);
      expect(controller.document.elementById("s")!.track, isNull);
    });

    testWidgets("clear all is one undo step", (tester) async {
      // A single decision, and unpicking it element by element is not
      // something anybody would want to do twenty-two times.
      var (controller, _, _) = pitch();
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      await tester
          .tap(find.byTooltip("Clear every keyframe in the whole canvas"));
      await tester.pumpAndSettle();
      controller.undo();

      expect(controller.document.hasKeyframes, isTrue);
      expect(teamOf(controller).players[6].track, isNotNull);
      expect(controller.document.elementById("s")!.track, isNotNull);
    });

    testWidgets("both are off when there is nothing to clear", (tester) async {
      var controller = CanvasController(const CanvasDocument(frames: 30));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      expect(
          tester
              .widget<InkWell>(find.descendant(
                  of: find
                      .byTooltip("Clear every keyframe in the whole canvas"),
                  matching: find.byType(InkWell)))
              .onTap,
          isNull);
    });

    testWidgets("a path's points are not clearable from the strip",
        (tester) async {
      // They are where the curve goes rather than a pose, so clearing them
      // would delete the route instead of its timing -- and a path with no
      // points is not a path.
      var path = PathElement(
        const ElementBase(id: "p", width: 200, height: 200),
        nodes: const [
          PathNode(x: 0, y: 0, frame: 0),
          PathNode(x: 1, y: 1, frame: 10),
        ],
      );
      var controller =
          CanvasController(const CanvasDocument(frames: 30).addElement(path));
      addTearDown(controller.dispose);
      controller.selectOnly("p");
      await pump(tester, CanvasTimeline(controller: controller));

      var button = find.byTooltip(
          "A path's marks are its points — remove them in its settings");
      expect(button, findsOneWidget);
      expect(
          tester
              .widget<InkWell>(
                  find.descendant(of: button, matching: find.byType(InkWell)))
              .onTap,
          isNull);
      expect(
          (controller.document.elements.single as PathElement).nodes.length, 2);
    });

    test("clearing the whole document leaves paths their points", () {
      // Re-applying a route is a button press; redrawing it is not.
      var path = PathElement(
        const ElementBase(id: "p", width: 200, height: 200),
        nodes: const [
          PathNode(x: 0, y: 0, frame: 0),
          PathNode(x: 1, y: 1, frame: 10),
        ],
        follow: const PathFollow(elementId: "s"),
      );
      var shape =
          ShapeElement(const ElementBase(id: "s", width: 20, height: 20));
      var controller = CanvasController(
          const CanvasDocument(frames: 30).addElement(shape).addElement(path));
      addTearDown(controller.dispose);

      controller.applyPathFollow(
          controller.document.elements.whereType<PathElement>().single);
      expect(controller.document.hasKeyframes, isTrue);

      controller.clearAllKeyframes();
      expect(controller.document.hasKeyframes, isFalse);
      expect(
          controller.document.elements
              .whereType<PathElement>()
              .single
              .nodes
              .length,
          2);
    });
  });

  group("a follower's row on the strip", () {
    (CanvasController, TeamElement) followed() {
      var team = TeamElement(
        const ElementBase(
            id: "t", name: "Home", x: 0, y: 0, width: 400, height: 300),
      ).withFormation(TeamFormation.f442);
      var path = PathElement(
        const ElementBase(
            id: "p", name: "Run", x: 0, y: 0, width: 400, height: 300),
        nodes: const [
          PathNode(x: 0, y: 0, frame: 0),
          PathNode(x: 1, y: 1, frame: 12),
        ],
        follow: const PathFollow(elementId: "t", playerIndex: 0),
      );
      var controller = CanvasController(
          const CanvasDocument(frames: 30).addElement(team).addElement(path));
      controller.applyPathFollow(path);
      return (controller, team);
    }

    testWidgets("shows no marks of its own", (tester) async {
      // The reported problem: assigning the keeper to a path put keyframes on
      // the player *and* on the path, and editing the copy on the player did
      // nothing that survived the next re-bake.
      var (controller, _) = followed();
      addTearDown(controller.dispose);
      controller.selectOnly("t");
      controller.focusedPlayer = 0;
      await pump(tester, CanvasTimeline(controller: controller));

      expect(
          find.byTooltip("#1 (Home) is following Run — "
              "its timing is that path's points"),
          findsOneWidget);
      expect(find.byTooltip("Add a keyframe for #1 (Home) here"), findsNothing);
      expect(
          find.byTooltip("Remove this keyframe from #1 (Home)"), findsNothing);
    });

    testWidgets("cannot be cleared from the strip either", (tester) async {
      var (controller, _) = followed();
      addTearDown(controller.dispose);
      controller.selectOnly("t");
      controller.focusedPlayer = 0;
      await pump(tester, CanvasTimeline(controller: controller));

      var button = find.byTooltip("#1 (Home) is following Run — "
          "clear it by unlinking the path");
      expect(button, findsOneWidget);
      expect(
          tester
              .widget<InkWell>(
                  find.descendant(of: button, matching: find.byType(InkWell)))
              .onTap,
          isNull);
    });

    testWidgets("the pose bar says where the timing lives", (tester) async {
      var (controller, _) = followed();
      addTearDown(controller.dispose);
      controller.selectOnly("t");
      controller.focusedPlayer = 0;
      await pump(tester, CanvasKeyframeBar(controller: controller));

      expect(find.textContaining("is following Run"), findsOneWidget);
      expect(find.text("Easing"), findsNothing);
    });

    testWidgets("another player of the same team keeps his own row",
        (tester) async {
      var (controller, _) = followed();
      addTearDown(controller.dispose);
      controller.selectOnly("t");
      controller.focusedPlayer = 5;
      await pump(tester, CanvasTimeline(controller: controller));

      expect(
          find.byTooltip("Add a keyframe for #6 (Home) here"), findsOneWidget);
    });
  });

  group("the area outside the canvas", () {
    testWidgets("the grid, the guides and the rulers each have a switch",
        (tester) async {
      // And a switch for a thing that has not been set up is a switch that
      // does nothing, so each appears only once there is something to show.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      var quiet = CanvasPreferences();
      addTearDown(quiet.dispose);
      await pump(
          tester,
          CanvasSettingsBar(
            controller: controller,
            onPublish: () {},
            canvasSettingsOpen: false,
            onToggleCanvasSettings: () {},
            guidesOpen: false,
            onToggleGuides: () {},
            timelineOpen: true,
            onToggleTimeline: () {},
          ),
          prefs: quiet);

      expect(find.byTooltip("Show the grid"), findsOneWidget,
          reason: "there is always a grid to show");

      // Whether they are offered at all is a preference, set on the line that
      // sets the three tools up: somebody who does not use a grid should not
      // have to press anything in the bar to be rid of the switches for it.
      quiet.markSwitches = false;
      await tester.pumpAndSettle();
      expect(find.byTooltip("Show the grid"), findsNothing);
      expect(
          find.byTooltip("Grid, guides, rulers and snapping"), findsOneWidget,
          reason: "the line that sets them up is still a button away");
      quiet.markSwitches = true;
      await tester.pumpAndSettle();
      expect(find.byTooltip("Show the guides"), findsNothing);
      expect(find.byTooltip("Show the rulers"), findsNothing);

      await tester.tap(find.byTooltip("Show the grid"));
      await tester.pumpAndSettle();
      expect(controller.document.guides.showGrid, isTrue);
      expect(find.byTooltip("Hide the grid"), findsOneWidget);

      // Once there are guides and a ruler edge, their switches turn up.
      controller.apply(controller.document.copyWith(
          guides: controller.document.guides.copyWith(
        guides: const [CanvasGuide(axis: GuideAxis.vertical, at: 100)],
        rulers: const CanvasRulers(top: true),
      )));
      await tester.pumpAndSettle();
      expect(find.byTooltip("Hide the guides"), findsOneWidget);
      await tester.tap(find.byTooltip("Hide the rulers"));
      await tester.pumpAndSettle();
      expect(controller.document.guides.showRulers, isFalse,
          reason: "hidden without forgetting which edges they were on");
      expect(controller.document.guides.rulers.top, isTrue);
    });

    testWidgets("the join switches are only there when there is a join",
        (tester) async {
      // Two switches for something that is not on the canvas, in a strip that
      // is short of room.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(
          tester,
          CanvasSettingsBar(
            controller: controller,
            onPublish: () {},
            canvasSettingsOpen: false,
            onToggleCanvasSettings: () {},
            guidesOpen: false,
            onToggleGuides: () {},
            timelineOpen: true,
            onToggleTimeline: () {},
          ));
      expect(find.byTooltip("Lock the joins between text boxes"), findsNothing);

      controller.apply(controller.document
          .addElement(TextElement(
              const ElementBase(id: "a", width: 200, height: 60),
              text: "Words",
              flowTo: "b"))
          .addElement(TextElement(
              const ElementBase(id: "b", y: 100, width: 200, height: 60))));
      await tester.pumpAndSettle();
      expect(
          find.byTooltip("Lock the joins between text boxes"), findsOneWidget);
    });

    testWidgets("is off by default and toggles from the band", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(
          tester,
          CanvasSettingsBar(
            controller: controller,
            onPublish: () {},
            canvasSettingsOpen: false,
            onToggleCanvasSettings: () {},
            guidesOpen: false,
            onToggleGuides: () {},
            timelineOpen: true,
            onToggleTimeline: () {},
          ));

      expect(controller.showOverspill, isFalse,
          reason: "what the canvas shows is what gets published");
      await tester.tap(find.byTooltip("Show a margin outside the canvas, "
          "for animating things on and off"));
      await tester.pumpAndSettle();
      expect(controller.showOverspill, isTrue);

      await tester.tap(find.byTooltip("Hide the area outside the canvas"));
      await tester.pumpAndSettle();
      expect(controller.showOverspill, isFalse);
    });
  });

  group("selecting a keyframe", () {
    (CanvasController, CanvasElement) animated() {
      var document = const CanvasDocument(frames: 30);
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      controller.selectOnly(element.id);
      controller.setKeyframe(element.id, const Keyframe(frame: 0));
      controller.setKeyframe(element.id, const Keyframe(frame: 10, dx: 40));
      controller.setKeyframe(element.id, const Keyframe(frame: 20, dx: 80));
      return (controller, element);
    }

    /// tapMark clicks the mark at [frame] on the strip.
    Future<void> tapMark(WidgetTester tester, int frame, int frames) async {
      var ruler = find
          .descendant(
              of: find.byType(CanvasTimeline),
              matching: find.byType(CustomPaint))
          .last;
      var box = tester.getRect(ruler);
      await tester.tapAt(Offset(
          box.left + (frame + 0.5) / frames * box.width, box.top + 22 + 14));
      await tester.pumpAndSettle();
    }

    testWidgets("delete takes the keyframe, not the element", (tester) async {
      // The canvas's own Delete removes what is selected there, and with a
      // keyframe picked out that is the wrong thing by a long way: one is a
      // pose, the other is the whole element and everything on it.
      var (controller, element) = animated();
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      await tapMark(tester, 10, 30);
      expect(controller.frame, 10, reason: "clicking a mark goes to it");

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(controller.document.elements.length, 1,
          reason: "the element is still there");
      var track = controller.document.elementById(element.id)!.track!;
      expect(track.keyAt(10), isNull, reason: "but that pose is gone");
      expect(track.keyAt(0), isNotNull);
      expect(track.keyAt(20), isNotNull);
    });

    testWidgets("delete does nothing with no mark picked out", (tester) async {
      var (controller, element) = animated();
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      // Focus the strip without landing on a mark *or* on the bar between
      // two of them: a stretch where something happens is a bar now, and
      // clicking one takes both of its ends. Past the last mark there is
      // neither.
      await tapMark(tester, 25, 30);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(
          controller.document.elementById(element.id)!.track!.keys.length, 3);
    });

    testWidgets("the selection is dropped when the row changes",
        (tester) async {
      // A frame number means nothing once the strip is showing somebody
      // else's keyframes, and a stale one would put Delete on a mark the
      // reader never picked.
      var (controller, element) = animated();
      addTearDown(controller.dispose);
      var other = newElement(ElementKind.text, controller.document);
      controller.apply(controller.document.addElement(other));
      await pump(tester, CanvasTimeline(controller: controller));

      await tapMark(tester, 10, 30);
      controller.selectOnly(other.id);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();

      expect(controller.document.elementById(element.id)!.track!.keys.length, 3,
          reason: "the other element's keyframes were left alone");
      expect(controller.document.elements.length, 2);
    });
  });

  group("the element settings", () {
    testWidgets("carry no lock, hide or reorder controls", (tester) async {
      // All four are properties of the *layer* rather than of the thing on it,
      // and the layer list already shows them on the row that names the
      // element -- where hiding something does not make the panel you are
      // hiding it from disappear.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);

      await pump(tester, CanvasDesignPanel(controller: controller));

      // The layer row has them.
      expect(find.byTooltip("Lock"), findsOneWidget);
      expect(find.byTooltip("Hide"), findsOneWidget);
      expect(find.byTooltip("Move forward"), findsOneWidget);
      // The settings below it do not.
      expect(find.byTooltip("Lock in place"), findsNothing);
      expect(find.byTooltip("Bring to front"), findsNothing);
      expect(find.byTooltip("Send to back"), findsNothing);
    });

    testWidgets("a player row keeps its own, since the layer list has none",
        (tester) async {
      var team = TeamElement(
        const ElementBase(id: "t", name: "Home", width: 400, height: 300),
      ).withFormation(TeamFormation.f442);
      var controller =
          CanvasController(const CanvasDocument().addElement(team));
      addTearDown(controller.dispose);
      controller.selectOnly("t");

      await pump(tester, CanvasDesignPanel(controller: controller));
      // Scrolled to first: the squad list is below the fold in a panel this
      // tall, and a tap at a point outside the viewport hits nothing.
      await tester.ensureVisible(find.text("PLAYERS"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("PLAYERS"));
      await tester.pumpAndSettle();

      expect(find.byTooltip("Lock in place"), findsWidgets,
          reason: "a player is not a layer and has nowhere else to be locked");
    });
  });

  group("animated settings", () {
    (CanvasController, CanvasElement) moving() {
      var document = const CanvasDocument(frames: 30);
      var element = ShapeElement(
          const ElementBase(id: "s", x: 100, y: 50, width: 40, height: 40));
      var controller = CanvasController(document.addElement(element));
      controller.selectOnly("s");
      controller.setKeyframe("s", const Keyframe(frame: 0));
      controller.setKeyframe("s", const Keyframe(frame: 20, dx: 200, dy: 60));
      return (controller, element);
    }

    testWidgets("X and Y show where the element is on this frame",
        (tester) async {
      // They showed where it *rests*, so scrubbing into the middle of a move
      // left two numbers describing somewhere the element visibly was not.
      var (controller, _) = moving();
      addTearDown(controller.dispose);
      controller.frame = 10;
      await pump(tester, CanvasDesignPanel(controller: controller));

      var x = find.byKey(const ValueKey("elementX"));
      expect(find.descendant(of: x, matching: find.text("200")), findsOneWidget,
          reason: "half way along a 100 to 300 move");
    });

    testWidgets("typing a position while animating writes a keyframe",
        (tester) async {
      var (controller, _) = moving();
      addTearDown(controller.dispose);
      controller.frame = 10;
      await pump(tester, CanvasDesignPanel(controller: controller));

      await tester.enterText(find.byKey(const ValueKey("elementX")), "500");
      await tester.pumpAndSettle();

      var element = controller.document.elementById("s")!;
      expect(element.x, 100, reason: "the resting position is untouched");
      expect(element.track!.keyAt(10)!.dx, 400);
      expect(element.boundsAt(10).left, 500);
      expect(element.boundsAt(0).left, 100, reason: "and frame 0 is unchanged");
    });

    testWidgets("the diamond adds and removes the pose here", (tester) async {
      var (controller, _) = moving();
      addTearDown(controller.dispose);
      controller.frame = 7;
      await pump(tester, CanvasDesignPanel(controller: controller));

      expect(controller.document.elementById("s")!.track!.keyAt(7), isNull);
      await tester.tap(find.byTooltip("Add a keyframe here for this element's "
          "position, size, angle and fade"));
      await tester.pumpAndSettle();
      expect(controller.document.elementById("s")!.track!.keyAt(7), isNotNull);

      await tester.tap(find.byTooltip(
          "Remove this element's keyframe here — one keyframe holds its "
          "position, size, angle and fade together"));
      await tester.pumpAndSettle();
      expect(controller.document.elementById("s")!.track!.keyAt(7), isNull);
    });

    testWidgets("the diamonds are off on a still canvas", (tester) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasDesignPanel(controller: controller));

      // One diamond for the group, not one per field: a keyframe here is a
      // whole pose, so six of them lit up and went out in unison.
      var dot =
          find.byTooltip("Give the canvas more than one frame to animate this "
              "element");
      expect(dot, findsOneWidget);
      expect(
          tester
              .widget<InkWell>(
                  find.descendant(of: dot, matching: find.byType(InkWell)))
              .onTap,
          isNull);
    });

    testWidgets("angle and opacity follow the pose too", (tester) async {
      var (controller, _) = moving();
      addTearDown(controller.dispose);
      controller.setKeyframe(
          "s", const Keyframe(frame: 20, rotate: 90, opacity: 0.5));
      controller.frame = 20;
      await pump(tester, CanvasDesignPanel(controller: controller));

      expect(
          find.descendant(
              of: find.byKey(const ValueKey("elementAngle")),
              matching: find.text("90")),
          findsOneWidget);
    });
  });

  group("the shape settings", () {
    /// panel builds an element's settings the way the Layers sidebar does.
    Future<CanvasController> panel(WidgetTester tester, ShapeElement shape,
        {String? text}) async {
      var element = text == null ? shape : shape.copyWith(text: text);
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasDesignPanel(controller: controller));
      return controller;
    }

    ShapeElement shapeOf(ShapeKind kind) => ShapeElement(
          const ElementBase(id: "s", width: 200, height: 120),
          shape: kind,
        );

    /// tail opens the button on the end of the Bubble line, which holds the
    /// tail's own measurements. Only if it is shut: an opened area stays open
    /// for the rest of the file.
    Future<void> tail(WidgetTester tester) async {
      var button = find.byKey(const ValueKey("more-shapeBubbleMore"));
      if (find.text("Length").evaluate().isNotEmpty) return;
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets("a bubble shows its own settings, label or no label",
        (tester) async {
      // They were nested inside "if there is a label" by accident, so a bubble
      // with nothing written in it offered none of them -- which is exactly
      // the state a bubble is in when it has just been added.
      await panel(tester, shapeOf(ShapeKind.speechBubble));
      expect(find.text("BUBBLE"), findsOneWidget);
      expect(find.text("Body"), findsOneWidget);
      expect(find.text("Tail"), findsOneWidget);
      // Where the tail points is a measurement, so it is behind the button
      // on the end of that line.
      await tail(tester);
      expect(find.text("Points"), findsOneWidget);
    });

    testWidgets("and still shows them once it has one", (tester) async {
      await panel(tester, shapeOf(ShapeKind.speechBubble), text: "Hello");
      expect(find.text("BUBBLE"), findsOneWidget);
      expect(find.text("LABEL TYPE"), findsOneWidget);
    });

    testWidgets("another shape shows none of them", (tester) async {
      await panel(tester, shapeOf(ShapeKind.star), text: "Hi");
      expect(find.text("BUBBLE"), findsNothing);
      expect(find.text("Tail"), findsNothing);
    });

    testWidgets("the label's type appears only when there is a label",
        (tester) async {
      await panel(tester, shapeOf(ShapeKind.star));
      expect(find.text("LABEL TYPE"), findsNothing);
    });

    testWidgets("changing the tail writes it to the element", (tester) async {
      var controller = await panel(tester, shapeOf(ShapeKind.speechBubble));

      // Scrolled to first: the settings share their column with the add grid
      // and the layer list now, so a control this far down the panel is below
      // the fold until it is brought up.
      await tester.ensureVisible(find.text(BubbleTail.pointer.label).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(BubbleTail.pointer.label).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(BubbleTail.thought.label).last);
      await tester.pumpAndSettle();

      var after = controller.document.elements.single as ShapeElement;
      expect(after.bubble.tail, BubbleTail.thought);
    });

    testWidgets("the tail angle can be typed", (tester) async {
      var controller = await panel(tester, shapeOf(ShapeKind.speechBubble));
      await tail(tester);
      await tester.enterText(
          find.byKey(const ValueKey("bubbleTailAngle")), "270");
      await tester.pump();
      expect(
          (controller.document.elements.single as ShapeElement)
              .bubble
              .tailAngle,
          270);
    });

    testWidgets("the fill swatch goes away while a picture is over it",
        (tester) async {
      // The same as the box next door: a picture or a pattern fills the whole
      // outline, so the swatch changed nothing you could see. The stroke's
      // colour stays either way -- the outline is drawn over the picture.
      var controller = await panel(tester, shapeOf(ShapeKind.star));
      var fill = find.byWidgetPredicate(
          (w) => w is CanvasColorButton && w.label == "Fill");
      var stroke = find.byWidgetPredicate(
          (w) => w is CanvasColorButton && w.label == "Colour");
      expect(fill, findsOneWidget);

      var kind = find.byKey(const ValueKey("shapeFillKind"));
      if (kind.evaluate().isEmpty) {
        var button = find.byKey(const ValueKey("more-shapeMore"));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(kind);
      await tester.pumpAndSettle();
      await tester.tap(kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Pattern").last);
      await tester.pumpAndSettle();

      expect((controller.document.elements.single as ShapeElement).painted.kind,
          TextFillKind.pattern);
      expect(fill, findsNothing, reason: "the pattern decides now");
      expect(stroke, findsOneWidget, reason: "but the outline is still drawn");
    });

    testWidgets("choosing a stroke colour gives the shape a stroke",
        (tester) async {
      // A shape arrives with a stroke 0 wide, and a stroke 0 wide is not
      // drawn however it is coloured -- so the swatch called Colour was a
      // setting that did nothing at all until a number was typed into the
      // box beside it. Asking for a colour is asking for a line.
      var controller = await panel(tester, shapeOf(ShapeKind.star));
      expect((controller.document.elements.single as ShapeElement).strokeWidth,
          0,
          reason: "otherwise this test is not asking anything");

      var colour = find.byWidgetPredicate(
          (w) => w is CanvasColorButton && w.label == "Colour");
      expect(colour, findsOneWidget);
      tester.widget<CanvasColorButton>(colour).onChanged(const Color(0xFF00FF00));
      await tester.pumpAndSettle();

      var after = controller.document.elements.single as ShapeElement;
      expect(after.strokeColor, const Color(0xFF00FF00));
      expect(after.strokeWidth, greaterThan(0), reason: "and a line to see it on");
    });

    testWidgets("but leaves a stroke it already has alone", (tester) async {
      var controller = await panel(
          tester,
          ShapeElement(const ElementBase(id: "s", width: 200, height: 120),
              shape: ShapeKind.star, strokeWidth: 12));
      var colour = find.byWidgetPredicate(
          (w) => w is CanvasColorButton && w.label == "Colour");
      tester.widget<CanvasColorButton>(colour).onChanged(const Color(0xFF00FF00));
      await tester.pumpAndSettle();
      expect((controller.document.elements.single as ShapeElement).strokeWidth,
          12);
    });

    testWidgets("a colour and a fade set in one visit both land",
        (tester) async {
      // Two writes to the same element, and the panel's controls are built
      // from the element as it was when it was last laid out -- so written in
      // one frame the second was built on the same stale copy and undid the
      // first. Reported as a gradient point's opacity not sticking.
      var controller = await panel(tester, shapeOf(ShapeKind.star));
      var fill = find.byWidgetPredicate(
          (w) => w is CanvasColorButton && w.label == "Fill");
      await tester.ensureVisible(fill);
      await tester.pumpAndSettle();
      await tester.tap(fill);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey("colorModegradient")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("gradientAdd")));
      await tester.pumpAndSettle();

      // Back to the first point, and its opacity turned down.
      var bar = tester.getRect(find.byKey(const ValueKey("gradientBar")));
      await tester.tapAt(Offset(bar.left + 4, bar.center.dy));
      await tester.pumpAndSettle();
      var slider =
          tester.getRect(find.byKey(const ValueKey("gradientOpacity")));
      await tester.dragFrom(Offset(slider.right - 20, slider.center.dy),
          Offset(-slider.width / 2, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Select"));
      await tester.pumpAndSettle();

      var after = controller.document.elements.single as ShapeElement;
      expect(after.fillFade, isNotNull, reason: "the fade was set");
      expect(after.fill.a, lessThan(0.9),
          reason: "and so was the first colour's opacity");
    });

    testWidgets("the curl appears only for a curved tail", (tester) async {
      await panel(tester, shapeOf(ShapeKind.speechBubble));
      await tail(tester);
      expect(find.text("Curl"), findsNothing);

      var curved = ShapeElement(
        const ElementBase(id: "s", width: 200, height: 120),
        shape: ShapeKind.speechBubble,
        bubble: const SpeechBubbleSpec(tail: BubbleTail.curved),
      );
      await panel(tester, curved);
      await tail(tester);
      expect(find.text("Curl"), findsOneWidget);
    });
  });

  group("scrubbing a number", () {
    testWidgets("one pixel is one of the field's own last digits",
        (tester) async {
      // Not a fraction of the field's range, which was the first attempt and
      // was hundreds per pixel: most of these ranges are guard rails rather
      // than scales.
      var controller = CanvasController(const CanvasDocument(frames: 200));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      var caption = find.descendant(
          of: find.byKey(const ValueKey("canvasFrames")),
          matching: find.text("Length"));
      await tester.drag(caption, const Offset(40, 0));
      await tester.pumpAndSettle();

      // A whole-number field, so forty pixels is forty frames.
      expect(controller.document.frames, 240);
    });

    testWidgets("dragging the caption runs the value up and down",
        (tester) async {
      var controller = CanvasController(const CanvasDocument(frames: 40));
      addTearDown(controller.dispose);
      controller.frame = 10;
      await pump(tester, CanvasTimeline(controller: controller));

      var before = controller.document.frames;
      // The caption above the field is the handle -- a TextField owns its own
      // drag, which is how text is selected, so the field itself cannot be it.
      var caption = find.descendant(
          of: find.byKey(const ValueKey("canvasFrames")),
          matching: find.text("Length"));
      expect(caption, findsOneWidget);

      await tester.drag(caption, const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(controller.document.frames, greaterThan(before));

      var up = controller.document.frames;
      await tester.drag(caption, const Offset(-60, 0));
      await tester.pumpAndSettle();
      expect(controller.document.frames, lessThan(up),
          reason: "and back down again");
    });

    testWidgets("it stays inside the field's own limits", (tester) async {
      var controller = CanvasController(const CanvasDocument(frames: 40));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      var caption = find.descendant(
          of: find.byKey(const ValueKey("canvasFrameRate")),
          matching: find.text("Per second"));
      // Far past the bottom of a 1..60 field.
      await tester.drag(caption, const Offset(-4000, 0));
      await tester.pumpAndSettle();
      expect(controller.document.frameRate, 1);

      await tester.drag(caption, const Offset(8000, 0));
      await tester.pumpAndSettle();
      expect(controller.document.frameRate, 60);
    });

    testWidgets("where in the caption it is grabbed makes no difference",
        (tester) async {
      // The gesture reports the pointer's position within the widget rather
      // than how far it has travelled, so an unadjusted read moved the value
      // by wherever in the label it was taken hold of.
      Future<int> dragFromFraction(double at) async {
        var controller = CanvasController(const CanvasDocument(frames: 200));
        addTearDown(controller.dispose);
        await pump(tester, CanvasTimeline(controller: controller));

        var caption = find.descendant(
            of: find.byKey(const ValueKey("canvasFrames")),
            matching: find.text("Length"));
        var box = tester.getRect(caption);
        await tester.dragFrom(Offset(box.left + box.width * at, box.center.dy),
            const Offset(30, 0));
        await tester.pumpAndSettle();
        return controller.document.frames;
      }

      expect(await dragFromFraction(0.1), await dragFromFraction(0.9));
      expect(await dragFromFraction(0.5), 230);
    });

    testWidgets("holding the number itself scrubs it as well", (tester) async {
      // A caption is written once per column, so a chart's fourth series has
      // an Offset field with nothing above it to drag -- a number that could
      // only be typed. Holding the field is the other handle: a press on a
      // number means nothing else, where a *drag* on one is how text is
      // selected.
      var controller = CanvasController(const CanvasDocument(frames: 200));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      var field = find.byKey(const ValueKey("canvasFrames"));
      String shown() => tester
          .widget<TextField>(
              find.descendant(of: field, matching: find.byType(TextField)))
          .controller!
          .text;

      var press = await tester.startGesture(tester.getCenter(field));
      await tester.pump(const Duration(milliseconds: 500));
      await press.moveBy(const Offset(40, 0));
      await tester.pump();

      expect(controller.document.frames, 240,
          reason: "forty pixels, forty frames, the same as the caption");
      // While it is still being dragged: pressing the field is what gives it
      // the focus, and a field with the focus is not rewritten from outside
      // -- so the number ran up and down on the canvas with the old figure
      // still sitting in the box.
      expect(shown(), "240", reason: "and the box says what the value is");

      await press.up();
      await tester.pumpAndSettle();
      expect(shown(), "240");
    });

    testWidgets("but a drag that was not held leaves the number alone",
        (tester) async {
      // That is the field's own drag, which selects the digits to retype
      // them. Taking it would make an exact number impossible to type over.
      var controller = CanvasController(const CanvasDocument(frames: 200));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      await tester.drag(
          find.byKey(const ValueKey("canvasFrames")), const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(controller.document.frames, 200);
    });

    testWidgets("and the hold itself reaches nothing but the field",
        (tester) async {
      // What made it temperamental: the hold used to drop the focus, to keep
      // the caret out of the way. Losing the focus calls onCommit, which
      // closes the undo step, which rebuilds the settings panel -- which can
      // take the field's own state away in the middle of its gesture. So the
      // scrub worked or did not depending on what the panel did next.
      var commits = 0;
      var value = 10.0;
      await pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => CanvasNumberField(
            key: const ValueKey("held"),
            label: "Size",
            value: value,
            onChanged: (v) => setState(() => value = v),
            onCommit: () => commits++,
          ),
        ),
      );

      var field = find.byKey(const ValueKey("held"));
      // Focused first, which is the ordinary way round: a number is clicked,
      // looked at, and then dragged. That is also the case the old hold broke,
      // since a field with nothing to lose loses no focus.
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(commits, 0, reason: "clicking into a field finishes nothing");

      var press = await tester.startGesture(tester.getCenter(field));
      await tester.pump(const Duration(milliseconds: 500));
      await press.moveBy(const Offset(20, 0));
      await tester.pump();

      expect(value, 30, reason: "twenty pixels on a whole-number field");
      expect(commits, 0, reason: "nothing is finished until it is let go");

      await press.up();
      await tester.pumpAndSettle();
      expect(commits, 1);
    });

    testWidgets("and the pointer says so over the box", (tester) async {
      // The same left-and-right cursor the caption shows, which is the only
      // thing that says a number can be dragged at all. On the field itself
      // rather than in a region around it: a text field carries a cursor of
      // its own and the innermost one wins, so an I-beam would have said
      // "type here" over the one control that also does something else.
      var controller = CanvasController(const CanvasDocument(frames: 200));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      var box = tester.widget<TextField>(find.descendant(
          of: find.byKey(const ValueKey("canvasFrames")),
          matching: find.byType(TextField)));
      expect(box.mouseCursor, SystemMouseCursors.resizeLeftRight);
    });

    testWidgets("typing into the field still works", (tester) async {
      // The scrub must not have taken the field over.
      var controller = CanvasController(const CanvasDocument(frames: 40));
      addTearDown(controller.dispose);
      await pump(tester, CanvasTimeline(controller: controller));

      await tester.enterText(find.byKey(const ValueKey("canvasFrames")), "125");
      await tester.pump();
      expect(controller.document.frames, 125);
    });
  });

  group("cropping a picture", () {
    test("trims the frame, so what is left stays where it was", () {
      // Reported as "some kind of strange zoom which is very hard to
      // control": the crop showed less of the picture in the same box, so
      // the rest was re-fitted to fill the frame. What a crop means to
      // anybody using one is that the edge moves in and takes that strip
      // with it.
      var picture = ImageElement(
        const ElementBase(id: "p", x: 100, y: 50, width: 400, height: 200),
        assetId: "a",
      );

      // A quarter off the left: the left edge moves in by a quarter of the
      // frame, and the right edge does not move at all.
      var cropped = picture.croppedTo(const ImageCrop(left: 0.25));
      expect(cropped.x, closeTo(200, 0.01));
      expect(cropped.width, closeTo(300, 0.01));
      expect(cropped.x + cropped.width, closeTo(500, 0.01),
          reason: "the right-hand edge is where it was");
      expect(cropped.y, 50, reason: "and nothing happened to the height");
      expect(cropped.height, 200);

      // And a second crop is measured against what is showing now, not
      // against the whole picture: another quarter off the left of what is
      // left takes a quarter of *this* frame.
      var again = cropped.croppedTo(const ImageCrop(left: 0.5));
      expect(again.x, closeTo(300, 0.01));
      expect(again.width, closeTo(200, 0.01));
    });

    test("and giving it all back puts the frame back", () {
      var picture = ImageElement(
        const ElementBase(id: "p", x: 100, y: 50, width: 400, height: 200),
        assetId: "a",
      );
      var cropped = picture
          .croppedTo(const ImageCrop(left: 0.25, bottom: 0.5))
          .croppedTo(const ImageCrop());
      expect(cropped.x, closeTo(100, 0.01));
      expect(cropped.width, closeTo(400, 0.01));
      expect(cropped.height, closeTo(200, 0.01));
    });

    test("but not to nothing", () {
      var picture = ImageElement(
        const ElementBase(id: "p", width: 40, height: 40),
        assetId: "a",
      );
      var flat = picture.croppedTo(const ImageCrop(left: 0.99));
      expect(flat.width, 40, reason: "the frame is left alone");
      expect(flat.crop.left, 0.99, reason: "and the crop is still written");
    });
  });

  group("the image settings", () {
    Future<CanvasController> panel(
        WidgetTester tester, ImageElement image) async {
      var controller =
          CanvasController(const CanvasDocument().addElement(image));
      addTearDown(controller.dispose);
      controller.selectOnly(image.id);
      await pump(tester, CanvasDesignPanel(controller: controller));
      return controller;
    }

    ImageElement empty() =>
        const ImageElement(ElementBase(id: "i", width: 200, height: 200));
    ImageElement filled() =>
        const ImageElement(ElementBase(id: "i", width: 200, height: 200),
            assetId: "abcdefghij123456");

    testWidgets("an empty one offers somewhere to put a picture",
        (tester) async {
      // The control the element did not have, and without which it does
      // nothing at all.
      await panel(tester, empty());
      expect(find.byTooltip("Add a picture"), findsOneWidget);
    });

    testWidgets("a filled one offers to replace or remove it", (tester) async {
      var controller = await panel(tester, filled());
      expect(find.byTooltip("Replace this picture"), findsOneWidget);

      await tester.ensureVisible(find.byTooltip("Take the picture out"));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip("Take the picture out"));
      await tester.pumpAndSettle();
      expect((controller.document.elements.single as ImageElement).hasImage,
          isFalse);
    });

    testWidgets("the zoom field reaches the picture", (tester) async {
      // Reported as the numbers moving while the picture did not. The field
      // writes the element, and the element is what the painter places --
      // see placeImage, which is tested against the pixels next door.
      var controller = await panel(tester, filled());
      var zoom = find.ancestor(
          of: find.text("Zoom"), matching: find.byType(CanvasNumberField));
      expect(zoom, findsOneWidget, reason: "offered for a picture that fills");
      await tester.ensureVisible(zoom);
      await tester.pumpAndSettle();

      await tester.enterText(zoom, "2");
      await tester.pump();
      expect((controller.document.elements.single as ImageElement).framing.zoom,
          2);
    });

    testWidgets("and framing is not offered where it can do nothing",
        (tester) async {
      // Contained or stretched there is no slack to spend and no window to
      // shrink, so the three numbers would be three dead controls.
      await panel(tester, filled().copyWith(fit: ImageFit.contain));
      expect(find.text("FRAMING"), findsNothing);
      // A hint is a question mark with a tooltip, so it is found by what it
      // has to say.
      expect(
          find.byWidgetPredicate((w) =>
              w is CanvasHint && w.message.contains("fills its frame")),
          findsOneWidget,
          reason: "and it says where they went");
    });

    testWidgets("frame, crop and look appear only once there is a picture",
        (tester) async {
      await panel(tester, empty());
      expect(find.text("FRAME"), findsNothing);
      expect(find.text("CROP"), findsNothing);
      expect(find.text("LOOK"), findsNothing);

      await panel(tester, filled());
      expect(find.text("FRAME"), findsOneWidget);
      expect(find.text("CROP"), findsOneWidget);
      expect(find.text("LOOK"), findsOneWidget);
    });

    testWidgets("the overlay colour appears only once a blend is chosen",
        (tester) async {
      // By key: several groups have a colour in them, and the border's is
      // always there.
      await panel(tester, filled());
      expect(find.byKey(const ValueKey("imageOverlayColour")), findsNothing);

      await panel(tester, filled().copyWith(blend: OverlayBlend.multiply));
      expect(find.byKey(const ValueKey("imageOverlayColour")), findsOneWidget);
    });

    testWidgets("a frame can be chosen and cleared", (tester) async {
      var controller = await panel(tester, filled());

      await tester.ensureVisible(find.text("Rectangle").first);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Rectangle").first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(ShapeKind.circle.label).last);
      await tester.pumpAndSettle();
      expect((controller.document.elements.single as ImageElement).frame,
          ShapeKind.circle);
    });
  });

  group("element settings use numbers, not sliders", () {
    testWidgets("a fraction is typed and dragged like every other number",
        (tester) async {
      // A slider inside a settings row is a few dozen pixels wide, so the
      // whole of an opacity is about forty pixels of travel and nothing can be
      // set precisely. They are number fields now, which type and scrub.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasDesignPanel(controller: controller));

      expect(find.byType(Slider), findsNothing,
          reason: "no sliders left in an element's settings");

      var opacity = find.ancestor(
          of: find.text("Opacity"), matching: find.byType(CanvasNumberField));
      expect(opacity, findsOneWidget);

      await tester.enterText(
          find.descendant(of: opacity, matching: find.byType(TextField)),
          "0.4");
      await tester.pump();
      expect(controller.document.elements.single.opacity, closeTo(0.4, 0.001));
    });

    testWidgets("dragging its caption scrubs in hundredths", (tester) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasDesignPanel(controller: controller));

      await tester.drag(find.text("Opacity"), const Offset(-25, 0));
      await tester.pumpAndSettle();

      // Two decimals, so twenty-five pixels is a quarter.
      expect(controller.document.elements.single.opacity, closeTo(0.75, 0.02));
    });
  });

  group("renaming a layer", () {
    // The settings under the list are full of text fields, so the rename is
    // found by its own key rather than by being "the text field".
    var field = find.byKey(layerRenameFieldKey);

    Future<CanvasController> panel(WidgetTester tester) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      await pump(tester, CanvasDesignPanel(controller: controller));
      return controller;
    }

    /// inRow scopes a name to the layer list. Selecting a layer puts its own
    /// settings under the list, and those are headed with the same word.
    Finder inRow(String name) => find.descendant(
        of: find.byType(CanvasLayerRow), matching: find.text(name));

    Future<void> doubleClick(WidgetTester tester, String name) async {
      await tester.tap(inRow(name));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(inRow(name));
      await tester.pumpAndSettle();
    }

    testWidgets("double clicking the name opens a field", (tester) async {
      // Double click rather than a pencil button: the row already carries five
      // controls, and a sixth for something done occasionally would be paid
      // for on every row of every canvas.
      var controller = await panel(tester);
      expect(field, findsNothing);

      await doubleClick(tester, "Shape");
      expect(field, findsOneWidget);

      await tester.enterText(field, "Goal area");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(controller.document.elements.single.name, "Goal area");
      expect(inRow("Goal area"), findsOneWidget);
      expect(field, findsNothing);
    });

    testWidgets("clearing it puts the kind's own name back", (tester) async {
      // An empty name is not a name, and it is also how the model says "use
      // the kind's label" -- so clearing the field is how you undo a rename
      // rather than how you get a row with nothing written on it.
      var controller = await panel(tester);
      controller.replaceElement(
          controller.document.elements.single.withBase(name: "Goal area"));
      await tester.pumpAndSettle();

      await doubleClick(tester, "Goal area");
      await tester.enterText(field, "   ");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(controller.document.elements.single.name, "Shape");
    });

    testWidgets("a single click selects it, and does so at once",
        (tester) async {
      // Not GestureDetector.onDoubleTap, which holds the arena open for the
      // three hundred milliseconds a second tap might arrive in -- so every
      // single click on a layer name would have selected it a third of a
      // second late, and selecting layers is what this list is mostly for.
      var controller = await panel(tester);
      await tester.tap(inRow("Shape"));
      await tester.pump();

      expect(controller.selection, {controller.document.elements.single.id});
      expect(field, findsNothing);
    });
  });

  group("dragging a layer", () {
    /// three builds a document with three named layers, bottom to top.
    Future<CanvasController> panel(WidgetTester tester) async {
      var document = const CanvasDocument();
      for (var name in ["Bottom", "Middle", "Top"]) {
        document = document.addElement(
            newElement(ElementKind.shape, document).withBase(name: name));
      }
      var controller = CanvasController(document);
      addTearDown(controller.dispose);
      await pump(tester, CanvasDesignPanel(controller: controller));
      return controller;
    }

    List<String> order(CanvasController controller) =>
        [for (var e in controller.document.elements) e.name];

    testWidgets("press and hold moves it to the row it is dropped on",
        (tester) async {
      // A long press to start rather than a plain drag: the list scrolls, and
      // a row that begins moving the moment a pointer travels across it is a
      // row that cannot be scrolled past.
      var controller = await panel(tester);
      expect(order(controller), ["Bottom", "Middle", "Top"]);

      // The list is drawn top-first, so "Top" is the first row and "Bottom"
      // the last. Dragging Top onto Bottom's row sends it to the back.
      var drag = await tester.startGesture(tester.getCenter(find.text("Top")));
      await tester.pump(const Duration(milliseconds: 700));
      await drag.moveTo(tester.getCenter(find.text("Bottom")));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();

      expect(order(controller), ["Top", "Bottom", "Middle"]);
      expect(controller.selection.length, 1,
          reason: "what was dropped is what is selected, so it can be found");
    });

    testWidgets("a short drag scrolls rather than reordering", (tester) async {
      var controller = await panel(tester);
      await tester.drag(find.text("Top"), const Offset(0, 60));
      await tester.pumpAndSettle();

      expect(order(controller), ["Bottom", "Middle", "Top"],
          reason: "no long press, no reorder");
    });

    testWidgets("the background is neither picked up nor dropped on",
        (tester) async {
      // It is painted before every element and cannot be reordered into the
      // middle of them, so it is not a row that moves. It has no draggable and
      // no target of its own; a layer dropped on it goes nowhere.
      var controller = await panel(tester);
      // Scoped to the layer list: with nothing selected the settings panel is
      // showing the background's own controls, which are also called that.
      var background = find.descendant(
          of: find.byType(CanvasBackgroundLayerRow),
          matching: find.textContaining("Background"));
      expect(background, findsOneWidget);

      expect(
          find.ancestor(
              of: background,
              matching: find.byType(LongPressDraggable<String>)),
          findsNothing);
      expect(
          find.ancestor(
              of: background, matching: find.byType(DragTarget<String>)),
          findsNothing);

      var drag = await tester.startGesture(tester.getCenter(find.text("Top")));
      await tester.pump(const Duration(milliseconds: 700));
      await drag.moveTo(tester.getCenter(background));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();

      expect(order(controller), ["Bottom", "Middle", "Top"]);
    });
  });

  group("a table's settings", () {
    Future<CanvasController> panel(WidgetTester tester) async {
      var element = TableElement(
        const ElementBase(id: "t", width: 400, height: 200),
        rows: const [
          ["Team", "Points"],
          ["Hull City", "6"],
        ],
      );
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("t");
      await pump(tester, CanvasDesignPanel(controller: controller));
      return controller;
    }

    TableElement tableIn(CanvasController controller) =>
        controller.document.elements.single as TableElement;

    Future<void> press(WidgetTester tester, Finder what) async {
      await tester.ensureVisible(what);
      await tester.pumpAndSettle();
      await tester.tap(what);
      await tester.pumpAndSettle();
    }

    /// showStyle opens the Style section if it is shut, and hands back what
    /// closes it again.
    ///
    /// Only if, and only what this test opened: an expander remembers whether
    /// it was open and that memory outlives the test, so a blind tap leaves
    /// the next test looking at a panel it did not ask for.
    Future<Future<void> Function()> showStyle(WidgetTester tester) async {
      var open =
          find.byKey(const ValueKey("tablePadding")).evaluate().isNotEmpty;
      if (!open) await press(tester, find.text("STYLE"));
      return () async {
        if (!open) await press(tester, find.text("STYLE"));
      };
    }

    testWidgets("the padding can be asked for a side at a time",
        (tester) async {
      // One figure until somebody wants four: almost every table wants the
      // same room on every side.
      var controller = await panel(tester);
      var shut = await showStyle(tester);
      expect(find.byKey(const ValueKey("tablePadding")), findsOneWidget);
      expect(find.byKey(const ValueKey("tablePadTop")), findsNothing);

      await press(tester, find.byKey(const ValueKey("tableSidedPadding")));
      for (var side in ["Top", "Right", "Bottom", "Left"]) {
        expect(find.byKey(ValueKey("tablePad$side")), findsOneWidget);
      }
      // Switched on, nothing has changed yet: each side starts where the one
      // figure left it.
      expect(tableIn(controller).topPad, tableIn(controller).cellPadding);

      await tester.enterText(find.byKey(const ValueKey("tablePadTop")), "30");
      await tester.pumpAndSettle();
      expect(tableIn(controller).topPad, 30);
      expect(tableIn(controller).leftPad, tableIn(controller).cellPadding,
          reason: "one side, not all of them");

      await press(tester, find.byKey(const ValueKey("tableSidedPadding")));
      expect(tableIn(controller).evenPadding, isTrue);
      expect(find.byKey(const ValueKey("tablePadTop")), findsNothing);
      await shut();
    });

    testWidgets("and the columns can be put back", (tester) async {
      // A column width is dragged on the table itself, and there was no way
      // back from it.
      var controller = await panel(tester);
      controller.replaceElement(
          tableIn(controller).copyWith(columnWidths: const [0.8, 0.2]));
      await tester.pumpAndSettle();
      var shut = await showStyle(tester);

      var sizing = find.byKey(const ValueKey("tableColumnSizing"));
      expect(sizing, findsOneWidget);
      // Three states, and the third only while the columns are in it: a
      // dragged table is neither of the two a reader can ask for.
      expect(
          tester
              .widget<CanvasDropdown<String>>(sizing)
              .options
              .map((o) => o.$1),
          ["fit", "even", "dragged"]);

      await press(tester, sizing);
      await press(tester, find.text("All the same").last);
      expect(tableIn(controller).columnWidths, [0.5, 0.5]);

      await press(tester, find.byKey(const ValueKey("tableColumnSizing")));
      await press(tester, find.text("Fit to contents").last);
      expect(tableIn(controller).evenColumns, isTrue);
      expect(
          tester
              .widget<CanvasDropdown<String>>(
                  find.byKey(const ValueKey("tableColumnSizing")))
              .options
              .map((o) => o.$1),
          ["fit", "even"],
          reason: "nothing is dragged any more, so there is no such state");
      await shut();
    });

    testWidgets("Refresh is on the Table section as well as the Data one",
        (tester) async {
      // Where somebody is standing when they want the numbers again: looking
      // at the cells. Sending them to another section to press the same
      // button is asking them to know which section owns the wire.
      var controller = await panel(tester);
      // Nothing to read yet, so no button: a heading does not carry one that
      // could never do anything.
      expect(find.byTooltip("Read the data and put it in the table"),
          findsNothing);

      controller.replaceElement(tableIn(controller).copyWith(
          source: const DataSource(kind: DataKind.file)
              .copyWith(where: "/nowhere/none.json")));
      await tester.pumpAndSettle();

      // One on the Table section and one on the Data section, both saying
      // the same thing.
      expect(find.byTooltip("Read the data and put it in the table"),
          findsNWidgets(2));
    });

    testWidgets("typing a coin offers the coins", (tester) async {
      // Only where the rows are what the source is asked for, and only in the
      // column that names one: a suggestion against a column of numbers is a
      // list nobody wants over their typing.
      var controller = await panel(tester);
      controller.replaceElement(tableIn(controller).copyWith(
        rows: const [
          ["Coin", "Price"],
          ["", "0"],
        ],
        source: coinGeckoMarkets
            .applyTo(const DataSource(), coinGeckoMarkets.choices.first.$1)
            .copyWith(fromRows: true),
      ));
      await tester.pumpAndSettle();

      var toGrid = find.byTooltip("Edit the cells in a grid");
      if (toGrid.evaluate().isNotEmpty) await press(tester, toGrid);

      // The empty cell under the Coin heading.
      var cells = find.byType(CanvasGridCell);
      expect(cells, findsWidgets);
      var named = tester
          .widgetList<CanvasGridCell>(cells)
          .where((cell) => cell.suggestions.isNotEmpty)
          .toList();
      expect(named, isNotEmpty, reason: "the column that names a row");
      expect(named.first.suggestions, contains("Decred"));
      expect(named.length, 1,
          reason: "one cell: the body of the match column, not its heading "
              "and not the column of prices");
    });

    testWidgets("and a table of typed numbers offers none", (tester) async {
      var controller = await panel(tester);
      await tester.pumpAndSettle();
      var toGrid = find.byTooltip("Edit the cells in a grid");
      if (toGrid.evaluate().isNotEmpty) await press(tester, toGrid);
      for (var cell
          in tester.widgetList<CanvasGridCell>(find.byType(CanvasGridCell))) {
        expect(cell.suggestions, isEmpty);
      }
      expect(controller.document.elements, hasLength(1));
    });

    testWidgets("a row and a column can be moved", (tester) async {
      // Buttons rather than dragging: a row added at the end and wanted
      // second is one press away either way, and a drag inside a grid of text
      // fields has to be told apart from selecting text in one of them.
      var controller = await panel(tester);
      var toGrid = find.byTooltip("Edit the cells in a grid");
      if (toGrid.evaluate().isNotEmpty) await press(tester, toGrid);

      expect(tableIn(controller).rows.first.first, "Team");
      await press(tester, find.byTooltip("Move this row down").first);
      expect(tableIn(controller).rows.first.first, "Hull City",
          reason: "the header has gone under the row that was below it");

      await press(tester, find.byTooltip("Move this column right").first);
      expect(tableIn(controller).rows.first, ["6", "Hull City"]);
    });

    testWidgets("the ends of the table have nowhere further to go",
        (tester) async {
      var controller = await panel(tester);
      var toGrid = find.byTooltip("Edit the cells in a grid");
      if (toGrid.evaluate().isNotEmpty) await press(tester, toGrid);

      // The first row's "up" and the last row's "down" are there and do
      // nothing, rather than being missing and shuffling the other buttons
      // along by one on every row.
      var up = tester.widget<CanvasIconButton>(find
          .ancestor(
              of: find.byTooltip("Move this row up").first,
              matching: find.byType(CanvasIconButton))
          .first);
      expect(up.onPressed, isNull);
      expect(tableIn(controller).rows.first.first, "Team");
    });

    testWidgets("a rule can be added and taken away from the same line",
        (tester) async {
      // Adding and removing in the same place, rather than one here and one
      // at the foot of a section that has to be opened first.
      var controller = await panel(tester);
      await press(tester, find.text("SPECIAL CELLS"));
      expect(find.byTooltip("Add a rule"), findsOneWidget);

      await press(tester, find.byTooltip("Add a rule"));
      expect(tableIn(controller).rules.length, 1);

      // At the foot of the rule it removes rather than beside Add: one button
      // per rule on one line is fine for two rules and is twenty buttons for
      // twenty.
      expect(find.byTooltip("Remove this rule"), findsNothing,
          reason: "the rule is closed");
      await press(tester, find.text("EVERY CELL"));
      await press(tester, find.byTooltip("Remove this rule"));
      expect(tableIn(controller).rules, isEmpty);
    });

    /// sections is every collapsible section's label, in the order they are
    /// laid out down the panel.
    ///
    /// Read off the widgets rather than off the text, because the pane heads
    /// itself with the element's own name -- "Table" for a table -- and a
    /// section called Table is a second one of those.
    List<String> sections(WidgetTester tester) {
      var found = [
        for (var element in find.byType(CanvasExpander).evaluate())
          (
            tester.getTopLeft(find.byWidget(element.widget)).dy,
            (element.widget as CanvasExpander).label,
          ),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      return [for (var (_, label) in found) label];
    }

    testWidgets("the cells are a section of their own", (tester) async {
      // The longest thing in these settings and the least often changed once
      // it is right, so it was pushing everything else off the bottom.
      await panel(tester);
      expect(sections(tester), contains("Table"));
      expect(find.text("2 rows, 2 columns"), findsOneWidget);
      expect(find.byType(TableDataEditor), findsOneWidget);
    });

    testWidgets("the presets list says what it is for", (tester) async {
      // The list is never blank. With nothing saved it offers to save this
      // design -- an empty box at the top of every element's settings says
      // nothing at all -- and nothing to rename or throw away until
      // something has been chosen.
      //
      // Nothing ships with the app any more, so this is what a fresh
      // install shows. What a saved one does is in
      // canvas_element_presets_test, where there is a temp folder to save
      // into.
      await panel(tester);
      var list = find.byKey(const ValueKey("elementPresets"));
      await tester.ensureVisible(list);
      await tester.pumpAndSettle();

      expect(find.text("Save this design"), findsOneWidget);
      expect(find.byKey(const ValueKey("elementPresetSave")), findsOneWidget,
          reason: "and the button that does it");
      expect(find.byKey(const ValueKey("elementPresetRename")), findsNothing);
      expect(find.byKey(const ValueKey("elementPresetRemove")), findsNothing);
    });

    testWidgets("the panel is ordered by what it is about", (tester) async {
      // The cells, then where they come from, then their order -- what the
      // table says -- and only after that how it looks. The look is two sets
      // of type controls and a dozen colour rows, which is what pushed the
      // data and the order off the bottom of the panel.
      await panel(tester);
      // Presets is not among them: it is one uncaptioned line at the top of
      // the panel rather than a section that has to be opened to find one
      // button.
      expect(find.byKey(const ValueKey("elementPresets")), findsOneWidget);
      expect(sections(tester), [
        "Table",
        "Data",
        "Order",
        "Special cells",
        "Style",
        // And last, how it arrives -- a handful of choices made once and
        // then left alone, like a headline's.
        "Animation",
      ]);
    });

    testWidgets("the two sets of type controls fold away inside Style",
        (tester) async {
      await panel(tester);
      // Inside Style, which is shut, so neither is even listed yet.
      expect(find.text("CELL TYPE"), findsNothing);
      expect(find.text("Weight"), findsNothing);

      await press(tester, find.text("STYLE"));
      expect(find.text("CELL TYPE"), findsOneWidget);
      expect(find.text("HEADER TYPE"), findsOneWidget);
      expect(find.text("Weight"), findsNothing,
          reason: "listed, but still folded away");

      await press(tester, find.text("CELL TYPE"));
      expect(find.text("Weight"), findsOneWidget);
    });

    testWidgets("the data settings fit a narrow sidebar", (tester) async {
      // Controls ask CanvasControlScope for their width and are clamped to
      // the column. A raw SizedBox bypasses that, and the key field's did --
      // 190 pixels plus a save button in a sidebar narrower than either,
      // which is an overflow stripe across the panel rather than a field
      // that is merely too wide. It now sizes itself from the room it is
      // actually given.
      var element = TableElement(
        const ElementBase(id: "t", width: 400, height: 200),
        rows: const [
          ["Team", "Points"],
          ["Hull City", "6"],
        ],
        source: footballData.applyTo(const DataSource(), "PL"),
      );
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("t");

      // Constrained here rather than by shrinking the view, which the pump
      // helper sets for itself.
      await pump(
          tester,
          SizedBox(
              width: 200, child: CanvasDesignPanel(controller: controller)));

      // The panel already overflows by 32 pixels at this width with every
      // section shut, and has since before any of this existed -- something
      // in the layers list rather than in these settings. Taken and thrown
      // away here so that this test is about the sections it opens; it is not
      // a licence for a new one, which is what the checks below catch.
      tester.takeException();

      await press(tester, find.text("DATA"));
      expect(find.text("KEY"), findsOneWidget,
          reason: "the key field only exists once the source is an address, "
              "so without it this test is testing nothing");
      expect(tester.takeException(), isNull);

      await press(tester, find.text("COLUMNS"));
      expect(tester.takeException(), isNull);

      // Shut again. A section remembers whether it is open in a static map
      // that outlives one test, so a section left open here is a section open
      // in every test that runs after this one -- and the panel has more than
      // one button called Add once this section is showing.
      await press(tester, find.text("COLUMNS"));
      await press(tester, find.text("DATA"));
    });

    testWidgets("a table is refreshed and reordered from the headings",
        (tester) async {
      // Both without opening anything: pressing a button inside a section
      // means opening it, finding the button, and closing it again, every
      // time.
      var controller = await panel(tester);
      controller.replaceElement((tableIn(controller)).copyWith(
        headerRow: true,
        sort: const TableSort(levels: [TableSortLevel(column: 1)]),
      ));
      await tester.pumpAndSettle();

      expect(find.byTooltip("Put the rows back in this order"), findsOneWidget);
      expect(find.byTooltip("Choose where the data comes from first"),
          findsOneWidget);
    });

    testWidgets("a row and a column can be added and taken away",
        (tester) async {
      var controller = await panel(tester);
      var toGrid = find.byTooltip("Edit the cells in a grid");
      if (toGrid.evaluate().isNotEmpty) await press(tester, toGrid);

      await press(tester, find.byTooltip("Add a row"));
      expect(tableIn(controller).rows.length, 3);

      await press(tester, find.byTooltip("Add a column"));
      expect(tableIn(controller).columnCount, 3);
      expect(tableIn(controller).rows.every((r) => r.length == 3), isTrue,
          reason: "every row gains the column, or the grid goes ragged");

      await press(tester, find.byTooltip("Remove this column").first);
      expect(tableIn(controller).columnCount, 2);

      await press(tester, find.byTooltip("Remove this row").first);
      expect(tableIn(controller).rows.length, 2);
    });
  });

  group("the sidebar's explanations", () {
    // Each panel carried a paragraph, permanently, taking a fifth of a narrow
    // column to say something read once and never again. Behind a question
    // mark it is still there for whoever has not read it and costs nothing to
    // whoever has.

    /// shown is the text of every hint the panel is offering.
    // Both kinds: the canvas's own hint inside a settings group, and the
    // shared panel stack's, which is what a panel header carries now.
    List<String> shown(WidgetTester tester) => [
          for (var h in tester.widgetList<CanvasHint>(find.byType(CanvasHint)))
            h.message,
          for (var h in tester.widgetList<PanelHint>(find.byType(PanelHint)))
            h.message,
        ];

    testWidgets("the Add grid explains itself on a question mark",
        (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      // Through the design panel, because the hint hangs off the Add panel's
      // own header now rather than off a heading inside the grid.
      await pump(tester, CanvasDesignPanel(controller: controller));

      const hint = "Click to add one in the middle of the canvas, or drag it "
          "where you want it.";
      expect(find.text(hint), findsNothing, reason: "not in the column");
      expect(shown(tester), contains(hint));

      // Tap as well as hover: a hint reachable only by hovering does not
      // exist on a touch screen.
      await tester.tap(find.byType(PanelHint).first);
      await tester.pumpAndSettle();
      expect(find.text(hint), findsOneWidget);
    });

    testWidgets("so do the presets, on each of the three lists",
        (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(
          tester,
          CanvasPresetsSidebar(
              controller: controller, onChoose: (_, __) {}));

      // Three panels in a stack now, like the Design sidebar: a canvas to
      // start from, a scene to add, an element to drop on.
      for (var heading in ["CANVAS", "SCENE", "ELEMENT"]) {
        expect(find.text(heading), findsOneWidget, reason: heading);
      }
      expect(
          shown(tester),
          contains("A whole document to start from. Tap one to begin a new "
              "canvas, or use its menu to add its scenes to the canvas "
              "already open."));
    });

    testWidgets("and the element settings, on their panel's own header",
        (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);

      await pump(tester, CanvasDesignPanel(controller: controller));
      expect(find.text(elementSettingsHint), findsNothing,
          reason: "not sitting in the column");
      expect(shown(tester), contains(elementSettingsHint));
    });
  });

  group("a layer row", () {
    Future<CanvasController> panel(WidgetTester tester) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      await pump(tester, CanvasDesignPanel(controller: controller));
      return controller;
    }

    testWidgets("duplicates rather than copying", (tester) async {
      // A copy did nothing anybody could see: the canvas was unchanged and the
      // only evidence was that a paste somewhere else would now produce this.
      var controller = await panel(tester);
      var original = controller.document.elements.single;

      expect(find.byTooltip("Copy"), findsNothing);
      await tester.tap(find.byTooltip("Duplicate"));
      await tester.pumpAndSettle();

      var elements = controller.document.elements;
      expect(elements.length, 2);
      expect(elements.last.id, isNot(original.id), reason: "a new element");
      expect(elements.last.x, greaterThan(original.x),
          reason: "offset, so it is visibly a second thing");
      expect(controller.selection, {elements.last.id},
          reason: "and selected, which is what makes it findable");
    });

    testWidgets("duplicating leaves the clipboard alone", (tester) async {
      // Wanting a second one of these is not a reason to lose whatever was
      // copied to paste onto another canvas.
      var controller = await panel(tester);
      controller.selectOnly(controller.document.elements.single.id);
      controller.copySelected();
      var copied = controller.document.elements.single.id;

      await tester.tap(find.byTooltip("Duplicate"));
      await tester.pumpAndSettle();
      controller.paste();

      expect(controller.document.elements.length, 3);
      expect(controller.canPaste, isTrue);
      expect(copied, isNotEmpty);
    });

    testWidgets("the lock is legible either way round", (tester) async {
      // It was lock_outline against lock_open_outlined, which are the same
      // padlock with the shackle moved a couple of pixels. At fourteen pixels
      // on a row of five icons, locking something looked like it had done
      // nothing at all.
      var controller = await panel(tester);

      expect(find.byIcon(Icons.lock_open_outlined), findsOneWidget);
      await tester.tap(find.byTooltip("Lock"));
      await tester.pumpAndSettle();

      expect(controller.document.elements.single.locked, isTrue);
      expect(find.byIcon(Icons.lock), findsOneWidget,
          reason: "filled, not another outline");
      expect(find.byIcon(Icons.lock_open_outlined), findsNothing);

      await tester.tap(find.byTooltip("Unlock"));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.lock_open_outlined), findsOneWidget);
    });
  });

  group("the design panel", () {
    // Adding, the layer list and the settings used to be tabs, and two of them
    // carried copies of the third just to shorten the journey between them.
    // They are one column of panels now, each opening, closing, resizing and
    // moving, and all of that remembered.
    Future<CanvasController> panel(WidgetTester tester) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      await pump(tester, CanvasDesignPanel(controller: controller));
      return controller;
    }

    testWidgets("all three are in one column", (tester) async {
      await panel(tester);
      for (var name in ["ADD", "LAYERS", "BACKGROUND SETTINGS"]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.byType(PanelStack), findsOneWidget);
    });

    testWidgets("the settings are never empty", (tester) async {
      // Nothing selected is the state a canvas starts in and returns to every
      // time somebody clicks the page. A panel that empties itself is a panel
      // that keeps taking its room back and giving it away again -- so with
      // nothing selected these are the canvas's own background, which is the
      // one thing always there and always worth changing.
      var controller = await panel(tester);
      expect(controller.selected, isNull);
      expect(find.text("Background"), findsWidgets);

      controller.selectOnly(controller.document.elements.single.id);
      await tester.pumpAndSettle();
      expect(find.text("Opacity"), findsOneWidget,
          reason: "and the element's own controls once there is one");

      controller.clearSelection();
      await tester.pumpAndSettle();
      expect(find.text("Background"), findsWidgets,
          reason: "and back to the background rather than to nothing");
    });

    testWidgets("a panel closes and stays closed when something is selected",
        (tester) async {
      // The instruction that makes closing one worth doing. A panel that
      // reopens because an element was clicked has to be closed again after
      // every click.
      var controller = await panel(tester);

      // The header names what is being edited, so with nothing selected it is
      // the background's.
      await tester.tap(find.text("BACKGROUND SETTINGS"));
      await tester.pumpAndSettle();
      expect(find.text("Opacity"), findsNothing);

      controller.selectOnly(controller.document.elements.single.id);
      await tester.pumpAndSettle();
      expect(find.text("Opacity"), findsNothing,
          reason: "selecting does not reopen it");

      controller.addElement(newElement(ElementKind.text, controller.document));
      await tester.pumpAndSettle();
      expect(find.text("Opacity"), findsNothing, reason: "nor does adding one");

      // And the header is still there, because a panel with no way back is a
      // trap. It is named for whatever is selected by now, so it is found by
      // what every one of those names ends with.
      await tester.tap(find.textContaining("SETTINGS").last);
      await tester.pumpAndSettle();
      expect(find.text("Opacity"), findsOneWidget);
    });

    testWidgets("every panel can be carried, and none of them by its name",
        (tester) async {
      await panel(tester);
      // One handle each. The name is the switch, so it cannot also be the
      // grip -- a panel that moved when you tried to open it would be a panel
      // you could not open.
      // One per panel: Add, Scenes, Layers and the settings.
      expect(find.byType(Draggable<PanelDrag>), findsNWidgets(4),
          reason: "and carried as their own type, not as the plain strings "
              "the layer list drags -- otherwise a panel could be dropped on "
              "a layer");
      expect(find.byIcon(Icons.drag_indicator), findsNWidgets(4));
    });

    testWidgets("the boundaries are the grips, and the top has none",
        (tester) async {
      // Resizing is done on the line between two panels rather than on an icon
      // in a header: the boundary is the thing being moved. Three panels have
      // two boundaries, and the top of the first is not one of them -- there
      // is nothing above it to take the room from.
      await panel(tester);
      expect(find.byIcon(Icons.drag_handle), findsNothing,
          reason: "the grip that used to sit in the header is gone");
      expect(
          find.descendant(
              of: find.byType(PanelStack),
              matching: find.byWidgetPredicate((w) =>
                  w is MouseRegion &&
                  w.cursor == SystemMouseCursors.resizeUpDown)),
          findsNWidgets(3),
          reason: "four panels have three boundaries, and the top of the "
              "first is not one of them");
    });

    testWidgets("every handle is in the same place, hard right",
        (tester) async {
      // They were at three different places, because the label was a Flexible
      // and the space after it was a Spacer -- two flexible children of one
      // Row, so the gap was half of whatever was left and the handle sat
      // wherever the name's length put it.
      await panel(tester);
      var handles =
          tester.widgetList<Widget>(find.byIcon(Icons.drag_indicator)).length;
      expect(handles, 4);

      var rights = [
        for (var i = 0; i < handles; i++)
          tester.getRect(find.byIcon(Icons.drag_indicator).at(i)).right,
      ];
      expect(rights.toSet(), hasLength(1),
          reason: "all of them line up: $rights");

      // And hard right, not floating in the middle of the band.
      var band = tester.getRect(find.byType(PanelStack)).right;
      expect(rights.first, closeTo(band, 14));
    });

    testWidgets("a header is a band, and the whole of it is the switch",
        (tester) async {
      // No expander arrow: the whole band opens and closes the panel, and an
      // arrow beside it is a smaller target that looks like the only one.
      await panel(tester);

      // Beside the name, rather than anywhere on the page: a section *inside*
      // a panel -- the Lights under a background, the Table under a chart --
      // is a CanvasExpander and has an arrow of its own, which is a different
      // control and not what this is about.
      var header = tester.getRect(find.text("ADD"));
      for (var arrow in [Icons.expand_more, Icons.chevron_right]) {
        for (var element in find.byIcon(arrow).evaluate()) {
          expect(tester.getRect(find.byElementPredicate((e) => e == element)),
              isNot(predicate<Rect>((r) => r.overlaps(header))),
              reason: "an arrow on the header's own line");
        }
      }

      // Tapping the name, which is nowhere near where an arrow would have
      // been, still closes it.
      expect(find.byType(CanvasElementsPanel), findsOneWidget);
      await tester.tap(find.text("ADD"));
      await tester.pumpAndSettle();
      expect(find.byType(CanvasElementsPanel), findsNothing);
    });
  });

  group("an element's keyframe easing", () {
    /// showAnimation opens the Animation section if it is shut, and hands
    /// back what shuts it again -- an expander remembers, and the memory
    /// outlives the test.
    Future<Future<void> Function()> showAnimation(WidgetTester tester) async {
      var open = find
          .byKey(const ValueKey("elementAnimationFamily"))
          .evaluate()
          .isNotEmpty;
      if (!open) {
        await tester.ensureVisible(find.text("ANIMATION"));
        await tester.pumpAndSettle();
        await tester.tap(find.text("ANIMATION"));
        await tester.pumpAndSettle();
      }
      return () async {
        if (!open) {
          await tester.tap(find.text("ANIMATION"));
          await tester.pumpAndSettle();
        }
      };
    }

    // Easing belongs to the keyframe it leaves, so it is offered wherever
    // somebody is looking at one -- and it matters more now that a run of
    // keyframes can be copied and pasted, because what gets pasted is
    // whatever easing each of them had.
    testWidgets("is offered while the playhead is on one", (tester) async {
      var document = const CanvasDocument(frames: 40);
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      controller.frame = 5;
      await pump(tester, CanvasDesignPanel(controller: controller));
      var shut = await showAnimation(tester);

      var easing = find.byKey(const ValueKey("elementKeyframeEasing"));
      expect(easing, findsNothing, reason: "no keyframe here to ease out of");

      controller.setKeyframe(element.id, const Keyframe(frame: 5, dx: 20));
      controller.setKeyframe(element.id, const Keyframe(frame: 15, dx: 60));
      await tester.pumpAndSettle();
      easing = find.byKey(const ValueKey("elementKeyframeEasing"));
      await tester.ensureVisible(easing);
      await tester.pumpAndSettle();
      expect(easing, findsOneWidget);

      await tester.tap(easing);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Bounce").last);
      await tester.pumpAndSettle();
      expect(controller.document.elements.single.track?.keyAt(5)?.easing,
          KeyframeEasing.bounce);
      expect(controller.document.elements.single.track?.keyAt(15)?.easing,
          KeyframeEasing.linear,
          reason: "one keyframe, not the whole track");

      // And the button beside it gives every keyframe the same one.
      var all = find.byKey(const ValueKey("elementKeyframeEasingAll"));
      await tester.ensureVisible(all);
      await tester.pumpAndSettle();
      await tester.tap(all);
      await tester.pumpAndSettle();
      expect(controller.document.elements.single.track?.keyAt(15)?.easing,
          KeyframeEasing.bounce);
      await shut();
    });

    testWidgets("and says so even when the playhead is between two",
        (tester) async {
      // Hidden until the playhead stood on a keyframe, it was a control
      // nobody could find: there is no telling a setting that does not exist
      // from one waiting for the playhead to be somewhere else.
      var document = const CanvasDocument(frames: 40);
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      controller.setKeyframe(element.id, const Keyframe(frame: 5, dx: 20));
      controller.setKeyframe(element.id, const Keyframe(frame: 15, dx: 60));
      controller.frame = 9;
      await pump(tester, CanvasDesignPanel(controller: controller));
      var shut = await showAnimation(tester);

      var easing = find.byKey(const ValueKey("elementKeyframeEasing"));
      expect(easing, findsOneWidget, reason: "there for the finding");
      expect(tester.widget<CanvasDropdown<KeyframeEasing>>(easing).enabled,
          isFalse,
          reason: "and greyed, because there is no keyframe on this frame");
      expect(
          tester
              .widgetList<CanvasHint>(find.byType(CanvasHint))
              .map((h) => h.message)
              .where((m) => m.contains("2 marks")),
          isNotEmpty,
          reason: "and says where to put the playhead to use it");
      await shut();
    });

    testWidgets("and an element with no keyframes at all offers none",
        (tester) async {
      var document = const CanvasDocument(frames: 40);
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasDesignPanel(controller: controller));
      var shut = await showAnimation(tester);
      expect(find.byKey(const ValueKey("elementKeyframeEasing")), findsNothing);
      await shut();
    });

    testWidgets("a caption and a chart have it too", (tester) async {
      // They have animation sections of their own, and "the easing of this
      // keyframe" is not a question about what kind of element it is.
      for (var kind in [ElementKind.text, ElementKind.chart]) {
        var document = const CanvasDocument(frames: 40);
        var element = newElement(kind, document);
        var controller = CanvasController(document.addElement(element));
        addTearDown(controller.dispose);
        controller.selectOnly(element.id);
        controller.setKeyframe(element.id, const Keyframe(frame: 0, dx: 4));
        await pump(tester, CanvasDesignPanel(controller: controller));

        await tester.ensureVisible(find.text("ANIMATION"));
        await tester.pumpAndSettle();
        await tester.tap(find.text("ANIMATION"));
        await tester.pumpAndSettle();
        expect(
            find.byKey(const ValueKey("elementKeyframeEasing")), findsOneWidget,
            reason: kind.name);
        await tester.tap(find.text("ANIMATION"));
        await tester.pumpAndSettle();
      }
    });

    testWidgets("and Hold is among the choices", (tester) async {
      // "Stays the same until the next keyframe", which is what a count in
      // steps and a cut both need.
      var document = const CanvasDocument(frames: 40);
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      controller.frame = 5;
      controller.setKeyframe(element.id, const Keyframe(frame: 5, dx: 20));
      await pump(tester, CanvasDesignPanel(controller: controller));
      var shut = await showAnimation(tester);

      var easing = find.byKey(const ValueKey("elementKeyframeEasing"));
      await tester.ensureVisible(easing);
      await tester.pumpAndSettle();
      await tester.tap(easing);
      await tester.pumpAndSettle();
      expect(find.text("Hold (stays the same)"), findsWidgets);
      expect(find.text("Overshoot"), findsWidgets);
      await tester.tap(find.text("Hold (stays the same)").last);
      await tester.pumpAndSettle();
      expect(controller.document.elements.single.track?.keyAt(5)?.easing,
          KeyframeEasing.hold);
      await shut();
    });
  });

  group("the counter settings", () {
    // Two elements in one, and the switch between them is the thing to pin:
    // keyframes on, the number is read off the timeline; off, it runs in real
    // time and the buttons under it mean something.
    Future<CanvasController> panel(WidgetTester tester,
        {CounterElement Function(CounterElement)? shape,
        int frames = 60}) async {
      var element = const CounterElement(
        ElementBase(id: "n", width: 320, height: 160),
        from: 0,
        to: 100,
      );
      var controller = CanvasController(CanvasDocument(frames: frames)
          .addElement(shape == null ? element : shape(element)));
      addTearDown(controller.dispose);
      controller.selectOnly("n");
      await pump(tester, CanvasDesignPanel(controller: controller));
      return controller;
    }

    CounterElement counterIn(CanvasController controller) =>
        controller.document.elements.single as CounterElement;

    Future<void> press(WidgetTester tester, Finder what) async {
      await tester.ensureVisible(what);
      await tester.pumpAndSettle();
      await tester.tap(what);
      await tester.pumpAndSettle();
    }

    /// showCount opens the Count section if it is shut, and hands back what
    /// shuts it again -- an expander remembers, and the memory outlives the
    /// test.
    Future<Future<void> Function()> showCount(WidgetTester tester) async {
      var open =
          find.byKey(const ValueKey("counterKeyed")).evaluate().isNotEmpty;
      if (!open) await press(tester, find.text("COUNT"));
      return () async {
        if (!open) await press(tester, find.text("COUNT"));
      };
    }

    testWidgets("count from, to and how the number is written", (tester) async {
      var controller = await panel(tester);
      await tester.enterText(find.byKey(const ValueKey("counterTo")), "250");
      await tester.pumpAndSettle();
      expect(counterIn(controller).to, 250);

      await tester.enterText(
          find.byKey(const ValueKey("counterDecimals")), "2");
      await tester.pumpAndSettle();
      expect(counterIn(controller).decimals, 2);
      expect(counterIn(controller).format(1234.5), "1234.50");
    });

    testWidgets("the words either side are the counter's, not the number's",
        (tester) async {
      var controller = await panel(tester);
      await tester.enterText(find.byKey(const ValueKey("counterBefore")), "£");
      await tester.pumpAndSettle();
      expect(counterIn(controller).before, "£");
      expect(counterIn(controller).textFor(12), "£12");
    });

    testWidgets("the two ends can be pinned where the playhead is",
        (tester) async {
      var controller = await panel(tester);
      var shut = await showCount(tester);

      controller.frame = 0;
      await tester.pumpAndSettle();
      await press(tester, find.byKey(const ValueKey("counterPinFrom")));
      controller.frame = 24;
      await tester.pumpAndSettle();
      await press(tester, find.byKey(const ValueKey("counterPinTo")));

      controller.frame = 12;
      expect(
          controller.valueAt(counterIn(controller), KeyframeChannel.count, -1),
          closeTo(50, 0.001),
          reason: "half way along, half way through the count");

      // And pinning a number says nothing about where the element is. It used
      // to: the seed keyframe is a resting pose, which is how a track says it
      // has been animated in space -- so the position, size, angle and fade
      // diamond lit up and every later drag wrote a pose.
      expect(counterIn(controller).track?.posesAnything, isFalse);
      await shut();
    });

    testWidgets("and a point in between is another keyframe", (tester) async {
      var controller = await panel(tester);
      var shut = await showCount(tester);

      controller.frame = 10;
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey("counterPointValue")), "140");
      await tester.pumpAndSettle();

      expect(counterIn(controller).track?.keyAt(10), isNotNull);
      expect(
          controller.valueAt(counterIn(controller), KeyframeChannel.count, -1),
          140,
          reason: "a point can be higher than either end");
      await shut();
    });

    testWidgets("and one easing can be given to every point", (tester) async {
      var controller = await panel(tester);
      var shut = await showCount(tester);

      for (var frame in [0, 6, 12]) {
        controller.frame = frame;
        await tester.pumpAndSettle();
        await press(tester, find.byKey(const ValueKey("counterAddPoint")));
      }

      controller.frame = 6;
      await tester.pumpAndSettle();
      await press(tester, find.byKey(const ValueKey("counterEasing")));
      await press(tester, find.text("Hold (stays the same)").last);
      await press(tester, find.byKey(const ValueKey("counterEasingAll")));

      var track = counterIn(controller).track!;
      for (var frame in [0, 6, 12]) {
        expect(track.keyAt(frame)?.easing, KeyframeEasing.hold,
            reason: "frame $frame");
      }
      await shut();
    });

    testWidgets("and each point says how the number leaves it", (tester) async {
      var controller = await panel(tester);
      var shut = await showCount(tester);

      controller.frame = 6;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey("counterEasing")), findsNothing,
          reason: "no keyframe here, so nothing to ease out of");

      await press(tester, find.byKey(const ValueKey("counterPinFrom")));
      var easing = find.byKey(const ValueKey("counterEasing"));
      expect(easing, findsOneWidget);

      await press(tester, easing);
      await press(tester, find.text("Hold (stays the same)").last);
      expect(
          counterIn(controller).track?.keyAt(6)?.easing, KeyframeEasing.hold);
      expect(
          counterIn(controller).track?.keyAt(6)?.values[KeyframeChannel.count],
          0,
          reason: "and the number it pins is still there");
      await shut();
    });

    testWidgets("switching the keyframes off offers the live settings instead",
        (tester) async {
      var controller = await panel(tester);
      var shut = await showCount(tester);
      expect(find.byKey(const ValueKey("counterPinFrom")), findsOneWidget);
      expect(find.byKey(const ValueKey("counterRate")), findsNothing);

      await press(tester, find.byKey(const ValueKey("counterKeyed")));
      expect(counterIn(controller).live, isTrue);
      expect(find.byKey(const ValueKey("counterPinFrom")), findsNothing);
      expect(find.byKey(const ValueKey("counterRate")), findsOneWidget);
      expect(find.byKey(const ValueKey("counterLoop")), findsOneWidget);
      await shut();
    });

    testWidgets("and asking for the time writes it the way a clock is written",
        (tester) async {
      // A clock written plainly is a number of seconds since midnight, which
      // is not a thing anybody wants to read.
      var controller =
          await panel(tester, shape: (e) => e.copyWith(keyed: false));
      var shut = await showCount(tester);

      await press(tester, find.byKey(const ValueKey("counterSource")));
      await press(tester, find.text("The time").last);
      expect(counterIn(controller).source, CounterSource.clock);
      expect(counterIn(controller).separator.isTime, isTrue);
      await shut();
    });

    testWidgets("the number's spacing and the words' placing are offered",
        (tester) async {
      // Both of these went missing once: they live inside the two type
      // sections rather than in a group of their own, and a section nobody
      // opens is a setting nobody has.
      var controller = await panel(tester);
      await press(tester, find.text("NUMBER TYPE"));
      expect(find.byKey(const ValueKey("counterGap")), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey("counterGap")), "1.5");
      await tester.pumpAndSettle();
      expect(counterIn(controller).gap, 1.5);
      await press(tester, find.text("NUMBER TYPE"));

      await press(tester, find.text("WORDS TYPE"));
      expect(find.byKey(const ValueKey("counterLoose")), findsOneWidget);
      expect(find.byKey(const ValueKey("counterBeforeAtX")), findsNothing);

      await press(tester, find.byKey(const ValueKey("counterLoose")));
      expect(counterIn(controller).loose, isTrue);
      for (var key in [
        "counterBeforeAtX",
        "counterBeforeAtY",
        "counterAfterAtX",
        "counterAfterAtY",
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }

      await tester.enterText(
          find.byKey(const ValueKey("counterAfterAtY")), "0.3");
      await tester.pumpAndSettle();
      expect(counterIn(controller).afterAt.dy, 0.3);
      expect(counterIn(controller).beforeAt.dy, 0,
          reason: "one word, not both");
      await press(tester, find.text("WORDS TYPE"));
    });

    testWidgets("the buttons are switched on one at a time", (tester) async {
      var controller =
          await panel(tester, shape: (e) => e.copyWith(keyed: false));
      await press(tester, find.text("BUTTONS"));
      expect(counterIn(controller).buttons, isEmpty);

      await press(
          tester, find.byKey(const ValueKey("counterButton-startStop")));
      await press(tester, find.byKey(const ValueKey("counterButton-input")));
      expect(counterIn(controller).buttons,
          [CounterButton.startStop, CounterButton.input],
          reason: "kept in the order they are declared in, not switched on");

      await press(
          tester, find.byKey(const ValueKey("counterButton-startStop")));
      expect(counterIn(controller).buttons, [CounterButton.input]);
      await press(tester, find.text("BUTTONS"));
    });
  });

  group("the chart settings", () {
    Future<CanvasController> panel(WidgetTester tester,
        {ChartElement Function(ChartElement)? shape}) async {
      var element = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        title: "Messages",
        description: "By week",
        data: ChartData.parse("Cat\tA\nx\t10\ny\t6"),
      );
      if (shape != null) element = shape(element);
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("c");
      await pump(tester, CanvasDesignPanel(controller: controller));
      return controller;
    }

    ChartElement chartIn(CanvasController controller) =>
        controller.document.elements.single as ChartElement;

    /// press scrolls the settings to a control and taps it. A chart has more
    /// settings than fit in the panel, so most of them start off screen.
    Future<void> press(WidgetTester tester, Finder what) async {
      await tester.ensureVisible(what);
      await tester.pumpAndSettle();
      await tester.tap(what);
      await tester.pumpAndSettle();
    }

    /// labels opens the section the title, the description and the key are
    /// now gathered in. Closed to begin with, like the other sections.
    Future<void> labels(WidgetTester tester) async {
      // Keyed off the "over the chart" switch at the foot of the section
      // rather than off a caption: the title and the description have no
      // captions any more, only placeholders inside their own fields.
      if (find.text("Over the chart").evaluate().isEmpty) {
        await press(tester, find.text("LABELS"));
      }
    }

    /// grid opens the section the rules, the scale and the way a number is
    /// written are gathered in.
    Future<void> grid(WidgetTester tester) async {
      if (find.text("Log scale").evaluate().isEmpty) {
        await press(tester, find.text("GRID"));
      }
    }

    /// axisMore opens the button on the end of the X and Y labels line, which
    /// is where everything about how the writing on the axes looks now lives.
    Future<void> axisMore(WidgetTester tester) async {
      await labels(tester);
      if (find.text("Label size").evaluate().isEmpty) {
        await press(
            tester, find.byKey(const ValueKey("more-chartAxisLabelsMore")));
      }
    }

    /// legendMore opens the button on the end of the Legend line, which holds
    /// the key's own settings.
    Future<void> legendMore(WidgetTester tester) async {
      await labels(tester);
      if (find.text("Place").evaluate().isEmpty) {
        await press(tester, find.byKey(const ValueKey("more-chartLegendMore")));
      }
    }

    testWidgets("smooth is behind the series it curves", (tester) async {
      // It was a chart setting in a group called Lines, which on a chart of
      // bars with a line over it said nothing about which half of the chart
      // it meant. It is on the series now.
      await panel(tester, shape: (e) => e.copyWith(type: ChartType.line));
      expect(find.text("Smooth"), findsNothing,
          reason: "not until the series is opened");

      await press(tester, find.byKey(const ValueKey("seriesMore0")));
      expect(find.text("Smooth"), findsOneWidget);
      expect(find.text("Width"), findsOneWidget,
          reason: "the rest of how a line is drawn is in there with it");
    });

    testWidgets("and a set of bars is offered what bars have instead",
        (tester) async {
      // A switch that does nothing is indistinguishable from a broken one,
      // and bars have nothing to curve.
      await panel(tester);
      await press(tester, find.byKey(const ValueKey("seriesMore0")));
      expect(find.text("Smooth"), findsNothing);
      expect(find.text("Corner"), findsOneWidget);
      expect(find.text("Spacing"), findsOneWidget);
    });

    testWidgets("grouped bars say what they need", (tester) async {
      // They draw exactly what plain bars draw until there is a second series
      // to group, so choosing one on a one-series chart looks like the setting
      // doing nothing at all.
      var controller =
          await panel(tester, shape: (e) => e.copyWith(type: ChartType.bar));
      Iterable<String> hints() => tester
          .widgetList<CanvasHint>(find.byType(CanvasHint))
          .map((h) => h.message)
          .where((m) => m.contains("Grouped and stacked"));
      expect(hints(), isEmpty);

      controller.replaceElement(
          chartIn(controller).copyWith(type: ChartType.groupedBar));
      await tester.pumpAndSettle();
      expect(hints(), isNotEmpty);

      controller.replaceElement(chartIn(controller)
          .copyWith(data: ChartData.parse("Cat\tA\tB\nx\t10\t5\ny\t6\t9")));
      await tester.pumpAndSettle();
      expect(hints(), isEmpty, reason: "with two series it has its answer");
    });

    testWidgets("the grid line carries the switches and hides the rest",
        (tester) async {
      // Four switches and a button. What is ruled and what is written on the
      // plot are the things anybody changes; how finely it is ruled and what
      // colour the rules are are things they set once.
      var controller = await panel(tester);
      Finder toggle(String label) => find.ancestor(
          of: find.text(label), matching: find.byType(CanvasToggle));
      for (var label in ["Grid", "Axes", "Log scale", "Values"]) {
        expect(toggle(label), findsOneWidget, reason: label);
      }
      expect(find.text("Lines"), findsNothing);
      expect(find.byKey(const ValueKey("chartAxisSteps")), findsNothing);

      await press(tester, find.byKey(const ValueKey("more-chartGridMore")));
      expect(find.byKey(const ValueKey("chartAxisSteps")), findsOneWidget);
      // The rules' colour with them. It was in a section called Style, two
      // headings away from the switch it belongs to.
      expect(find.byKey(const ValueKey("chartGridColour")), findsOneWidget);

      // Values is the chart's own, not the key's.
      var was = chartIn(controller).showValues;
      await press(tester, toggle("Values"));
      expect(chartIn(controller).showValues, !was);
      // Shut it again: an open button stays open for the rest of the file.
      await press(tester, find.byKey(const ValueKey("more-chartGridMore")));
    });

    testWidgets("the first series' Drawn as is the chart's own type",
        (tester) async {
      // There was a Type dropdown as well, three sections above the series
      // list, and the two said the same thing in two places: a one-series
      // chart set to bars with its series set to "As the chart" has one
      // answer and two controls for it that could disagree.
      var controller = await panel(tester);
      expect(find.text("TYPE"), findsNothing);

      var drawnAs = find.byKey(const ValueKey("chartType"));
      expect(drawnAs, findsOneWidget);
      // Every kind, including the circular ones no later series can be: this
      // is the chart's own setting, not a series' override.
      expect(tester.widget<CanvasDropdown<String>>(drawnAs).options.length,
          ChartType.values.length);

      await press(tester, drawnAs);
      await tester.tap(find.text(ChartType.pie.label).last);
      await tester.pumpAndSettle();
      expect(chartIn(controller).type, ChartType.pie);

      // And the series goes back to following the chart in the same write.
      // Left pinned to what it was, choosing here would change the chart and
      // draw the first series the old way.
      controller.replaceElement(chartIn(controller).copyWith(
          data: ChartData(
        categories: chartIn(controller).data.categories,
        series: [
          chartIn(controller).data.series.first.copyWith(type: ChartType.bar),
          ...chartIn(controller).data.series.skip(1),
        ],
      )));
      await tester.pumpAndSettle();

      await press(tester, find.byKey(const ValueKey("chartType")));
      await tester.tap(find.text(ChartType.area.label).last);
      await tester.pumpAndSettle();
      expect(chartIn(controller).type, ChartType.area);
      expect(chartIn(controller).data.series.first.type, isNull);
    });

    testWidgets("the title and the description can be switched off",
        (tester) async {
      var controller = await panel(tester);
      await labels(tester);
      // No captions at all now: an empty field says which it is, and a full
      // one says what it says.
      expect(find.text("TITLE"), findsNothing);
      expect(find.text("DESCRIPTION"), findsNothing);
      var hints = tester
          .widgetList<CanvasTextField>(find.byType(CanvasTextField))
          .map((f) => f.hint);
      expect(hints, containsAll(["Title", "Description"]));
      expect(chartIn(controller).titleBox.show, isTrue);

      // Two "Show" toggles, one per label, so the title's is the first.
      await press(tester, find.text("Show").first);
      expect(chartIn(controller).titleBox.show, isFalse);
      expect(chartIn(controller).descriptionBox.show, isTrue,
          reason: "one switch each");
    });

    testWidgets("floating offers where each label goes", (tester) async {
      // There used to be a "place it yourself" button per label, which was a
      // second switch saying the same thing as "Over the chart": a label that
      // floats is one that sits where it is put.
      var controller = await panel(tester);
      await labels(tester);
      expect(chartIn(controller).floatingLabels, isFalse);
      // Two X already: the element's own position at the top of the panel,
      // and the switch that shows the X axis' title.
      expect(find.text("X"), findsNWidgets(2));
      expect(find.text("H"), findsOneWidget);
      expect(find.byTooltip("Place it yourself — then drag it on the canvas"),
          findsNothing);

      await press(tester, find.text("Over the chart"));

      // And now one for the title and one for the description as well.
      expect(find.text("X"), findsNWidgets(4));
      expect(find.text("H"), findsNWidgets(3));
    });

    testWidgets("switching it off keeps where they were put", (tester) async {
      // The switch goes both ways without losing anything: off puts the chart
      // back exactly as it was, and on again finds the labels where they were
      // dragged rather than back at their defaults.
      var controller = await panel(tester);
      await labels(tester);
      await press(tester, find.text("Over the chart"));

      controller.replaceElement(chartIn(controller).copyWith(
          titleBox:
              const ChartLabel(x: 0.4, y: 0.5, width: 0.3, height: 0.12)));
      await tester.pumpAndSettle();

      // And the box goes back round the chart, rather than staying as big as
      // the labels made it while they were floating.
      controller.replaceElement(chartIn(controller).copyWith(
          body: const ChartBody(x: 0.1, y: 0.1, width: 0.9, height: 0.9)));
      await tester.pumpAndSettle();

      await press(tester, find.text("Over the chart"));
      expect(chartIn(controller).floatingLabels, isFalse);
      expect(chartIn(controller).body.isWhole, isTrue,
          reason: "the chart fills its element again");
      expect(chartIn(controller).titleBox.x, 0.4,
          reason: "kept, not thrown away");

      await press(tester, find.text("Over the chart"));
      expect(chartIn(controller).titleBox.x, 0.4);
    });

    testWidgets("how a number is written is a setting", (tester) async {
      // The decimals only appear once there is a style to apply them to:
      // automatic picks its own, so a box under it would do nothing.
      var controller = await panel(tester);
      // It sits with the gridlines and the scale -- how this chart is
      // measured -- which is a section that starts shut.
      await grid(tester);
      expect(find.text("Decimal places"), findsNothing);

      await press(tester, find.text("Automatic — 1000000, 12.5"));
      await tester.tap(find.text("Millions — 1.0M").last);
      await tester.pumpAndSettle();

      var chart = chartIn(controller);
      expect(chart.numbers.style, NumberStyle.millions);
      expect(chart.numbers.decimals, 1,
          reason: "seeded from what automatic was doing rather than reset to "
              "none");
      expect(find.text("Decimal places"), findsOneWidget);
      expect(chart.numbers.format(1000000), "1.0M");
    });

    testWidgets("and the list shows what it is set to do", (tester) async {
      // Listed with a fixed example, "Millions — 1.0M" reads as the only
      // thing millions can be, and the places beside it look like something
      // else's setting -- which is how somebody wanting 1.00M concludes they
      // cannot have it.
      await panel(tester,
          shape: (e) => e.copyWith(
              numbers: const ChartNumbers(
                  style: NumberStyle.millions, decimals: 2)));
      await grid(tester);

      expect(find.text("Millions — 1.00M"), findsOneWidget);
      expect(find.text("Millions — 1.0M"), findsNothing);
      // Automatic keeps its own, because what it does is vary: one example
      // would be a promise it does not make.
      await press(tester, find.text("Millions — 1.00M"));
      expect(find.text("Automatic — 1000000, 12.5"), findsWidgets);
      expect(find.text("In full — 1,000,000.00"), findsWidgets,
          reason: "the same two places, in the style beside it");
    });

    testWidgets("the axis can be set apart from the values", (tester) async {
      // An exact reading on the bar, a round number on the scale, which is
      // the pairing anybody setting these separately is after.
      var controller = await panel(tester,
          shape: (e) => e.copyWith(
              numbers: const ChartNumbers(
                  style: NumberStyle.millions, decimals: 3)));
      await grid(tester);

      expect(find.text("Axis numbers"), findsNothing,
          reason: "it follows the values until told not to");
      await press(tester, find.text("Axis the same"));

      expect(find.text("Axis numbers"), findsOneWidget);
      var chart = chartIn(controller);
      expect(chart.axisNumbers, isNotNull);
      expect(chart.axisFigures.decimals, 3,
          reason: "it starts as a copy of the values rather than as nothing");

      // And back again.
      await press(tester, find.text("Axis the same"));
      expect(chartIn(controller).axisNumbers, isNull);
    });

    testWidgets("the axis titles have a size and a distance", (tester) async {
      var controller = await panel(tester);
      await axisMore(tester);

      expect(find.text("Label size"), findsOneWidget);
      expect(find.text("Label gap"), findsOneWidget);
      expect(chartIn(controller).axisSpec, isNull,
          reason: "following the label size, which is where they started");
    });

    testWidgets("a pie is offered no axes, but still its values",
        (tester) async {
      // The switches are all the same question -- what does this chart write
      // on itself -- so they are one group, and a pie keeps the half of it
      // that applies.
      // "Grid" twice over: the switch here and the colour in Style, so it is
      // found by the control it belongs to rather than by its word.
      Finder toggle(String label) => find.ancestor(
          of: find.text(label), matching: find.byType(CanvasToggle));

      await panel(tester);
      expect(toggle("Grid"), findsOneWidget);
      expect(toggle("Values"), findsOneWidget);
      await axisMore(tester);
      expect(find.text("X label"), findsOneWidget);
      // "X values", not "X labels": beside a switch called X, which shows the
      // word naming the axis, "X labels" was the same thing said twice.
      expect(find.text("X values"), findsOneWidget);

      // A pie has no axes to rule or to name, so neither the section about
      // the grid nor the line about the axis labels is offered at all. What
      // it writes on its slices still is.
      await panel(tester, shape: (e) => e.copyWith(type: ChartType.pie));
      expect(find.text("GRID"), findsNothing);
      await labels(tester);
      expect(find.text("X label"), findsNothing);
      expect(find.text("X values"), findsNothing);
      // Its switch moves to the Numbers line, which a pie does have.
      expect(toggle("Values"), findsOneWidget);
    });

    testWidgets("each axis' labels can be switched off on their own",
        (tester) async {
      // One switch each. It was one for both, and often enough they are not
      // read together: a bar chart named by its categories does not always
      // want the figures up the side as well.
      var controller = await panel(tester);
      await axisMore(tester);
      expect(chartIn(controller).showXLabels, isTrue);
      expect(chartIn(controller).showYLabels, isTrue);

      await press(tester, find.text("X values"));
      expect(chartIn(controller).showXLabels, isFalse);
      expect(chartIn(controller).showYLabels, isTrue,
          reason: "the other axis is not touched");

      await press(tester, find.text("Y values"));
      expect(chartIn(controller).showYLabels, isFalse);
      expect(chartIn(controller).showAxisLabels, isFalse,
          reason: "and with both off, on a chart whose axes are unnamed, "
              "there is no writing on the axes at all");
    });

    testWidgets("a radial bar says where its numbers went", (tester) async {
      // Rings a few pixels thick have nowhere to write a number and no axis to
      // read one against, so theirs go in the legend -- which is no use with
      // the legend switched off.
      const hint = "A radial bar has no room to write a number on and no axis "
          "to read one against, so its values go in the legend. Switch the "
          "legend on, and its values with it, to see them.";
      Iterable<String> hints() => tester
          .widgetList<CanvasHint>(find.byType(CanvasHint))
          .map((h) => h.message);

      await panel(tester,
          shape: (e) =>
              e.copyWith(type: ChartType.radialBar, showLegend: false));
      await labels(tester);
      expect(hints(), contains(hint));

      // The legend on but its own values off is still nowhere for them to go:
      // the two switches are separate now.
      await panel(tester,
          shape: (e) =>
              e.copyWith(type: ChartType.radialBar, showLegend: true));
      await labels(tester);
      expect(hints(), contains(hint));

      await panel(tester,
          shape: (e) => e.copyWith(
              type: ChartType.radialBar,
              showLegend: true,
              legend: const ChartLegend(values: true)));
      await labels(tester);
      expect(hints(), isNot(contains(hint)),
          reason: "with both on, the numbers are where it says");
    });

    testWidgets("one switch decides whether the labels take room",
        (tester) async {
      // The three of them together, because taking room is what made every
      // one of their settings a setting that resized the chart.
      var controller = await panel(tester);
      await labels(tester);
      expect(chartIn(controller).floatingLabels, isFalse,
          reason: "stacked above the plot is what a chart looks like");

      await press(tester, find.text("Over the chart"));
      expect(chartIn(controller).floatingLabels, isTrue);
    });

    testWidgets("a section remembers whether it was open", (tester) async {
      // The panel is rebuilt from scratch whenever the selection changes, so
      // a section opened, deselected and selected again used to be shut --
      // the stored answer arrives asynchronously and the default is what
      // anybody saw.
      var controller = await panel(tester);
      await labels(tester);
      expect(find.text("Over the chart"), findsOneWidget);

      controller.clearSelection();
      await tester.pumpAndSettle();
      expect(find.text("Over the chart"), findsNothing);

      controller.selectOnly("c");
      await tester.pumpAndSettle();
      expect(find.text("Over the chart"), findsOneWidget,
          reason: "still open, without waiting for a preference to load");
    });

    testWidgets("a closed section still fills the column", (tester) async {
      // The settings are a Column of start-aligned children, so a box left to
      // size itself shrank to fit its own heading -- and a closed section
      // narrower than the one above it does not read as a section, it reads
      // as a button somebody has left lying there.
      await panel(tester);

      var panelWidth = tester.getSize(find.byType(CanvasLayersPanel)).width;
      for (var name in ["DATA SOURCE", "TABLE", "ANIMATION"]) {
        var heading = find.text(name);
        await tester.ensureVisible(heading);
        await tester.pumpAndSettle();
        // The box around the section, which is the widest thing in it.
        var box = tester.getSize(find
            .ancestor(
                of: heading,
                matching: find.byWidgetPredicate(
                    (w) => w is Container && w.decoration is BoxDecoration))
            .first);
        expect(box.width, greaterThan(panelWidth * 0.8), reason: name);
      }
    });

    testWidgets("the legend is in with the other words on the chart",
        (tester) async {
      // The title, the description and the key are the same kind of thing --
      // writing laid over a picture -- and were three clusters and an
      // expander scattered down the panel with the data between them.
      var controller = await panel(tester);
      await labels(tester);

      // One switch on the line, with everything else about the key behind the
      // button at the end of it. A section of its own for what is mostly two
      // dropdowns and a size was a heading for each of them.
      //
      // Last of the label lines, because it is the last thing anybody sets:
      // what the chart says, how it is measured, how it is written, and then
      // where the key for all of it sits.
      expect(find.text("Over the chart"), findsOneWidget,
          reason: "and the switch that places them, on the same line");
      expect(find.byKey(const ValueKey("chartShowLegend")), findsOneWidget);
      expect(find.text("Place"), findsNothing, reason: "the key is off");

      await press(tester, find.byKey(const ValueKey("chartShowLegend")));
      expect(chartIn(controller).showLegend, isTrue);

      await legendMore(tester);
      expect(find.text("Place"), findsOneWidget);
      expect(find.text("Along"), findsOneWidget);
      expect(find.byType(CanvasDropdown<LegendPlacement>), findsOneWidget);
      expect(find.text("Between"), findsNothing,
          reason: "nothing to separate until the key shows values");

      // Two "Values" on the panel now: the chart's own up on the Grid line,
      // and the key's in here. The key's is the later of the two.
      await press(tester, find.text("Values").last);
      expect(chartIn(controller).legend.values, isTrue);
      expect(find.text("Between"), findsOneWidget);
    });

    testWidgets("the title and the description size separately",
        (tester) async {
      // The description took the label size, which is also the tick labels'
      // -- so making the description bigger made the numbers up the side of
      // the chart bigger with it.
      var controller = await panel(tester);
      await labels(tester);
      var before = chartIn(controller).labelSpec.fontSize;

      // By name rather than by counting: there are four Size fields in this
      // section -- the title's, the description's, and one per axis -- and
      // counting finds a different one every time a field is added.
      await tester.enterText(
          find.byKey(const ValueKey("chartDescriptionSize")), "44");
      await tester.pump();

      var after = chartIn(controller);
      expect(after.descriptionText.fontSize, 44);
      expect(after.labelSpec.fontSize, before,
          reason: "and the axis labels are where they were");
    });

    testWidgets(
        "a series is added beside the data, not in a section of its "
        "own", (tester) async {
      // A series is a column of the table, so it is added where the table is
      // -- and its name, colour and type are the section directly under it
      // rather than three headings away.
      var controller = await panel(tester);
      expect(chartIn(controller).data.series.length, 1);
      expect(
          tester
              .getTopLeft(find.text("SERIES"))
              .dy
              .compareTo(tester.getTopLeft(find.text("TABLE")).dy),
          1,
          reason: "directly under the numbers it names");

      await press(
          tester,
          find.byTooltip("Add a series — give it its own type below to lay "
              "one kind of chart over another"));

      var data = chartIn(controller).data;
      expect(data.series.length, 2);
      expect(data.series[1].type, isNull, reason: "following the chart");
      expect(data.series[1].values.length, data.categories.length,
          reason: "a value per row, so it lines up with what is there");

      // Two "Drawn as" dropdowns now, one per series, under the table. Found
      // inside the series list rather than by type: the presets line at the
      // top of the panel is a dropdown of strings as well.
      expect(
          find.descendant(
              of: find.byType(ChartDataEditor).last,
              matching: find.byType(CanvasDropdown<String>)),
          findsNWidgets(2));
    });
  });

  group("the settings' layout", () {
    // Six clusters of small controls down one narrow column, separated by nine
    // pixels of nothing, ran together into one field of boxes: the caption
    // over each was the only thing saying where one ended, and a caption is
    // nine pixels tall and grey.

    testWidgets("a group is ruled off from the next", (tester) async {
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasDesignPanel(controller: controller));

      expect(find.byType(CanvasControlGroup), findsWidgets);
      // One rule per group, drawn under it.
      var rules = find.descendant(
          of: find.byType(CanvasControlGroup),
          matching: find.byWidgetPredicate(
              (w) => w is Container && w.constraints?.maxHeight == 1.0));
      expect(rules, findsWidgets);
    });

    testWidgets("where it is and how it is turned are two lines",
        (tester) async {
      // Left to the Wrap, the line fell between W and H or after Angle
      // depending on how wide the sidebar happened to be.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasDesignPanel(controller: controller));

      expect(find.byType(CanvasLineBreak), findsWidgets);
      var x = tester.getRect(find.byKey(const ValueKey("elementX")));
      var angle = tester.getRect(find.byKey(const ValueKey("elementAngle")));
      expect(angle.top, greaterThan(x.bottom - 2),
          reason: "Angle starts a line of its own, under X");
    });

    testWidgets("the background's settings are not captioned Background",
        (tester) async {
      // The header says it. A caption underneath repeating it was the word
      // twice, and the background is what the panel shows whenever nothing is
      // selected -- so it was the commonest thing on the panel.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasDesignPanel(controller: controller));

      expect(find.text("BACKGROUND SETTINGS"), findsOneWidget);
      expect(find.text("BACKGROUND"), findsNothing);
      expect(find.text("Style"), findsOneWidget,
          reason: "and its controls are still there");
    });

    testWidgets("a path's points are not folded away", (tester) async {
      // They are the thing anybody opens a path's settings for, and a section
      // that has to be opened first is a press paid every time.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.path, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasDesignPanel(controller: controller));

      expect(find.textContaining("POINTS ("), findsOneWidget,
          reason: "a group with its count in the caption, not an expander");
      expect(find.byKey(ValueKey("node-frame-0-${element.id}")), findsOneWidget,
          reason: "and the first point's row is already showing");
    });

    testWidgets("the panel's header names what is being edited",
        (tester) async {
      // The settings used to head themselves with the element's name, three
      // lines above a group with the same name again. The header says it now,
      // and says it usefully: "Shape settings" rather than a phrase that is
      // true of everything.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      await pump(tester, CanvasDesignPanel(controller: controller));

      expect(find.text("BACKGROUND SETTINGS"), findsOneWidget,
          reason: "with nothing selected, that is what these are");

      controller.selectOnly(element.id);
      await tester.pumpAndSettle();
      expect(find.text("SHAPE SETTINGS"), findsOneWidget);
      expect(find.text("ELEMENT SETTINGS"), findsNothing);
    });

    testWidgets("and a group does not say it again", (tester) async {
      // A panel headed "Shape settings" over a group captioned "Shape" over a
      // control labelled "Shape" is the same word three times in four lines.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasDesignPanel(controller: controller));

      expect(find.text("SHAPE"), findsNothing,
          reason: "the group caption is gone; the header carries the name");
      // The control that chooses which shape keeps its own label. The other
      // two "Shape"s in the column are the chip that adds one and the layer
      // row that names it, neither of which is this panel repeating itself.
      expect(
          find.descendant(
              of: find.byType(CanvasDropdown<ShapeKind>),
              matching: find.text("Shape")),
          findsOneWidget);
    });

    testWidgets("a field that explains itself has no caption", (tester) async {
      // "Label" over a field captioned "Text inside" was the same instruction
      // twice. The empty field says what it is for.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasDesignPanel(controller: controller));

      expect(find.text("Text inside"), findsNothing);
      expect(find.text("Type text on the shape"), findsOneWidget);
    });

    testWidgets("the element's own name is not said twice", (tester) async {
      // The settings are headed with it already, so the group caption under
      // that heading said "Chart" directly under "Chart".
      var document = const CanvasDocument();
      var element = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        data: ChartData.parse("Cat\tA\nx\t10"),
      );
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("c");
      await pump(tester, CanvasDesignPanel(controller: controller));

      // Not at all in the settings themselves: the panel's header says it.
      expect(find.text("CHART"), findsNothing);
      expect(find.text("CHART SETTINGS"), findsOneWidget);
      // Wherever else the word appears in the column -- the layer row that
      // names the element, the Add chip that makes one -- it is not the
      // caption this test is about. How many of those are on screen depends
      // on what fits under the settings, so what is pinned is that the one
      // inside the layer row is there and the caption is not.
      expect(find.text("Chart"), findsAtLeastNWidgets(1));
      expect(
          find.descendant(
              of: find.byType(CanvasLayerRow), matching: find.text("Chart")),
          findsOneWidget);
    });
  });

  group("a chart's animation", () {
    /// openAnimation opens the section if it is not already open.
    ///
    /// Whether a section is open is remembered for the session, deliberately
    /// -- somebody who opens the animation settings is working on animation
    /// -- so a test cannot assume it starts closed and cannot simply tap the
    /// heading, which would shut one a previous test left open.
    Future<void> openAnimation(WidgetTester tester) async {
      if (find.text("ARRIVING").evaluate().isNotEmpty) return;
      var heading = find.text("ANIMATION");
      await tester.ensureVisible(heading);
      await tester.pumpAndSettle();
      await tester.tap(heading);
      await tester.pumpAndSettle();
    }

    (CanvasController, ChartElement) build({int frames = 1}) {
      var document = CanvasDocument(frames: frames);
      var chart = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        data: ChartData.parse("Cat\tA\nx\t10\ny\t6"),
      );
      var controller = CanvasController(document.addElement(chart));
      return (controller, chart);
    }

    ChartElement chartIn(CanvasController controller) =>
        controller.document.elements.single as ChartElement;

    test("choosing a preset lays a keyframe at each end of it", () {
      // One gesture, because it is one decision. A preset with nothing
      // pinning the reveal channel draws exactly what a still chart draws, so
      // applying it separately from keying it would be asking somebody to
      // know how this is implemented.
      var (controller, chart) = build(frames: 24);
      addTearDown(controller.dispose);

      controller.applyChartAnimation(chart, ChartAnimationPreset.grow);

      var after = chartIn(controller);
      expect(after.animation.preset, ChartAnimationPreset.grow);

      var keys = after.track!.keys;
      expect(keys.length, 2);
      expect(keys.first.values[KeyframeChannel.reveal], 0);
      expect(keys.last.values[KeyframeChannel.reveal], 1);
      expect(keys.last.frame, greaterThan(keys.first.frame),
          reason: "the gap between them is the length of the animation");
    });

    test("a still document is given frames to play it in", () {
      // An animation on a one-frame canvas is an animation nobody can watch.
      var (controller, chart) = build();
      addTearDown(controller.dispose);
      expect(controller.document.isAnimated, isFalse);

      controller.applyChartAnimation(chart, ChartAnimationPreset.wipe);

      expect(controller.document.isAnimated, isTrue);
      expect(chartIn(controller).track!.keys.length, 2);
    });

    test("it starts from where the reader is looking", () {
      var (controller, chart) = build(frames: 60);
      addTearDown(controller.dispose);
      controller.frame = 20;

      controller.applyChartAnimation(chart, ChartAnimationPreset.grow);

      expect(chartIn(controller).track!.keys.first.frame, 20,
          reason: "rather than jumping the playhead back to the start");
    });

    test("and keeps a pose that was put there by hand", () {
      // Choosing None used to clear the whole track. A chart that had been
      // moved or faded by keyframe lost all of that for choosing a word on a
      // dropdown, which is not what None means: it means no arrival.
      var (controller, chart) = build(frames: 60);
      addTearDown(controller.dispose);
      controller.replaceElement(chart.withBase(
          track: ElementTrack([
        const Keyframe(frame: 0, dx: -40),
        const Keyframe(frame: 30),
      ])));

      controller.applyChartAnimation(
          chartIn(controller), ChartAnimationPreset.grow);
      var withBoth = chartIn(controller).track!.keys;
      expect(withBoth.where((k) => k.values.containsKey("reveal")).length, 2,
          reason: "the arrival is laid beside the pose, not over it");
      expect(withBoth.first.dx, -40,
          reason: "and a keyframe that holds both holds both");

      controller.applyChartAnimation(
          chartIn(controller), ChartAnimationPreset.none);
      var left = chartIn(controller).track!.keys;
      expect(left.where((k) => k.values.containsKey("reveal")), isEmpty,
          reason: "only the arrival is taken away");
      expect(left.first.dx, -40, reason: "the pose is untouched");
    });

    test("trying another preset leaves the timing where it was put", () {
      // The Length setting is for laying a new one down. Once it is on the
      // timeline the keyframes are where somebody has put them, and trying
      // the next preset in the list must not shove them about.
      var (controller, chart) = build(frames: 60);
      addTearDown(controller.dispose);

      controller.applyChartAnimation(chart, ChartAnimationPreset.grow,
          length: 12);
      var (from, span) = controller.elementAnimationSpan(chartIn(controller));
      expect(span, 12);

      controller.applyChartAnimation(
          chartIn(controller), ChartAnimationPreset.wipe);
      expect(controller.elementAnimationSpan(chartIn(controller)), (from, 12));
    });

    test("choosing None takes the keyframes away with it", () {
      var (controller, chart) = build(frames: 24);
      addTearDown(controller.dispose);
      controller.applyChartAnimation(chart, ChartAnimationPreset.grow);
      expect(chartIn(controller).track, isNotNull);

      controller.applyChartAnimation(
          chartIn(controller), ChartAnimationPreset.none);

      expect(chartIn(controller).animation.on, isFalse);
      expect(chartIn(controller).track, isNull,
          reason: "no animation left, so no empty track in the saved file");
    });

    test("it is one undo step", () {
      var (controller, chart) = build(frames: 24);
      addTearDown(controller.dispose);
      controller.applyChartAnimation(chart, ChartAnimationPreset.grow);

      controller.undo();
      var back = controller.document.elements.single as ChartElement;
      expect(back.animation.on, isFalse);
      expect(back.track, isNull);
    });

    testWidgets("the presets offered suit the chart", (tester) async {
      // A sweep round a bar chart is a sweep round a rectangle, and a wipe
      // across a pie is worse.
      var (controller, _) = build(frames: 24);
      addTearDown(controller.dispose);
      controller.selectOnly("c");
      await pump(tester, CanvasDesignPanel(controller: controller));

      await openAnimation(tester);

      // Read off the control rather than off an open menu, the same way the
      // text element's presets are checked: a dropdown builds the items it
      // can see.
      List<String> offered() => [
            for (var (_, text) in tester
                .widget<CanvasDropdown<ChartAnimationPreset>>(
                    find.byKey(const ValueKey("chartAnimationPreset")))
                .options)
              text,
          ];

      expect(offered().first, "None",
          reason: "the way to have none of it comes first");
      expect(offered(), contains("Grow"));
      expect(offered(), contains("Wipe across"));
      expect(offered(), isNot(contains("Sweep round")),
          reason: "not on a bar chart");

      controller.replaceElement(
          (controller.document.elements.single as ChartElement)
              .copyWith(type: ChartType.pie));
      await tester.pumpAndSettle();
      expect(offered(), contains("Sweep round"));
      expect(offered(), isNot(contains("Wipe across")),
          reason: "nor a wipe across a circle");
    });

    testWidgets("the gap is only offered where there is something to space",
        (tester) async {
      var (controller, chart) = build(frames: 24);
      addTearDown(controller.dispose);
      controller.selectOnly("c");
      await pump(tester, CanvasDesignPanel(controller: controller));

      await openAnimation(tester);
      expect(find.text("Gap"), findsNothing, reason: "no preset yet");

      controller.applyChartAnimation(chart, ChartAnimationPreset.grow);
      await tester.pumpAndSettle();
      expect(find.text("Gap"), findsOneWidget);
      expect(find.text("Curve"), findsOneWidget);
      expect(find.text("Length"), findsOneWidget,
          reason: "and how long it takes, as every other element has");

      controller.applyChartAnimation(
          chartIn(controller), ChartAnimationPreset.wipe);
      await tester.pumpAndSettle();
      expect(find.text("Gap"), findsNothing,
          reason: "one edge crossing everything has nothing to space out");
      expect(find.text("Curve"), findsOneWidget);
    });
  });

  group("the chart's numbers", () {
    Future<CanvasController> panel(WidgetTester tester) async {
      var element = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        data: ChartData.parse("Cat\tA\nx\t10\ny\t6"),
      );
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("c");
      await pump(tester, CanvasDesignPanel(controller: controller));
      return controller;
    }

    ChartData dataIn(CanvasController controller) =>
        (controller.document.elements.single as ChartElement).data;

    Future<void> press(WidgetTester tester, Finder what) async {
      await tester.ensureVisible(what);
      await tester.pumpAndSettle();
      await tester.tap(what);
      await tester.pumpAndSettle();
    }

    /// grid switches to the table, if it is not already showing one.
    ///
    /// Which view the editor is in is remembered for the session, deliberately
    /// -- somebody who works in the grid works in the grid, whatever chart
    /// they open next -- so a test cannot assume it starts in the text one.
    Future<void> grid(WidgetTester tester) async {
      var toTable = find.byTooltip("Edit the numbers in a table");
      if (toTable.evaluate().isNotEmpty) await press(tester, toTable);
    }

    testWidgets("the numbers are a section of their own", (tester) async {
      // They are the longest thing in a chart's settings and the least often
      // changed once they are right, so they were pushing everything else off
      // the bottom of the panel.
      //
      // Called Table, because that is what is in it: the numbers in rows and
      // columns, with what they are drawn as above them and how that drawing
      // looks below.
      await panel(tester);
      expect(find.text("TABLE"), findsOneWidget);
      expect(find.text("2 rows, 1 series"), findsOneWidget);
    });

    testWidgets("it switches between pasted text and a table", (tester) async {
      // Pasted text is the fast way in; it is a bad way to change one number
      // in the middle of forty, which is the other thing people do all day.
      var controller = await panel(tester);
      // Two of them: the numbers in the Table section, and the series list
      // under it, which is the same widget showing only its series rows.
      expect(find.byType(ChartDataEditor), findsNWidgets(2));
      expect(find.byTooltip("Add a row"), findsOneWidget,
          reason: "rows and series are added the same way in either view");

      await grid(tester);
      // "Raw table", not "Edit the numbers as pasted text": the button sits
      // on a line of three and the sentence was longer than the row.
      expect(find.byTooltip("Raw table"), findsOneWidget);

      // The first row's category, then its value.
      await tester.enterText(
          find
              .descendant(
                  of: find.byType(ChartDataEditor).first,
                  matching: find.byType(TextField))
              .at(2),
          "42");
      await tester.pumpAndSettle();
      expect(dataIn(controller).valueAt(0, 0), 42);
    });

    testWidgets("a row can be added and taken away", (tester) async {
      var controller = await panel(tester);
      await grid(tester);

      await press(tester, find.byTooltip("Add a row"));
      expect(dataIn(controller).categories.length, 3);

      await press(tester, find.byTooltip("Remove this row").first);
      expect(dataIn(controller).categories.length, 2);
      expect(dataIn(controller).series.single.values.length, 2,
          reason: "the series loses the row too, or the data goes ragged");
    });
  });

  group("the outline settings", () {
    Future<CanvasController> panel(WidgetTester tester,
        {ImageOutline outline = const ImageOutline(),
        String assetId = "abcdefghijklmnop"}) async {
      var element = ImageElement(
        const ElementBase(id: "i", width: 200, height: 200),
        assetId: assetId,
        outline: outline,
      );
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("i");
      await pump(tester, CanvasDesignPanel(controller: controller));
      return controller;
    }

    testWidgets("the width is the only control until there is a width",
        (tester) async {
      // The width is also the off switch, so everything else is noise while
      // it is zero -- and a colour and a style sitting there doing nothing is
      // how a reader concludes the feature is broken.
      await panel(tester);

      expect(find.text("Width"), findsOneWidget);
      expect(find.byKey(const ValueKey("imageOutlineColour")), findsNothing);
      expect(find.text("Feather"), findsNothing);
    });

    testWidgets("with a width, it offers a colour, a style and a feather",
        (tester) async {
      await panel(tester, outline: const ImageOutline(width: 4));

      expect(find.byKey(const ValueKey("imageOutlineColour")), findsOneWidget);
      expect(find.text("Feather"), findsOneWidget);
      expect(find.byType(CanvasDropdown<OutlineStyle>), findsOneWidget);
    });

    testWidgets("typing a width turns it on", (tester) async {
      var controller = await panel(tester);
      var width = find.ancestor(
          of: find.text("Width"), matching: find.byType(CanvasNumberField));

      await tester.enterText(
          find.descendant(of: width, matching: find.byType(TextField)), "6");
      await tester.pump();

      var element = controller.document.elements.single as ImageElement;
      expect(element.outline.width, 6);
      expect(element.outline.on, isTrue);
    });

    testWidgets("a picture's size can be changed after it is already in",
        (tester) async {
      // The width, quality and format controls are offered on the way in, and
      // only above half a megabyte, so a reader who wanted them for a smaller
      // picture -- or who took a size on the way in and thought better of it
      // -- had nowhere to go.
      const tooltip = "Change this picture's size and quality";
      await panel(tester);
      expect(find.byTooltip(tooltip), findsOneWidget);

      await panel(tester, assetId: "");
      expect(find.byTooltip(tooltip), findsNothing,
          reason: "nothing to resize until there is a picture");
    });

    testWidgets("there is nothing to outline without a picture",
        (tester) async {
      await panel(tester, assetId: "");
      expect(find.text("Width"), findsNothing);
    });
  });

  group("the remove-background settings", () {
    Future<CanvasController> panel(WidgetTester tester,
        {BackgroundRemoval removal = const BackgroundRemoval()}) async {
      var element = ImageElement(
        const ElementBase(id: "i", width: 200, height: 200),
        assetId: "abcdefghijklmnop",
        removal: removal,
      );
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("i");
      await pump(tester, CanvasDesignPanel(controller: controller));
      return controller;
    }

    testWidgets("the brushes are there on a picture nothing has been done to",
        (tester) async {
      // They were inside "if anything is being removed", which made them
      // unreachable on exactly the picture they are for: a fresh image has no
      // method and no strokes, so nothing was being removed, so the brushes
      // were hidden -- and the only way to reach the tool that needs no method
      // was to choose a method first.
      await panel(tester);

      expect(find.byTooltip("Rub the background out by hand"), findsOneWidget);
      expect(
          find.byTooltip("Put back what was taken by mistake"), findsOneWidget);
    });

    testWidgets("turning a brush on offers its size, hardness and cling",
        (tester) async {
      var controller = await panel(tester);
      expect(find.text("Brush"), findsNothing,
          reason: "not until there is a brush in hand");

      controller.retouch = RetouchBrush.erase;
      await tester.pumpAndSettle();

      expect(find.text("Brush"), findsOneWidget);
      expect(find.text("Hardness"), findsOneWidget);
      expect(find.text("Cling"), findsOneWidget);
    });

    testWidgets("the cut offers to take the other side of the line",
        (tester) async {
      var controller = await panel(tester);
      const outward = "Taking what is outside the line — press to take what "
          "is inside";
      const inward = "Taking what is inside the line — press to take what "
          "is outside";

      expect(find.byTooltip(outward), findsNothing,
          reason: "only the cut has two sides to choose between");

      controller.retouch = RetouchBrush.cutAround;
      await tester.pumpAndSettle();

      expect(find.byTooltip(outward), findsOneWidget);
      expect(find.byTooltip("Cling"), findsNothing);

      await tester.ensureVisible(find.byTooltip(outward));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(outward));
      await tester.pumpAndSettle();

      expect(controller.cutInside, isTrue);
      expect(find.byTooltip(inward), findsOneWidget);
    });

    testWidgets("a marking brush offers neither hardness nor cling",
        (tester) async {
      // A hint is a sample rather than a mark on the picture, so it is taken
      // exactly where it was drawn.
      var controller = await panel(tester,
          removal: const BackgroundRemoval(mode: RemovalMode.learn));
      controller.retouch = RetouchBrush.markBackground;
      await tester.pumpAndSettle();

      expect(find.text("Brush"), findsOneWidget);
      expect(find.text("Hardness"), findsNothing);
      expect(find.text("Cling"), findsNothing);
    });

    testWidgets("the marking brushes appear with the method that uses them",
        (tester) async {
      await panel(tester);
      expect(
          find.byTooltip("Mark some background — draw over a few parts "
              "that should go"),
          findsNothing);

      await panel(tester,
          removal: const BackgroundRemoval(mode: RemovalMode.learn));
      expect(
          find.byTooltip("Mark some background — draw over a few parts "
              "that should go"),
          findsOneWidget);
      expect(
          find.byTooltip("Mark the subject — draw over a few parts that "
              "should stay"),
          findsOneWidget);
    });

    testWidgets("undo and clear appear once something has been painted",
        (tester) async {
      await panel(tester);
      expect(find.byTooltip("Undo the last brush stroke"), findsNothing);

      await panel(tester,
          removal: const BackgroundRemoval(strokes: [
            RemovalStroke(points: [Offset(0.5, 0.5)], radius: 0.1, keep: false),
          ]));
      expect(find.byTooltip("Undo the last brush stroke"), findsOneWidget);
      expect(find.byTooltip("Clear every brush stroke"), findsOneWidget);
    });

    testWidgets("a picture worked on by hand is offered no method settings",
        (tester) async {
      // They were shown whenever anything was being removed, which includes a
      // picture the brush alone has been used on -- so somebody working by
      // hand was offered a tolerance and a softness that nothing reads.
      await panel(tester,
          removal: const BackgroundRemoval(strokes: [
            RemovalStroke(points: [Offset(0.5, 0.5)], radius: 0.1, keep: false),
          ]));

      expect(find.text("Softness"), findsNothing);
      expect(find.text("Tolerance"), findsNothing);
      expect(find.text("Spread"), findsNothing);
      expect(find.text("Invert"), findsNothing);
      // The brush's own are still there.
      expect(find.byTooltip("Undo the last brush stroke"), findsOneWidget);
    });

    testWidgets("the brightness method is offered no tolerance",
        (tester) async {
      // It cuts at a threshold and never reads one.
      await panel(tester,
          removal: const BackgroundRemoval(mode: RemovalMode.luminance));
      expect(find.text("Threshold"), findsOneWidget);
      expect(find.text("Tolerance"), findsNothing);
      expect(find.text("Softness"), findsOneWidget);
    });

    testWidgets("a method's own settings stay behind the method",
        (tester) async {
      await panel(tester);
      expect(find.text("Edge"), findsNothing);
      expect(find.text("Spread"), findsNothing);

      await panel(tester,
          removal: const BackgroundRemoval(mode: RemovalMode.cornerFlood));
      expect(find.text("Edge"), findsOneWidget);
      expect(find.text("Spread"), findsOneWidget);
    });
  });

  group("how the canvas is framed", () {
    // Reported: the fit setting was not remembered. It was applied when the
    // page opened and thrown away by the next load -- which is opening a
    // canvas, the moment it is most wanted.
    test("opening a canvas keeps the frame the reader chose", () {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);

      controller.fitWidth();
      expect(controller.fit, CanvasFit.width);

      controller.load(const CanvasDocument(title: "Another"));
      expect(controller.fit, CanvasFit.width,
          reason: "the frame is about the screen, not about the document");
    });

    test("but the zoom and the pan do not survive it", () {
      // Both are a position inside the document being replaced, and mean
      // nothing in the new one.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);

      controller.zoom = 2.5;
      controller.pan = const Offset2(40, -20);

      controller.load(const CanvasDocument(title: "Another"));
      expect(controller.zoom, 1);
      expect(controller.pan.dx, 0);
      expect(controller.pan.dy, 0);
    });

    test("restoring it tells nobody", () async {
      // It is applied from a State's initState, before the page has built
      // anything. The controller is handed round by a Provider, and notifying
      // one mid-build marks an inherited widget dirty while the framework is
      // already building -- which Flutter answers with an exception whose
      // stack is four hundred frames deep, on every visit to the page. That
      // was a visible stutter for a setting nobody has to be told about.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);

      var told = 0;
      controller.addListener(() => told++);

      controller.restoreFit(CanvasFit.width);
      expect(controller.fit, CanvasFit.width);
      expect(told, 0, reason: "nothing has painted yet, so nothing needs it");

      // The ordinary setter still does tell everyone.
      controller.fit = CanvasFit.whole;
      expect(told, 1);
    });

    test("the preference is stored by name, not by position", () async {
      // So that adding or reordering the fits later does not silently change
      // what an old preference means.
      SharedPreferences.setMockInitialValues({});
      var prefs = CanvasPreferences();
      addTearDown(prefs.dispose);

      prefs.fit = CanvasFit.width.name;
      expect(prefs.fit, "width");

      var back = CanvasPreferences();
      addTearDown(back.dispose);
      await back.load();
      expect(back.fit, "width");
    });
  });

  group("locking an element's proportions", () {
    // The lock is about the shape, not about the size: it must not stop a
    // resize, only stop one from changing the proportions.
    Future<CanvasController> panel(WidgetTester tester,
        {bool locked = false}) async {
      var document = const CanvasDocument();
      var element = ShapeElement(
        ElementBase(
            id: "s", x: 0, y: 0, width: 200, height: 100, lockAspect: locked),
      );
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("s");
      await pump(tester, CanvasDesignPanel(controller: controller));
      return controller;
    }

    ElementBase baseIn(CanvasController c) => c.document.elements.single.base;

    testWidgets("unlocked, the two numbers are free of each other",
        (tester) async {
      var controller = await panel(tester);
      await tester.enterText(find.byKey(const ValueKey("elementW")), "400");
      await tester.pumpAndSettle();

      expect(baseIn(controller).width, 400);
      expect(baseIn(controller).height, 100, reason: "the height stayed");
    });

    testWidgets("locked, the height follows the width", (tester) async {
      var controller = await panel(tester, locked: true);
      await tester.enterText(find.byKey(const ValueKey("elementW")), "400");
      await tester.pumpAndSettle();

      expect(baseIn(controller).width, 400);
      expect(baseIn(controller).height, 200,
          reason: "twice as wide, so twice as tall -- 2:1 either way");
    });

    testWidgets("and the width follows the height", (tester) async {
      var controller = await panel(tester, locked: true);
      await tester.enterText(find.byKey(const ValueKey("elementH")), "50");
      await tester.pumpAndSettle();

      expect(baseIn(controller).height, 50);
      expect(baseIn(controller).width, 100);
    });

    testWidgets("the lock is a button beside the two numbers it holds",
        (tester) async {
      var controller = await panel(tester);
      expect(find.byIcon(Icons.link_off), findsOneWidget);

      await tester.tap(find.byIcon(Icons.link_off));
      await tester.pumpAndSettle();
      expect(baseIn(controller).lockAspect, isTrue);
      expect(find.byIcon(Icons.link), findsOneWidget);
    });

    testWidgets("it does not stop a resize, it only holds the shape",
        (tester) async {
      // The whole of what it is for. Refusing the edit would be a lock that
      // stopped the element being resized at all.
      var controller = await panel(tester, locked: true);
      var before = baseIn(controller).width;
      await tester.enterText(find.byKey(const ValueKey("elementW")), "500");
      await tester.pumpAndSettle();
      expect(baseIn(controller).width, isNot(before));
    });
  });

  group("what the sidebar rebuilds for", () {
    // The controller notifies for everything: every pixel of a drag, every
    // frame of playback, every notch of the zoom. The settings panel is
    // twenty or thirty text fields, and laying those out for a change it does
    // not show is the whole of why clicking around felt slow.

    testWidgets("a watch ignores a notification that changes nothing",
        (tester) async {
      var source = ValueNotifier<int>(0);
      addTearDown(source.dispose);
      var builds = 0;

      await pump(
          tester,
          CanvasWatch<String>(
            listenable: source,
            // Deliberately blind to the odd numbers.
            select: () => "${source.value ~/ 2}",
            builder: (context, value) {
              builds++;
              return Text(value);
            },
          ));
      expect(builds, 1);

      source.value = 1;
      await tester.pumpAndSettle();
      expect(builds, 1, reason: "the key did not move, so nor did the panel");

      source.value = 2;
      await tester.pumpAndSettle();
      expect(builds, 2, reason: "and it does rebuild when the key moves");
      expect(find.text("1"), findsOneWidget);
    });

    testWidgets("zooming does not rebuild the settings", (tester) async {
      // The zoom, the pan, how the canvas is framed, which tool is held: the
      // settings show none of it.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.text, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasDesignPanel(controller: controller));

      var before = tester.widget<TextField>(find.byType(TextField).first);
      controller.zoom = 2.5;
      controller.pan = const Offset2(30, 30);
      await tester.pumpAndSettle();

      expect(
          identical(
              tester.widget<TextField>(find.byType(TextField).first), before),
          isTrue,
          reason: "the same widget instance: nothing was rebuilt");
    });

    testWidgets("a brush is not in the document, and still rebuilds them",
        (tester) async {
      // The trap this counts the safe way round for. These controls show the
      // retouching brush, its size and its hardness, and none of that is in
      // the document -- so a key naming what the settings read would have
      // gone stale here. The revision moves for everything except the view.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      var before = controller.revision;

      controller.retouch = RetouchBrush.erase;
      expect(controller.revision, greaterThan(before),
          reason: "not a view change, so the settings hear about it");

      before = controller.revision;
      controller.zoom = 2;
      controller.pan = const Offset2(10, 10);
      controller.showHelpers = false;
      expect(controller.revision, before,
          reason: "and these are, so they do not");
    });

    testWidgets("moving an element does rebuild them", (tester) async {
      // The other half of the rule. A panel that is cheap because it is stale
      // is not cheap, it is broken.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasDesignPanel(controller: controller));

      controller.replaceElement(element.withBase(x: 321), transient: true);
      await tester.pumpAndSettle();

      expect(
          tester
              .widget<TextField>(find.descendant(
                  of: find.byKey(const ValueKey("elementX")),
                  matching: find.byType(TextField)))
              .controller
              ?.text,
          "321");
    });
  });

  group("the grid and guides line", () {
    // It opens where the canvas settings open, and for the same reason: over
    // the top of the canvas rather than pushing it down, so opening a panel
    // does not move the design or change the zoom under what is being looked
    // at.
    testWidgets("the button sits beside the canvas settings", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);

      await pump(
          tester,
          CanvasSettingsBar(
            controller: controller,
            onPublish: () {},
            canvasSettingsOpen: false,
            onToggleCanvasSettings: () {},
            guidesOpen: false,
            onToggleGuides: () {},
            timelineOpen: true,
            onToggleTimeline: () {},
          ));

      var grid = find.byTooltip("Grid, guides, rulers and snapping");
      var canvas = find.byTooltip("Canvas settings");
      expect(grid, findsOneWidget);
      expect(canvas, findsOneWidget);
      expect(tester.getCenter(grid).dx, lessThan(tester.getCenter(canvas).dx),
          reason: "to its left, and next to it");
    });

    testWidgets("the button says whether there is any scaffolding",
        (tester) async {
      // Lit when there is a grid or a guide, so a canvas that is snapping to
      // something invisible says so.
      var controller = CanvasController(const CanvasDocument()
          .copyWith(guides: const CanvasGuides(showGrid: true)));
      addTearDown(controller.dispose);

      await pump(
          tester,
          CanvasSettingsBar(
            controller: controller,
            onPublish: () {},
            canvasSettingsOpen: false,
            onToggleCanvasSettings: () {},
            guidesOpen: false,
            onToggleGuides: () {},
            timelineOpen: true,
            onToggleTimeline: () {},
          ));
      expect(
          find.byTooltip("Grid, guides, rulers and snapping"), findsOneWidget);
    });

    testWidgets("the line itself carries the settings", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasGuidesPanel(controller: controller));

      for (var group in ["GRID AND RULERS", "GUIDES", "SNAPPING", "RULERS"]) {
        expect(find.text(group), findsOneWidget, reason: group);
      }
      expect(find.text("Show a grid"), findsOneWidget);
    });

    testWidgets("switching the grid on writes it to the document",
        (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasGuidesPanel(controller: controller));

      expect(controller.document.guides.showGrid, isFalse);
      await tester.tap(find.text("Show a grid"));
      await tester.pumpAndSettle();
      expect(controller.document.guides.showGrid, isTrue);
    });

    testWidgets("a guide can be put down and cleared", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasGuidesPanel(controller: controller));

      await tester.tap(find.byTooltip("Add a vertical guide down the middle"));
      await tester.pumpAndSettle();
      expect(controller.document.guides.guides.single.axis, GuideAxis.vertical);
      expect(controller.document.guides.guides.single.at,
          controller.document.size.size.width / 2);

      await tester.tap(find.byTooltip("Remove every guide"));
      await tester.pumpAndSettle();
      expect(controller.document.guides.guides, isEmpty);
    });
  });

  group("a text element's animation", () {
    /// open scrolls the settings to the animation section and opens it, if it
    /// is not open already.
    ///
    /// A section remembers whether it was open and the memory outlives one
    /// test, so tapping unconditionally shuts the one the test before left
    /// open -- and everything inside it is then nowhere to be found.
    Future<void> open(WidgetTester tester) async {
      if (find
          .byKey(const ValueKey("textAnimationPreset"))
          .evaluate()
          .isNotEmpty) {
        return;
      }
      await tester.ensureVisible(find.text("ANIMATION"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("ANIMATION"));
      await tester.pumpAndSettle();
    }

    testWidgets("choosing one applies it and lays the keyframes",
        (tester) async {
      // The same gesture a chart's animation is chosen with: a preset with
      // nothing pinning the reveal channel draws exactly what a still element
      // draws, and asking somebody to key a channel they have never heard of
      // is asking them to know how this is implemented.
      var element = TextElement(
        const ElementBase(id: "t", x: 40, y: 40, width: 300, height: 120),
        text: "A headline",
      );
      var controller = CanvasController(
          const CanvasDocument(frames: 24, frameRate: 12).addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("t");
      await pump(tester, CanvasDesignPanel(controller: controller));
      await open(tester);
      // The family first. Choosing one applies its first preset, so the
      // canvas shows something at once rather than waiting for a second
      // choice.
      var kind = find.byKey(const ValueKey("textAnimationFamily"));
      await tester.ensureVisible(kind);
      await tester.pumpAndSettle();
      await tester.tap(kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Sequential").last);
      await tester.pumpAndSettle();

      var after = controller.document.elements.single as TextElement;
      expect(after.animation.preset.family, TextAnimationFamily.sequential);
      expect(after.track, isNotNull,
          reason: "and it has a length on the timeline");

      // Then which one, out of that family alone.
      var which = find.byKey(const ValueKey("textAnimationPreset"));
      await tester.ensureVisible(which);
      await tester.pumpAndSettle();
      await tester.tap(which);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Word by word").last);
      await tester.pumpAndSettle();

      expect(
          (controller.document.elements.single as TextElement).animation.preset,
          TextAnimationPreset.words);
    });

    testWidgets("the list is grouped, because thirty names is a wall",
        (tester) async {
      var element = TextElement(
        const ElementBase(id: "t", x: 40, y: 40, width: 300, height: 120),
        text: "A headline",
        animation: const TextAnimation(preset: TextAnimationPreset.fadeIn),
      );
      var controller = CanvasController(
          const CanvasDocument(frames: 24, frameRate: 12).addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("t");
      await pump(tester, CanvasDesignPanel(controller: controller));

      await open(tester);

      // Read off the controls rather than off an open menu: a dropdown builds
      // the items it can see, and thirty of them do not fit on a screen.
      var families = tester.widget<CanvasDropdown<TextAnimationFamily?>>(
          find.byKey(const ValueKey("textAnimationFamily")));
      var kinds = [for (var (_, text) in families.options) text];
      expect(kinds.first, "None",
          reason: "the way to have none of it comes first");
      for (var family in TextAnimationFamily.values) {
        expect(kinds, contains(family.label));
      }

      // And the second box holds that family alone, not all thirty.
      var which = tester.widget<CanvasDropdown<TextAnimationPreset>>(
          find.byKey(const ValueKey("textAnimationPreset")));
      expect(which.options.length,
          TextAnimationPreset.inFamily(TextAnimationFamily.fade).length);
      expect(which.options.length, lessThan(8),
          reason: "a family, not the whole list");
    });
  });

  group("a chart's own data source", () {
    // A chart used to have two ways to get numbers: typed in, or read off a
    // table on the same canvas. Neither covers a chain's history, which has
    // no table beside it and would not want one four thousand rows long.
    //
    // What is tested here is the wiring, since the mapping itself is model
    // work and is tested against the real responses in
    // canvas_chart_source_test.dart.

    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp("canvas_chart_source");
    });
    tearDown(() => dir.delete(recursive: true));

    /// idle turns the real event loop, because a file is read on it while a
    /// widget test runs in a fake one. See the note in the notes tests: one
    /// step of an I/O chain needs one runAsync and one pump.
    Future<void> idle(WidgetTester tester) async {
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 4)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<CanvasController> panel(WidgetTester tester,
        {DataSource source = const DataSource(),
        ChartSourceMap map = const ChartSourceMap()}) async {
      var element = ChartElement(
        const ElementBase(id: "c", width: 400, height: 300),
        source: source,
        fromSource: map,
      );
      var controller =
          CanvasController(const CanvasDocument().addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly("c");
      await pump(tester, CanvasDesignPanel(controller: controller));
      return controller;
    }

    ChartElement chartIn(CanvasController c) =>
        c.document.elements.single as ChartElement;

    /// openColumn opens one column's line in the Columns list.
    ///
    /// A column remembers whether it was open by its *name*, so that the one
    /// left open stays open when a column is moved past it -- which means the
    /// memory outlives a test, exactly as a section's does.
    Future<void> openColumn(WidgetTester tester, String name) async {
      if (find.text("Header").evaluate().isNotEmpty) return;
      await tester.ensureVisible(find.text(name).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).first);
      await tester.pumpAndSettle();
    }

    /// open opens the section if it is not already open.
    ///
    /// Sections remember whether they were open, and the memory outlives one
    /// test: tapping unconditionally shut the section that the test before
    /// had left open, and the controls inside it were then nowhere to be
    /// found. [probe] is something only that section has, which is how "is it
    /// already open" is asked.
    Future<void> open(WidgetTester tester, String section,
        [String probe = "Preset"]) async {
      if (find.text(probe).evaluate().isNotEmpty) return;
      await tester.ensureVisible(find.text(section));
      await tester.pumpAndSettle();
      await tester.tap(find.text(section));
      await tester.pumpAndSettle();
    }

    testWidgets("it is a section of its own, beside the numbers",
        (tester) async {
      // Not called "Data": the chart already has a section by that name --
      // the numbers themselves -- and two of them on one panel is a panel
      // nobody can navigate.
      await panel(tester);
      expect(find.text("DATA SOURCE"), findsOneWidget);
      expect(find.text("TABLE"), findsOneWidget,
          reason: "the numbers themselves are still a section of their own");
    });

    testWidgets("the sections read in the order the work happens",
        (tester) async {
      // What the chart is, then what it says, then where its numbers come
      // from and how they are mapped, then how it arrives.
      //
      // Custom fields is not among them: a custom field is an ordinary column
      // with a recipe instead of a field, and a section of its own listed the
      // same columns a second time.
      var controller = await panel(tester,
          source: dcrdataChart.applyTo(const DataSource(), "coin-supply"));
      expect(controller.document.elements.single, isA<ChartElement>());

      var headings = [
        for (var it
            in tester.widgetList<CanvasExpander>(find.byType(CanvasExpander)))
          it.label,
      ];
      // Labels is not among them: it is a run of plain lines now rather than
      // a section, so it has no expander to be counted here. What is left
      // reads as the work does -- where the numbers come from, the numbers,
      // how they are mapped, and last how the chart arrives.
      var wanted = [
        "Data source",
        "Columns",
        "Table",
        "Animation",
      ];
      expect([for (var w in wanted) headings.contains(w)], everyElement(isTrue),
          reason: "$headings");
      var places = [for (var w in wanted) headings.indexOf(w)];
      var sorted = [...places]..sort();
      expect(places, sorted, reason: "out of order: $headings");
    });

    testWidgets("and the mapping is hidden while the numbers are typed in",
        (tester) async {
      // A mapping with nothing to map is two sections that only ever say
      // nothing.
      await panel(tester);
      expect(find.text("COLUMNS"), findsNothing);
      expect(find.text("CUSTOM FIELDS"), findsNothing);
    });

    testWidgets("each column is a line that opens", (tester) async {
      // Laid out in full, a dozen columns of seven settings each is eighty
      // rows of controls to change one heading -- and the one being looked
      // for has to be found by counting.
      var controller = await panel(tester,
          source: dcrdataChart.applyTo(const DataSource(), "coin-supply"));
      expect(controller.document.elements.single, isA<ChartElement>());
      await open(tester, "COLUMNS", "Path to the list");

      // Closed, each says its name and what it is mapped to.
      expect(find.text("COIN SUPPLY (DCR)"), findsWidgets);
      expect(find.text("Header"), findsNothing,
          reason: "the settings are behind the line, not spread down it");

      await openColumn(tester, "COIN SUPPLY (DCR)");
      expect(find.text("Header"), findsOneWidget);
      // A cell can hold a club badge and a badge chosen by hand has to
      // survive a refresh. Neither is true of a number on a chart, so on one
      // they are two switches that do nothing.
      expect(find.text("A picture"), findsNothing);
      expect(find.text("Keep mine"), findsNothing);
      // And a custom field is an ordinary column with a recipe, edited here
      // rather than listed a second time in a section of its own.
      expect(find.text("Built from fields"), findsOneWidget);
    });

    testWidgets("a column can be moved, and the drawing follows it",
        (tester) async {
      // There was no way to reorder a mapping at all: a column in the wrong
      // place had to be deleted and the rest re-done by hand.
      var controller = await panel(
        tester,
        source: dcrdataChart.applyTo(const DataSource(), "coin-supply"),
        map: const ChartSourceMap(categoryColumn: 0, valueColumns: [1]),
      );
      await open(tester, "COLUMNS", "Path to the list");
      await openColumn(tester, "COIN SUPPLY (DCR)");

      var earlier = find.byTooltip("Move this column earlier");
      await tester.ensureVisible(earlier.last);
      await tester.pumpAndSettle();
      await tester.tap(earlier.last);
      await tester.pumpAndSettle();

      var chart = controller.document.elements.single as ChartElement;
      expect([for (var c in chart.source.columns) c.header],
          ["Coin supply (DCR)", "Date"]);
      expect(chart.fromSource.categoryColumn, 1,
          reason: "the date is still the axis, at its new number");
      expect(chart.fromSource.valueColumns, [0],
          reason: "and the supply is still the series");
    });

    testWidgets("which end a chart empties from is its own switch",
        (tester) async {
      // Not eight more entries in the preset list: "which preset" and "which
      // end it starts from" are different questions, and the list is long
      // enough already.
      var controller = await panel(tester);
      await open(tester, "ANIMATION", "Goes off");
      expect(find.text("In the same order"), findsNothing,
          reason: "there is no way out to order yet");

      var chart = controller.document.elements.single as ChartElement;
      controller.applyChartExit(chart, ChartAnimationPreset.grow);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text("In the same order"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("In the same order"));
      await tester.pumpAndSettle();

      var after = controller.document.elements.single as ChartElement;
      expect(after.animation.exitInOrder, isTrue);
      expect(after.animation.leaving.flipOrder, isTrue,
          reason: "which is what the painter draws the way out with");
    });

    testWidgets("a date axis can be read at intervals", (tester) async {
      // Thinning evenly gives a readable chart and a meaningless axis: the
      // points land wherever the arithmetic put them. One a year, on a date
      // chosen, gives an axis that says 2020, 2021, 2022.
      var controller = await panel(tester,
          source: dcrdataChart.applyTo(const DataSource(), "coin-supply"));
      await open(tester, "DATA SOURCE");

      var reading = find.text("A reading");
      expect(reading, findsOneWidget,
          reason: "the axis is the date column, so this can mean something");
      // Which axis, on a chart that has two of them.
      expect(find.text("Along the x axis"), findsOneWidget);

      // The anchor only appears once there is an interval to anchor.
      expect(find.text("On the"), findsNothing);
      await tester.ensureVisible(find.text("Every point"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Every point"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Yearly").last);
      await tester.pumpAndSettle();

      var chart = controller.document.elements.single as ChartElement;
      expect(chart.fromSource.interval.unit, IntervalUnit.year);
      expect(find.text("On the"), findsOneWidget,
          reason: "a yearly reading is on a day of a month");
      expect(find.text("In"), findsOneWidget);
      expect(find.text("Most points"), findsNothing,
          reason: "two answers to the same question, so only one is offered");
      // The count says what it is counting. On its own the number read as a
      // number of readings, which is not what it is.
      expect(find.text("Each one is"), findsOneWidget,
          reason: "adding a year of transactions up is the point of the "
              "feature, and it cannot be guessed from the numbers");
      expect(find.text("year"), findsOneWidget,
          reason: "a reading every N *years* — one of them, so singular");
      // The hint is a tooltip on a question mark, so what it says is read off
      // the widget rather than off the screen.
      var hints = [
        for (var it in tester.widgetList<Tooltip>(find.byType(Tooltip)))
          it.message ?? "",
      ];
      expect(hints.any((m) => m.contains("One reading a year, on 1 January")),
          isTrue,
          reason: "it should say the interval in words: $hints");
    });

    testWidgets("and a column of names cannot be", (tester) async {
      // On a column of team names an interval is a control that could not do
      // anything.
      await panel(tester,
          source: coinGeckoMarkets.applyTo(const DataSource(), "decred"));
      await open(tester, "DATA SOURCE");
      expect(find.text("A reading"), findsNothing);
      expect(find.text("Most points"), findsOneWidget);
    });

    testWidgets("choosing a preset fills in the address and the mapping",
        (tester) async {
      // The choice decides the mapping as well as the address: dcrdata keeps
      // every series in an array named after itself, so a preset that only
      // set the URL would fetch four thousand rows and draw none of them.
      var controller = await panel(tester);
      await open(tester, "DATA SOURCE");

      await tester.ensureVisible(find.text("None — set it up myself"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("None — set it up myself"));
      await tester.pumpAndSettle();
      await tester.tap(find.text(dcrdataChart.label).last);
      await tester.pumpAndSettle();

      var source = chartIn(controller).source;
      expect(source.preset, dcrdataChart.id);
      expect(source.shape, DataShape.columns);
      expect(source.where, contains("dcrdata.decred.org"));
      expect(source.columns.length, 2);
      expect(chartIn(controller).fromSource.valueColumns, [1]);
      expect(chartIn(controller).fromSource.maxPoints, greaterThan(0),
          reason: "a daily series since 2016 has to be thinned to be drawn");
    });

    testWidgets("a league table is not offered to a chart", (tester) async {
      // A chart of a league table comes from the table beside it -- one
      // request, one set of figures, and they cannot disagree.
      await panel(tester);
      await open(tester, "DATA SOURCE");
      await tester.ensureVisible(find.text("None — set it up myself"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("None — set it up myself"));
      await tester.pumpAndSettle();

      expect(find.text(footballData.label), findsNothing);
      expect(find.text(dcrdataChart.label), findsWidgets);
    });

    testWidgets("refreshing draws what came back", (tester) async {
      // End to end through the panel, over a file rather than the network:
      // the fetching is the same code either way and a test that needed the
      // internet would be a test that fails on a train.
      // Written synchronously. A dart:io future completes on the real event
      // loop and its continuation is a microtask in the fake one, so awaiting
      // one in the body of a widget test hangs the whole suite with no error
      // at all -- which is exactly what this did.
      var file = File("${dir.path}/supply.json");
      file.writeAsStringSync(jsonEncode({
        "t": [1454889600, 1454976000, 1455062400],
        "supply": [168720623595120, 169504574718296, 170288525841472],
      }));

      var controller = await panel(
        tester,
        source: dcrdataChart
            .applyTo(const DataSource(), "coin-supply")
            .copyWith(kind: DataKind.file, where: file.path),
        map: const ChartSourceMap(valueColumns: [1]),
      );
      expect(chartIn(controller).data.isEmpty, isTrue);

      // Two of them now: the Data source section's and the one on the Table
      // section, which is where somebody looking at the numbers is standing.
      var refresh =
          find.byTooltip("Read the data and put it in the chart").first;
      await tester.ensureVisible(refresh);
      await tester.pumpAndSettle();
      await tester.tap(refresh);
      await idle(tester);

      var data = chartIn(controller).data;
      expect(data.categories.length, 3);
      expect(data.series.single.name, "Coin supply (DCR)");
      // In DCR rather than in atoms, which is what the chain counts in.
      expect(data.series.single.values.first, closeTo(1687206.2, 0.1));
      expect(chartIn(controller).source.fetchedAt, isNotNull,
          reason: "so the heading can say how old the numbers are");
    });

    testWidgets("and the columns can be changed without fetching again",
        (tester) async {
      var file = File("${dir.path}/two.json");
      file.writeAsStringSync(jsonEncode({
        "t": [1454889600, 1454976000],
        "supply": [100000000, 200000000],
        "count": [7, 9],
      }));

      var controller = await panel(
        tester,
        source: const DataSource(
          kind: DataKind.file,
          columns: [
            SourceColumn(header: "Date", path: "t", date: "MMM yy"),
            SourceColumn(header: "Supply", path: "supply", divide: 1e8),
            SourceColumn(header: "Transactions", path: "count"),
          ],
          shape: DataShape.columns,
        ).copyWith(where: file.path),
        map: const ChartSourceMap(valueColumns: [1]),
      );

      // Two of them now: the Data source section's and the one on the Table
      // section, which is where somebody looking at the numbers is standing.
      // This presses the Table section's, which is the one that is *not*
      // inside the data panel -- so what follows also pins that a refresh
      // from there leaves the mapping controls able to redraw.
      var refresh =
          find.byTooltip("Read the data and put it in the chart").first;
      await tester.ensureVisible(refresh);
      await tester.pumpAndSettle();
      await tester.tap(refresh);
      await idle(tester);
      expect(chartIn(controller).data.series.single.name, "Supply");

      // Adding a second series redraws from the rows already in hand. It is a
      // row per series now rather than a switch per column, so the gesture is
      // "add one" and it lands on the first column not already drawn.
      await open(tester, "DATA SOURCE");
      var add = find.byKey(const ValueKey("chartSeriesAdd"));
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();

      var data = chartIn(controller).data;
      expect([for (var s in data.series) s.name], ["Supply", "Transactions"]);
      expect(data.series[1].values, [7, 9]);
      expect(chartIn(controller).fromSource.valueColumns, [1, 2]);
    });
  });

  group("a dropdown's ink", () {
    testWidgets("is painted by a Material of its own", (tester) async {
      // Ink -- the splash, and the highlight a focused control keeps -- is
      // painted by the nearest Material *ancestor*, in that ancestor's
      // coordinates and clipped to it. With the sidebar's Material as the
      // nearest, the highlight left behind by choosing a chart type was drawn
      // at the dropdown's place in the sidebar and stayed there: a grey box
      // floating over the Add panel while the settings scrolled underneath.
      await pump(
        tester,
        CanvasDropdown<int>(
          label: "Type",
          value: 1,
          options: const [(1, "Bars"), (2, "Lines")],
          onChanged: (_) {},
        ),
      );

      var inside = find.descendant(
          of: find.byType(CanvasDropdown<int>),
          matching: find.byType(Material));
      expect(inside, findsWidgets,
          reason: "without one, the ink is the sidebar's to paint");
      expect(
          find.descendant(
              of: inside.last, matching: find.byType(DropdownButton<int>)),
          findsOneWidget);
    });
  });

  group("the band over the canvas", () {
    // Two lines, not three: the captions sit beside their controls rather
    // than above them, which is a whole line of nine-pixel grey text saved in
    // a strip that is only as tall as what is on it.

    testWidgets("captions sit beside their controls", (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasSettingsPanel(controller: controller));

      var caption = tester.getRect(find.text("Max width"));
      // The box itself, not the widget around it -- the caption is inside
      // that, so its rectangle would contain both.
      var field = tester.getRect(find.descendant(
          of: find.byKey(const ValueKey("canvasWidth")),
          matching: find.byType(TextField)));
      expect(caption.right, lessThanOrEqualTo(field.left + 1),
          reason: "the caption should be to the left of the field");
      expect((caption.center.dy - field.center.dy).abs(), lessThan(8),
          reason: "and level with it, not above");
    });

    testWidgets("and down a sidebar they stay above", (tester) async {
      // The band has room sideways and none downwards; a sidebar is the other
      // way round, and captions above line the controls up with each other.
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      controller.selectOnly(element.id);
      await pump(tester, CanvasDesignPanel(controller: controller));

      var caption = find.text("W").first;
      var field = find.descendant(
          of: find.ancestor(
              of: caption, matching: find.byType(CanvasNumberField)),
          matching: find.byType(TextField));
      expect(tester.getRect(caption).bottom,
          lessThanOrEqualTo(tester.getRect(field).top + 1),
          reason: "the caption should be above the box, not beside it");
    });

    testWidgets("everything on a line is level", (tester) async {
      // A line of controls is not all one height -- a switch, a box with a
      // caption beside it, a readout -- and aligned at the top they sat at
      // three different heights on a strip whose whole job is to be one line.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasSettingsPanel(controller: controller));

      var middles = [
        for (var it in [
          find.byType(DropdownButton<CanvasRatio>),
          find.descendant(
              of: find.byKey(const ValueKey("canvasWidth")),
              matching: find.byType(TextField)),
          find.textContaining("×"),
          find.byKey(const ValueKey("estimateAs")),
        ])
          tester.getRect(it).center.dy,
      ];
      var spread = middles.reduce(math.max) - middles.reduce(math.min);
      expect(spread, lessThan(5), reason: "the line sits at $middles");
    });

    testWidgets("and a switch is level with a field beside it", (tester) async {
      // The grid line is mostly switches. They carry a nudge that lines a
      // control with no caption up under ones that have them, which on a band
      // with the captions beside their controls pushed them out of line.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasGuidesPanel(controller: controller));

      var toggle = tester.getRect(find.ancestor(
          of: find.text("Show a grid"), matching: find.byType(CanvasToggle)));
      var field = tester.getRect(find.ancestor(
          of: find.text("Every"), matching: find.byType(CanvasNumberField)));
      expect((toggle.center.dy - field.center.dy).abs(), lessThan(5),
          reason: "the switch is at ${toggle.center.dy} and the field at "
              "${field.center.dy}");
    });

    testWidgets("groups do not run into each other", (tester) async {
      // "1280 × 72055.0 KiB" was two groups with nothing between them.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasSettingsPanel(controller: controller));

      var canvas = tester.getRect(find.text("CANVAS"));
      var estimate = tester.getRect(find.text("ESTIMATED SIZE"));
      expect(estimate.left - canvas.left, greaterThan(100),
          reason: "the second group starts well clear of the first");
    });

    testWidgets("the zoom can be typed in", (tester) async {
      // The obvious thing to do with a percentage is type one, and until now
      // the only way to a particular scale was pressing a button that
      // multiplies by 1.25 and hoping.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(
          tester,
          CanvasSettingsBar(
            controller: controller,
            onPublish: () {},
            canvasSettingsOpen: false,
            onToggleCanvasSettings: () {},
            guidesOpen: false,
            onToggleGuides: () {},
            timelineOpen: true,
            onToggleTimeline: () {},
          ));

      // The band has no stage under it, so the fitted scale is one and the
      // percentage is the zoom.
      var field = find.byType(TextField);
      expect(field, findsOneWidget);
      await tester.enterText(field, "250");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(controller.viewScale, closeTo(2.5, 0.001));
      // And the sign comes back with the reading once it is not being typed
      // into: the digits alone while the caret is in it, because nobody wants
      // to steer round a per cent sign to change a number.
      expect(find.text("250%"), findsOneWidget);
    });

    testWidgets("the zoom sits on the same line as the buttons",
        (tester) async {
      // Given a box taller than its own text the field sat at the top of it,
      // which put the number and the per cent sign above the row of buttons.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(
          tester,
          CanvasSettingsBar(
            controller: controller,
            onPublish: () {},
            canvasSettingsOpen: false,
            onToggleCanvasSettings: () {},
            guidesOpen: false,
            onToggleGuides: () {},
            timelineOpen: true,
            onToggleTimeline: () {},
          ));

      var field = tester.getRect(find.byType(TextField));
      var icon = tester.getRect(find.byIcon(Icons.zoom_in));
      var suffix = tester.getRect(find.text("100%"));
      expect((field.center.dy - icon.center.dy).abs(), lessThan(2),
          reason: "the box is at ${field.center.dy} and the buttons at "
              "${icon.center.dy}");
      expect((suffix.center.dy - icon.center.dy).abs(), lessThan(2),
          reason: "and the reading with them");
    });

    testWidgets("and sits against the buttons whatever the number is",
        (tester) async {
      // The box used to be as wide as the widest number there could be, with
      // the digits against its right-hand edge -- so at 100% there was half a
      // button of nothing between the zoom buttons and the number, which read
      // as the number belonging to whatever was on its right.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(
          tester,
          CanvasSettingsBar(
            controller: controller,
            onPublish: () {},
            canvasSettingsOpen: false,
            onToggleCanvasSettings: () {},
            guidesOpen: false,
            onToggleGuides: () {},
            timelineOpen: true,
            onToggleTimeline: () {},
          ));

      double gapNow() =>
          tester.getRect(find.byType(TextField)).left -
          tester.getRect(find.byIcon(Icons.zoom_in)).right;

      var gap = gapNow();
      var box = tester.getRect(find.byType(TextField)).width;
      expect(gap, lessThan(12),
          reason: "the number sits with the buttons it belongs to: $gap");

      // One width, big enough for the widest reading there is, and the
      // reading is left-aligned inside it: what varies is the empty room
      // after the sign rather than a gap before the number.
      controller.zoom = 0.25;
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(TextField)).width, box);
      expect((gapNow() - gap).abs(), lessThan(0.5),
          reason: "the box does not move when the number gets shorter");

      controller.zoom = 16;
      await tester.pumpAndSettle();
      var wide = tester.getRect(find.byType(TextField));
      var reading = tester.getRect(find.text("1600%"));
      expect(wide.width, box, reason: "still one width");
      expect(reading.left, greaterThanOrEqualTo(wide.left - 0.5),
          reason: "nothing is cut off the front of it");
      expect(reading.right, lessThanOrEqualTo(wide.right + 0.5),
          reason: "nor off the end");
    });

    testWidgets("a number the view changed by itself is readable",
        (tester) async {
      // The reported fault: resizing the canvas moved the zoom, and the new
      // number was cut off until the field was clicked into and out of
      // again. Clicking into a field and out of it is not a way to read a
      // number.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(
          tester,
          CanvasSettingsBar(
            controller: controller,
            onPublish: () {},
            canvasSettingsOpen: false,
            onToggleCanvasSettings: () {},
            guidesOpen: false,
            onToggleGuides: () {},
            timelineOpen: true,
            onToggleTimeline: () {},
          ));

      // From a short number to a long one, which is where a box measured
      // against the number that was there before comes up short.
      controller.zoom = 0.25;
      await tester.pumpAndSettle();
      expect(find.text("25%"), findsOneWidget);

      controller.zoom = 16;
      await tester.pumpAndSettle();
      expect(find.text("1600%"), findsOneWidget);

      var field = tester.getRect(find.byType(TextField));
      var digits = tester.getRect(find.text("1600%"));
      expect(digits.width, greaterThan(0));
      expect(digits.left, greaterThanOrEqualTo(field.left - 0.5),
          reason: "the number is inside its box, not cut off by it");
      expect(digits.right, lessThanOrEqualTo(field.right + 0.5),
          reason: "and so is the sign, which is part of it now");
    });

    testWidgets("the number stays on screen in a narrow window",
        (tester) async {
      // The reported fault: with a sidebar open or the nav bar showing, the
      // end of the row of tools ran under the buttons on the right -- and the
      // end of that row is the number, so the bigger the number the sooner it
      // went, which is exactly backwards.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(
          tester,
          CanvasSettingsBar(
            controller: controller,
            onPublish: () {},
            canvasSettingsOpen: false,
            onToggleCanvasSettings: () {},
            guidesOpen: false,
            onToggleGuides: () {},
            timelineOpen: true,
            onToggleTimeline: () {},
          ));

      controller.zoom = 8.88;
      await tester.pumpAndSettle();
      expect(find.text("888%"), findsOneWidget);

      // A window narrow enough that the tools cannot all fit.
      tester.view.physicalSize = const Size(430, 900);
      await tester.pumpAndSettle();

      var reading = tester.getRect(find.text("888%"));
      var field = tester.getRect(find.byType(TextField));
      // Inside its own box, sign and all. The box is sized against the widest
      // digits there are rather than against a number that happens to have a
      // narrow one in it -- 888% is wider than 1400% in a face whose one is
      // narrow, which is how the sign was still being cut off.
      expect(reading.right, lessThanOrEqualTo(field.right + 0.5),
          reason: "the reading ends at ${reading.right} and the box at "
              "${field.right}");

      var bar = tester.getRect(find.byType(CanvasSettingsBar));
      expect(reading.left, greaterThanOrEqualTo(bar.left),
          reason: "the reading is inside the bar");
      expect(reading.right, lessThanOrEqualTo(bar.right));

      // Not under the buttons on the right either, which is where it went.
      var undo = tester.getRect(find.byIcon(Icons.undo));
      expect(reading.right, lessThanOrEqualTo(undo.left),
          reason: "the reading ends at ${reading.right} and Undo starts at "
              "${undo.left}");
    });

    testWidgets("the timeline can be hidden from the bar", (tester) async {
      // A still canvas has no use for a transport, and forty pixels of it
      // under a picture nobody is animating is forty pixels of picture.
      var open = true;
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);

      await pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => CanvasSettingsBar(
            controller: controller,
            onPublish: () {},
            canvasSettingsOpen: false,
            onToggleCanvasSettings: () {},
            guidesOpen: false,
            onToggleGuides: () {},
            timelineOpen: open,
            onToggleTimeline: () => setState(() => open = !open),
          ),
        ),
      );

      await tester.tap(find.byTooltip("Hide the timeline"));
      await tester.pumpAndSettle();
      expect(open, isFalse);
      expect(find.byTooltip("Show the timeline"), findsOneWidget,
          reason: "and it says how to get it back");
    });
  });

  group("panels that share a place", () {
    // Two panels can be tabbed together: they take one panel's worth of room
    // and one shows at a time, which is what somebody with a tall list, a
    // tall settings panel and a short sidebar actually wants.
    //
    // Where a drop lands is decided by which third of a header it is over --
    // the top moves the panel above, the bottom below, the middle makes a
    // tab -- so these drag to a particular part of a particular header rather
    // than to a header.

    Future<CanvasController> stack(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      var document = const CanvasDocument();
      var element = newElement(ElementKind.shape, document);
      var controller = CanvasController(document.addElement(element));
      addTearDown(controller.dispose);
      await pump(tester, CanvasDesignPanel(controller: controller));
      return controller;
    }

    /// grip is the handle a single panel is carried by, in the header whose
    /// name is [name].
    Finder grip(String name) => find.descendant(
        of: find.ancestor(
            of: find.text(name), matching: find.byType(DragTarget<PanelDrag>)),
        matching: find.byIcon(Icons.drag_indicator));

    /// dropOn drags [from] onto the given fraction down the header holding
    /// [onto]: the top third moves it above, the bottom third below, the
    /// middle tabs the two together.
    Future<void> dropOn(
        WidgetTester tester, Finder from, String onto, double at) async {
      var target = tester.getRect(find.ancestor(
          of: find.text(onto), matching: find.byType(DragTarget<PanelDrag>)));
      var gesture = await tester.startGesture(tester.getCenter(from));
      // Away first, so the drag is recognised before it is aimed.
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      await gesture
          .moveTo(Offset(target.center.dx, target.top + target.height * at));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets("dropping one on the middle of another tabs them together",
        (tester) async {
      await stack(tester);
      expect(find.text("ADD"), findsOneWidget);
      expect(find.text("LAYERS"), findsOneWidget);

      await dropOn(tester, grip("LAYERS"), "ADD", 0.5);

      // Both names are still there -- as tabs now, in one band.
      expect(find.text("ADD"), findsOneWidget);
      expect(find.text("LAYERS"), findsOneWidget);
      // One header fewer, which is the room the tabbing bought.
      expect(find.byType(DragTarget<PanelDrag>).evaluate().length, lessThan(7),
          reason: "one place fewer than there are panels, and the tabs are "
              "targets too");
      // And the one dropped is the one showing.
      expect(find.byType(CanvasElementsPanel), findsNothing);
      expect(find.byType(CanvasLayersPanel), findsOneWidget);
    });

    testWidgets("and the top and bottom thirds move it instead",
        (tester) async {
      await stack(tester);
      double topOf(String name) => tester
          .getRect(find.ancestor(
              of: find.text(name),
              matching: find.byType(DragTarget<PanelDrag>)))
          .top;
      expect(topOf("ADD"), lessThan(topOf("LAYERS")));

      // Onto the top of the first, which puts it above.
      await dropOn(tester, grip("LAYERS"), "ADD", 0.1);
      expect(topOf("LAYERS"), lessThan(topOf("ADD")),
          reason: "dropped above rather than tabbed");
      // Still three separate places.
      expect(find.byType(CanvasElementsPanel), findsOneWidget);
      expect(find.byType(CanvasLayersPanel), findsOneWidget);
    });

    testWidgets("a tab shows its panel, and shuts it when pressed again",
        (tester) async {
      await stack(tester);
      await dropOn(tester, grip("LAYERS"), "ADD", 0.5);
      expect(find.byType(CanvasLayersPanel), findsOneWidget);

      // The other tab.
      await tester.tap(find.text("ADD"));
      await tester.pumpAndSettle();
      expect(find.byType(CanvasElementsPanel), findsOneWidget,
          reason: "asking for a panel should show it");
      expect(find.byType(CanvasLayersPanel), findsNothing);

      // The one already showing: shut, then open again.
      await tester.tap(find.text("ADD"));
      await tester.pumpAndSettle();
      expect(find.byType(CanvasElementsPanel), findsNothing,
          reason: "a tab is the switch for the whole place");
      await tester.tap(find.text("ADD"));
      await tester.pumpAndSettle();
      expect(find.byType(CanvasElementsPanel), findsOneWidget);
    });

    testWidgets("tabs are divided from each other, shut as well as open",
        (tester) async {
      // Shut, no tab is lit and nothing else says where one ends: three names
      // in a row read as one long heading with odd spacing.
      await stack(tester);
      await dropOn(tester, grip("LAYERS"), "ADD", 0.5);

      /// edges is the right-hand border of each tab in the place, which is
      /// the line between it and the next.
      List<BorderSide> edges() => [
            for (var it in tester.widgetList<Container>(find.descendant(
                of: find.ancestor(
                    of: find.text("LAYERS"),
                    matching: find.byType(DragTarget<PanelDrag>)),
                matching: find.byType(Container))))
              if (it.decoration case BoxDecoration box)
                if (box.border case Border border) border.right,
          ];

      var lines = [
        for (var side in edges())
          if (side.style != BorderStyle.none) side
      ];
      expect(lines.length, 1,
          reason: "two tabs, so one line between them and none after the last");

      // And the same with the place shut, which is when it matters most.
      await tester.tap(find.text("LAYERS"));
      await tester.pumpAndSettle();
      expect(find.byType(CanvasLayersPanel), findsNothing,
          reason: "shut, so this is the case being checked");
      expect(
          [
            for (var side in edges())
              if (side.style != BorderStyle.none) side
          ].length,
          1);
    });

    testWidgets("a tab can be dragged back out to a place of its own",
        (tester) async {
      await stack(tester);
      await dropOn(tester, grip("LAYERS"), "ADD", 0.5);
      expect(find.byType(CanvasElementsPanel), findsNothing,
          reason: "tabbed, so only one of the two is showing");

      // Out of the tabs and below the settings, which is a place of its own
      // again.
      await dropOn(tester, find.text("ADD"), "BACKGROUND SETTINGS", 0.9);
      await tester.pumpAndSettle();
      expect(find.byType(CanvasElementsPanel), findsOneWidget);
      expect(find.byType(CanvasLayersPanel), findsOneWidget,
          reason: "and the one it left is showing again");
    });

    testWidgets("a place has one height, whichever tab is showing",
        (tester) async {
      // A group of tabs is one box that different panels take turns inside.
      // Kept per tab, the height changed every time somebody looked at the
      // other one, and the sidebar jumped under them.
      await stack(tester);
      await dropOn(tester, grip("LAYERS"), "ADD", 0.5);

      double bodyHeight(Type panel) =>
          tester.getRect(find.byType(panel)).height;
      var before = bodyHeight(CanvasLayersPanel);

      // The boundary under the tabbed place, dragged down to make it taller.
      await tester.drag(find.byKey(const ValueKey("panelDivider:settings")),
          const Offset(0, 60));
      await tester.pumpAndSettle();

      var taller = bodyHeight(CanvasLayersPanel);
      expect(taller, greaterThan(before + 40),
          reason: "the drag should have made the place taller");

      await tester.tap(find.text("ADD"));
      await tester.pumpAndSettle();
      expect(bodyHeight(CanvasElementsPanel), closeTo(taller, 1),
          reason: "the other tab should be given the same box");
    });

    testWidgets("the arrangement is remembered", (tester) async {
      await stack(tester);
      await dropOn(tester, grip("LAYERS"), "ADD", 0.5);

      // Saved with those two as one place: "add+layers".
      var saved = await StorageManager.readString("canvasDesign.order");
      expect(saved, contains("+"));
      expect(saved.split(",").length, 3,
          reason: "one place fewer than there are panels: $saved");
    });

    testWidgets("a panel that comes and goes keeps its place", (tester) async {
      // The transition settings are there only while there is a scene to give
      // way to. Filtered out of the arrangement on the way in -- it is not a
      // panel yet when the column is built -- it came back at the end of the
      // column however it had been arranged, which is a place nobody put it.
      SharedPreferences.setMockInitialValues({});
      await StorageManager.saveString(
          "canvasDesign.order", "transitions,add,layers,scenes,settings");

      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasDesignPanel(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text("TRANSITION"), findsNothing,
          reason: "one scene has nothing to give way to");

      controller.addScene();
      await tester.pumpAndSettle();

      double topOf(String name) => tester
          .getRect(find.ancestor(
              of: find.text(name),
              matching: find.byType(DragTarget<PanelDrag>)))
          .top;
      expect(topOf("TRANSITION"), lessThan(topOf("ADD")),
          reason: "back at the top, where the arrangement left it");
    });

    testWidgets("and an arrangement saved before tabs existed still reads",
        (tester) async {
      // "a,b,c" is three places of one, which is exactly what it was.
      SharedPreferences.setMockInitialValues({});
      await StorageManager.saveString(
          "canvasDesign.order", "settings,layers,elements");

      var document = const CanvasDocument();
      var controller = CanvasController(document);
      addTearDown(controller.dispose);
      await pump(tester, CanvasDesignPanel(controller: controller));
      await tester.pumpAndSettle();

      double topOf(String name) => tester
          .getRect(find.ancestor(
              of: find.text(name),
              matching: find.byType(DragTarget<PanelDrag>)))
          .top;
      expect(topOf("BACKGROUND SETTINGS"), lessThan(topOf("LAYERS")));
      expect(topOf("LAYERS"), lessThan(topOf("ADD")));
    });
  });

  group("the text settings", () {
    /// panel builds a text element's settings the way the Layers sidebar does.
    Future<CanvasController> panel(WidgetTester tester,
        {TextElement? element}) async {
      var text = element ??
          TextElement(
            ElementBase(id: newElementId(), width: 400, height: 200),
            text: "You come across an idea",
          );
      var controller =
          CanvasController(const CanvasDocument().addElement(text));
      addTearDown(controller.dispose);
      controller.selectOnly(text.id);
      await pump(tester, CanvasDesignPanel(controller: controller));
      await tester.pumpAndSettle();
      return controller;
    }

    TextElement textIn(CanvasController c) =>
        c.document.elements.whereType<TextElement>().single;

    testWidgets("are five sections, in the order the work happens",
        (tester) async {
      // How it is laid out, which words are different, and how it arrives.
      // Flat, it was eight groups down one narrow column with the animation
      // settings below the fold.
      //
      // Three of them are not among them any more. The type was a section
      // that was open every time anybody looked, which is a chevron and a
      // word standing between the panel and the first thing it is for; the
      // columns and the line are one row each, and a heading with a chevron
      // on it for one row is more furniture than setting.
      await panel(tester);
      var headings = [
        for (var it
            in tester.widgetList<CanvasExpander>(find.byType(CanvasExpander)))
          it.label,
      ];
      for (var gone in ["Type", "Columns", "On a line"]) {
        expect(headings, isNot(contains(gone)));
      }
      // And they are still on the panel, in that order, as rows.
      expect(find.text("COLUMNS"), findsOneWidget);
      expect(find.text("ON A LINE"), findsOneWidget);
      expect(tester.getRect(find.text("COLUMNS")).top,
          lessThan(tester.getRect(find.text("ON A LINE")).top));

      var wanted = [
        "Parts of the text",
        "Animation",
      ];
      expect([for (var w in wanted) headings.contains(w)], everyElement(isTrue),
          reason: "$headings");
      var places = [for (var w in wanted) headings.indexOf(w)];
      var sorted = [...places]..sort();
      expect(places, sorted, reason: "out of order: $headings");
    });

    testWidgets("the colour settings are behind the type button",
        (tester) async {
      // One line and one button for one piece of writing. This is the element
      // that has several pieces of writing in it, and a row each plus a
      // colour row each is a panel nothing can be found in. Everywhere else
      // the colour keeps a row of its own -- see the table below.
      await panel(tester);
      expect(find.text("COLOUR"), findsNothing,
          reason: "no group of its own here");
      expect(find.text("Outline"), findsNothing, reason: "nor its controls");

      var button = find.byTooltip("Spacing, alignment and case");
      await tester.ensureVisible(button.first);
      await tester.pumpAndSettle();
      await tester.tap(button.first);
      await tester.pumpAndSettle();
      expect(find.text("Outline"), findsOneWidget);
      expect(find.byType(CanvasColorButton), findsWidgets);
    });

    testWidgets("but a shape's label keeps a colour row of its own",
        (tester) async {
      var shape = ShapeElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Labelled",
      );
      var controller =
          CanvasController(const CanvasDocument().addElement(shape));
      addTearDown(controller.dispose);
      controller.selectOnly(shape.id);
      await pump(tester, CanvasDesignPanel(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text("COLOUR"), findsWidgets,
          reason: "one thing to colour, and the swatch is worth seeing");
    });

    testWidgets("a piece is added, placed and taken away from the panel",
        (tester) async {
      // The words are typed on the canvas; everything else about a piece is
      // here. Its row is the element's own row and nothing more, so where it
      // sits and the button that takes it away are behind its button.
      var controller = await panel(tester);
      expect(textIn(controller).items, isEmpty);

      var add = find.byKey(const ValueKey("textAddItem"));
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();

      expect(textIn(controller).items.length, 1);
      expect(textIn(controller).items.first.text, "Text",
          reason: "something to see and to click on the canvas");

      // Open its button, if an earlier test has not left it open -- a
      // more-button remembers, and remembers across tests. Done while there
      // is one piece, because two fresh pieces say the same thing and a
      // caption is how a row is told from the next. Captions are drawn in
      // capitals, so that is what to look for.
      var group = find.ancestor(
          of: find.text(textIn(controller).items.first.says.toUpperCase()),
          matching: find.byType(CanvasMoreGroup));
      var button =
          find.descendant(of: group, matching: find.byIcon(Icons.tune));
      if (button.evaluate().isNotEmpty) {
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      var slot = find.byKey(const ValueKey("textItemSlot0"));
      await tester.ensureVisible(slot);
      await tester.pumpAndSettle();
      await tester.tap(slot);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Middle right").last);
      await tester.pumpAndSettle();
      expect(textIn(controller).items.first.slot, TextSlot.middleRight);

      // A second one goes to a free slot rather than on top of the first.
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(textIn(controller).items.length, 2);
      expect(textIn(controller).items.last.slot,
          isNot(textIn(controller).items.first.slot));

      var remove = find.byKey(const ValueKey("textItemRemove0"));
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(textIn(controller).items.length, 1);
      expect(textIn(controller).items.first.slot, isNot(TextSlot.middleRight),
          reason: "the one that was moved is the one that went");
    });

    testWidgets("and each piece's row is the same control the words get",
        (tester) async {
      // Face, size, weight and a button holding the rest -- not a second set
      // of controls that happen to do the same things.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        items: const [
          TextItem(id: "n", text: "01", slot: TextSlot.topLeft),
        ],
      );
      var controller = await panel(tester, element: element);
      expect(find.text("01"), findsOneWidget,
          reason: "the row is captioned with what the piece says");

      // The piece's own group, and only that: a more-button tapped open in an
      // earlier test of this file is still open in this one -- which changes
      // both what the panel holds and what the buttons are called -- so every
      // finder here is scoped to the piece and the button is opened only if
      // it is shut.
      var group = find.ancestor(
          of: find.text("01"), matching: find.byType(CanvasMoreGroup));
      expect(group, findsOneWidget, reason: "the piece has a group of its own");
      var button =
          find.descendant(of: group, matching: find.byIcon(Icons.tune));
      if (button.evaluate().isNotEmpty) {
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }
      expect(find.descendant(of: group, matching: find.text("Outline")),
          findsOneWidget,
          reason: "the piece has its own colour behind its own button");

      // And changing it writes to the piece, not to the element.
      var size =
          find.descendant(of: group, matching: find.byType(CanvasNumberField));
      await tester.ensureVisible(size.first);
      await tester.pumpAndSettle();
      await tester.enterText(size.first, "11");
      await tester.pumpAndSettle();
      expect(textIn(controller).items.first.spec.fontSize, 11);
      expect(textIn(controller).textSpec.fontSize, isNot(11));
    });

    testWidgets("a piece is offered where it sits, not an alignment",
        (tester) async {
      // Reported: the alignment dropdowns were there on a piece and did
      // nothing. They could not: a piece is held to the corner of the box its
      // slot names, so its place is the slot's to decide. A control that does
      // nothing is worse than no control.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        items: const [
          TextItem(id: "n", text: "01", slot: TextSlot.topLeft),
        ],
      );
      await panel(tester, element: element);

      var group = find.ancestor(
          of: find.text("01"), matching: find.byType(CanvasMoreGroup));
      var button =
          find.descendant(of: group, matching: find.byIcon(Icons.tune));
      if (button.evaluate().isNotEmpty) {
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      expect(find.descendant(of: group, matching: find.text("Where")),
          findsOneWidget);
      expect(find.descendant(of: group, matching: find.text("Align")),
          findsNothing);
      expect(find.descendant(of: group, matching: find.text("Vertical")),
          findsNothing);
      // The element's own words keep both -- they fill the box rather than
      // sitting in a corner of it, and Align says Justify as well -- but they
      // are behind a button of their own, which this test has not opened.
    });

    testWidgets("the element's own words can be given a slot too",
        (tester) async {
      // Which is what lets a title and the paragraph under it stack instead
      // of being drawn over each other.
      var controller = await panel(tester);
      expect(textIn(controller).slot, isNull, reason: "the box, by default");

      var where = find.byKey(const ValueKey("textBodySlot"));
      if (where.evaluate().isEmpty) {
        var button = find.byTooltip("Spacing, alignment and case");
        await tester.ensureVisible(button.first);
        await tester.pumpAndSettle();
        await tester.tap(button.first);
        await tester.pumpAndSettle();
      }

      await tester.ensureVisible(where);
      await tester.pumpAndSettle();
      await tester.tap(where);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Top left").last);
      await tester.pumpAndSettle();
      expect(textIn(controller).slot, TextSlot.topLeft);

      await tester.ensureVisible(where);
      await tester.pumpAndSettle();
      await tester.tap(where);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Fills the box").last);
      await tester.pumpAndSettle();
      expect(textIn(controller).slot, isNull);
    });

    testWidgets("a piece keeps two numbers for where it sits, side by side",
        (tester) async {
      // Gap down the box and Left/right across it. Both go either way from
      // zero, so four of them -- one per side -- was four fields saying what
      // two say, and a switch to hide them was a switch over nothing.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        items: const [
          TextItem(id: "n", text: "01", slot: TextSlot.topLeft, gap: 8),
        ],
      );
      var controller = await panel(tester, element: element);

      var group = find.ancestor(
          of: find.text("01"), matching: find.byType(CanvasMoreGroup));
      var button =
          find.descendant(of: group, matching: find.byIcon(Icons.tune));
      if (button.evaluate().isNotEmpty) {
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      var gap = find.byKey(const ValueKey("textItemGap0"));
      var side = find.byKey(const ValueKey("textItemSide0"));
      expect(gap, findsOneWidget);
      expect(side, findsOneWidget, reason: "not behind a switch of its own");
      expect(tester.getRect(side).top, closeTo(tester.getRect(gap).top, 0.5),
          reason: "side by side");

      await tester.ensureVisible(side);
      await tester.pumpAndSettle();
      await tester.enterText(side, "14");
      await tester.pumpAndSettle();
      expect(textIn(controller).items.first.side, 14);
    });

    testWidgets("a piece's row is directly under the element's own",
        (tester) async {
      // Another piece of writing in the same box belongs with the writing
      // that is already there, not below the box, the columns and the line.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        items: const [
          TextItem(id: "n", text: "01", slot: TextSlot.topLeft),
        ],
      );
      await panel(tester, element: element);

      var faces = find.byType(CanvasDropdown<String>);
      var own = tester.getRect(faces.first);
      var piece = tester.getRect(find.descendant(
          of: find.ancestor(
              of: find.text("01"), matching: find.byType(CanvasMoreGroup)),
          matching: find.byType(CanvasDropdown<String>)));
      var add = tester.getRect(find.byKey(const ValueKey("textAddItem")));
      var box = tester.getRect(find.text("BOX"));

      var ownFont = tester.getRect(find.byWidgetPredicate(
          (w) => w is CanvasDropdown<String> && w.label == "Font"));
      var ownWeight = tester.getRect(find.byWidgetPredicate(
          (w) => w is CanvasDropdown<int> && w.label == "Weight"));
      var pieceWeight = tester.getRect(find.descendant(
          of: find.ancestor(
              of: find.text("01"), matching: find.byType(CanvasMoreGroup)),
          matching: find.byType(CanvasDropdown<int>)));
      // The same row, to the pixel: both fill the panel and share what is
      // left over the same way. Reported when they did not -- the slot and
      // the bin were on a piece's line, so there was nothing left to share.
      expect(piece.left, ownFont.left);
      expect(piece.right, ownFont.right);
      expect(pieceWeight.left, ownWeight.left);
      expect(pieceWeight.right, ownWeight.right);
      expect(piece.top, greaterThan(own.top), reason: "under the words");
      expect(add.top, greaterThan(piece.top), reason: "and the + under it");
      expect(box.top, greaterThan(add.top), reason: "the box comes after");
    });

    testWidgets("the colour is on the row and the switches are behind it",
        (tester) async {
      // What colour the words are is the first thing anybody changes about
      // them and the last thing that should be behind a button. Italic and
      // the face's own underline are set once, so they have swapped places
      // with it.
      await panel(tester);
      var own = find.ancestor(
          of: find.byWidgetPredicate(
              (w) => w is CanvasDropdown<String> && w.label == "Font"),
          matching: find.byType(CanvasMoreGroup));

      var face = tester.getRect(find.byWidgetPredicate(
          (w) => w is CanvasDropdown<String> && w.label == "Font"));
      // The first of them: with the button open there are more swatches
      // behind it -- the outline's, the shadow's, the glow's -- and the one
      // on the row is the one in front.
      var swatch = tester.getRect(find
          .descendant(of: own, matching: find.byType(CanvasColorButton))
          .first);
      expect(swatch.top, closeTo(face.top, 0.5),
          reason: "the swatch is on the row with the face");

      var button = find.descendant(of: own, matching: find.byIcon(Icons.tune));
      if (button.evaluate().isNotEmpty) {
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }
      expect(
          find.descendant(of: own, matching: find.byIcon(Icons.format_italic)),
          findsOneWidget,
          reason: "italic is behind the button now");
      expect(find.text("Outline"), findsWidgets,
          reason: "and the rest of the colour settings are first back here");
    });

    testWidgets("and there is one underline, not two", (tester) async {
      // The face's own underline and a drawn one under the words are two
      // switches called Underline on one panel. The one that can do more --
      // a colour, a width, a distance under the letters -- is the one kept.
      await panel(tester);
      var own = find.ancestor(
          of: find.byWidgetPredicate(
              (w) => w is CanvasDropdown<String> && w.label == "Font"),
          matching: find.byType(CanvasMoreGroup));
      var button = find.descendant(of: own, matching: find.byIcon(Icons.tune));
      if (button.evaluate().isNotEmpty) {
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      expect(find.byIcon(Icons.format_underlined), findsNothing);
      expect(find.text("Underline"), findsOneWidget);
    });

    testWidgets("a part is there to fill in before anything is added",
        (tester) async {
      // Pressing a plus to be shown the controls, and only then being able to
      // use them, is a step that exists because the list is empty -- which is
      // not a thing the reader did. The row is there in its own default
      // state, and setting something on it is what adds it.
      var controller = await panel(tester);
      expect(textIn(controller).parts, isEmpty);

      // A section heading is drawn in capitals.
      var heading = find.text("PARTS OF THE TEXT");
      await tester.ensureVisible(heading);
      await tester.pumpAndSettle();
      if (find.byKey(const ValueKey("partBold0")).evaluate().isEmpty) {
        await tester.tap(heading);
        await tester.pumpAndSettle();
      }

      var bold = find.byKey(const ValueKey("partBold0"));
      expect(bold, findsOneWidget, reason: "a row, before the plus was used");
      expect(textIn(controller).parts, isEmpty,
          reason: "and nothing written until it is");

      await tester.ensureVisible(bold);
      await tester.pumpAndSettle();
      await tester.tap(bold);
      await tester.pumpAndSettle();
      expect(textIn(controller).parts.length, 1);
      var part = textIn(controller).parts.first;
      expect(part.weight, isNotNull);
      expect(
          part.weight! >= 600, isNot(textIn(controller).textSpec.weight >= 600),
          reason: "the switch turned, whichever way it was pointing");
    });

    testWidgets("and its switches are buttons, so the row is one line",
        (tester) async {
      // Bold, italic, an outline and the two marks: five words in a column is
      // a column, and five buttons is a line.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        parts: const [TextPart(from: 1, to: 2)],
      );
      await panel(tester, element: element);

      // A section heading is drawn in capitals.
      var heading = find.text("PARTS OF THE TEXT");
      await tester.ensureVisible(heading);
      await tester.pumpAndSettle();
      if (find.byKey(const ValueKey("partBold0")).evaluate().isEmpty) {
        await tester.tap(heading);
        await tester.pumpAndSettle();
      }

      var tops = <double>[];
      for (var key in [
        "partBold0",
        "partItalic0",
        "partOutline0",
        "part0HighlightOn",
        "part0UnderlineOn",
      ]) {
        var button = find.byKey(ValueKey(key));
        expect(button, findsOneWidget, reason: key);
        tops.add(tester.getRect(button).top);
      }
      for (var top in tops) {
        expect(top, closeTo(tops.first, 0.5),
            reason: "all five on one line: $tops");
      }
    });

    testWidgets(
        "a picture's own controls sit with the choice that asked for it",
        (tester) async {
      // Choosing a picture is the next thing anybody does after saying "a
      // picture", so the two buttons are on the line with Painted with -- not
      // two lines down under the outline. And the outline starts a line of
      // its own either way, so the first line is always "what are these
      // letters painted with".
      var controller = await panel(tester);
      var own = find.ancestor(
          of: find.byWidgetPredicate(
              (w) => w is CanvasDropdown<String> && w.label == "Font"),
          matching: find.byType(CanvasMoreGroup));
      var button = find.descendant(of: own, matching: find.byIcon(Icons.tune));
      if (button.evaluate().isNotEmpty) {
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      var kind = find.byKey(const ValueKey("textFillKind"));
      await tester.ensureVisible(kind);
      await tester.pumpAndSettle();
      await tester.tap(kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Picture").last);
      await tester.pumpAndSettle();
      expect(textIn(controller).textSpec.fill.kind, TextFillKind.image);

      var choose = find.byKey(const ValueKey("textFillPicture"));
      expect(choose, findsOneWidget);
      expect(tester.getRect(choose).top, closeTo(tester.getRect(kind).top, 0.5),
          reason: "on the line with the choice that asked for it");

      var outline = find.ancestor(
          of: find.text("Outline"), matching: find.byType(CanvasNumberField));
      expect(tester.getRect(outline).top,
          greaterThan(tester.getRect(kind).bottom - 0.5),
          reason: "and the outline starts a line of its own");
    });

    testWidgets("a picture showing through gets a picture element's Look",
        (tester) async {
      // The same two settings, under the same two names and in the same
      // order: Filter and Overlay. A Look that was named differently and had
      // half of it missing was a second answer to a question that has one.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        textSpec: const TextSpec(
            fill: TextFill(kind: TextFillKind.image, assetId: "abcdefghij12")),
      );
      var controller = await panel(tester, element: element);
      var own = find.ancestor(
          of: find.byWidgetPredicate(
              (w) => w is CanvasDropdown<String> && w.label == "Font"),
          matching: find.byType(CanvasMoreGroup));
      var button = find.descendant(of: own, matching: find.byIcon(Icons.tune));
      if (button.evaluate().isNotEmpty) {
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      var filter = find.byKey(const ValueKey("textFillLook"));
      var overlay = find.byKey(const ValueKey("textFillBlend"));
      expect(tester.widget<CanvasDropdown<ImageFilterPreset>>(filter).label,
          "Filter");
      expect(tester.widget<CanvasDropdown<OverlayBlend>>(overlay).label,
          "Overlay");
      // And no colour to choose until there is something to lay it with.
      expect(find.byKey(const ValueKey("textFillOverlay")), findsNothing);

      await tester.ensureVisible(overlay);
      await tester.pumpAndSettle();
      await tester.tap(overlay);
      await tester.pumpAndSettle();
      await tester.tap(find.text(OverlayBlend.multiply.label).last);
      await tester.pumpAndSettle();
      expect(textIn(controller).textSpec.fill.blend, OverlayBlend.multiply);
      expect(find.byKey(const ValueKey("textFillOverlay")), findsOneWidget,
          reason: "and now a colour to lay");
      expect(
          tester
              .widget<CanvasColorButton>(
                  find.byKey(const ValueKey("textFillOverlay")))
              .onGradientChanged,
          isNotNull,
          reason: "and two to fade between, like every other swatch");

      // And how much of the picture lands at all, which a colour does not
      // need -- its alpha is in the picker -- and a photograph has no other
      // way to get.
      var opacity = find.byKey(const ValueKey("textFillOpacity"));
      await tester.ensureVisible(opacity);
      await tester.pumpAndSettle();
      await tester.enterText(opacity, "0.25");
      await tester.pumpAndSettle();
      expect(textIn(controller).textSpec.fill.opacity, 0.25);
    });

    testWidgets("the box can be painted with a picture or a pattern too",
        (tester) async {
      // The same question of a different shape, so the same three answers --
      // behind the box's own button, where a thing chosen once belongs.
      var controller = await panel(tester);
      var kind = find.byKey(const ValueKey("textBoxFillKind"));
      if (kind.evaluate().isEmpty) {
        var button = find.byKey(const ValueKey("more-textBox"));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await tester.ensureVisible(kind);
      await tester.pumpAndSettle();
      await tester.tap(kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Pattern").last);
      await tester.pumpAndSettle();

      expect(textIn(controller).box.painted.kind, TextFillKind.pattern);
      expect(find.byKey(const ValueKey("textBoxFillPattern")), findsOneWidget,
          reason: "and what that answer needs is on the line with it");

      // A picture, which is *not* on until one has been chosen -- and the
      // buttons that choose one are these, so they cannot wait for it.
      await tester.tap(kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Picture").last);
      await tester.pumpAndSettle();
      expect(textIn(controller).box.painted.on, isFalse,
          reason: "nothing named yet");
      expect(find.byKey(const ValueKey("textBoxFillPicture")), findsOneWidget);
      expect(find.byKey(const ValueKey("textBoxFillLibrary")), findsOneWidget);
    });

    testWidgets("and its colour goes away while a picture is over it",
        (tester) async {
      // A picture or a pattern is drawn across the whole box, so the swatch
      // beside it changed nothing anybody could see -- which reads as a
      // broken control rather than as one that has been overruled.
      var controller = await panel(tester);
      var fill = find.byWidgetPredicate(
          (w) => w is CanvasColorButton && w.label == "Fill");
      expect(fill, findsOneWidget, reason: "a colour to begin with");

      var kind = find.byKey(const ValueKey("textBoxFillKind"));
      if (kind.evaluate().isEmpty) {
        var button = find.byKey(const ValueKey("more-textBox"));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(kind);
      await tester.pumpAndSettle();
      await tester.tap(kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Pattern").last);
      await tester.pumpAndSettle();

      expect(textIn(controller).box.painted.kind, TextFillKind.pattern);
      expect(fill, findsNothing, reason: "the pattern decides now");

      // And back again when the colour is what decides.
      await tester.tap(kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Colour").last);
      await tester.pumpAndSettle();
      expect(fill, findsOneWidget);
    });

    testWidgets("a middle slot says why its block moves as the words change",
        (tester) async {
      // Reported as the gap growing when text was taken out: a middle slot
      // centres the stack, so half of whatever the words lose is given back
      // above it. The setting is doing what it says, and the panel is where
      // that can be said.
      var centredHint = find.byWidgetPredicate((w) =>
          w is CanvasHint && w.message.contains("keeps this block centred"));
      var middle = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        items: const [
          TextItem(
              id: "n", text: "Master Block Vote", slot: TextSlot.middleLeft),
        ],
      );
      await panel(tester, element: middle);
      var button = find.byKey(const ValueKey("more-textItemnType"));
      expect(button, findsOneWidget, reason: "the piece's own button");
      if (find.byKey(const ValueKey("textItemGap0")).evaluate().isEmpty) {
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }
      // A hint is a question mark with a tooltip, so it is found by what it
      // has to say rather than by what is written on the panel.
      expect(centredHint, findsOneWidget);

      // And nothing to say about a slot that holds it to an edge, where the
      // gap means what somebody setting a gap expects.
      await panel(tester,
          element: middle.copyWith(items: [
            middle.items.single.copyWith(slot: TextSlot.topLeft),
          ]));
      expect(centredHint, findsNothing);
    });

    testWidgets("a piece is offered a background once it has a colour",
        (tester) async {
      // The colour is the switch: with nothing painted behind the words there
      // is no shape to round and no room to keep inside it.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        items: const [
          TextItem(id: "n", text: "01", slot: TextSlot.topLeft),
        ],
      );
      var controller = await panel(tester, element: element);

      var group = find.ancestor(
          of: find.text("01"), matching: find.byType(CanvasMoreGroup));
      var button =
          find.descendant(of: group, matching: find.byIcon(Icons.tune));
      if (button.evaluate().isNotEmpty) {
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      expect(find.byKey(const ValueKey("textItemFill0")), findsOneWidget);
      expect(find.byKey(const ValueKey("textItem0Radius")), findsNothing,
          reason: "nothing to round until something is painted");

      // Painted, and the rest comes with it: the corners and the room
      // inside, evenly and one at a time.
      controller.replaceElement(element.copyWith(items: [
        element.items.first
            .copyWith(box: const BoxSpec(fill: Color(0xFF223344))),
      ]));
      await tester.pumpAndSettle();

      // The same controls every other box gets, from the same place: the one
      // number and the four beside it, for the corners and for the room.
      for (var key in [
        "textItem0Radius",
        "textItem0Radius↖",
        "textItem0Padding",
        "textItem0PadLeft",
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
    });

    testWidgets("a pattern can be put back to how it started", (tester) async {
      // A pattern nobody likes any more is quicker to start again than to
      // put back a colour, a density, a size and a turn at a time.
      var controller = await panel(tester);
      var own = find.ancestor(
          of: find.byWidgetPredicate(
              (w) => w is CanvasDropdown<String> && w.label == "Font"),
          matching: find.byType(CanvasMoreGroup));
      var button = find.descendant(of: own, matching: find.byIcon(Icons.tune));
      if (button.evaluate().isNotEmpty) {
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      var kind = find.byKey(const ValueKey("textFillKind"));
      await tester.ensureVisible(kind);
      await tester.pumpAndSettle();
      await tester.tap(kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Pattern").last);
      await tester.pumpAndSettle();

      var seed = find.byKey(const ValueKey("textFillSeed"));
      await tester.ensureVisible(seed);
      await tester.pumpAndSettle();
      await tester.tap(seed);
      await tester.tap(seed);
      await tester.pumpAndSettle();
      var stirred = textIn(controller).textSpec.fill.pattern;
      expect(stirred.seed, isNot(const ProceduralSpec().seed));

      var reset = find.byKey(const ValueKey("textFillReset"));
      await tester.ensureVisible(reset);
      await tester.pumpAndSettle();
      await tester.tap(reset);
      await tester.pumpAndSettle();

      var back = textIn(controller).textSpec.fill.pattern;
      expect(back.seed, const ProceduralSpec().seed);
      expect(back.style, stirred.style, reason: "the style it was, though");
    });

    testWidgets("a piece can be given a name to find it by", (tester) async {
      // Every picture piece said "Picture", so a card with three of them had
      // three rows called the same thing.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        items: const [
          TextItem(id: "p", icon: TextIcon(assetId: "a")),
        ],
      );
      var controller = await panel(tester, element: element);
      expect(find.text("PICTURE"), findsOneWidget,
          reason: "before it is named");

      var group = find.ancestor(
          of: find.text("PICTURE"), matching: find.byType(CanvasMoreGroup));
      var button =
          find.descendant(of: group, matching: find.byIcon(Icons.tune));
      if (button.evaluate().isNotEmpty) {
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      var name = find.byKey(const ValueKey("textItemName0"));
      await tester.ensureVisible(name);
      await tester.pumpAndSettle();
      await tester.enterText(name, "Leeds badge");
      await tester.pumpAndSettle();

      expect(textIn(controller).items.single.name, "Leeds badge");
      expect(find.text("LEEDS BADGE"), findsOneWidget);
      expect(find.text("PICTURE"), findsNothing);
    });

    testWidgets("or renamed by double-clicking the caption itself",
        (tester) async {
      // Which is the gesture a file, a scene and a layer are all renamed by,
      // and the one anybody tries first.
      var element = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Spend or burn",
        items: const [
          TextItem(id: "p", text: "01", slot: TextSlot.topLeft),
        ],
      );
      var controller = await panel(tester, element: element);

      var caption = find.text("01");
      await tester.ensureVisible(caption);
      await tester.pumpAndSettle();
      await tester.tap(caption);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(caption);
      await tester.pumpAndSettle();

      var field =
          find.ancestor(of: find.text("01"), matching: find.byType(TextField));
      expect(field, findsOneWidget, reason: "it opened for typing");
      await tester.enterText(field, "The number");
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(textIn(controller).items.single.name, "The number");
      expect(find.text("THE NUMBER"), findsOneWidget);
    });

    testWidgets("a shape can be painted with a picture or a pattern",
        (tester) async {
      // The same three answers the letters and a box have, cut to a third
      // shape -- behind the button, where a thing chosen once belongs.
      var shape = ShapeElement(
        ElementBase(id: newElementId(), width: 300, height: 200),
      );
      var controller =
          CanvasController(const CanvasDocument().addElement(shape));
      addTearDown(controller.dispose);
      controller.selectOnly(shape.id);
      await pump(tester, CanvasDesignPanel(controller: controller));
      await tester.pumpAndSettle();

      var kind = find.byKey(const ValueKey("shapeFillKind"));
      if (kind.evaluate().isEmpty) {
        var button = find.byKey(const ValueKey("more-shapeMore"));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await tester.ensureVisible(kind);
      await tester.pumpAndSettle();
      await tester.tap(kind);
      await tester.pumpAndSettle();
      await tester.tap(find.text("Picture").last);
      await tester.pumpAndSettle();

      var after = controller.document.elements.whereType<ShapeElement>().single;
      expect(after.painted.kind, TextFillKind.image);
      expect(find.byKey(const ValueKey("shapeFillPicture")), findsOneWidget,
          reason: "and the buttons that name one are with the choice");
    });

    testWidgets("the type settings are out on the panel, not in a section",
        (tester) async {
      // They were behind a heading that was open every time anybody looked.
      var controller = await panel(tester);
      expect(find.text("Fit to box"), findsOneWidget);
      expect(find.text("Font"), findsOneWidget);
      expect(find.text("BOX"), findsOneWidget);

      // Scrolled to first: with four panels in the column the settings can
      // start below the fold, and a tap outside the viewport hits nothing.
      await tester.ensureVisible(find.text("Fit to box"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Fit to box"));
      await tester.pumpAndSettle();
      expect(textIn(controller).autoSize, isTrue);
    });

    testWidgets(
        "No blank first line is offered without columns, and only "
        "on the box the words belong to", (tester) async {
      // A chain of boxes asks the same question of boxes that columns ask of
      // columns, so it is not a columns-only setting -- and every box in a
      // chain follows what the head says, so there is nowhere else to ask it.
      var head = TextElement(
        const ElementBase(id: "head", width: 400, height: 60),
        text: "A long paragraph",
        flowTo: "tail",
      );
      var tail = TextElement(
        const ElementBase(id: "tail", width: 400, height: 200),
      );
      var controller = CanvasController(
          const CanvasDocument().addElement(head).addElement(tail));
      addTearDown(controller.dispose);

      controller.selectOnly("head");
      await pump(tester, CanvasDesignPanel(controller: controller));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text("COLUMNS"));
      await tester.pumpAndSettle();

      expect(find.text("No blank first line"), findsOneWidget,
          reason: "one column, and still the box the words belong to");
      // On to begin with -- a column top that starts with a blank line is a
      // fault every time, so the switch is there to turn the tidying off --
      // and pressing it turns it off.
      expect(
          (controller.document.elementById("head") as TextElement)
              .columns
              .noBlankStart,
          isTrue);
      await tester.tap(find.text("No blank first line"));
      await tester.pumpAndSettle();
      expect(
          (controller.document.elementById("head") as TextElement)
              .columns
              .noBlankStart,
          isFalse);

      controller.selectOnly("tail");
      await tester.pumpAndSettle();
      expect(find.text("No blank first line"), findsNothing);
    });

    testWidgets("the presets section offers to save this one", (tester) async {
      // A section that lists things and does nothing when they are pressed is
      // what a model-only test cannot see.
      var controller = await panel(tester);
      expect(controller.document.elements.length, 1);

      // One line, not a section that has to be opened, and not captioned:
      // what was behind the expander was one button and a list of at most a
      // few names, which is less than the heading it was hidden under.
      expect(find.text("PRESETS"), findsNothing);
      var list = find.byKey(const ValueKey("elementPresets"));
      expect(list, findsOneWidget);
      await tester.ensureVisible(list);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey("elementPresetSave")), findsOneWidget);
      // Nothing chosen, so there is nothing to rename or throw away.
      expect(find.byKey(const ValueKey("elementPresetRename")), findsNothing);
      expect(find.byKey(const ValueKey("elementPresetRemove")), findsNothing);
      // With nothing saved the list says what the button next to it is for
      // rather than sitting there empty.
      expect(find.text("Save this design"), findsOneWidget);
      expect(find.text("THIS ONE"), findsNothing,
          reason: "a caption over a button that already says what it does");
    });

    testWidgets("turning off From a document gives back what was typed",
        (tester) async {
      // Left showing the document's words, the switch would be off and the
      // element would still say what the document says, with nothing on
      // screen to say what was there before.
      var reading = TextElement(
        ElementBase(id: newElementId(), width: 400, height: 200),
        text: "Whatever the document said",
        document: const TextDocumentRef(
            name: "Launch", wasText: "A headline of my own"),
      );
      var controller = await panel(tester, element: reading);

      expect(find.text("From document"), findsOneWidget);
      // Below the fold now that the presets are above it, and a tap at a
      // point outside the viewport hits nothing.
      await tester.ensureVisible(find.text("From document"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("From document"));
      await tester.pumpAndSettle();

      expect(textIn(controller).document.on, isFalse);
      expect(textIn(controller).text, "A headline of my own");
    });

    testWidgets("and a box being flowed into is not offered one",
        (tester) async {
      // Its words belong to the box in front of it, so a document chosen here
      // would be read, stored and never seen -- and the most confusing
      // version of that is a chain already carrying a document, where every
      // box in it looks like somewhere to attach another.
      var head = TextElement(
        const ElementBase(id: "head", width: 400, height: 60),
        text: "A long paragraph",
        flowTo: "tail",
      );
      var tail = TextElement(
        const ElementBase(id: "tail", width: 400, height: 200),
      );
      var controller = CanvasController(
          const CanvasDocument().addElement(head).addElement(tail));
      addTearDown(controller.dispose);

      controller.selectOnly("head");
      await pump(tester, CanvasDesignPanel(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text("From document"), findsOneWidget,
          reason: "the box the words belong to still chooses");

      controller.selectOnly("tail");
      await tester.pumpAndSettle();
      expect(find.text("From document"), findsNothing);
    });

    testWidgets("and the columns section still works once it is opened",
        (tester) async {
      // A section that shuts its controls away is a section that can hide a
      // dead one, which is what a model-only test cannot see.
      var controller = await panel(tester);
      // Out on the panel rather than behind a heading: one number and a
      // switch is not a section.
      var field = find.byKey(const ValueKey("textColumns"));
      expect(field, findsOneWidget);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();

      await tester.enterText(field, "3");
      await tester.pumpAndSettle();
      expect(textIn(controller).columns.count, 3);
      // And the rest of them arrive once there is a gutter to put them in.
      expect(find.text("Gap"), findsOneWidget);
      expect(find.text("Rule"), findsOneWidget);
    });
  });
}
