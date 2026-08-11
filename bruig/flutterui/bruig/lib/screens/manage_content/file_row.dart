import 'package:file_icon/file_icon.dart';
import 'package:flutter/material.dart';

// ManageFileRow is one file on a Manage page. Downloads and Shared list
// different things about a file but they're the same kind of row, so they
// draw it through here: a type icon, the file name with its actions on the
// right, an optional middle line (the download progress bar, or the path on
// disk), and a summary line underneath.
//
// Actions always sit on the name line, on both pages -- they used to hang
// off whichever line happened to be last, which moved them around as soon
// as a row had one line fewer than its neighbour.
class ManageFileRow extends StatelessWidget {
  final String filename;
  final String title;
  final String subtitle;
  // subtitleTrailing is the tail of the summary line when it needs to be
  // more than text -- the sender's nick on Downloads, which opens their
  // chat. It gives way before the summary does, a nick being arbitrarily
  // long and last on the line.
  final Widget? subtitleTrailing;
  final Widget? middle;
  // footer is drawn under the summary line, inside the same card -- the
  // per-recipient list a shared file expands into.
  final Widget? footer;
  final List<Widget> actions;
  final VoidCallback? onTap;
  // framed draws the row as a card. On by default: it's what makes a list
  // of files read as separate rows rather than one block of text. The Add
  // page turns it off, since its preview already sits inside a card.
  final bool framed;
  const ManageFileRow({
    required this.filename,
    required this.title,
    required this.subtitle,
    this.subtitleTrailing,
    this.middle,
    this.footer,
    this.actions = const [],
    this.onTap,
    this.framed = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    var cs = Theme.of(context).colorScheme;
    var row = Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      // An empty name has no type to draw an icon from, so it keeps the
      // space instead and the rows still line up.
      filename != "" ? FileIcon(filename, size: 48) : const SizedBox(width: 48),
      const SizedBox(width: 12),
      Expanded(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
            if (actions.isNotEmpty) const SizedBox(width: 10),
            ...actions,
          ]),
          if (middle != null) middle!,
          DefaultTextStyle.merge(
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            child: Row(children: [
              Flexible(child: Text(subtitle, overflow: TextOverflow.ellipsis)),
              if (subtitleTrailing != null) ...[
                const SizedBox(width: 5),
                Flexible(child: subtitleTrailing!),
              ],
            ]),
          ),
          if (footer != null) footer!,
        ]),
      ),
    ]);

    Widget content = framed
        ? Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                // outlineVariant (not outline) -- a file-card border should
                // blend into the background like other panel borders, not
                // stand out like a button border.
                border: Border.all(color: cs.outlineVariant)),
            child: row)
        : row;

    return onTap == null ? content : InkWell(onTap: onTap, child: content);
  }
}
