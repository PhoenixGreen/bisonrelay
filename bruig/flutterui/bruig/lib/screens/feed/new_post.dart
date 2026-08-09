import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';

import 'package:bruig/components/buttons.dart';
import 'package:bruig/components/feed/markdown_preview.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/components/feed/embed_options.dart';
import 'package:bruig/models/feed.dart';
import 'package:bruig/post_library/embed_store.dart';
import 'package:bruig/post_library/post_library_model.dart';
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

  /// _options are remembered between embeds, because somebody who has
  /// decided their posts should hold 1000-pixel pictures has decided it for
  /// all of them, not for this one.
  static EmbedOptions _options =
      const EmbedOptions(maxWidth: 1600, quality: 80);

  /// _prepared is the picture as it will be stored, and _preparing guards
  /// against a second run starting while one is going.
  PreparedEmbed? _prepared;
  bool _preparing = false;

  /// _original is widget.data decoded once. It arrives as base64 -- that is
  /// the form the post text carries -- and decoding it on every change of
  /// the slider would be work for nothing.
  late final Uint8List _original = base64Decode(widget.data);

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  /// _prepare applies the current options, so the size shown is the size
  /// that will be stored rather than an estimate of it.
  void _prepare() async {
    if (_preparing) return;
    setState(() => _preparing = true);
    var out = await prepareEmbed(_original, mime, _options);
    if (!mounted) return;
    setState(() {
      _prepared = out;
      _preparing = false;
    });
  }

  void _setOptions(EmbedOptions next) {
    _options = next;
    _prepare();
  }

  void _addEmbed() async {
    // Whatever the options produced, falling back to the original if the
    // work has not finished -- the writer pressing Add is not a reason to
    // make them wait, and the original is always valid.
    var ready = _prepared ?? PreparedEmbed(_original, mime);

    List<String> embed = [];
    if (ready.mime != "") {
      embed.add("type=${ready.mime}");
    }
    if (embedAlt.text != "") {
      embed.add("alt=${Uri.encodeComponent(embedAlt.text)}");
    }

    var id = widget.post.trackEmbed(base64Encode(ready.data));
    if (id != "") {
      embed.add("data=[content $id]");
      // Written now rather than when the draft is saved. The text carries
      // only the reference, so a picture that is not on disk by the time the
      // app closes is a picture the draft comes back without -- which is
      // exactly what used to happen to every one of them.
      await EmbedStore.save(id, base64Encode(ready.data));
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

    // Checked because the save above is awaited: the dialog can be dismissed
    // while a large picture is still being written.
    if (!mounted) return;
    Navigator.pop(context);
  }

  /// _sizeLine says what the picture will cost, and what it costs now.
  ///
  /// The number that matters is the stored one, so it is measured rather
  /// than estimated: the options are actually applied and the result
  /// weighed. Anything else would be advertising a saving that might not
  /// arrive.
  Widget _sizeLine() {
    var prepared = _prepared;
    if (_preparing || prepared == null) {
      return const Txt.S("Working out the size...",
          color: TextColor.onSurfaceVariant);
    }
    // Base64 is what the post carries, and it is a third larger than the
    // bytes -- so that is the figure quoted, being the one that lands in
    // the post's size limit.
    var was = (widget.data.length / 1024).round();
    var now = (base64Encode(prepared.data).length / 1024).round();
    var size =
        prepared.width == null ? "" : "  ${prepared.width}x${prepared.height}";
    return Txt.S(now < was ? "$was KB down to $now KB$size" : "$now KB$size",
        color: TextColor.onSurfaceVariant);
  }

  @override
  Widget build(BuildContext context) {
    var isImage = mime.startsWith("image/");
    return Container(
      padding: const EdgeInsets.all(30),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (isImage) ...[
          Row(children: [
            const Text("Maximum width: "),
            const SizedBox(width: 5),
            DropdownButton<int?>(
              value: _options.maxWidth,
              items: const [
                DropdownMenuItem(value: null, child: Text("Original")),
                DropdownMenuItem(value: 2000, child: Text("2000 px")),
                DropdownMenuItem(value: 1600, child: Text("1600 px")),
                DropdownMenuItem(value: 1200, child: Text("1200 px")),
                DropdownMenuItem(value: 1000, child: Text("1000 px")),
                DropdownMenuItem(value: 800, child: Text("800 px")),
                DropdownMenuItem(value: 600, child: Text("600 px")),
              ],
              onChanged: (v) => _setOptions(
                  _options.copyWith(maxWidth: v, clearMaxWidth: v == null)),
            ),
            const SizedBox(width: 20),
            const Text("Quality: "),
            Expanded(
              child: Slider(
                value: _options.quality.toDouble(),
                min: 10,
                max: 100,
                divisions: 18,
                // 100 is not a quality setting but a decision to leave the
                // original encoding alone, so it is labelled as one.
                label: _options.quality == 100
                    ? "Original"
                    : "${_options.quality}",
                onChanged: (v) => setState(
                    () => _options = _options.copyWith(quality: v.round())),
                onChangeEnd: (v) =>
                    _setOptions(_options.copyWith(quality: v.round())),
              ),
            ),
          ]),
          Align(alignment: Alignment.centerLeft, child: _sizeLine()),
          const SizedBox(height: 10),
        ],
        Row(
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
      ]),
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
      // The guide the writer picked, so the preview shows what a reader
      // with that guide will see rather than a house style of its own.
      // The guide the post will carry, which is a built-in by definition --
      // only those can be named in a published post.
      var guide = builtInGuideFor(post.styleGuideId);
      return markdownDecorations(
        text,
        embeds: composerEmbeds(post),
        muted: theme.colors.onSurfaceVariant,
        link: theme.colors.primary,
        guide: guide == null || guide.id == defaultGuideId ? null : guide,
        roleColor: theme.markdownRoleColor,
        image: guide == null ? null : theme.markdownImageRule(guide),
        // So a continued line hangs under the first line's text by the same
        // amount the rendered post will indent it.
        indent: (guide ?? theme.markdownGuide).listIndent,
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
    // Before the early return below: a selection change is exactly what this
    // needs to hear about, and exactly what that return is there to skip.
    _rememberCaret();

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
    _loadMissingEmbeds();
    recalcEstimatedSize();
  }

  /// _fetchingEmbeds are the ids already being read, so a second keystroke
  /// does not start the same read again.
  final Set<String> _fetchingEmbeds = {};

  /// _loadMissingEmbeds fills in any picture the text refers to and the
  /// model does not have.
  ///
  /// Driven off the text rather than off opening a document, which means it
  /// covers every way a reference can arrive: a draft opened from the
  /// library, a post still in the composer after a restart, or text pasted
  /// from one draft into another. The alternative was a callback from the
  /// library model, which would have covered only the first.
  void _loadMissingEmbeds() {
    for (var id in EmbedStore.idsIn(contentCtrl.text)) {
      if (post.embedContents.containsKey(id)) continue;
      if (!_fetchingEmbeds.add(id)) continue;
      EmbedStore.load(id).then((data) {
        if (!mounted || data == null) return;
        setState(() => post.embedContents[id] = data);
      });
    }
  }

  /// _rememberCaret keeps the cursor where it was, for the same reason the
  /// text is kept: coming back to a post and finding the caret at the top of
  /// it is losing your place in your own writing.
  void _rememberCaret() {
    var at = contentCtrl.selection.baseOffset;
    if (at >= 0) post.caret = at;
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
    // Setting the text puts the caret at the start, so the remembered
    // position is restored after it and clamped -- the text can have been
    // changed from elsewhere since.
    contentCtrl.selection = TextSelection.collapsed(
        offset: post.caret.clamp(0, contentCtrl.text.length));
    contentCtrl.addListener(contentChanged);
    // The listener is added after the text, so the first pass has to be
    // asked for: a post restored from the model already has its references
    // in it and nothing has been typed yet.
    _loadMissingEmbeds();
    // Offer the post to whatever panel wants it: the formatting sidebar
    // reads and sets the style guide it will be published with.
    Provider.of<ComposerSidebarController>(context, listen: false).post = post;
    // Tell the library what the composer is holding, so its sweep of
    // unreferenced pictures does not take one out from under a post that
    // has not been saved anywhere yet.
    Provider.of<PostLibraryModel>(context, listen: false).alsoLive =
        () => post.embedContents.keys.toSet();
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
