import 'package:bruig/plugin_system/canvas/ui/settings/parallax_settings.dart';
import 'package:bruig/plugin_system/canvas/presets/parallax_looks.dart';
import 'package:bruig/plugin_system/canvas/model/backdrop.dart';
import 'package:bruig/plugin_system/canvas/model/elements/parallax_element.dart';
import 'package:bruig/plugin_system/canvas/model/canvas_element.dart';
import 'package:bruig/plugin_system/canvas/ui/settings/backdrop_settings.dart';
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

// element_settings_pane.dart is the settings of whatever is selected: the body
// of one of the Design column's panels (see design_panel.dart).

/// elementSettingsBody is the settings for the current selection: one
/// element, several, or none. With none it shows the canvas's background, so
/// the panel is never empty in the state a canvas starts in and returns to on
/// every click on the page.
Widget elementSettingsBody(BuildContext context, CanvasController controller) {
  var selected = controller.selected;

  if (controller.selection.length > 1) {
    return CanvasStaggerSection(controller: controller);
  }

  // A clip picked on the timeline from another canvas (the master's
  // music seen from a scene) is edited here too, written back wherever
  // it lives.
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
    // The backdrop on screen (see CanvasDocument.editedBackground). Read
    // from anything else, the panel shows a background nobody is looking
    // at and each edit is built from the wrong values.
    var showing = document.editedBackground;

    var picker = backdropKindPicker(showing.backdrop, (kind) {
      controller.beginInteraction();
      controller.setBackground(showing.copyWith(
          backdrop: kind,
          stage: showing.stage ?? defaultBackgroundStage,
          parallax: kind == BackdropKind.parallax
              ? showing.parallax ??
                  parallaxLooks.first.scenery
                          .rebase(const ElementBase(id: backgroundParallaxId))
                      as ParallaxElement
              : null));
      controller.endInteraction();
    });
    // A stage in the pattern's place: its camera, its set, its light.
    var stage = showing.isStage
        ? stageBackdropSettings(
            context, controller, showing.stageOn(document.size.rect),
            picker: picker, write: (s) {
            controller.beginInteraction();
            controller.putStage(s, transient: true);
          },
            begin: controller.beginInteraction,
            commit: controller.endInteraction,
            rememberAs: "canvasBackground")
        : showing.isParallax
            ? [
                ParallaxSettings(
                  key: const ValueKey("parallaxSettings-background"),
                  controller: controller,
                  scenery: showing.parallaxOn(document.size.rect),
                  picker: picker,
                  write: (p) {
                    controller.beginInteraction();
                    controller.putBackdrop(p, transient: true);
                  },
                  begin: controller.beginInteraction,
                  commit: controller.endInteraction,
                  rememberAs: "canvasBackground",
                ),
              ]
            : null;

    var pattern = ProceduralSettings(
      kindPicker: picker,
      sections: true,
      rememberAs: "canvasBackground",
      // For the button that makes one run of a movement fit the canvas.
      canvasFrames: document.frames,
      // No caption: the panel's header already says these are the
      // background's.
      spec: showing.spec,
      onBegin: controller.beginInteraction,
      onCommit: controller.endInteraction,
      // The pattern back to its start only, keeping any music or picture
      // laid over it.
      onReset: () => controller.setBackground(CanvasBackground(
          picture: showing.picture,
          imageAssetId: showing.imageAssetId,
          imageFit: showing.imageFit,
          video: showing.video,
          sound: showing.sound,
          stage: showing.stage)),
      onChanged: (spec) {
        controller.beginInteraction();
        controller.setBackground(showing.copyWith(spec: spec), transient: true);
      },
    );

    // What the background carries over the pattern: a picture, a video,
    // a sound.
    var settings = CanvasSections(
      key: const ValueKey("backgroundSections"),
      children: [
        ...?stage,
        if (stage == null) pattern,
        ...backgroundMediaSettings(context, controller),
        // Saved background designs, last as on every element; patterns only,
        // so not while the background is a stage.
        if (stage == null)
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

    // A backdrop on the shared canvas is drawn in front of every scene's,
    // so these settings are the master's and change every scene: say so.
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

  // No heading naming the element: the panel's header already does.
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: elementSettings(context, controller, selected),
  );
}

/// elementSettingsTitle is the name of the panel holding these, following
/// the selection ("Image settings"), since the settings themselves do not
/// name what is being edited.
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
