import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_document.dart';
import 'package:bruig/plugin_system/canvas/ui/canvas_controller.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/background_media_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/element_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/procedural_settings.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/panel_kit.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/presets_section.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/plugin_system/canvas/ui/sidebar/stagger_section.dart';
import 'package:bruig/plugin_system/canvas/model/elements/audio_element.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/audio_settings.dart';
import 'package:flutter/material.dart';

// element_settings_pane.dart is the settings of whatever is selected, and the
// collapsible section that carries them.
//
// They were in three places at once -- both sidebar tabs and the band above
// the canvas -- because the things they belong with were in different tabs,
// and the first thing anybody does after adding an element is change it. Now
// that adding, the layer list and these live in one column together, they are
// needed in one place, and this is the body of one of its panels. See
// panel_stack.dart.

/// elementSettingsBody is the settings for the current selection.
///
/// Three cases: something is selected, several things are, or nothing is --
/// and the last one falls back to the canvas's own background rather than to
/// an empty column.
///
/// The background, because this panel should never be empty. Nothing selected
/// is the state a canvas starts in and returns to every time somebody clicks
/// the page, and a panel that empties itself is a panel that keeps taking its
/// room back and giving it away again. The background is also the one thing on
/// a canvas that is always there and always worth changing, so it is the
/// honest answer to "what am I editing" rather than a placeholder.
Widget elementSettingsBody(BuildContext context, CanvasController controller) {
  var selected = controller.selected;

  if (controller.selection.length > 1) {
    return CanvasStaggerSection(controller: controller);
  }

  // A clip picked on the timeline from another canvas -- the master's
  // music seen from a scene -- has its settings here too, written back
  // wherever it lives. Without this, the master's sounds could only be
  // changed with the master open.
  if (selected == null && controller.pickedClip is AudioElement) {
    var clip = controller.pickedClip as AudioElement;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: audioSettings(
        context,
        controller,
        clip,
        (next) {
          controller.beginInteraction();
          controller.replaceAnywhere(next, transient: true);
        },
        controller.beginInteraction,
        controller.endInteraction,
        background: true,
      ),
    );
  }

  if (selected == null) {
    var document = controller.document;
    // The backdrop that is on screen -- see CanvasDocument.editedBackground.
    // Read from anything else, the panel shows the values of a background
    // nobody is looking at and every edit is built from those: a scene given
    // a new colour went on reporting the old one and the next edit undid the
    // last, and with a backdrop on the shared canvas nothing moved at all.
    var showing = document.editedBackground;

    var pattern = ProceduralSettings(
      // In sections, as every element's settings are.
      sections: true,
      rememberAs: "canvasBackground",
      // How long the canvas is, for the button that makes one run of a
      // movement fit it.
      canvasFrames: document.frames,
      // No caption: the panel's header already says these are the
      // background's, and this is what it shows whenever nothing is selected
      // -- so the repetition would be the commonest thing on the panel.
      spec: showing.spec,
      onBegin: controller.beginInteraction,
      onCommit: controller.endInteraction,
      // The pattern back to its start, and nothing else: resetting a
      // pattern is not a reason to lose the music or the photograph laid
      // over it.
      onReset: () => controller.setBackground(CanvasBackground(
          picture: showing.picture,
          imageAssetId: showing.imageAssetId,
          imageFit: showing.imageFit,
          video: showing.video,
          sound: showing.sound)),
      onChanged: (spec) {
        controller.beginInteraction();
        controller.setBackground(showing.copyWith(spec: spec), transient: true);
      },
    );

    // And what the background carries over the pattern: a picture, a video,
    // a sound.
    var settings = CanvasSections(
      key: const ValueKey("backgroundSections"),
      children: [
        pattern,
        ...backgroundMediaSettings(context, controller),
        // The designs saved from here or from a background element, to start
        // from or to keep this one -- last, as on every element.
        CanvasSection(
          key: const ValueKey("elementSection-presets"),
          icon: Icons.bookmarks_outlined,
          title: "Presets",
          summary: "Backgrounds to start from",
          remember: "canvasBackground.presets",
          children: [
            backgroundPresetsSection(context, controller, showing.spec,
                onUse: (spec) {
              controller.beginInteraction();
              controller.setBackground(showing.copyWith(spec: spec));
              controller.endInteraction();
            }),
          ],
        ),
      ],
    );

    // Whose backdrop this is, where it is not this canvas's. One on the
    // shared canvas is drawn in front of every scene's, so these settings are
    // the master's and changing them changes every scene -- which is worth
    // saying before somebody does it, and worth a great deal more than the
    // silence it replaces.
    if (!document.sharedBackdrop) return settings;
    return Column(
      key: const ValueKey("sharedBackdropNote"),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Txt.S(
            "This is the shared canvas's backdrop, so it is behind every "
            "scene and these settings change all of them.",
            color: TextColor.onSurfaceVariant,
          ),
        ),
        settings,
      ],
    );
  }

  // No heading naming the element. The panel's own header says what is being
  // edited -- "Shape settings" -- and a heading under it saying "Shape" was
  // the same word twice, three lines apart, above a group also called Shape.
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: elementSettings(context, controller, selected),
  );
}

/// elementSettingsTitle is what the panel holding these is called.
///
/// It follows the selection rather than always saying "Element settings": the
/// panel is the only thing naming what is being edited now that the settings
/// themselves do not, and "Image settings" is a more useful heading than a
/// word that is true of every element there is.
String elementSettingsTitle(CanvasController controller) {
  if (controller.selection.length > 1) return "Element settings";
  var selected = controller.selected;
  // A sound picked on the timeline from another canvas is what is shown --
  // see elementSettingsBody.
  if (selected == null && controller.pickedClip is AudioElement) {
    return "Audio settings";
  }
  if (selected == null) return "Background settings";
  return "${selected.kind.label} settings";
}

/// elementSettingsHint is what this section is for, in one sentence, for the
/// question mark beside its name.
const String elementSettingsHint =
    "The settings of whatever is selected. With nothing selected these are "
    "the canvas's own background, which is what the whole page is drawn on.";
