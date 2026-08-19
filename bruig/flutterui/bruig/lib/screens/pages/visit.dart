import 'package:bruig/components/interactive_avatar.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/pages.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

/// relativeTime renders a duration the way a reader thinks about it. Kept
/// coarse on purpose: the underlying figure is the last time anything was
/// decrypted from someone, which is evidence they were connected around then,
/// not a timestamp worth reading to the minute.
String relativeTime(DateTime then, {DateTime? now}) {
  var d = (now ?? DateTime.now()).difference(then);
  if (d.isNegative || d.inMinutes < 1) return "just now";
  if (d.inMinutes < 60) return "${d.inMinutes}m ago";
  if (d.inHours < 24) return "${d.inHours}h ago";
  if (d.inDays < 30) return "${d.inDays}d ago";
  if (d.inDays < 365) return "${(d.inDays / 30).floor()}mo ago";
  return "${(d.inDays / 365).floor()}y ago";
}

/// VisitTab lists the contacts whose sites can be opened.
///
/// The status beside each one is only ever the record of an answer. There is
/// no presence in Bison Relay, so nothing here claims a contact is online --
/// see [SiteStatus].
class VisitTab extends StatefulWidget {
  final ClientModel client;
  final PagesModel pages;
  final ResourcesModel resources;
  final VoidCallback onOpened;
  const VisitTab(this.client, this.pages, this.resources, this.onOpened,
      {super.key});

  @override
  State<VisitTab> createState() => _VisitTabState();
}

class _VisitTabState extends State<VisitTab> {
  String filter = "";

  List<ChatModel> get contacts {
    var seen = <String>{};
    var res = <ChatModel>[];
    for (var list in [
      widget.client.activeChats.sorted,
      widget.client.hiddenChats.sorted
    ]) {
      for (var c in list) {
        // Group chats have no resource provider of their own, and the
        // notes pseudo-chat is not a remote user at all.
        if (c.isGC || c.isNotes) continue;
        if (!seen.add(c.id)) continue;
        res.add(c);
      }
    }
    res.sort((a, b) => a.nick.toLowerCase().compareTo(b.nick.toLowerCase()));
    if (filter.isEmpty) return res;
    var f = filter.toLowerCase();
    return res.where((c) => c.nick.toLowerCase().contains(f)).toList();
  }

  void visit(ChatModel chat) async {
    var snackbar = SnackBarModel.of(context);
    try {
      var sess =
          await widget.resources.fetchPage(chat.id, ["index.md"], 0, 0, null, "");
      widget.resources.mostRecent = sess;
      unawaitedRefresh(chat.id);
      widget.onOpened();
    } catch (exception) {
      snackbar.error("Unable to open ${chat.nick}'s site: $exception");
    }
  }

  void unawaitedRefresh(String uid) {
    widget.pages.refreshLastSeen(uid);
  }

  @override
  Widget build(BuildContext context) {
    var list = contacts;
    return ListenableBuilder(
      listenable: widget.pages,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Txt.L("Visit a site"),
          const SizedBox(height: 4),
          const Txt.S(
              "Sites are served by the people who host them, so a site can "
              "only be read while its owner is reachable.",
              color: TextColor.onSurfaceVariant),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: "Filter contacts",
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => filter = v),
          ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            const Expanded(
                child: Center(
                    child: Txt.M("No contacts to visit yet.",
                        color: TextColor.onSurfaceVariant)))
          else
            Expanded(
              child: ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => _ContactRow(
                  chat: list[i],
                  client: widget.client,
                  info: widget.pages.siteInfo(list[i].id),
                  onCheck: () => widget.pages.check(list[i].id),
                  onVisit: () => visit(list[i]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final ChatModel chat;
  final ClientModel client;
  final SiteInfo info;
  final VoidCallback onCheck;
  final VoidCallback onVisit;
  const _ContactRow({
    required this.chat,
    required this.client,
    required this.info,
    required this.onCheck,
    required this.onVisit,
  });

  @override
  Widget build(BuildContext context) {
    var subtitle = info.status.label;
    if (info.lastSeen != null) {
      subtitle = "$subtitle · heard from ${relativeTime(info.lastSeen!)}";
    }

    return ListTile(
      leading: UserAvatarFromID(client, chat.id, disableTooltip: true),
      title: Txt.M(chat.nick),
      subtitle: Txt.S(subtitle, color: TextColor.onSurfaceVariant),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        _StatusChip(info.status),
        const SizedBox(width: 8),
        if (info.status == SiteStatus.unknown ||
            info.status == SiteStatus.noAnswer ||
            info.status == SiteStatus.failed)
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: "Check for a site",
            onPressed: onCheck,
          ),
        IconButton(
          icon: const Icon(Icons.arrow_forward, size: 18),
          tooltip: info.status.visitable
              ? "Open ${chat.nick}'s site"
              : "${chat.nick} answered that they host nothing",
          onPressed: info.status.visitable ? onVisit : null,
        ),
      ]),
      onTap: info.status.visitable ? onVisit : null,
    );
  }
}

class _StatusChip extends StatelessWidget {
  final SiteStatus status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    Color color;
    switch (status) {
      case SiteStatus.hosting:
        color = theme.extraColors.successOnSurface;
        break;
      case SiteStatus.notHosting:
      case SiteStatus.failed:
        color = theme.colors.error;
        break;
      case SiteStatus.checking:
        color = theme.colors.primary;
        break;
      default:
        color = theme.colors.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(status.label,
          style: TextStyle(fontSize: 11, color: color)),
    );
  }
}
