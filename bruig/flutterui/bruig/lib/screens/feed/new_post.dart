import 'dart:convert';
import 'dart:async';

import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/feed/markdown_preview.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/models/feed.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/components/composer_sidebar_shell.dart';
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
import 'package:bruig/theming_system/theme_preset.dart';
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
  //
  // The decorations are how the preview is drawn: when it is off the field
  // gets nothing extra and paints exactly what was typed, and when it is on
  // the same characters are restyled in place. Asked for on every build
  // rather than stored, so toggling the preview is a repaint and never an
  // edit -- the text the post is made of is untouched either way.
  late final TextEditingController contentCtrl = WritingTextEditingController(
    decorations: (text) {
      if (!previewing) return const [];
      var theme = ThemeNotifier.of(context, listen: false);
      return markdownDecorations(
        text,
        embeds: composerEmbeds(post),
        muted: theme.colors.onSurfaceVariant,
        link: theme.colors.primary,
      );
    },
  );

  /// previewing is read from the sidebar the composer is sitting beside.
  ///
  /// Held there rather than here because the control that changes it is in
  /// the Formatting & Content panel, and the panel and the composer already
  /// meet through that controller and nowhere else.
  bool get previewing =>
      Provider.of<ComposerSidebarController>(context, listen: false).preview;

  // The page's heading is the post's title, and the title is the name of the
  // document it is filed under -- so there is one name for a post rather
  // than a heading that says "New Post" forever and a filename chosen in a
  // dialog nobody remembers opening.
  final TextEditingController titleCtrl = TextEditingController();
  final FocusNode titleFocus = FocusNode();

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
    _composerSidebar
      ?..detach(contentCtrl)
      ..onAddEmbed = null;
    _postLibrary?.removeListener(syncTitle);
    titleFocus.dispose();
    titleCtrl.dispose();
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
    // Committed on leaving the field or pressing enter rather than on every
    // keystroke: renaming a file once per letter would leave a trail of
    // documents named after every prefix of the title.
    titleFocus.addListener(() {
      if (!titleFocus.hasFocus) commitTitle();
    });
    // Offer this composer's text to whatever screen owns the sidebar slot.
    // Offering is not opening: arriving at the editor should not rearrange
    // the screen, only make the tools reachable.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _composerSidebar =
          Provider.of<ComposerSidebarController>(context, listen: false)
            ..attach(contentCtrl);
      _postLibrary = Provider.of<PostLibraryModel>(context, listen: false)
        ..watch(contentCtrl)
        ..addListener(syncTitle);
      syncTitle();
      // The formatting panel's embed button is this screen's file picker:
      // tracking an embed and re-estimating the post's size is the
      // composer's business, and the panel only needs somewhere to send a
      // press.
      _composerSidebar?.onAddEmbed = () => pickFile(context);
    });
  }

  /// syncTitle follows the library: opening a document puts its name in the
  /// title, and closing one leaves the box empty.
  ///
  /// Skipped while the field has focus, so the name does not change under
  /// somebody in the middle of typing a new one.
  void syncTitle() {
    if (!mounted || titleFocus.hasFocus) return;
    var name = _postLibrary?.openName ?? "";
    if (titleCtrl.text != name) titleCtrl.text = name;
  }

  /// commitTitle names the post, which is also how an unfiled one becomes a
  /// document.
  void commitTitle() async {
    var library = _postLibrary;
    if (library == null) return;
    var name = titleCtrl.text.trim();
    if (name.isEmpty || name == library.openName) {
      syncTitle();
      return;
    }
    await library.renameOpen(name);
    syncTitle();
  }

  @override
  Widget build(BuildContext context) {
    var validSize = estimatedSize <= Golib.maxPayloadSize;
    var sidebar = context.watch<ComposerSidebarController>();
    var publishMenu =
        ThemeNotifier.of(context).areaStyle(ThemeArea.feed).feedPublishMenu;

    return Container(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          _topBar(context, sidebar, publishMenu, validSize),
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 15),
              child: TextField(
                decoration: const InputDecoration(hintText: "Post Content"),
                controller: contentCtrl,
                keyboardType: TextInputType.multiline,
                maxLines: null,
                // The strut forces every line to one height, which is what
                // is wanted for text and disastrous for a picture: a tall
                // image was drawn at its full size inside a line that had
                // stayed 19 pixels, so it spilled over the words above it
                // and off the top of the page. Measured at 72 pixels of line
                // for 200 pixels of image.
                //
                // Only while previewing. With no pictures in it, raw text
                // wants the even spacing the strut is there to give.
                strutStyle: previewing ? StrutStyle.disabled : null,
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
          // Unless they have moved to the top-right menu -- see the Feed
          // area's "Publish menu".
          if (!publishMenu)
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

  /// _topBar is the post's title, with the sidebar's way back on one side
  /// and the publish menu on the other.
  ///
  /// The title is a text field dressed as the heading it replaces. That
  /// heading read "New Post" whatever you were writing, which names the
  /// screen rather than the post -- and the post's own name lived only in
  /// the library sidebar, where you had to go looking for it. Naming it here
  /// is also how an unfiled post becomes a document.
  Widget _topBar(BuildContext context, ComposerSidebarController sidebar,
      bool publishMenu, bool validSize) {
    var theme = ThemeNotifier.of(context);
    return Row(children: [
      // Only while the sidebar is hidden, and always in the same corner: a
      // hidden sidebar with no way back is a trap.
      if (sidebar.minimized)
        ComposerSidebarRestoreButton(controller: sidebar)
      else
        const SizedBox(width: 40),
      Expanded(
        child: TextField(
          controller: titleCtrl,
          focusNode: titleFocus,
          textAlign: TextAlign.center,
          style: theme.textStyleFor(context, TextSize.large, null),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => commitTitle(),
          // Dressed as the heading it replaced, not as a field. A box and
          // an underline around the title are a permanent reminder that it
          // is a control, on a page whose whole job is to get out of the way
          // of the writing.
          //
          // Every border variant, not just `border`: the app's
          // InputDecorationTheme sets enabledBorder and focusedBorder of its
          // own, and those win over the base one -- which is why clearing
          // only `border` still left an underline that appeared on focus.
          decoration: const InputDecoration(
            hintText: "Untitled post",
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            filled: false,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
      SizedBox(width: 40, child: publishMenu ? _publishMenu(validSize) : null),
    ]);
  }

  /// _publishMenu is the publish actions behind one icon.
  ///
  /// A menu rather than a button because it is where the rest of the publish
  /// options are going, and because the footer it came from cost the editor
  /// that height on every screen for something pressed once per post.
  ///
  /// Clear Post is deliberately not here. It was, and it does not belong: a
  /// menu of ways to publish is the wrong place to keep the one action that
  /// destroys the draft, and the mismatch only gets worse as more publish
  /// options arrive beside it and push it under the reader's thumb. It stays
  /// in the footer for anyone with the menu switched off, and a draft is
  /// autosaved to the post library regardless.
  Widget _publishMenu(bool validSize) => PopupMenuButton<String>(
        icon: const Icon(Icons.ios_share, size: 20),
        tooltip: "Publish options",
        onSelected: (choice) {
          switch (choice) {
            case "create":
              createPost();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: "create",
            // Disabled rather than absent when the post is too large: that
            // is something the writer needs to be told, and a missing entry
            // says nothing at all.
            enabled: !loading && validSize,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.send, size: 18),
              title: const Text("Create Post"),
              subtitle:
                  validSize ? null : const Text("Larger than the maximum size"),
            ),
          ),
        ],
      );
}
