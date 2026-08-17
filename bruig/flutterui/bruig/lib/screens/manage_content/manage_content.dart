import 'package:bruig/components/inputs.dart';
import 'package:bruig/plugin_system/writing_tools/writing_tools.dart';
import 'package:bruig/screens/manage_content/file_filter_bar.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/services.dart';
import 'package:bruig/components/snackbars.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:bruig/screens/manage_content/file_row.dart';
import 'package:bruig/util.dart';
import 'package:golib_plugin/util.dart';
import 'package:open_filex/open_filex.dart';
import 'dart:async';
import 'package:bruig/components/dcr_input.dart';
import 'package:bruig/components/interactive_avatar.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/components/usersearch/user_search_model.dart';
import 'package:bruig/components/usersearch/user_search_panel.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/components/tooltips.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

typedef RemoveContentCB = Future<void> Function(String fid, String? uid);

// contentEmbedLink is the markdown the app's own renderer turns into a
// download link for a shared file (see EmbedInlineSyntax in
// components/md_elements.dart) -- the same form a post uses to link to
// content, sent as a plain message.
String contentEmbedLink(SharedFileAndShares file) =>
    "--embed[download=${file.sf.fid},alt=${Uri.encodeComponent(file.sf.filename)}]--";

class SharedContentFile extends StatefulWidget {
  final SharedFileAndShares file;
  final RemoveContentCB removeContentCB;
  final ClientModel client;
  // onTap is only set when the screen was opened to pick a file for
  // something else (see ManageContentScreenArgs).
  final VoidCallback? onTap;
  const SharedContentFile(
      this.file, this.removeContentCB, this.client, this.onTap,
      {super.key});

  @override
  State<SharedContentFile> createState() => _SharedContentFileState();
}

class _SharedContentFileState extends State<SharedContentFile> {
  bool loading = false;
  bool expanded = false;

  // Stops sharing the file entirely: the global share if it has one, and
  // every individual share besides. The bin previously only appeared on
  // globally-shared files and did nothing for the rest, so a file shared
  // with one person couldn't be unshared from here at all.
  removeContent(BuildContext context) async {
    var snackbar = SnackBarModel.of(context);
    var file = widget.file;
    setState(() => loading = true);
    try {
      if (file.global) await widget.removeContentCB(file.sf.fid, null);
      for (var uid in file.shares) {
        await widget.removeContentCB(file.sf.fid, uid);
      }
    } catch (exception) {
      snackbar.error('Unable to unshare content: $exception');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // Unshares from one recipient, leaving the file shared with everyone
  // else it was shared with.
  removeShare(BuildContext context, String uid) async {
    var snackbar = SnackBarModel.of(context);
    setState(() => loading = true);
    try {
      await widget.removeContentCB(widget.file.sf.fid, uid);
    } catch (exception) {
      snackbar.error('Unable to unshare content: $exception');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: contentEmbedLink(widget.file)));
    showSuccessSnackbar(context, "Copied link to ${widget.file.sf.filename}");
  }

  // Sends the download link as a message to whichever chats are picked.
  // The recipients don't gain access by being sent the link -- the file
  // still has to be shared with them (or globally) for the download to
  // work, which is what the share list above the button is for.
  void sendLink(BuildContext context) async {
    var snackbar = SnackBarModel.of(context);
    var chats = await showSendToChatDialog(context, widget.client);
    if (chats == null || chats.isEmpty) return;
    var link = contentEmbedLink(widget.file);
    try {
      for (var chat in chats) {
        await chat.sendMsg(link);
      }
      snackbar.success(chats.length == 1
          ? "Sent link to ${chats.first.nick}"
          : "Sent link to ${chats.length} chats");
    } catch (exception) {
      snackbar.error('Unable to send link: $exception');
    }
  }

  String get sharedWith {
    var file = widget.file;
    if (file.global) return "shared with everyone";
    if (file.shares.isEmpty) return "not shared";
    var nicks = file.shares
        .map((uid) => widget.client.getExistingChat(uid)?.nick ?? uid)
        .join(", ");
    return "shared with $nicks";
  }

  @override
  Widget build(BuildContext context) {
    var file = widget.file;
    // The client records where a file was read from when it was shared
    // (clientdb.SharedFileAndShares.DiskPath), but a file shared by an
    // older version or on another machine has none -- Open is disabled
    // then, rather than missing, so every row keeps the same shape.
    var diskPath = file.diskPath;
    var canOpen = diskPath != "" && File(diskPath).existsSync();
    var cs = Theme.of(context).colorScheme;

    return ManageFileRow(
      onTap: widget.onTap,
      filename: file.sf.filename,
      title: file.sf.filename,
      subtitle:
          "${humanReadableSize(file.size)} - ${formatDCR(atomsToDCR(file.cost))} - $sharedWith",
      middle: file.descr != ""
          ? Text(file.descr,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))
          : null,
      // Individual shares are collapsed by default: a file shared with a
      // dozen people would otherwise bury every other row on the page.
      footer: expanded && file.shares.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                  children: file.shares.map((uid) {
                var nick = widget.client.getExistingChat(uid)?.nick ?? uid;
                return Row(children: [
                  const SizedBox(width: 8),
                  Icon(Icons.person_outline,
                      size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(nick,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5, color: cs.onSurfaceVariant))),
                  IconButton(
                    iconSize: 16,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: "Stop sharing with $nick",
                    onPressed: loading ? null : () => removeShare(context, uid),
                  ),
                ]);
              }).toList()),
            )
          : null,
      actions: [
        if (file.shares.isNotEmpty)
          IconButton(
            iconSize: 18,
            icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            tooltip: expanded ? "Hide recipients" : "Show recipients",
            onPressed: () => setState(() => expanded = !expanded),
          ),
        IconButton(
          iconSize: 18,
          icon: const Icon(Icons.forward_to_inbox),
          tooltip: "Send link to a chat",
          onPressed: loading ? null : () => sendLink(context),
        ),
        IconButton(
          iconSize: 18,
          icon: const Icon(Icons.link),
          tooltip: "Copy link",
          onPressed: () => copyLink(context),
        ),
        TextButton(
          onPressed: canOpen ? () => OpenFilex.open(diskPath) : null,
          child: Text("Open",
              style: TextStyle(
                  color: canOpen ? null : Theme.of(context).disabledColor)),
        ),
        IconButton(
          iconSize: 18,
          icon: Icon(loading ? Icons.hourglass_bottom : Icons.delete),
          tooltip: "Stop sharing",
          onPressed: loading ? null : () => removeContent(context),
        ),
      ],
    );
  }
}

// showSendToChatDialog picks the chats to send a content link to, through
// the same user search panel the rest of the app uses. Returns null when
// dismissed.
Future<List<ChatModel>?> showSendToChatDialog(
    BuildContext context, ClientModel client) async {
  var userSel = UserSelectionModel(allowMultiple: true);
  return showDialog<List<ChatModel>>(
    context: context,
    builder: (context) => Dialog(
      child: SizedBox(
        width: 500,
        height: 500,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: UserSearchPanel(
            client,
            userSelModel: userSel,
            targets: UserSearchPanelTargets.usersAndGCs,
            searchInputHintText: "Search for users and groups",
            confirmLabel: "Send link",
            onCancel: () => Navigator.of(context).pop(),
            onConfirm: () => Navigator.of(context).pop(userSel.selected),
          ),
        ),
      ),
    ),
  );
}

typedef FileSelectedCB = Function(SharedFile);

// _SharedSort is how the shared file list is ordered. Name is the default
// because it's the only one that doesn't change under you as files are
// added.
enum _SharedSort { name, size, cost }

const Map<_SharedSort, String> _sharedSortLabels = {
  _SharedSort.name: "Name",
  _SharedSort.size: "Size",
  _SharedSort.cost: "Cost",
};

class SharedContent extends StatefulWidget {
  final List<SharedFileAndShares> files;
  final RemoveContentCB removeContent;
  final ClientModel client;
  final FileSelectedCB? fileSelectedCB;
  const SharedContent(
      this.client, this.files, this.removeContent, this.fileSelectedCB,
      {super.key});

  @override
  State<SharedContent> createState() => _SharedContentState();
}

class _SharedContentState extends State<SharedContent> {
  String filter = "";
  _SharedSort sort = _SharedSort.name;

  @override
  Widget build(BuildContext context) {
    var needle = filter.trim().toLowerCase();
    var files = widget.files.where((f) {
      if (needle == "") return true;
      // Matched against the description too: it's the only other thing
      // written about a file that the sharer chose themselves.
      return f.sf.filename.toLowerCase().contains(needle) ||
          f.descr.toLowerCase().contains(needle);
    }).toList();
    files.sort((a, b) => switch (sort) {
          _SharedSort.name => a.sf.filename.compareTo(b.sf.filename),
          // Largest and dearest first: with size and cost, the interesting
          // end of the list is the top of it.
          _SharedSort.size => b.size.compareTo(a.size),
          _SharedSort.cost => b.cost.compareTo(a.cost),
        });
    var totalSize = files.fold<int>(0, (sum, f) => sum + f.size);

    return NoteTargetScope(
      target: NoteTarget.page("/manage/shared", "Shared"),
      child: Column(children: [
        FileFilterBar<_SharedSort>(
          hintText: "Search shared files",
          onSearch: (v) => setState(() => filter = v),
          sort: sort,
          sortLabels: _sharedSortLabels,
          onSort: (s) => setState(() => sort = s),
          summary: fileCountSummary(files.length, humanReadableSize(totalSize)),
        ),
        Expanded(
          child: ListView.builder(
            // The same gutters every content-area page uses; the top comes
            // from the filter bar above.
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: files.length,
            itemBuilder: (BuildContext context, int index) {
              // The row draws its own card (see ManageFileRow), so both
              // Manage pages frame their files identically.
              return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: SharedContentFile(
                      files[index],
                      widget.removeContent,
                      widget.client,
                      widget.fileSelectedCB != null
                          ? () => widget.fileSelectedCB!(files[index].sf)
                          : null));
            },
          ),
        ),
      ]),
    );
  }
}

typedef AddContentCB = Future<void> Function(
    String filename, String uid, double cost, String descr);

class AddContentPanel extends StatefulWidget {
  final AddContentCB addContentCB;
  const AddContentPanel(this.addContentCB, {super.key});

  @override
  State<AddContentPanel> createState() => _AddContentPanelState();
}

class _AddContentPanelState extends State<AddContentPanel> {
  bool loading = false;
  // The files queued to share. A list rather than one path: picking (or
  // dropping) several at once and sharing them on the same terms is the
  // normal case, and one at a time meant re-entering the cost and the
  // recipient for every file.
  List<String> picked = [];
  AmountEditingController costCtrl = AmountEditingController();
  TextEditingController descrCtrl = TextEditingController();
  bool dragging = false;
  ChatModel? limitToUser;
  Timer? _debounce;
  bool selectingTargetUser = false;
  UserSelectionModel userSel = UserSelectionModel();

  @override
  dispose() {
    _debounce?.cancel();
    descrCtrl.dispose();
    super.dispose();
  }

  void pickFile() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      var filePickRes =
          await FilePicker.platform.pickFiles(allowMultiple: true);
      if (filePickRes == null) return;
      addPaths(filePickRes.files
          .map((f) => f.path?.trim() ?? "")
          .where((p) => p != ""));
    });
  }

  // Adds to the queue, ignoring anything already in it -- picking the same
  // file twice would try to share it twice and fail the second time.
  void addPaths(Iterable<String> paths) {
    setState(() {
      for (var p in paths) {
        if (!picked.contains(p)) picked.add(p);
      }
    });
  }

  void addContent() async {
    var snackbar = SnackBarModel.of(context);
    if (picked.isEmpty) return;
    double cost = 0;
    if (costCtrl.text.isNotEmpty) {
      cost = double.parse(costCtrl.text);
    }
    var uid = limitToUser?.id ?? "";
    var descr = descrCtrl.text.trim();
    setState(() => loading = true);
    // One at a time, and a failure part-way through keeps whatever hasn't
    // been shared yet in the queue rather than clearing the lot -- one bad
    // file shouldn't lose the rest of the selection.
    var remaining = List<String>.from(picked);
    try {
      for (var fname in picked) {
        await widget.addContentCB(fname, uid, cost, descr);
        remaining.remove(fname);
      }
      snackbar.success(picked.length == 1
          ? "Shared ${path.basename(picked.first)}"
          : "Shared ${picked.length} files");
      setState(() {
        picked = [];
        costCtrl.clear();
        descrCtrl.clear();
        limitToUser = null;
        userSel.clear();
      });
    } catch (exception) {
      snackbar.error('Unable to share content: $exception');
      setState(() => picked = remaining);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget buildSelectTargetUser(BuildContext context) {
    var client = ClientModel.of(context, listen: false);
    return Container(
      padding: const EdgeInsets.all(10),
      child: Column(children: [
        Expanded(
            child: UserSearchPanel(
          client,
          userSelModel: userSel,
          targets: UserSearchPanelTargets.users,
          searchInputHintText: "Search for users",
          confirmLabel: "Select as target user",
          onCancel: () {
            setState(() => selectingTargetUser = false);
          },
          onConfirm: () {
            setState(() {
              limitToUser =
                  userSel.selected.isNotEmpty ? userSel.selected[0] : null;
              selectingTargetUser = false;
            });
          },
        ))
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (selectingTargetUser) {
      return buildSelectTargetUser(context);
    }

    var cs = Theme.of(context).colorScheme;

    return DropTarget(
      // Desktop drag-and-drop. Directories arrive as paths too, and the
      // client can only share files, so anything that isn't a readable
      // file is dropped on the floor rather than queued to fail later.
      onDragDone: (detail) => addPaths(
          detail.files.map((f) => f.path).where((p) => File(p).existsSync())),
      onDragEntered: (_) => setState(() => dragging = true),
      onDragExited: (_) => setState(() => dragging = false),
      child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            _card(
              cs,
              highlight: dragging,
              [
                Row(children: [
                  OutlinedButton.icon(
                    onPressed: loading ? null : pickFile,
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: const Txt.S("Select Files"),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Txt.S(
                          picked.isEmpty
                              ? "No files selected -- or drop them here"
                              : "${picked.length} selected",
                          overflow: TextOverflow.ellipsis)),
                  if (picked.isNotEmpty)
                    TextButton(
                        onPressed:
                            loading ? null : () => setState(() => picked = []),
                        child: const Txt.S("Clear")),
                ]),
                // Each queued file is previewed as a ManageFileRow, so
                // what you're about to share looks like what it will look
                // like once shared. The size is read off disk: nothing
                // else here knows it yet.
                for (var f in picked) ...[
                  const SizedBox(height: 10),
                  ManageFileRow(
                    framed: false,
                    filename: f,
                    title: path.basename(f),
                    subtitle: _sizeAndPath(f),
                    actions: [
                      IconButton(
                        iconSize: 18,
                        icon: const Icon(Icons.close),
                        tooltip: "Remove from selection",
                        onPressed: loading
                            ? null
                            : () => setState(() => picked.remove(f)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            _card(cs, [
              _label("Shared with"),
              const SizedBox(height: 6),
              Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (limitToUser != null) ...[
                      ChatAvatar(limitToUser!),
                      Txt.S(limitToUser!.nick),
                      IconButton(
                        iconSize: 18,
                        icon: const Icon(Icons.close),
                        tooltip: "Share with everyone instead",
                        onPressed: loading
                            ? null
                            : () => setState(() {
                                  limitToUser = null;
                                  userSel.clear();
                                }),
                      ),
                    ] else
                      const Txt.S("Everyone"),
                    TextButton(
                        onPressed: loading
                            ? null
                            : () => setState(() => selectingTargetUser = true),
                        child: Txt.S(limitToUser == null
                            ? "Limit to one user"
                            : "Change user")),
                  ]),
            ]),
            const SizedBox(height: 14),
            _card(cs, [
              Row(children: [
                _label("Cost for user"),
                const SizedBox(width: 8),
                const HelpTooltip(
                  message: "How much others will pay for this content",
                  child: Icon(Icons.help_outline, size: 16),
                ),
              ]),
              const SizedBox(height: 6),
              SizedBox(width: 140, child: dcrInput(controller: costCtrl)),
              const SizedBox(height: 16),
              _label("Description"),
              const SizedBox(height: 6),
              TextField(
                controller: descrCtrl,
                style: kInputTextStyle,
                // Flutter's plain underline, deliberately *not*
                // themedInputDecoration.
                //
                // This box sits directly under the Cost field, which is a
                // dcrInput and draws a bare underline of its own, and two
                // different input designs stacked in one card read as an
                // accident rather than as a choice. The Input Areas theme
                // area draws a full outlined box, so routing this through it
                // -- which the code did, while the comment here claimed the
                // opposite -- is what put a border around one of the pair
                // and not the other.
                decoration: const InputDecoration(
                    hintText: "Optional -- shown with the file when offered"),
              ),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              OutlinedButton.icon(
                // Nothing to share without a file, so the button says so by
                // being unavailable rather than failing on press.
                onPressed: loading || picked.isEmpty ? null : addContent,
                icon: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file, size: 18),
                label: Txt.S(picked.length > 1
                    ? "Share ${picked.length} files"
                    : "Share"),
              ),
            ]),
          ]),
    );
  }

  // The size line under a queued file. A path that can't be read is shown
  // without one rather than blocking the preview -- sharing it will fail
  // with a real error.
  String _sizeAndPath(String fullPath) {
    try {
      return "${humanReadableSize(File(fullPath).lengthSync())} - $fullPath";
    } catch (exception) {
      return fullPath;
    }
  }

  Widget _label(String text) =>
      Txt.S(text, style: const TextStyle(fontWeight: FontWeight.w500));

  // The same card the Account settings page frames its groups with, so the
  // Add page reads as part of the same app as the pages beside it.
  Widget _card(ColorScheme cs, List<Widget> children,
          {bool highlight = false}) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          // The border is what says "drop here" while a drag is over the
          // page -- the card is already the file area, so it doesn't need
          // an overlay saying so as well.
          border: Border.all(
              color: highlight ? cs.primary : cs.outlineVariant,
              width: highlight ? 2 : 1),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

class ManageContentScreenArgs {
  final bool selectFile;

  ManageContentScreenArgs(this.selectFile);
}

class ManageContent extends StatefulWidget {
  static String routeName = "/manageContent";
  final int view;
  const ManageContent(this.view, {super.key});

  @override
  State<ManageContent> createState() => _ManageContentState();
}

class _ManageContentState extends State<ManageContent> {
  List<SharedFileAndShares> files = [];

  Future<void> loadSharedContent() async {
    var newfiles = await Golib.listSharedFiles();
    newfiles.sort((SharedFileAndShares a, SharedFileAndShares b) {
      // Sort by dir, then filename.
      return a.sf.filename.compareTo(b.sf.filename);
    });
    setState(() {
      files = newfiles;
    });
  }

  Future<void> addContent(
      String filename, String uid, double cost, String descr) async {
    await Golib.shareFile(filename, uid, cost, descr);
    await loadSharedContent();
  }

  Future<void> removeContent(String fid, String? uid) async {
    await Golib.unshareFile(fid, uid);
    await loadSharedContent();
  }

  @override
  void initState() {
    super.initState();
    loadSharedContent();
  }

  void fileSelected(SharedFile sf) {
    Navigator.of(context).pop(sf);
  }

  @override
  Widget build(BuildContext context) {
    FileSelectedCB? fileSelCB;
    if (ModalRoute.of(context)!.settings.arguments is ManageContentScreenArgs) {
      var args =
          ModalRoute.of(context)!.settings.arguments as ManageContentScreenArgs;
      if (args.selectFile) {
        fileSelCB = fileSelected;
      }
    }
    return Consumer<ClientModel>(
        // No padding here: each page below owns its own gutters, so that
        // they match each other and the rest of the content area.
        builder: (context, client, child) => widget.view == 1
            ? SharedContent(client, files, removeContent, fileSelCB)
            : AddContentPanel(addContent));
  }
}
