import 'package:bruig/theming_system/theming_areas_section.dart';
import 'package:flutter/material.dart';

// theming_area_filemanager.dart is the "File Manager" area: the Manage
// screen's own pages (Add, Shared, Downloads).
List<Widget> fileManagerAreaEditor(AreaEditorContext ctx) => [
      ctx.toggle(
        "Hide file locations",
        subtitle: "Drops the full path from each row on Manage > Downloads, "
            "leaving the file name above its size and sender",
        value: ctx.style.hideFilePaths,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(hideFilePaths: v)),
      ),
    ];
