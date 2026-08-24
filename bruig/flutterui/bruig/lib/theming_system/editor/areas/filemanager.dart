import 'package:bruig/theming_system/theme_editor.dart';
import 'package:flutter/material.dart';

// filemanager.dart is the "File Manager" area: the Manage
// screen's own pages (Add, Shared, Downloads).
List<Widget> fileManagerAreaEditor(AreaEditorContext ctx) => [
      ctx.toggle(
        "Hide file locations",
        subtitle: "Drops the full path from each row on Manage > Downloads, "
            "leaving the file name above its size and sender",
        value: ctx.style.hideFilePaths,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(hideFilePaths: v)),
      ),
      ctx.toggle(
        "Open Markdown in the reader",
        subtitle: "Shows a .md file set the way it was written, rather than "
            "as its own source. The source is still a press away, and this "
            "does not stop anyone reading or keeping the file",
        value: ctx.style.readMarkdown,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(readMarkdown: v)),
      ),
    ];
