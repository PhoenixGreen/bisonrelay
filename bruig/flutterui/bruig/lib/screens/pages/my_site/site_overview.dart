import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/config.dart';
import 'package:bruig/models/pages.dart';
import 'package:bruig/components/pages/add_picture_dialog.dart';
import 'package:bruig/screens/pages/page_editor.dart';
import 'package:bruig/screens/pages/site_rows.dart';
import 'package:bruig/models/menus.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:bruig/screens/pages/my_site/shop_frame_fields.dart';
import 'package:bruig/screens/pages/my_site/site_help.dart';

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
  });

  @override
  Widget build(BuildContext context) {
    var cfg = pages.hostConfig;

    if (!pages.hostEditable) {
      return ManagedElsewhere(mode: cfg.mode);
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      const Txt.L("Site Settings"),
      const SizedBox(height: 4),
      const Txt.S(
          "Your site is served from this client, to people you are already "
          "connected to, while you are online. Nothing is uploaded anywhere.",
          color: TextColor.onSurfaceVariant),
      const SizedBox(height: 16),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Txt.M("Host a site"),
        subtitle: Txt.S(
            cfg.hostsPages
                ? "Serving from ${displayPath(cfg.pagesPath)}"
                : "Not serving anything",
            color: TextColor.onSurfaceVariant),
        value: cfg.hostsPages,
        onChanged: pages.loadingHost ? null : onToggle,
      ),
      if (pages.hostError != null) ...[
        const SizedBox(height: 8),
        Txt.S(pages.hostError!, color: TextColor.onErrorContainer),
      ],
      const SizedBox(height: 8),
      Row(children: [
        OutlinedButton.icon(
          onPressed: onChooseDir,
          icon: const Icon(Icons.folder_open, size: 16),
          label: const Text("Change folder"),
        ),
        const SizedBox(width: 8),
        if (cfg.hostsPages)
          OutlinedButton.icon(
            onPressed: onView,
            icon: const Icon(Icons.visibility_outlined, size: 16),
            label: const Text("View my site"),
          ),
      ]),
      if (cfg.hostsStore && cfg.hostsPages) ...[
        const SizedBox(height: 24),
        ShopFrameFields(pages: pages),
      ],
      const SizedBox(height: 24),
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
        const Txt.S("No pages yet.", color: TextColor.onSurfaceVariant)
      else
        ...documents.map((p) => SiteRow(
              item: p,
              onEdit: () => onEdit(p.name),
              onDelete: () => onDelete(p),
              onPublish: () => onPublish(p),
              onUnpublish: () => onUnpublish(p),
              onPreview: () => onPreview(p),
            )),
      if (cfg.hostsPages) ...[
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
        const SizedBox(height: 24),
        Row(children: [
          const Expanded(child: Txt.L("Pictures")),
          OutlinedButton.icon(
            onPressed: onAddImage,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
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
    ]);
  }
}

/// _SiteRow is one thing the site is made of: a page, or a fragment its
/// pages share.
///

/// _FragmentRow is one shared fragment.
///
/// Deliberately plainer than a page's row: a fragment has no front-page
/// warning, and no preview -- a visitor never opens one, so there is nothing
/// to look at on its own.

/// ShopFrameFields names the two fragments the shop wears.
///
/// Two names rather than a switch, because a shop and a site are framed the
/// same way and a writer already has both fragments: the banner at the top
/// and whatever runs along the bottom. Naming them here means changing the
/// banner changes the shop with it -- a shop restyled separately is a shop
/// that ends up looking like a different website.
///
/// Only shown with both hosted. A shop on its own has no site to take them
/// from, and offering the fields would be offering something that could not
/// work.
