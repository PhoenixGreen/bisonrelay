import 'package:bruig/components/text.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// site_help.dart is what the Site Settings screen says when there is
// nothing to change -- hosting handed to something else -- and the note
// explaining how one page links to another.

class ManagedElsewhere extends StatelessWidget {
  final String mode;
  const ManagedElsewhere({required this.mode});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Txt.L("Site Settings"),
        const SizedBox(height: 8),
        Txt.M("Hosting is set to \"$mode\" in the config file."),
        const SizedBox(height: 6),
        const Txt.S(
            "Pages are being served by something outside this app, so they "
            "cannot be edited here. Change the [resources] upstream line in "
            "brclient.conf to host from the app instead.",
            color: TextColor.onSurfaceVariant),
      ]),
    );
  }
}

class LinkHelp extends StatelessWidget {
  const LinkHelp();

  @override
  Widget build(BuildContext context) {
    return const ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Txt.M("Writing pages"),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Txt.S("Pages are markdown. index.md is the front page."),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Txt.S(
              "Link to another of your pages with a plain path: [About](about.md)"),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Txt.S(
              "Link to someone else's site with br://<their id>/index.md — a "
              "reader following it fetches that page from them."),
        ),
      ],
    );
  }
}
