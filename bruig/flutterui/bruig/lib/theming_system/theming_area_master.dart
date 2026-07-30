import 'package:bruig/theming_system/theming_areas_section.dart';
import 'package:flutter/material.dart';

// theming_area_master.dart is the "Master" area's own settings: the ones
// that apply to the whole app rather than to any one region of it. Its
// background/border/spacing come from the shared block, like every other
// framed area.
List<Widget> masterAreaEditor(AreaEditorContext ctx) => [
      ctx.toggle(
        "Hide hover text",
        subtitle: "Drops the labels that pop up over avatars, images and "
            "icons -- the ones naming a control you already recognise",
        value: ctx.style.hideTooltips,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(hideTooltips: v)),
      ),
      ctx.toggle(
        "Hide help text",
        subtitle: "The separate few that explain something written nowhere "
            "else, like the help icon beside a content cost",
        value: ctx.style.hideHelpTooltips,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(hideHelpTooltips: v)),
      ),
    ];
