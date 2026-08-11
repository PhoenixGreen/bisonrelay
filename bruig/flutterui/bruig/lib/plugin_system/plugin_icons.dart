import 'package:flutter/material.dart';

// plugin_icons.dart is the fixed set of icons a plugin may name.
//
// A plugin ships no assets and no code the app draws with, so anywhere it
// wants an icon -- its nav item, a button, an "icon" widget -- it picks a name
// from this list rather than supplying an image. One list for all of them: it
// was previously private to plugin_nav.dart, which meant the widget renderer
// either duplicated it or went without icons entirely.
//
// An unrecognized name falls back rather than failing, so a plugin built
// against a later version that added an icon still renders. Names are
// therefore permanent: removing one silently changes what installed plugins
// draw.
const Map<String, IconData> pluginIcons = {
  "article": Icons.article_outlined,
  "attach": Icons.attach_file,
  "bookmark": Icons.bookmark_outline,
  "calendar": Icons.calendar_today_outlined,
  "chat": Icons.forum_outlined,
  "check": Icons.check,
  "cloud": Icons.cloud_outlined,
  "code": Icons.code,
  "copy": Icons.copy_outlined,
  "dashboard": Icons.dashboard_outlined,
  "delete": Icons.delete_outline,
  "download": Icons.download_outlined,
  "edit": Icons.edit_outlined,
  "explore": Icons.explore_outlined,
  "feed": Icons.dynamic_feed_outlined,
  "filter": Icons.filter_list,
  "folder": Icons.folder_outlined,
  "info": Icons.info_outline,
  "link": Icons.link,
  "lock": Icons.lock_outline,
  "music": Icons.music_note_outlined,
  "note": Icons.sticky_note_2_outlined,
  "open": Icons.open_in_new,
  "person": Icons.person_outline,
  "photo": Icons.photo_outlined,
  "refresh": Icons.refresh,
  "rss_feed": Icons.rss_feed,
  "search": Icons.search,
  "send": Icons.send_outlined,
  "settings": Icons.settings_outlined,
  "share": Icons.share_outlined,
  "spellcheck": Icons.spellcheck,
  "star": Icons.star_outline,
  "store": Icons.storefront_outlined,
  "tag": Icons.local_offer_outlined,
  "translate": Icons.translate,
  "upload": Icons.upload_outlined,
  "video": Icons.ondemand_video_outlined,
  "wallet": Icons.account_balance_wallet_outlined,
  "warning": Icons.warning_amber_outlined,
};

/// pluginIcon resolves a plugin-supplied name, falling back to a generic
/// marker for one this build does not know.
IconData pluginIcon(String name) =>
    pluginIcons[name] ?? Icons.extension_outlined;

/// pluginIconOrNull is [pluginIcon] for somewhere an icon is optional: an
/// empty or unknown name draws nothing rather than a puzzle piece, because a
/// button that asked for no icon should not grow one.
IconData? pluginIconOrNull(String name) =>
    name.isEmpty ? null : pluginIcons[name];
