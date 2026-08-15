import 'package:bruig/screens/manage_content/file_notes.dart';
import 'package:bruig/screens/manage_content/file_preview.dart';
import 'package:bruig/screens/manage_content/file_filter_bar.dart';
import 'package:bruig/screens/manage_content/file_row.dart';
import 'package:provider/provider.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'dart:io';

import 'package:bruig/components/confirmation_dialog.dart';
import 'package:bruig/components/copyable.dart';
import 'package:bruig/components/empty_widget.dart';
import 'package:bruig/components/snackbars.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/downloads.dart';
import 'package:bruig/screens/chats.dart';
import 'package:bruig/util.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/util.dart';
import 'package:open_filex/open_filex.dart';

class _ConfirmRemoveToggle extends StatefulWidget {
  final ValueChanged<bool> onToggled;
  const _ConfirmRemoveToggle(this.onToggled);

  @override
  State<_ConfirmRemoveToggle> createState() => _ConfirmRemoveToggleState();
}

class _ConfirmRemoveToggleState extends State<_ConfirmRemoveToggle> {
  int selOpt = 0;

  @override
  Widget build(BuildContext context) {
    return ToggleButtons(
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      constraints: const BoxConstraints(minHeight: 40, minWidth: 100),
      isSelected: [selOpt == 0, selOpt == 1],
      children: [
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            margin: const EdgeInsets.only(right: 5),
            child: const Text("Do not remove file")),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: const Text("Remove file from disk")),
      ],
      onPressed: (int index) {
        setState(() {
          selOpt = index;
          widget.onToggled(selOpt == 1);
        });
      },
    );
  }
}

class _FileDownloadW extends StatefulWidget {
  final FileDownloadModel fd;
  final DownloadsModel downloads;
  final ClientModel client;
  // onPreview opens this file in the page. Called with the path so the
  // list above owns which file is being previewed -- the row itself is
  // rebuilt (and replaced) whenever the download list changes.
  final ValueChanged<String> onPreview;
  // onNotes opens this file's notes panel, owned by the page for the same
  // reason: the panel has to outlive a row that is rebuilt on every
  // download progress tick.
  final ValueChanged<String> onNotes;
  final String? notesFor;
  const _FileDownloadW(this.fd, this.downloads, this.client, this.onPreview,
      this.onNotes, this.notesFor);

  @override
  State<_FileDownloadW> createState() => _FileDownloadWState();
}

class _FileDownloadWState extends State<_FileDownloadW> {
  ClientModel get client => widget.client;
  FileDownloadModel get fd => widget.fd;

  void downloadUpdated() {
    setState(() {});
  }

  void cancelDownload() async {
    confirmationDialog(context, () async {
      try {
        await widget.downloads.cancelDownload(widget.fd.uid, widget.fd.fid);
      } catch (exception) {
        showErrorSnackbar(this, "Unable to cancel download: $exception");
      }
    }, "Cancel Download?", "", "Yes", "No");
  }

  void removeDownload() async {
    bool removeFromDisk = false;

    showConfirmDialog(context, title: "Remove download?", onConfirm: () async {
      try {
        await widget.downloads.cancelDownload(widget.fd.uid, widget.fd.fid);
        if (removeFromDisk && fd.diskPath != "") {
          var f = File(fd.diskPath);
          if (f.existsSync()) {
            f.deleteSync();
          }
        }
      } catch (exception) {
        showErrorSnackbar(this, "Unable to remove download: $exception");
      }
    }, child: Builder(builder: (context) {
      if (fd.diskPath == "") return const Empty();
      return _ConfirmRemoveToggle((v) => removeFromDisk = v);
    }));
  }

  void openFile() {
    OpenFilex.open(fd.diskPath);
  }

  @override
  void initState() {
    super.initState();
    widget.fd.addListener(downloadUpdated);
  }

  @override
  void didUpdateWidget(_FileDownloadW oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.fd.removeListener(downloadUpdated);
    widget.fd.addListener(downloadUpdated);
  }

  @override
  void dispose() {
    widget.fd.removeListener(downloadUpdated);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var progress = widget.fd.progress;
    var diskPath = widget.fd.diskPath;
    var meta = widget.fd.rf.metadata;
    if (widget.fd.diskPath != "") {
      progress = 1;
    }

    String filenameTxt = meta?.filename ??
        "<metadata of file ${widget.fd.fid.substring(0, 8)}... not received yet>";

    var sender = client.getExistingChat(fd.uid);
    String fromTxt = "- from ${sender?.nick ?? fd.uid}";

    // The path line is the File Manager area's to hide. Everything else --
    // icon, name with its actions, summary line -- is the shape both
    // Manage pages share (see ManageFileRow).
    var hidePath = Provider.of<ThemeNotifier>(context)
        .areaStyle(ThemeArea.manageContent)
        .hideFilePaths;
    var downloading = diskPath == "";

    Widget? middle;
    if (downloading) {
      middle = Row(children: [
        Expanded(
          child: LinearProgressIndicator(
              minHeight: 8, value: progress > 1 ? 1 : progress),
        ),
        const SizedBox(width: 10),
        SizedBox(
            width: 65,
            child: Text("${(progress * 100).toStringAsFixed(2)}%",
                textAlign: TextAlign.right)),
      ]);
    } else if (!hidePath) {
      // The path is whatever length it is (the download dir plus a sender
      // nick plus a filename), so it ellipsizes rather than widening the
      // row, and carries the whole thing as a tooltip.
      middle = Copyable(diskPath,
          textOverflow: TextOverflow.ellipsis, tooltip: diskPath);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: ManageFileRow(
        filename: meta?.filename ?? "",
        title: filenameTxt,
        subtitle:
            "${humanReadableSize(meta?.size ?? 0)} - ${formatDCR(atomsToDCR(meta?.cost ?? 0))}",
        subtitleTrailing: InkWell(
            onTap: sender != null
                ? () => ChatsScreen.gotoChatScreenFor(context, sender)
                : null,
            child: Text(fromTxt, overflow: TextOverflow.ellipsis)),
        middle: middle,
        // Same actions, in the same order and the same shapes, as a file on
        // the Shared page: a text Open beside a bin.
        actions: downloading
            ? [
                IconButton(
                  iconSize: 18,
                  icon: const Icon(Icons.cancel),
                  tooltip: "Cancel download",
                  onPressed: cancelDownload,
                ),
              ]
            : [
                // Only for the kinds the app can actually show; everything
                // else has Open and nothing that would open blank.
                if (fileKindOf(diskPath) != FileKind.other)
                  TextButton(
                      onPressed: () => widget.onPreview(diskPath),
                      child: const Text("Preview")),
                FileNotesButton(
                  filePath: diskPath,
                  open: widget.notesFor == diskPath,
                  onPressed: () => widget.onNotes(diskPath),
                ),
                TextButton(onPressed: openFile, child: const Text("Open")),
                IconButton(
                  iconSize: 18,
                  icon: const Icon(Icons.delete),
                  tooltip: "Remove download",
                  onPressed: removeDownload,
                ),
              ],
      ),
    );
  }
}

class DownloadsScreen extends StatefulWidget {
  static String routeName = "/downloads";
  final DownloadsModel downloads;
  final ClientModel client;

  /// previewing/onPreviewing are which file is open in the preview, owned by
  /// the screen around this one.
  ///
  /// Held up there rather than here because opening a preview also takes the
  /// sidebar down (see SecondarySideMenuLayout.collapseSidebar), and that
  /// changes the shape of the tree this screen sits in -- Row(sidebar,
  /// content) becomes content alone. Flutter rebuilds this screen's State
  /// from scratch across that reshape, so a preview remembered *here* was
  /// destroyed by the very act of opening it: the first click collapsed the
  /// sidebar and lost the file, and only the second appeared to work.
  final String? previewing;
  final ValueChanged<String?>? onPreviewing;
  const DownloadsScreen(this.downloads, this.client,
      {this.previewing, this.onPreviewing, super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

// _DownloadSort orders the download list. Sender is here rather than the
// Shared page's Cost because that's the question this list gets asked --
// which of these came from whom.
enum _DownloadSort { name, size, sender }

const Map<_DownloadSort, String> _downloadSortLabels = {
  _DownloadSort.name: "Name",
  _DownloadSort.size: "Size",
  _DownloadSort.sender: "Sender",
};

class _DownloadsScreenState extends State<DownloadsScreen> {
  List<FileDownloadModel> files = [];
  String filter = "";
  _DownloadSort sort = _DownloadSort.name;
  String? get previewing => widget.previewing;

  /// _setPreviewing opens or closes the preview.
  ///
  /// One hop, straight to the owner above: it holds both the file and the
  /// sidebar's state, so a single rebuild up there puts the preview on
  /// screen and takes the sidebar down together, in the same frame.
  void _setPreviewing(String? path) => widget.onPreviewing?.call(path);
  // The file whose notes panel is open at the foot of the page, if any.
  String? notesFor;

  String _name(FileDownloadModel fd) => fd.rf.metadata?.filename ?? "";
  int _size(FileDownloadModel fd) => fd.rf.metadata?.size ?? 0;
  String _sender(FileDownloadModel fd) =>
      widget.client.getExistingChat(fd.uid)?.nick ?? fd.uid;

  void downloadsChanged() {
    setState(() {
      files = widget.downloads.downloads.toList();
    });
  }

  @override
  void initState() {
    super.initState();
    files = widget.downloads.downloads.toList();
    widget.downloads.addListener(downloadsChanged);
  }

  @override
  void didUpdateWidget(DownloadsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.downloads.removeListener(downloadsChanged);
    widget.downloads.addListener(downloadsChanged);
  }

  @override
  void dispose() {
    widget.downloads.removeListener(downloadsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var preview = previewing;
    if (preview != null) {
      return FilePreview(
          filePath: preview, onClose: () => _setPreviewing(null));
    }

    var needle = filter.trim().toLowerCase();
    // Matched against the sender as well as the name: "everything Phoenix
    // sent me" is as natural a search here as a filename is.
    var shown = files.where((fd) {
      if (needle == "") return true;
      return _name(fd).toLowerCase().contains(needle) ||
          _sender(fd).toLowerCase().contains(needle);
    }).toList();
    shown.sort((a, b) => switch (sort) {
          _DownloadSort.name => _name(a).compareTo(_name(b)),
          // Largest first: with size, the interesting end of the list is
          // the top of it.
          _DownloadSort.size => _size(b).compareTo(_size(a)),
          _DownloadSort.sender => _sender(a).compareTo(_sender(b)),
        });
    var totalSize = shown.fold<int>(0, (sum, fd) => sum + _size(fd));

    // No heading: the tab bar to the left already says Downloads, and none
    // of the other Manage pages repeat their own name.
    return Column(children: [
      FileFilterBar<_DownloadSort>(
        hintText: "Search downloads",
        onSearch: (v) => setState(() => filter = v),
        sort: sort,
        sortLabels: _downloadSortLabels,
        onSort: (s) => setState(() => sort = s),
        summary: fileCountSummary(shown.length, humanReadableSize(totalSize)),
      ),
      Expanded(
          child: ListView.builder(
        shrinkWrap: true,
        // The same gutters every content-area page uses; the top comes
        // from the filter bar above.
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: shown.length,
        itemBuilder: (context, index) => _FileDownloadW(
            shown[index],
            widget.downloads,
            widget.client,
            _setPreviewing,
            // Pressing the button of the file already showing closes the
            // panel, so the same button both opens and dismisses it.
            (p) => setState(() => notesFor = notesFor == p ? null : p),
            notesFor),
      )),
      if (notesFor != null)
        FileNotesPanel(
          filePath: notesFor!,
          onClose: () => setState(() => notesFor = null),
        ),
    ]);
  }
}
