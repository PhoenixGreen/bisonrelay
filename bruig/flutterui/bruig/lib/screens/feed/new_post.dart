import 'dart:convert';
import 'dart:async';

import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/feed.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/models/composer_sidebar.dart';
import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/post_library/post_library.dart';
import 'package:bruig/screens/feed.dart';
import 'package:bruig/util.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:bruig/components/snackbars.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:provider/provider.dart';

void showAltTextModal(BuildContext context, String mime, String data,
    NewPostModel post, TextEditingController contentCtrl) {
  showModalBottomSheet(
    context: context,
    builder: (BuildContext context) =>
        AddAltText(mime, data, post, contentCtrl),
  );
}

class AddAltText extends StatefulWidget {
  final String mime;
  final String data;
  final TextEditingController contentCtrl;
  final NewPostModel post;
  const AddAltText(this.mime, this.data, this.post, this.contentCtrl,
      {super.key});

  @override
  State<AddAltText> createState() => _AddAltTextState();
}

class _AddAltTextState extends State<AddAltText> {
  TextEditingController embedAlt = TextEditingController();

  String get mime => widget.mime;
  TextEditingController get contentCtrl => widget.contentCtrl;

  void _addEmbed() {
    List<String> embed = [];
    if (mime != "") {
      embed.add("type=$mime");
    }
    if (embedAlt.text != "") {
      embed.add("alt=${Uri.encodeComponent(embedAlt.text)}");
    }

    var id = widget.post.trackEmbed(widget.data);
    if (id != "") {
      embed.add("data=[content $id]");
    }
    var embedText = "--embed[${embed.join(",")}]--";

    var insertPos = contentCtrl.selection.start;
    if (insertPos > -1 && insertPos < contentCtrl.text.length) {
      contentCtrl.text = contentCtrl.text.substring(0, insertPos) +
          embedText +
          contentCtrl.text.substring(insertPos);
    } else {
      contentCtrl.text += "\n$embedText\n";
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(30),
      child: Row(
        children: [
          const Text("Alt Text: "),
          const SizedBox(width: 5),
          Expanded(
              child: TextField(
            onSubmitted: (_) {
              _addEmbed();
            },
            controller: embedAlt,
            autofocus: true,
          )),
          const SizedBox(width: 30),
          TextButton(
            onPressed: () => _addEmbed(),
            child: const Text("No alt text"),
          ),
          const SizedBox(width: 10),
          OutlinedButton(onPressed: _addEmbed, child: const Text("Add")),
        ],
      ),
    );
  }
}

class NewPostScreen extends StatefulWidget {
  final FeedModel feed;
  const NewPostScreen(this.feed, {super.key});

  @override
  State<NewPostScreen> createState() => _NewPostScreenState();
}

class _NewPostScreenState extends State<NewPostScreen> {
  NewPostModel get post => widget.feed.newPost;
  // A writing controller rather than a plain one: it is what paints the
  // spelling, grammar and phrasing marks. Behaves exactly like the plain
  // one when no plugin provides them.
  TextEditingController contentCtrl = WritingTextEditingController();
  bool loading = false;

  // Add embed fields.
  SharedFile? embedLink;
  int estimatedSize = 0;
  Timer? _debounce;
  Timer? _debounceSizeCalc;

  void goBack() {
    Navigator.pop(context);
  }

  void createPost() async {
    var snackbar = SnackBarModel.of(context);
    setState(() {
      loading = true;
    });
    try {
      await widget.feed.createPost(post.getFullContent());
      setState(() {
        post.clear();
        contentCtrl.clear();
        estimatedSize = 0;
      });
      snackbar.success("Created new post");
      pushNavigatorFromState(this, FeedScreen.routeName);
    } catch (exception) {
      snackbar.error("Unable to create post: $exception");
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  void recalcEstimatedSize() async {
    var snackbar = SnackBarModel.of(context);
    if (_debounceSizeCalc?.isActive ?? false) _debounceSizeCalc!.cancel();
    _debounceSizeCalc = Timer(const Duration(milliseconds: 500), () async {
      try {
        var estSize = await Golib.estimatePostSize(post.getFullContent());
        setState(() {
          estimatedSize = estSize;
        });
      } catch (exception) {
        snackbar.error("Unable to estimate post size: $exception");
      }
    });
  }

  // _lastContent is what contentChanged last acted on, so a notification
  // that did not actually change the text can be ignored.
  String _lastContent = "";

  void contentChanged() async {
    // A TextEditingController notifies on selection changes as well as
    // edits, and merely placing the caret cannot change the post's size.
    //
    // Skipping those is not only an optimisation. Right-clicking selects the
    // word under the pointer, so every context menu opened here used to
    // schedule a size estimate whose setState, arriving half a second later,
    // rebuilt the editor and tore the open menu down again -- visible as the
    // menu blinking as the pointer moved onto it.
    if (contentCtrl.text == _lastContent) return;
    _lastContent = contentCtrl.text;

    post.content = contentCtrl.text;
    recalcEstimatedSize();
  }

  void pickFile(BuildContext context) async {
    var snackbar = SnackBarModel.of(context);
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      var filePickRes = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          "avif",
          "bmp",
          "gif",
          "jpg",
          "jpeg",
          "jxl",
          "png",
          "webp",
          "txt"
        ],
        withData: true,
      );
      if (filePickRes == null) return;
      var f = filePickRes.files.first;
      var filePath = f.path;
      if (filePath == null) return;
      filePath = filePath.trim();
      if (filePath == "") return;

      if (f.size > Golib.maxPayloadSize) {
        showErrorSnackbar(
            this, "File is too large ${f.size} > ${Golib.maxPayloadSizeStr}");
        return;
      }

      var mime = "";
      switch (f.extension) {
        case "txt":
          mime = "text/plain";
          break;
        case "avif":
          mime = "image/avif";
          break;
        case "bmp":
          mime = "image/bmp";
          break;
        case "gif":
          mime = "image/gif";
          break;
        case "jpg":
        case "jpeg":
          mime = "image/jpeg";
          break;
        case "jxl":
          mime = "image/jxl";
          break;
        case "png":
          mime = "image/png";
          break;
        case "webp":
          mime = "image/webp";
          break;
        case "mp4":
          mime = "video/mp4";
          break;
        case "avi":
          mime = "video/avi";
          break;
        default:
          snackbar.error("Unable to recognize type of embed");
          return;
      }

      var data = const Base64Encoder().convert(f.bytes!);

      if (context.mounted) {
        showAltTextModal(context, mime, data, post, contentCtrl);
      }
    });
  }

  // TODO: Implement together with link to content button
  // void linkToFile() async {
  //   var args = ManageContentScreenArgs(true);
  //   var fid = await Navigator.of(context, rootNavigator: true)
  //       .pushNamed("/manageContent", arguments: args);
  //   if (fid == null) {
  //     return;
  //   }
  //   setState(() {
  //     embedLink = fid as SharedFile;
  //   });
  // }

  void clearPost() {
    post.clear();
    contentCtrl.text = "";
  }

  @override
  dispose() {
    _debounce?.cancel();
    _debounceSizeCalc?.cancel();
    // Withdraw this composer, so the sidebar slot goes back to whatever the
    // screen normally shows there. Read without listening: dispose must not
    // register a dependency.
    _composerSidebar?.detach(contentCtrl);
    // Flush before the controller goes: the pending write reads its text.
    _postLibrary?.flush();
    super.dispose();
  }

  // _composerSidebar is captured while the widget is still mounted, since
  // dispose cannot reach the provider tree.
  ComposerSidebarController? _composerSidebar;

  // Captured for the same reason: an edit still inside the autosave debounce
  // when the editor goes away would otherwise be lost.
  PostLibraryModel? _postLibrary;

  @override
  void initState() {
    super.initState();
    contentCtrl.text = post.content;
    contentCtrl.addListener(contentChanged);
    // Offer this composer's text to whatever screen owns the sidebar slot.
    // Offering is not opening: arriving at the editor should not rearrange
    // the screen, only make the tools reachable.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _composerSidebar =
          Provider.of<ComposerSidebarController>(context, listen: false)
            ..attach(contentCtrl);
      _postLibrary = Provider.of<PostLibraryModel>(context, listen: false)
        ..watch(contentCtrl);
    });
  }

  @override
  Widget build(BuildContext context) {
    var validSize = estimatedSize <= Golib.maxPayloadSize;

    return Container(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const Txt.L("New Post"),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 15),
              child: TextField(
                decoration: const InputDecoration(hintText: "Post Content"),
                controller: contentCtrl,
                keyboardType: TextInputType.multiline,
                maxLines: null,
                // Whatever an enabled plugin capability offers for the text
                // under the pointer, falling back to the standard menu. The
                // marks on the text come from contentCtrl, which is a
                // WritingTextEditingController.
                contextMenuBuilder: (context, editableTextState) =>
                    writingContextMenu(context, editableTextState,
                        fallbackItems:
                            editableTextState.contextMenuButtonItems),
              ),
            ),
          ),
          const Divider(),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              OutlinedButton(
                onPressed: () => pickFile(context),
                child: const Txt.S("Add Embbed"),
              ),
              // Keyed on whether a provider is enabled, not on whether
              // checking is currently switched on. Hiding it when checking
              // is off strands the user: the switch that turns it back on
              // lives inside the sidebar this button opens.
              if (context.watch<SpellcheckCapability>().active)
                OutlinedButton.icon(
                  onPressed: () => Provider.of<ComposerSidebarController>(
                          context,
                          listen: false)
                      .show(ComposerPanel.writing),
                  icon: const Icon(Icons.spellcheck, size: 16),
                  label: const Txt.S("Writing Tools"),
                ),
              // Always offered, unlike the writing tools: the library needs
              // no plugin, only a folder on disk.
              OutlinedButton.icon(
                onPressed: () => Provider.of<ComposerSidebarController>(context,
                        listen: false)
                    .show(ComposerPanel.posts),
                icon: const Icon(Icons.folder_outlined, size: 16),
                label: const Txt.S("My Posts"),
              ),
            ]),
          ),
          /*  XXX Need to figure out Link to Content button
            const SizedBox(width: 10),
            OutlinedButton(
                onPressed: linkToFile, child: const Text("Link to Content")),
            const SizedBox(width: 10),
            Flexible(
              flex: 3,
              fit: FlexFit.tight,
              child: Text(embedLink?.filename ?? ""),
            ),
            */
          const SizedBox(height: 10),
          const Divider(thickness: 2),
          Txt.S(
            "Estimated Size: ${humanReadableSize(estimatedSize)}",
            color: validSize ? TextColor.onSurfaceVariant : TextColor.error,
          ),
          const SizedBox(height: 10),
          SizedBox(
              width: double.infinity,
              child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 10,
                  children: [
                    Tooltip(
                        message: validSize
                            ? ""
                            : "Post is larger than max allowable size",
                        child: FilledButton.tonal(
                            onPressed:
                                !loading && validSize ? createPost : null,
                            child: const Text("Create Post"))),
                    CancelButton(onPressed: clearPost, label: "Clear Post"),
                  ]))
        ]));
  }
}
