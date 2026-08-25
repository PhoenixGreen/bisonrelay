import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/config.dart';
import 'package:bruig/models/pages.dart';
import 'package:bruig/screens/pages/site_rows.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:bruig/screens/pages/my_site/site_help.dart';
import 'package:bruig/screens/pages/my_site/site_tabs.dart';

// site_overview.dart is the site as its author opens it: where it is
// served from, the pages in it, the pictures it shows and the fragments its
// pages share.

class SiteOverview extends StatelessWidget {
  final PagesModel pages;
  final void Function(bool) onToggle;
  final VoidCallback onChooseDir;
  final VoidCallback onView;
  final VoidCallback onNew;
  final void Function(String) onEdit;
  final void Function(PageDocument) onDelete;
  final void Function(PageDocument) onPublish;
  final void Function(PageDocument) onUnpublish;

  /// onPreview fetches the page from the site: what a visitor would get.
  final void Function(PageDocument) onPreview;

  /// documents is every page of the site with where it stands -- see
  /// PageDocuments.list.
  final List<PageDocument> documents;

  /// fragments are the shared pieces those pages include.
  final List<PageDocument> fragments;

  /// onNewFragment is null without the writing tools: making one opens the
  /// Writing page, and there is nowhere else to write it.
  final VoidCallback? onNewFragment;
  final void Function(String) onEditFragment;
  final void Function(PageDocument) onDeleteFragment;
  final VoidCallback onAddImage;
  final void Function(LocalAsset) onDeleteImage;

  /// tab is which of the site's jobs is showing, and onTab moves to
  /// another. Held above so a half-written page survives the trip.
  final SiteTabKind tab;
  final ValueChanged<SiteTabKind> onTab;

  const SiteOverview({
    required this.pages,
    required this.documents,
    required this.fragments,
    required this.onNewFragment,
    required this.onEditFragment,
    required this.onDeleteFragment,
    required this.onAddImage,
    required this.onDeleteImage,
    required this.onToggle,
    required this.onChooseDir,
    required this.onView,
    required this.onNew,
    required this.onEdit,
    required this.onDelete,
    required this.onPublish,
    required this.onUnpublish,
    required this.onPreview,
    required this.tab,
    required this.onTab,
  });

  @override
  Widget build(BuildContext context) {
    var cfg = pages.hostConfig;

    if (!pages.hostEditable) {
      return ManagedElsewhere(mode: cfg.mode);
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      // One row, the way the shop's is: the title, what it is doing, and the
      // two things to do about it. This was a heading, a paragraph, a switch
      // and a row of buttons -- four rows of chrome above the thing somebody
      // came here to work on.
      Row(children: [
        const Expanded(child: Txt.L("Site Settings")),
        OutlinedButton.icon(
          onPressed: onChooseDir,
          icon: const Icon(Icons.folder_open, size: 16),
          label: const Text("Change folder"),
        ),
        if (cfg.hostsPages) ...[
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onView,
            icon: const Icon(Icons.visibility_outlined, size: 16),
            label: const Text("View my site"),
          ),
        ],
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: pages.loadingHost ? null : () => onToggle(!cfg.hostsPages),
          child: Text(cfg.hostsPages ? "Turn off" : "Turn on"),
        ),
      ]),
      const SizedBox(height: 4),
      Txt.S(
          cfg.hostsPages
              ? "Serving from ${displayPath(cfg.pagesPath)}"
              : "Not serving anything. Turn it on and the people you are "
                  "connected to can read your pages while you are online.",
          color: TextColor.onSurfaceVariant),
      if (pages.hostError != null) ...[
        const SizedBox(height: 8),
        Txt.S(pages.hostError!, color: TextColor.onErrorContainer),
      ],
      const SizedBox(height: 20),

      const SizedBox(height: 24),
      SiteTabs(
        current: tab,
        onChanged: onTab,
        // Counted here because only the page list knows: a page is behind
        // when what a visitor reads is older than what has been written.
        unpublished:
            documents.where((d) => d.state == PagePublishState.edited).length,
      ),
      const SizedBox(height: 16),
      if (!cfg.hostsPages)
        const Txt.S(
            "This client is hosting a shop and no pages. Switch hosting to "
            "pages, or to both, and they appear here.",
            color: TextColor.onSurfaceVariant)
      else
        switch (tab) {
          SiteTabKind.pages => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Expanded(child: Txt.L("Pages")),
                  if (cfg.hostsPages)
                    ElevatedButton.icon(
                      style: raisedButtonStyle(ThemeNotifier.of(context)),
                      onPressed: onNew,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text("New page"),
                    ),
                ]),
                const SizedBox(height: 8),
                if (!cfg.hostsPages)
                  const Txt.S("Switch hosting on to write pages.",
                      color: TextColor.onSurfaceVariant)
                else if (documents.isEmpty)
                  const Txt.S("No pages yet.",
                      color: TextColor.onSurfaceVariant)
                else
                  ...documents.map((p) => SiteRow(
                        item: p,
                        onEdit: () => onEdit(p.name),
                        onDelete: () => onDelete(p),
                        onPublish: () => onPublish(p),
                        onUnpublish: () => onUnpublish(p),
                        onPreview: () => onPreview(p),
                      )),
              ],
            ),
          SiteTabKind.fragments => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                const FragmentsHelp(),
                Row(children: [
                  const Expanded(child: Txt.L("Shared fragments")),
                  if (onNewFragment != null)
                    OutlinedButton.icon(
                      onPressed: onNewFragment,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text("New fragment"),
                    ),
                ]),
                const SizedBox(height: 8),
                if (fragments.isEmpty)
                  const Txt.S("None yet.", color: TextColor.onSurfaceVariant)
                else
                  ...fragments.map((f) => SiteRow(
                        item: f,
                        onEdit: () => onEditFragment(f.name),
                        onDelete: () => onDeleteFragment(f),
                        onPublish: () => onPublish(f),
                        onUnpublish: () => onUnpublish(f),
                      )),
              ],
            ),
          SiteTabKind.pictures => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Row(children: [
                  const Expanded(child: Txt.L("Pictures")),
                  OutlinedButton.icon(
                    onPressed: onAddImage,
                    icon: const Icon(Icons.add_photo_alternate_outlined,
                        size: 16),
                    label: const Text("Add picture"),
                  ),
                ]),
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 8),
                  child: Txt.S(
                      "Kept as files of their own rather than written into a page, so "
                      "one behind every page of the site is sent once. Adding a "
                      "picture copies the markdown to paste in.",
                      color: TextColor.onSurfaceVariant),
                ),
                if (pages.assets.isEmpty)
                  const Txt.S("None yet.", color: TextColor.onSurfaceVariant)
                else
                  ...pages.assets.map((a) => AssetRow(
                        asset: a,
                        onDelete: () => onDeleteImage(a),
                      )),
                const SizedBox(height: 24),
                const LinkHelp(),
              ],
            ),
        },
    ]);
  }
}
