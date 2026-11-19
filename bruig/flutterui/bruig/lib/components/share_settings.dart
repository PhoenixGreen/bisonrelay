import 'dart:io';

import 'package:bruig/components/dcr_input.dart';
import 'package:bruig/components/usersearch/user_search_model.dart';
import 'package:bruig/components/usersearch/user_search_panel.dart';
import 'package:bruig/models/client.dart';
import 'package:flutter/material.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:golib_plugin/util.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

// share_settings.dart is the terms a file is shared in Files on -- who can
// fetch it, what it costs and how it is described -- set before a canvas is
// shared from its publish sheet, and changed afterwards from the Shared
// page (Ken, 2026-11-19).
//
// Cost and description are part of the file's metadata, and the file's ID
// is that metadata's hash (clientdb.ShareFile), so sharing the same file
// again on new terms is ignored by the client: it keeps the old metadata
// while any share of it remains. Changing them means withdrawing every
// share, so the client lets the content go, and sharing it again -- under
// a new ID, which is why links already sent stop working.

/// ShareSettings is who can fetch a shared file, what it costs (in DCR) and
/// how it is described.
class ShareSettings {
  /// everyone shares it with anyone who lists your files; otherwise only
  /// with [people] (user IDs).
  final bool everyone;
  final List<String> people;
  final double cost;
  final String description;

  const ShareSettings({
    this.everyone = true,
    this.people = const [],
    this.cost = 0,
    this.description = "",
  });

  /// of is the terms [file] is shared on now.
  factory ShareSettings.of(SharedFileAndShares file) => ShareSettings(
        everyone: file.global,
        people: List.of(file.shares),
        cost: atomsToDCR(file.cost),
        description: file.descr,
      );

  /// reachesAnyone is false for "chosen people" with nobody chosen.
  bool get reachesAnyone => everyone || people.isNotEmpty;

  ShareSettings copyWith({
    bool? everyone,
    List<String>? people,
    double? cost,
    String? description,
  }) =>
      ShareSettings(
        everyone: everyone ?? this.everyone,
        people: people ?? this.people,
        cost: cost ?? this.cost,
        description: description ?? this.description,
      );

  /// sameTermsAs is whether [file] is already shared exactly so.
  bool sameTermsAs(SharedFileAndShares file) {
    var now = ShareSettings.of(file);
    if (now.everyone != everyone ||
        (cost * 1e8).round() != file.cost ||
        now.description != description) {
      return false;
    }
    if (everyone) return true;
    return now.people.toSet().containsAll(people) &&
        people.toSet().containsAll(now.people);
  }
}

/// shareOnTerms shares the file at [filePath] on [terms]: once with everyone,
/// or once per person chosen.
Future<void> shareOnTerms(String filePath, ShareSettings terms) async {
  if (terms.everyone) {
    await Golib.shareFile(filePath, null, terms.cost, terms.description);
    return;
  }
  for (var uid in terms.people) {
    await Golib.shareFile(filePath, uid, terms.cost, terms.description);
  }
}

/// unshareEverywhere withdraws every share of [file]: with everyone, and
/// with each person. Once the last goes, the client lets the content go.
Future<void> unshareEverywhere(SharedFileAndShares file) async {
  if (file.global) await Golib.unshareFile(file.sf.fid, null);
  for (var uid in file.shares) {
    await Golib.unshareFile(file.sf.fid, uid);
  }
}

/// sharedFileNamed is the shared file called [filename], or null.
Future<SharedFileAndShares?> sharedFileNamed(String filename) async {
  var name = path.basename(filename);
  for (var file in await Golib.listSharedFiles()) {
    if (file.sf.filename == name) return file;
  }
  return null;
}

/// changeShare shares [file] again on [terms], from the copy on disk it was
/// shared from. Throws, sharing nothing changed, where that copy is gone.
Future<void> changeShare(SharedFileAndShares file, ShareSettings terms) async {
  if (file.diskPath.isEmpty) {
    throw "Bison Relay doesn't know where this file was shared from.";
  }
  if (!await File(file.diskPath).exists()) {
    throw "The file it was shared from is gone: ${file.diskPath}";
  }
  await unshareEverywhere(file);
  await shareOnTerms(file.diskPath, terms);
}

/// showChangeShareDialog asks for new terms for [file] and shares it on
/// them. True when it was changed.
Future<bool> showChangeShareDialog(
    BuildContext context, SharedFileAndShares file) async {
  var terms = ShareSettings.of(file);
  var changed = await showDialog<ShareSettings>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text("Share settings for ${file.sf.filename}"),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShareSettingsFields(
                  initial: terms,
                  onChanged: (t) => setState(() => terms = t),
                ),
                const SizedBox(height: 14),
                const ShareChangeNote(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: !terms.reachesAnyone || terms.sameTermsAs(file)
                ? null
                : () => Navigator.of(context).pop(terms),
            child: const Text("Share again"),
          ),
        ],
      ),
    ),
  );
  if (changed == null) return false;
  await changeShare(file, changed);
  return true;
}

/// ShareChangeNote says what sharing on new terms does to links already
/// sent, where the change is made.
class ShareChangeNote extends StatelessWidget {
  /// republishing: said in a canvas's publish sheet, where Update shares a
  /// new copy whether or not the terms change.
  final bool republishing;
  const ShareChangeNote({this.republishing = false, super.key});

  @override
  Widget build(BuildContext context) {
    var cs = Theme.of(context).colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.info_outline, size: 15, color: cs.onSurfaceVariant),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          "${republishing ? "Updating" : "Changing these"} shares the file "
          "again under a new link. Links "
          "already sent in chats or posts stop working, and people need to "
          "list your files again to see it. Anyone who already downloaded "
          "it keeps their copy.",
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ),
    ]);
  }
}

/// ShareSettingsFields asks who can fetch a file, its cost and its
/// description, starting from [initial] and telling [onChanged] each change.
class ShareSettingsFields extends StatefulWidget {
  final ShareSettings initial;
  final ValueChanged<ShareSettings> onChanged;
  final bool enabled;

  const ShareSettingsFields({
    required this.initial,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  @override
  State<ShareSettingsFields> createState() => _ShareSettingsFieldsState();
}

class _ShareSettingsFieldsState extends State<ShareSettingsFields> {
  late ShareSettings _terms = widget.initial;
  final _cost = AmountEditingController();
  late final _description =
      TextEditingController(text: widget.initial.description);

  @override
  void initState() {
    super.initState();
    _cost.text = costText(widget.initial.cost);
  }

  @override
  void dispose() {
    _cost.dispose();
    _description.dispose();
    super.dispose();
  }

  void _set(ShareSettings terms) {
    setState(() => _terms = terms);
    widget.onChanged(terms);
  }

  Future<void> _addPeople(ClientModel client) async {
    var picked = UserSelectionModel(allowMultiple: true);
    var chosen = await showDialog<List<ChatModel>>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 500,
          height: 500,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: UserSearchPanel(
              client,
              userSelModel: picked,
              targets: UserSearchPanelTargets.users,
              excludeUIDs: _terms.people,
              searchInputHintText: "Search for people",
              confirmLabel: "Add",
              onCancel: () => Navigator.of(context).pop(),
              onConfirm: () => Navigator.of(context).pop(picked.selected),
            ),
          ),
        ),
      ),
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;
    _set(_terms.copyWith(people: [
      ..._terms.people,
      for (var chat in chosen)
        if (!_terms.people.contains(chat.id)) chat.id,
    ]));
  }

  @override
  Widget build(BuildContext context) {
    var cs = Theme.of(context).colorScheme;
    // Nullable: without a client (a test) names are their IDs and nobody
    // can be added.
    var client = context.watch<ClientModel?>();
    var small = TextStyle(fontSize: 11, color: cs.onSurfaceVariant);
    // The size of the publish sheet's own dropdowns, which these sit among.
    var body = TextStyle(fontSize: 13, color: cs.onSurface);
    String nick(String uid) => client?.getExistingChat(uid)?.nick ?? uid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("Who can fetch it", style: small),
        DropdownButton<bool>(
          key: const ValueKey("shareWho"),
          value: _terms.everyone,
          isDense: true,
          isExpanded: true,
          style: body,
          items: const [
            DropdownMenuItem(
                value: true, child: Text("Everyone who lists your files")),
            DropdownMenuItem(value: false, child: Text("Only people I choose")),
          ],
          onChanged: !widget.enabled
              ? null
              : (v) {
                  if (v != null) _set(_terms.copyWith(everyone: v));
                },
        ),
        if (!_terms.everyone) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var uid in _terms.people)
                InputChip(
                  label: Text(nick(uid)),
                  onDeleted: !widget.enabled
                      ? null
                      : () => _set(_terms.copyWith(
                          people: [..._terms.people]..remove(uid))),
                ),
              TextButton.icon(
                key: const ValueKey("shareAddPeople"),
                onPressed: widget.enabled && client != null
                    ? () => _addPeople(client)
                    : null,
                icon: const Icon(Icons.person_add_alt, size: 16),
                label: const Text("Add people"),
              ),
            ],
          ),
          if (_terms.people.isEmpty)
            Text("Choose at least one person.",
                style: TextStyle(fontSize: 11, color: cs.error)),
        ],
        const SizedBox(height: 12),
        Text("Cost (DCR)", style: small),
        SizedBox(
          width: 160,
          child: dcrInput(
            controller: _cost,
            onChanged: (v) => _set(_terms.copyWith(cost: v)),
          ),
        ),
        Text("Free if left empty. People pay this to download it.",
            style: small),
        const SizedBox(height: 12),
        Text("Description", style: small),
        TextField(
          key: const ValueKey("shareDescription"),
          controller: _description,
          enabled: widget.enabled,
          style: body,
          decoration: const InputDecoration(
              isDense: true,
              hintText: "Shown with the file when it is offered"),
          onChanged: (v) => _set(_terms.copyWith(description: v.trim())),
        ),
      ],
    );
  }
}

/// costText is [dcr] as the cost box shows it: empty for free, and no
/// trailing zeros.
String costText(double dcr) {
  if (dcr <= 0) return "";
  var text = dcr.toStringAsFixed(8);
  text = text.replaceFirst(RegExp(r"0+$"), "");
  return text.endsWith(".") ? text.substring(0, text.length - 1) : text;
}
