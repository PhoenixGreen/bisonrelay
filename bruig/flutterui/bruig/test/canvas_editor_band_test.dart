import 'package:bruig/plugin_system/canvas/model/elements/text_element.dart';
import 'support/canvas_app.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_estimate.dart';
import 'dart:math' as math;
import 'package:bruig/storage_manager.dart';
import 'package:bruig/plugin_system/canvas/canvas_preferences.dart';
import 'package:bruig/plugin_system/canvas/canvas_settings.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_geometry.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_guides.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/guides_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/controls.dart';
import 'package:bruig/plugin_system/canvas/ui/screen/canvas_settings_bar.dart';
import 'package:bruig/plugin_system/canvas/ui/element_factory.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/design_panel.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/elements_panel.dart';
import 'package:bruig/components/panel_stack.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/canvas_sidebar.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/layers_panel.dart';
import 'package:flutter/material.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/canvas_panel_helpers.dart';
import 'package:bruig/plugin_system/canvas/model/sidebar_layout.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/sidebar_panels.dart';

// canvas_editor_band_test.dart is the editor round the canvas: the settings
// band and its lines, the canvas settings, framing, the grid and guides, what
// is kept between visits, the clipboard and autosave.
//
// Built as widgets and used, rather than tested through the controller: a
// control drawn but wired to nothing passes every model test there is. So
// these tap the thing and look at the document.

void main() {
  // What the controls do, not where they are folded: every section open.
  setUpAll(() => CanvasSection.openAll = true);
  tearDownAll(() => CanvasSection.openAll = false);

  Future<void> pump(WidgetTester tester, Widget child,
          {CanvasPreferences? prefs}) =>
      pumpCanvasApp(tester, child, size: const Size(1400, 900), prefs: prefs);
  var published = 0;
  setUp(() => published = 0);

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

    // The mixer is opened from the timeline's header now, beside the
    // effects button -- see canvas_timeline_view_test.
    // Ken: on the canvas, the app's logo puts its menu away; while it is
    // away the logo sits at the start of this band, and brings it back.
    testWidgets("with the app's menu put away, its logo here brings it back",
        (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      var prefs = CanvasPreferences();
      await pump(tester, bar(controller), prefs: prefs);
      expect(find.byKey(const ValueKey("canvasShowMenu")), findsNothing,
          reason: "the menu showing: its logo is its own");
      prefs.menuHidden = true;
      await tester.pumpAndSettle();
      var logo = find.byKey(const ValueKey("canvasShowMenu"));
      expect(logo, findsOneWidget);
      // At the far left, and no taller than the band's controls.
      var band = tester.getRect(find.byType(CanvasSettingsBar));
      var at = tester.getRect(logo);
      expect(at.left - band.left, lessThan(20));
      expect(at.height, lessThanOrEqualTo(controlHeight + 1));
      await tester.tap(logo);
      await tester.pumpAndSettle();
      expect(prefs.menuHidden, isFalse);
      expect(find.byKey(const ValueKey("canvasShowMenu")), findsNothing);
    });

    // Ken: the game button makes a game -- the Game panel -- rather than
    // only playing one.
    testWidgets(
        "the game button makes the canvas a game, and stops it being one",
        (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, bar(controller));
      var button = find.byKey(const ValueKey("makeGame"));
      expect(button, findsOneWidget, reason: "there before anything is played");
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(controller.document.game, isTrue);
      controller.gaming = true;
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect((controller.document.game, controller.gaming), (false, false),
          reason: "no longer a game, it is not played either");
    });

    testWidgets("the canvas is put away and brought back from the band",
        (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      var shown = true;
      Widget bar() => CanvasSettingsBar(
            controller: controller,
            onPublish: () {},
            canvasSettingsOpen: false,
            onToggleCanvasSettings: () {},
            guidesOpen: false,
            onToggleGuides: () {},
            timelineOpen: true,
            onToggleTimeline: () {},
            canvasShown: shown,
            onToggleCanvas: () => shown = !shown,
          );
      await pump(tester, bar());
      var button = find.byKey(const ValueKey("toggleCanvas"));
      expect(button, findsOneWidget);
      // Right of the canvas settings, as asked.
      expect(tester.getCenter(button).dx,
          greaterThan(tester.getCenter(find.byIcon(Icons.tune)).dx));
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      await tester.tap(button);
      expect(shown, isFalse);
      await pump(tester, bar());
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    });

    testWidgets("the mixer's button is not on the band", (tester) async {
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
            timelineOpen: false,
            onToggleTimeline: () {},
          ));
      expect(find.byKey(const ValueKey("mixerToggle")), findsNothing);
    });

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

    testWidgets("offers both frames, on one button", (tester) async {
      // The whole canvas and its width were two buttons side by side; they
      // are one now, saying which it is and changing to the other.
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, bar(controller));

      expect(controller.fit, CanvasFit.whole);
      await tester.tap(find.byTooltip(
          "Showing the whole canvas — press to fit to width instead"));
      await tester.pumpAndSettle();
      expect(controller.fit, CanvasFit.width);

      await tester.tap(find.byKey(const ValueKey("canvasFit")));
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

      SidebarLayout? laid;
      await pump(
          tester,
          CanvasSidebar(
            controller: controller,
            layout: const SidebarLayout(current: "design"),
            onLayout: (l) => laid = l,
            bodies: SidebarPanelBodies(
              controller: controller,
              onOpen: (_, __) async {},
              onPublish: (_, __) {},
              onNew: (_, __) async {},
              onChoosePreset: (_, __) {},
            ),
            onCustomise: () {},
          ));
      await tester.tap(find.byTooltip("Hide the sidebar"));
      await tester.pumpAndSettle();
      expect(laid?.mode, SidebarMode.hidden);

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

      await enterValue(tester, field, "800");
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

      // At the far end of the bar, after the Audio settings.
      await tester.ensureVisible(find.byKey(const ValueKey("estimateAs")));
      await tester.pumpAndSettle();
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

      // And anything else through the list's own Custom entry, which then
      // names the rate rather than borrowing a name that would be untrue.
      await tester.tap(find.byKey(const ValueKey("canvasRatePreset")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Custom…").last);
      await tester.pumpAndSettle();
      await enterValue(tester, find.byType(TextField).last, "25");
      await tester.tap(find.text("OK"));
      await tester.pumpAndSettle();
      expect(controller.document.frameRate, 25);
      expect(find.text("Custom · 25"), findsOneWidget);

      // And the custom entry is the one that is set, never a list of every
      // number anybody has ever typed.
      await tester.tap(find.byKey(const ValueKey("canvasRatePreset")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("60 fps").last);
      await tester.pumpAndSettle();
      expect(controller.document.frameRate, 60);
      expect(find.text("Custom · 25"), findsNothing);

      // A rate above the list's highest is still a rate. The document used to
      // clamp at sixty while the box asked for up to a hundred and twenty, so
      // ninety came back as sixty with nothing said.
      await tester.tap(find.byKey(const ValueKey("canvasRatePreset")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Custom…").last);
      await tester.pumpAndSettle();
      await enterValue(tester, find.byType(TextField).last, "90");
      await tester.tap(find.text("OK"));
      await tester.pumpAndSettle();
      expect(controller.document.frameRate, 90);
      expect(find.text("Custom · 90"), findsOneWidget);

      // And past the ceiling is the ceiling, not the old sixty.
      await tester.tap(find.byKey(const ValueKey("canvasRatePreset")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Custom…").last);
      await tester.pumpAndSettle();
      await enterValue(tester, find.byType(TextField).last, "400");
      await tester.tap(find.text("OK"));
      await tester.pumpAndSettle();
      expect(controller.document.frameRate, maxFrameRate);
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
      await tester.tap(find.byKey(const ValueKey("canvasRatePreset")));
      await tester.pumpAndSettle();
      await tester.tap(find.text("12 fps").last);
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

      await enterValue(
          tester, find.byKey(const ValueKey("canvasWidth")), "2560");
      await tester.pump();
      expect(controller.document.size.width, 1280,
          reason: "a resolution: the design is where it was");

      // At the end of the line, after the size and the cost: it is set once
      // and left, rather than sitting between the ratio and the width.
      var scaling = find.byKey(const ValueKey("canvasScalesDesign"));
      // The line scrolls sideways, and it grew when the frame rate joined it.
      await tester.ensureVisible(scaling);
      await tester.pumpAndSettle();
      // Before the estimate, which is the last thing on the bar.
      expect(tester.getRect(scaling).left,
          lessThan(tester.getRect(find.text("ESTIMATED SIZE")).left));

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
      await enterValue(tester, field, "900");
      await tester.pump();
      await enterValue(tester, field, "901");
      await tester.pump();
      controller.endInteraction();

      expect(controller.canUndo, isTrue,
          reason: "a change made through the panel must be undoable at all");
      controller.undo();
      expect(controller.document.size.width, 1280,
          reason: "the whole typed edit is one step, not two");
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

    test("the timeline's cues are shown, then as they were left", () async {
      // And the keyframe row's old setting deleted: the row is gone
      // (keyframing is the Chain's, 2026-11-09).
      SharedPreferences.setMockInitialValues(
          {"flutter.canvasKeyframesShown": false});
      var prefs = CanvasPreferences();
      addTearDown(prefs.dispose);
      expect(prefs.cuesShown, isTrue);
      prefs.cuesShown = false;
      var back = CanvasPreferences();
      addTearDown(back.dispose);
      await back.load();
      expect(back.cuesShown, isFalse);
      var stored = await SharedPreferences.getInstance();
      expect(stored.containsKey("canvasKeyframesShown"), isFalse);

      // Handed to the page's controller as it opens, without a word to
      // anyone listening: that runs while the page is being built.
      var c = CanvasController(const CanvasDocument());
      addTearDown(c.dispose);
      var told = 0;
      c.addListener(() => told++);
      c.restoreShown(cues: back.cuesShown);
      expect(c.cuesShown, isFalse);
      expect(told, 0);
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

      // The switch on the fetching row.
      await tester.tap(find.descendant(
          of: find.ancestor(
              of: find.text("Let a canvas fetch data"),
              matching: find.byType(Row)),
          matching: find.byType(Switch)));
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

  group("the area outside the canvas", () {
    testWidgets("the grid, the guides and the rulers are not in the bar",
        (tester) async {
      // They were, with a preference for whether they were -- but the panel
      // behind the one button is where those three are set up, and a switch
      // up here is the same switch a scroll away from its own settings.
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

      expect(find.byTooltip("Show the grid"), findsNothing);
      expect(find.byTooltip("Show the guides"), findsNothing);
      expect(find.byTooltip("Show the rulers"), findsNothing);
      expect(
          find.byTooltip("Grid, guides, rulers and snapping"), findsOneWidget,
          reason: "the panel that sets them up is still one button");
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

      for (var group in ["RULERS", "GRID", "GUIDES", "SNAPPING", "ALIGN"]) {
        expect(find.text(group), findsOneWidget, reason: group);
      }
      expect(find.text("Show a grid"), findsOneWidget);

      // Rulers first: they are the edge of the page, and everything else here
      // is drawn inside the frame they make.
      expect(tester.getRect(find.text("RULERS")).left,
          lessThan(tester.getRect(find.text("GRID")).left));
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

    // Five groups of switches set up once and then left alone. Shutting the
    // ones you are not using is what turns a strip that scrolls sideways
    // into one that fits.
    //
    // Align rather than one of the others, because a group's open state is
    // remembered in a map that outlives a test: a failure between shutting
    // one and opening it again leaves it shut for the rest of the file, and
    // this is the group nothing else in here looks inside.
    testWidgets("a group can be shut, and its caption is what opens it again",
        (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasGuidesPanel(controller: controller));

      var spread = find.byKey(const ValueKey("spreadAcross"));
      expect(spread, findsOneWidget,
          reason: "a panel that opens with everything put away says nothing");

      // The strip scrolls sideways, so a caption at the far end of it is at
      // coordinates outside the viewport until it is scrolled to.
      await tester.ensureVisible(find.text("ALIGN"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("ALIGN"));
      await tester.pumpAndSettle();
      expect(spread, findsNothing);
      expect(find.text("ALIGN"), findsOneWidget,
          reason: "the caption is what there is left to press");
      expect(find.text("Snap"), findsOneWidget,
          reason: "and the other groups are untouched");

      await tester.ensureVisible(find.text("ALIGN"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("ALIGN"));
      await tester.pumpAndSettle();
      expect(spread, findsOneWidget);
    });

    // It was in the bar and nowhere else, so a canvas saved with the rulers
    // hidden had no way back to them once the bar stopped carrying switches.
    testWidgets("the rulers are shown and hidden from the panel",
        (tester) async {
      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasGuidesPanel(controller: controller));

      expect(controller.document.guides.showRulers, isTrue);
      // The strip scrolls sideways and Rulers is the last group on it, so a
      // tap at its coordinates lands outside the viewport.
      await tester
          .ensureVisible(find.byKey(const ValueKey("guidesShowRulers")));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey("guidesShowRulers")));
      await tester.pumpAndSettle();
      expect(controller.document.guides.showRulers, isFalse);
      expect(controller.document.guides.rulers.top, isFalse,
          reason: "hidden without forgetting which edges were asked for");
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
      var field = find.byKey(const ValueKey("elementW-less"));
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
      // percentage is the zoom. A click opens the reading for typing.
      // A click, once it is plainly not the first of a double-click.
      await tester.tap(find.byKey(const ValueKey("zoomScrub")));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      var field = find.byType(TextField);
      expect(field, findsOneWidget);
      await enterValue(tester, field, "250");
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

      var field = tester.getRect(find.byKey(const ValueKey("zoomScrub")));
      var icon = tester.getRect(find.byKey(const ValueKey("canvasFit")));
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

      // Against the view buttons before it, the rule between them -- the
      // zoom buttons it once sat between are gone, for dragging it.
      var reading = find.byKey(const ValueKey("zoomScrub"));
      double gapNow() =>
          tester.getRect(reading).left -
          tester
              .getRect(find.byTooltip("Show a margin outside the canvas, for "
                  "animating things on and off"))
              .right;

      var gap = gapNow();
      var box = tester.getRect(reading).width;
      expect(gap, lessThan(18),
          reason: "the number sits with the buttons it belongs to: $gap");

      // One width, big enough for the widest reading there is, and the
      // reading is left-aligned inside it: what varies is the empty room
      // after the sign rather than a gap before the number.
      controller.zoom = 0.25;
      await tester.pumpAndSettle();
      expect(tester.getRect(reading).width, box);
      expect((gapNow() - gap).abs(), lessThan(0.5),
          reason: "the box does not move when the number gets shorter");

      controller.zoom = 16;
      await tester.pumpAndSettle();
      var wide = tester.getRect(reading);
      var digits = tester.getRect(find.text("1600%"));
      expect(wide.width, box, reason: "still one width");
      expect(digits.left, greaterThanOrEqualTo(wide.left - 0.5),
          reason: "nothing is cut off the front of it");
      expect(digits.right, lessThanOrEqualTo(wide.right + 0.5),
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

      var field = tester.getRect(find.byKey(const ValueKey("zoomScrub")));
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
      var field = tester.getRect(find.byKey(const ValueKey("zoomScrub")));
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
      expect(find.byType(DragTarget<PanelDrag>).evaluate().length, lessThan(8),
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
      expect(saved.split(",").length, 5,
          reason: "one place fewer than there are panels: $saved");
    });

    testWidgets("the vocal cues keep their place, with one scene or many",
        (tester) async {
      // Where the transition panel was, which came and went with the scenes:
      // the cues are there for one scene as for many, where they were put.
      SharedPreferences.setMockInitialValues({});
      await StorageManager.saveString(
          "canvasDesign.order", "vocalCues,add,layers,scenes,settings");

      var controller = CanvasController(const CanvasDocument());
      addTearDown(controller.dispose);
      await pump(tester, CanvasDesignPanel(controller: controller));
      await tester.pumpAndSettle();

      double topOf(String name) => tester
          .getRect(find.ancestor(
              of: find.text(name),
              matching: find.byType(DragTarget<PanelDrag>)))
          .top;
      expect(topOf("VOCAL CUES"), lessThan(topOf("ADD")));
      controller.addScene();
      await tester.pumpAndSettle();
      expect(topOf("VOCAL CUES"), lessThan(topOf("ADD")),
          reason: "still at the top, where the arrangement left it");
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
}
