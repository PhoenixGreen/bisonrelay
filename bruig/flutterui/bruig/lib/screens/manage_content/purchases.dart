import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/downloads.dart';
import 'package:bruig/models/purchases.dart';
import 'package:bruig/models/uistate.dart';
import 'package:bruig/screens/manage_content/file_preview.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/material.dart';

// purchases.dart is what somebody has bought, gathered out of what they were
// sent.
//
// Apart from Downloads because it answers a different question. Downloads is
// everything anybody has ever sent you, newest first; this is the handful of
// things you paid for, one row each however many times a seller has sent
// them, and it says when one of them has been sent again.

class PurchasesScreen extends StatefulWidget {
  final DownloadsModel downloads;
  final ClientModel client;
  final String? previewing;
  final void Function(String?)? onPreviewing;

  /// nav keeps the reading position and zoom, so they outlive this widget
  /// being rebuilt.
  final ManageContentNavModel nav;
  const PurchasesScreen(
    this.downloads,
    this.client, {
    super.key,
    required this.nav,
    this.previewing,
    this.onPreviewing,
  });

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  List<FileDownloadModel> files = [];

  @override
  void initState() {
    super.initState();
    files = widget.downloads.downloads.toList();
    widget.downloads.addListener(_changed);
  }

  @override
  void didUpdateWidget(PurchasesScreen old) {
    super.didUpdateWidget(old);
    old.downloads.removeListener(_changed);
    widget.downloads.addListener(_changed);
  }

  @override
  void dispose() {
    widget.downloads.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {
        files = widget.downloads.downloads.toList();
      });

  /// _pathOf is where a copy of a product landed on this machine.
  ///
  /// Matched on the file's hash, which is what identifies a copy: a product
  /// sent twice is two downloads, and the one being opened has to be the
  /// version this row is about.
  String? _pathOf(String hash) {
    for (var f in files) {
      if (f.rf.metadata?.hash == hash && f.diskPath.isNotEmpty) {
        return f.diskPath;
      }
    }
    return null;
  }

  String _sellerName(String uid) =>
      widget.client.getExistingChat(uid)?.nick ?? uid;

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var purchases = purchasesOf([
      for (var f in files) (seller: f.uid, metadata: f.rf.metadata),
    ]);

    if (widget.previewing != null) {
      return FilePreview(
        filePath: widget.previewing!,
        onClose: () => widget.onPreviewing?.call(null),
        nav: widget.nav,
      );
    }

    if (purchases.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Txt.M(
              "Nothing yet. A file a shop sends when an order is paid for "
              "turns up here, as well as in Downloads.",
              textAlign: TextAlign.center),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: purchases.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        var p = purchases[i];
        var path = _pathOf(p.latest.hash);
        return ListTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: Row(children: [
            Flexible(child: Txt.M(p.title)),
            if (p.hasUpdate) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colors.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Txt.S("Updated"),
              ),
            ],
          ]),
          subtitle: Txt.S(
              "${_sellerName(p.seller)}"
              "${p.hasUpdate ? " · ${p.copies.length} versions sent" : ""}",
              color: TextColor.onSurfaceVariant),
          // Disabled rather than absent when the file is not on disk: a row
          // that is here at all is something bought, and a missing button
          // would read as the purchase itself being wrong.
          trailing: path == null
              ? const Txt.S("Not downloaded")
              : IconButton(
                  icon: const Icon(Icons.menu_book_outlined, size: 20),
                  tooltip: "Read ${p.title}",
                  onPressed: () => widget.onPreviewing?.call(path),
                ),
          onTap: path == null ? null : () => widget.onPreviewing?.call(path),
        );
      },
    );
  }
}
