import 'package:bruig/components/text.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// site_rows.dart is how one piece of a site is listed: a page, or a fragment
// its pages share.
//
// Split out of my_site.dart, which had grown to hold the hosting settings,
// the two lists, the rows themselves and a fallback editor. What is here is
// only the drawing of a row and the two marks it carries.

/// One row for both. They differ in three details -- what they are called by,
/// whether there is anything to look at on their own, and the warning the
/// front page carries -- and PageDocument already knows which it is, so two
/// widgets meant two copies of the same publish, unpublish, edit and delete
/// that had to be kept in step by hand.
class SiteRow extends StatelessWidget {
  final PageDocument item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPublish;
  final VoidCallback onUnpublish;

  /// onPreview is null for a fragment. A visitor never opens one on its own,
  /// so there is nothing to preview.
  final VoidCallback? onPreview;

  const SiteRow({
    required this.item,
    required this.onEdit,
    required this.onDelete,
    required this.onPublish,
    required this.onUnpublish,
    this.onPreview,
  });

  /// _subtitle is what to type to reach this, which is not its name: a page
  /// is linked by its slug and a fragment by an --include--. The front page
  /// says what it is instead, since nothing links to it by name.
  Widget _subtitle() {
    if (item.isPartial) {
      return _LinkChip("--include[${pageSlug(item.name)}]--",
          conflict: item.conflict);
    }
    if (!item.isIndex) {
      return _LinkChip(item.link, conflict: item.conflict);
    }
    // A front page that is not published does not take one page down: it
    // makes the whole site answer "no front page" to everyone who asks.
    return Txt.S(
        item.state.live
            ? "Front page — what visitors land on"
            : "Front page — nobody can reach the site without it",
        color: item.state.live
            ? TextColor.onSurfaceVariant
            : TextColor.onErrorContainer);
  }

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var kind = item.isPartial ? "fragment" : "page";

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(item.isPartial
          ? Icons.dashboard_customize_outlined
          : (item.isIndex ? Icons.home_outlined : Icons.description_outlined)),
      title: Row(children: [
        Flexible(child: Txt.M(item.name)),
        const SizedBox(width: 8),
        // Deliberately drawn for every state including the settled one: a
        // row with no marking reads as "no information" rather than
        // "published and current".
        _StateChip(item.state, warn: item.isIndex && !item.state.live),
      ]),
      subtitle: _subtitle(),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (onPreview != null)
          IconButton(
            icon: const Icon(Icons.visibility_outlined, size: 18),
            // Preview fetches from the site, which is the point: it is what
            // a visitor gets, not what the editor holds. So a page that is
            // not published has nothing to show, and says so rather than
            // opening an empty browser.
            tooltip: item.state.live
                ? "Preview ${item.name}"
                : "Publish ${item.name} to preview it",
            onPressed: item.state.live ? onPreview : null,
          ),
        // Publish is offered whenever the served copy is not what the
        // document says -- both "never published" and "written since",
        // which are the two cases where a visitor is not reading this.
        if (item.state != PagePublishState.published)
          IconButton(
            icon: const Icon(Icons.publish_outlined, size: 18),
            tooltip: item.state == PagePublishState.draft
                ? "Publish ${item.name}"
                : "Publish update to ${item.name}",
            color: theme.colors.primary,
            onPressed: onPublish,
          ),
        if (item.state.live)
          IconButton(
            icon: const Icon(Icons.visibility_off_outlined, size: 18),
            tooltip: "Unpublish ${item.name}",
            onPressed: onUnpublish,
          ),
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 18),
          tooltip: "Edit ${item.name}",
          onPressed: onEdit,
        ),
        // No delete for the front page: a site with no front page cannot be
        // visited at all, so taking it down is Unpublish's job, where it can
        // be put back.
        if (!item.isIndex)
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: "Delete $kind ${item.name}",
            onPressed: onDelete,
          ),
      ]),
      onTap: onEdit,
    );
  }
}

/// _LinkChip shows the link a page is reached by, and warns when two pages
/// want the same one.
class _LinkChip extends StatelessWidget {
  final String link;
  final bool conflict;
  const _LinkChip(this.link, {this.conflict = false});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: Text(link,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11,
                fontFamily: "monospace",
                color: theme.colors.onSurfaceVariant)),
      ),
      if (conflict) ...[
        const SizedBox(width: 6),
        Tooltip(
          message: "Another page publishes to this same link, and would "
              "replace this one",
          child: Icon(Icons.warning_amber_rounded,
              size: 13, color: theme.colors.error),
        ),
      ],
    ]);
  }
}

/// _StateChip says where a page stands. Deliberately drawn for every state
/// including the settled one: a row with no marking would read as "no
/// information" rather than "published and current".
class _StateChip extends StatelessWidget {
  final PagePublishState state;
  final bool warn;
  const _StateChip(this.state, {this.warn = false});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    Color color;
    if (warn) {
      color = theme.colors.error;
    } else {
      switch (state) {
        case PagePublishState.published:
          color = theme.extraColors.successOnSurface;
          break;
        case PagePublishState.edited:
          color = theme.colors.primary;
          break;
        case PagePublishState.draft:
          color = theme.colors.onSurfaceVariant;
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(state.label, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}

/// _FragmentsHelp explains what a fragment is for, once, above the list.
class FragmentsHelp extends StatelessWidget {
  const FragmentsHelp();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Txt.S(
            "A piece several pages share — a header, a navigation bar. Put "
            "--include[name]-- in a page and it appears there. It is sent "
            "once and reused, so a bar on twenty pages costs what one page "
            "costs.",
            color: TextColor.onSurfaceVariant),
      );
}
