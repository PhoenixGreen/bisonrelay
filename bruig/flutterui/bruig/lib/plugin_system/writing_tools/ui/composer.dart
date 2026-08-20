import 'dart:convert';
import 'dart:async';

import 'package:bruig/components/md_elements.dart';
import 'package:bruig/components/text.dart';
import 'package:bruig/components/feed/post_column.dart';
import 'package:bruig/components/feed/reading_selection.dart';
import 'package:bruig/models/feed.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/embed_store.dart';
import 'package:bruig/models/pages.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/page_documents.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/post_library_model.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/post_storage.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/plugin_system/writing_tools/ui/add_embed_dialog.dart';
import 'package:bruig/plugin_system/writing_tools/ui/composer_sidebar_shell.dart';
import 'package:bruig/plugin_system/writing_tools/composer_sidebar.dart';
import 'package:bruig/plugin_system/writing_tools/ui/writing_field.dart';
import 'package:bruig/plugin_system/writing_tools/ui/writing_popup.dart';
import 'package:bruig/screens/feed.dart';
import 'package:bruig/util.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:golib_plugin/definitions.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:bruig/components/snackbars.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:provider/provider.dart';

// composer.dart is the writing area of the Writing section: the post being
// written, its title, the choice between its source and its rendering, and
// the menu that publishes it.
//
// It lives here rather than under screens/feed/ because it is the writing
// tools' own editor. The Feed keeps its plain composer (screens/feed/
// new_post.dart) for anyone with this plugin switched off, and the two do not
// share a line: this one is free to assume a sidebar beside it, a document on
// disk behind it and marks under its words, none of which exist over there.

/// WritingComposer is the post editor the Writing section is built around.
class WritingComposer extends StatefulWidget {
  final FeedModel feed;
  const WritingComposer(this.feed, {super.key});

  @override
  State<WritingComposer> createState() => _WritingComposerState();
}

class _WritingComposerState extends State<WritingComposer> {
  NewPostModel get post => widget.feed.newPost;
  // A writing controller rather than a plain one: it is what paints the
  // spelling, grammar and phrasing marks. Behaves exactly like the plain
  // one when no plugin provides them.
  late final TextEditingController contentCtrl = WritingTextEditingController();

  /// previewContent is the post's markdown with its embeds filled in, ready
  /// to be rendered.
  ///
  /// The same substitution publishing does, but forgiving: a reference with
  /// nothing behind it yet is left as it stands rather than stopping the
  /// preview, because a post being written is allowed to be half finished.
  String get previewContent {
    try {
      return post.getFullContent();
    } catch (_) {
      return post.content;
    }
  }

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

  /// contentFocus is the writing area's own focus, so a click anywhere on the
  /// page lands in the field rather than only on the lines already written.
  final FocusNode contentFocus = FocusNode();

  /// pageCtrl scrolls the composer, and starts where the draft was left.
  ///
  /// The offset is written back on every scroll rather than read off in
  /// dispose, because by then the controller has already been detached from
  /// its position and there is nothing left to ask. Restoring it is
  /// initialScrollOffset's job -- Flutter clamps that to the real extent on
  /// first layout, so a draft that has since been shortened (or is being
  /// come back to in Preview, which is a different height from the raw
  /// text) lands at the bottom rather than out of range.
  late final ScrollController pageCtrl =
      ScrollController(initialScrollOffset: post.scrollOffset)
        ..addListener(_rememberScroll);

  void _rememberScroll() {
    if (pageCtrl.hasClients) post.scrollOffset = pageCtrl.offset;
  }

  bool loading = false;

  // Add embed fields.
  SharedFile? embedLink;
  int estimatedSize = 0;
  Timer? _debounce;
  Timer? _debounceSizeCalc;

  void goBack() {
    Navigator.pop(context);
  }

  // --- pages ---
  //
  // A document in the library's reserved Pages folder is a page of the
  // writer's own site, so the publish menu offers the site's actions rather
  // than Create Post. What "published" means, and why the served copy is
  // allowed to lag behind the document, is in page_documents.dart.

  PostLibraryModel get _library =>
      _postLibrary ?? Provider.of<PostLibraryModel>(context, listen: false);

  PagesModel? _pagesModel;
  PagesModel get _pages =>
      _pagesModel ?? Provider.of<PagesModel>(context, listen: false);

  /// isPage is whether the open document belongs to the site -- a page, or
  /// one of the fragments its pages share.
  ///
  /// Both, because both are published: a fragment nobody has published is a
  /// fragment every page including it renders as nothing. Checking only the
  /// Pages folder left a fragment offering Create Post, which is the one
  /// thing it cannot be.
  bool get isPage => isSiteFolder(_library.openFolder);

  /// isFragment distinguishes the two for what the menu says. They behave
  /// identically; they are not the same word.
  bool get isFragment => _library.openFolder == partialsFolderName;

  /// _thing is what the publish menu calls the open document.
  String get _thing => isFragment ? "fragment" : "page";

  /// pageState is where the open page stands.
  ///
  /// Worked out by comparing what is served against what is in the editor
  /// -- but the two are not written the same way. A document keeps its
  /// pictures as "data=[content abc]" references while it is being edited,
  /// and what is published has them filled in, so comparing the two
  /// directly reported "edited" the instant anything with a picture in it
  /// was published, and went on reporting it.
  ///
  /// The editor's text is therefore put through the same substitution
  /// publishing does before the comparison. That reads the embed store,
  /// which is why this is worked out on a debounce and held rather than
  /// computed in build.
  PagePublishState pageState = PagePublishState.draft;

  Timer? _stateDebounce;

  /// refreshPageStateSoon batches the typing case: the answer only changes
  /// at the moment the text stops matching what was published, and asking
  /// on every keystroke would read a file per character.
  void refreshPageStateSoon() {
    _stateDebounce?.cancel();
    _stateDebounce =
        Timer(const Duration(milliseconds: 400), refreshPageState);
  }

  Future<void> refreshPageState() async {
    if (!isPage) {
      if (pageState != PagePublishState.draft && mounted) {
        setState(() => pageState = PagePublishState.draft);
      }
      return;
    }
    var name = _library.openName;
    if (name == null) return;
    // The file it is actually served as, which is not always the slug of
    // its name -- see PageDocument.file.
    var page =
        PageDocuments.forName(_pages, name, folder: _library.openFolder);
    var served = page.state.live ? await _pages.readPage(page.file) : null;
    var mine = served == null
        ? contentCtrl.text
        : (await resolveEmbeds(contentCtrl.text)).text;
    if (!mounted) return;
    var next = pagePublishState(served, mine);
    if (next != pageState) setState(() => pageState = next);
  }

  void publishPage() async {
    var snackbar = SnackBarModel.of(context);
    var name = _library.openName;
    if (name == null) return;
    try {
      // Written out first, or the copy taken would be the last save rather
      // than what is on screen.
      await _library.flush();
      var missing = await PageDocuments.publish(_pages,
          PageDocuments.forName(_pages, name, folder: _library.openFolder));
      await refreshPageState();
      if (missing > 0) {
        snackbar.error("Published $name with $missing picture"
            "${missing == 1 ? "" : "s"} missing.");
      } else {
        snackbar.success("Published $name.");
      }
    } catch (exception) {
      snackbar.error("Unable to publish $name: $exception");
    }
  }

  void unpublishPage() async {
    var snackbar = SnackBarModel.of(context);
    var name = _library.openName;
    if (name == null) return;
    try {
      await PageDocuments.unpublish(_pages,
          PageDocuments.forName(_pages, name, folder: _library.openFolder));
      await refreshPageState();
      snackbar.success("$name is no longer published.");
    } catch (exception) {
      snackbar.error("Unable to unpublish $name: $exception");
    }
  }

  /// _openDocumentChanged rereads the page's state when the document being
  /// edited changes. Cheap to ask and skipped entirely for anything that is
  /// not a page.
  String? _lastOpen;
  void _openDocumentChanged() {
    var now = "${_library.openFolder}/${_library.openName}";
    if (now == _lastOpen) return;
    _lastOpen = now;
    refreshPageState();
  }

  void createPost() async {
    var snackbar = SnackBarModel.of(context);
    setState(() {
      loading = true;
    });
    try {
      await widget.feed.createPost(post.getFullContent());
      // Emptying the composer must not empty the document it was written
      // in. The library is watching this controller, so clearing it looks
      // exactly like selecting everything and pressing delete -- the
      // autosave wrote the empty text straight back, and publishing a post
      // left the draft it came from as a nought-byte file.
      //
      // Written out first and then closed, in that order: flush puts the
      // text that was just published on disk even if it was still inside
      // the autosave's debounce, and closing stops the clear below from
      // reaching it. The document stays exactly as it was published.
      await _postLibrary?.flush();
      _postLibrary?.closeDocument();
      if (!mounted) return;
      setState(() {
        post.clear();
        contentCtrl.clear();
        estimatedSize = 0;
      });
      snackbar.success("Created new post");
      // Published posts are read in the Feed, so that is where publishing
      // one leaves you -- the writing page's job is done.
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

  void clearPost() {
    post.clear();
    contentCtrl.text = "";
    // post.clear() resets the remembered offset, but the live view is still
    // wherever it was; an emptied composer left scrolled down shows nothing.
    if (pageCtrl.hasClients) pageCtrl.jumpTo(0);
  }

  @override
  dispose() {
    _debounce?.cancel();
    _debounceSizeCalc?.cancel();
    _stateDebounce?.cancel();
    _stateDebounce?.cancel();
    // Withdraw this composer, so the sidebar slot goes back to whatever the
    // screen normally shows there. Read without listening: dispose must not
    // register a dependency.
    _composerSidebar
      ?..detach(contentCtrl)
      ..onAddEmbed = null;
    _postLibrary?.removeListener(syncTitle);
    _postLibrary?.removeListener(_openDocumentChanged);
    _pagesModel?.removeListener(refreshPageState);
    titleFocus.dispose();
    contentFocus.dispose();
    titleCtrl.dispose();
    pageCtrl.dispose();
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
    // Typing is what moves a published page to "edited", so the menu has to
    // follow the text as well as the document.
    contentCtrl.addListener(refreshPageStateSoon);
    // Typing is what moves a published page to "edited", so the menu has to
    // follow the text as well as the document.
    contentCtrl.addListener(refreshPageStateSoon);
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
      // What the site is serving can change from the other screen -- My
      // Site publishes and unpublishes too -- and the menu here has to
      // agree with it. Without this the two disagreed until whichever one
      // was stale happened to be rebuilt.
      _pagesModel = Provider.of<PagesModel>(context, listen: false)
        ..addListener(refreshPageState);

      _postLibrary = Provider.of<PostLibraryModel>(context, listen: false)
        ..watch(contentCtrl)
        ..addListener(syncTitle)
        // Which document is open decides what the publish menu offers, so
        // the menu has to be told when it changes -- opening a page from My
        // Site is exactly that, happening while this screen is built.
        ..addListener(_openDocumentChanged);
      syncTitle();
      _openDocumentChanged();
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

  /// _editor is the composer itself: the post's markdown, as typed.
  Widget _editor(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        // The field is only as tall as what has been written, and the page
        // it sits on is as tall as the screen -- so without this, clicking
        // the empty part of the page below the last line did nothing.
        onTap: () => contentFocus.requestFocus(),
        child: TextField(
          decoration: const InputDecoration(hintText: "Post Content"),
          controller: contentCtrl,
          focusNode: contentFocus,
          keyboardType: TextInputType.multiline,
          maxLines: null,
          // Whatever an enabled plugin capability offers for the text under
          // the pointer, falling back to the standard menu. The marks on the
          // text come from contentCtrl, which is a
          // WritingTextEditingController.
          contextMenuBuilder: (context, editableTextState) =>
              writingContextMenu(context, editableTextState,
                  fallbackItems: editableTextState.contextMenuButtonItems),
        ),
      );

  /// _preview is the post as it will be read, drawn by the same renderer
  /// that draws it in the feed.
  ///
  /// The renderer itself rather than an imitation of it. This used to be the
  /// composer's own field with its markdown restyled where it was typed,
  /// which keeps the caret honest but can only ever approximate: a table has
  /// nowhere to put a grid when every character has to stay where the writer
  /// put it, a quotation gets a bar for each line rather than one down the
  /// side, and a block background can only be painted behind the letters
  /// rather than across the block. Rendering it properly costs the ability
  /// to type while looking at it, which is what the Raw view is for.
  Widget _preview(BuildContext context) => Align(
        alignment: Alignment.topLeft,
        child: ReadingSelectionArea(
          child: MarkdownArea(previewContent, false),
        ),
      );

  @override
  Widget build(BuildContext context) {
    var validSize = estimatedSize <= Golib.maxPayloadSize;
    var sidebar = context.watch<ComposerSidebarController>();

    // No horizontal padding out here. It goes on each row instead, and for
    // the scrolling one it goes *inside* the scroll view -- which is what
    // leaves the scrollbar hard against the edge of the screen, where a
    // post's is, rather than inset by the padding along with the writing.
    return Container(
        // The header row starts where the sidebar's does, and stands at the
        // same height, so the two line up as one band across the top instead
        // of as two rows that nearly agree.
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: composerNavHeight,
              child: _topBar(context, sidebar, validSize),
            ),
          ),
          const SizedBox(height: 12),
          // Written in the column it will be read in. Full width on no
          // background, the writing had none of the shape of the post it was
          // going to be: the lines ran the width of the window, which is
          // most of what a page looks like, and the words sat on the app
          // rather than on the post. Raw and Preview both, because the point
          // of the raw view is to be the same post with its markup showing.
          // The page scrolls, not the writing inside it -- which is what
          // puts the scrollbar at the edge of the screen, where a post's is,
          // instead of down the middle of the column across the words.
          //
          // The column is held to at least the height of the view so an
          // empty post still shows the page it is going to be, rather than a
          // card the depth of one line.
          //
          // No horizontal padding of its own: how far in a post sits is part
          // of how wide a post is, and PostColumn owns both. Padding to a
          // figure of the composer's own is what left the writing narrower
          // than the post on the default theme.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                controller: pageCtrl,
                padding: const EdgeInsets.only(bottom: 15),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      minHeight: (constraints.maxHeight - 15)
                          .clamp(0, double.infinity)),
                  child: PostColumn(
                    fill: true,
                    child: previewing ? _preview(context) : _editor(context),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(thickness: 2),
          ),
          Txt.S(
            "Estimated Size: ${humanReadableSize(estimatedSize)}",
            color: validSize ? TextColor.onSurfaceVariant : TextColor.error,
          ),
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
  Widget _topBar(
      BuildContext context, ComposerSidebarController sidebar, bool validSize) {
    var theme = ThemeNotifier.of(context);
    // Three slots, with the two ends given equal room so the title stays
    // centred on the page rather than drifting to whichever side has less
    // in it. Scaled down rather than overflowing when the window is too
    // narrow to hold all three at their natural size.
    return Row(children: [
      Expanded(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            // Only while the sidebar is hidden, and always in the same
            // corner: a hidden sidebar with no way back is a trap.
            if (sidebar.minimized)
              ComposerSidebarRestoreButton(controller: sidebar),
            // Beside the title, which is the one row that is about this post
            // rather than about the screen around it.
            ComposerViewToggle(controller: sidebar),
          ]),
        ),
      ),
      Expanded(
        flex: 3,
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
      Expanded(
        child: Align(
          alignment: Alignment.centerRight,
          child: _publishMenu(validSize),
        ),
      ),
    ]);
  }

  /// _publishMenu is the publish actions behind one icon.
  ///
  /// A menu rather than a button because it is where the rest of the publish
  /// options are going, and because the footer it came from cost the editor
  /// that height on every screen for something pressed once per post.
  ///
  /// Not a setting any more. It was one -- the Feed area's "Publish menu" --
  /// back when this editor and the Feed's were the same screen and the menu
  /// had to be opted into. They are two editors now: the Feed keeps the
  /// footer buttons, and this page, which exists only because the writing
  /// tools are switched on, is the one that reads as a writing page.
  ///
  /// Clear Post is deliberately not here. It was, and it does not belong: a
  /// menu of ways to publish is the wrong place to keep the one action that
  /// destroys the draft, and the mismatch only gets worse as more publish
  /// options arrive beside it and push it under the reader's thumb. A draft
  /// is autosaved to the post library regardless, and My Posts is where a
  /// document is deleted.
  Widget _publishMenu(bool validSize) => PopupMenuButton<String>(
        icon: const Icon(Icons.ios_share, size: 20),
        tooltip: "Publish options",
        onSelected: (choice) {
          switch (choice) {
            case "create":
              createPost();
              break;
            case "publish":
              publishPage();
              break;
            case "unpublish":
              unpublishPage();
              break;
          }
        },
        itemBuilder: (context) => [
          // A page is published to the site rather than sent as a post, so
          // it gets the site's actions instead of Create Post -- the same
          // menu, saying what this document can actually do.
          if (isPage) ...[
            PopupMenuItem(
              value: "publish",
              enabled: !loading && pageState != PagePublishState.published,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.publish_outlined, size: 18),
                title: Text(pageState == PagePublishState.draft
                    ? "Publish $_thing"
                    : "Publish update"),
                subtitle: pageState == PagePublishState.published
                    ? const Text("Already published, with no changes since")
                    : null,
              ),
            ),
            PopupMenuItem(
              value: "unpublish",
              // Disabled rather than absent when there is nothing published:
              // a missing entry says nothing, and this is the one action
              // whose absence would be read as "cannot be taken down".
              enabled: !loading && pageState.live,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.visibility_off_outlined, size: 18),
                title: Text("Unpublish $_thing"),
                subtitle: Text(isFragment
                    ? "Every page including it renders it as nothing"
                    : "Takes it down, keeps the writing"),
              ),
            ),
          ] else
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
