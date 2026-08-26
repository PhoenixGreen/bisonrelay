import 'dart:convert';
import 'dart:io';
// import 'package:dart_vlc/dart_vlc.dart' as vlc;
import 'package:bruig/components/context_menu.dart';
import 'package:bruig/components/feed/code_highlight.dart';
import 'package:bruig/components/feed/feed_image.dart';
import 'package:bruig/components/feed/feed_render_scope.dart';
import 'package:bruig/components/feed/markdown_blocks.dart';
import 'package:bruig/components/feed/markdown_header.dart';
import 'package:bruig/components/feed/page_image.dart';
import 'package:bruig/components/feed/markdown_nav.dart';
import 'package:bruig/components/feed/markdown_page.dart';
import 'package:bruig/components/feed/markdown_panel.dart';
import 'package:bruig/components/feed/markdown_button.dart';
import 'package:bruig/components/feed/markdown_listing.dart';
import 'package:bruig/components/pages/forms.dart';
import 'package:bruig/components/snackbars.dart';
import 'package:bruig/components/text_dialog.dart';
import 'package:bruig/components/audio_element.dart';
import 'package:bruig/components/interactive_avatar.dart';
import 'package:bruig/models/audio.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/models/downloads.dart';
import 'package:bruig/models/feed.dart';
import 'package:bruig/models/payments.dart';
import 'package:bruig/models/resources.dart';
import 'package:bruig/models/snackbar.dart';
import 'package:bruig/screens/feed.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:golib_plugin/util.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:bruig/components/image_dialog.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_avif/flutter_avif.dart';

class DownloadSource {
  final String uid;

  DownloadSource(this.uid);
}

class PagesSource {
  final String uid;
  final int sessionID;
  final int pageID;

  PagesSource(this.uid, this.sessionID, this.pageID);
}

class VideoInlineSyntax extends md.InlineSyntax {
  /// This is a primitive example pattern
  VideoInlineSyntax({
    String pattern = r'--video\[(.*?)\]--',
  }) : super(pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final videoURL = match.group(1);

    md.Element el = md.Element.text("video", videoURL!.toString());

    parser.addNode(el);
    return true;
  }
}

class ImageInlineSyntax extends md.InlineSyntax {
  /// This is a primitive example pattern
  ImageInlineSyntax({
    String pattern = r'--image\[(.*?)\]--',
  }) : super(pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final imageURL = match.group(1);

    md.Element el = md.Element.text("image", imageURL!.toString());

    parser.addNode(el);
    return true;
  }
}

class LnpayURLSyntax extends md.InlineSyntax {
  LnpayURLSyntax({
    String pattern = r'lnpay:\/\/(ln[td]?\w*)',
  }) : super(pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final url = match.group(1) ?? "";

    md.Element el = md.Element.text("lnpay", url);

    parser.addNode(el);
    return true;
  }
}

/// Matches bare (not already markdown-linked) http(s) URLs so the "Pretty
/// Links" plugin can offer a native preview card for known domains. Because
/// user-supplied inline syntaxes are tried before flutter_markdown's
/// built-in link/autolink syntaxes, this only ever fires on genuinely bare
/// URLs in the source text -- an explicit `[text](url)` markdown link is
/// fully consumed by the built-in LinkSyntax before the parser's cursor
/// ever reaches the URL text on its own.
class BareLinkSyntax extends md.InlineSyntax {
  /// The element tag matched URLs are emitted as, for whichever
  /// MarkdownExtension registered this syntax to render.
  final String tag;

  BareLinkSyntax({
    required this.tag,
    String pattern = r'https?:\/\/\S+',
  }) : super(pattern);

  /// aloneAttribute marks a URL that is the whole of what it was written in,
  /// as opposed to one sitting in a sentence.
  ///
  /// The difference decides how much room the card may take. A card has to be
  /// the full width of the line when there are words beside it, or
  /// flutter_markdown's Wrap seats them alongside it and the reader gets
  /// their message to the left of its own preview. Written on its own there
  /// is nothing to sit beside it, so it claims only what it draws -- and a
  /// chat bubble, which is as wide as its widest content, then fits the card
  /// instead of running the width of the window.
  static const aloneAttribute = "alone";

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    var url = match.group(0) ?? "";
    var el = md.Element.text(tag, url);
    if (parser.source.trim() == url) el.attributes[aloneAttribute] = "true";
    parser.addNode(el);
    return true;
  }
}

class EmbedInlineSyntax extends md.InlineSyntax {
  final String dbRoot;

  /// This is a primitive example pattern
  EmbedInlineSyntax(
    this.dbRoot, {
    String pattern = r'--embed\[(.*?)\]--',
  }) : super(pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final Map<String, String> parms = {};
    final rawParms = match.group(1) ?? "";
    rawParms.split(",").forEach((element) {
      var p = element.indexOf("=");
      if (p == -1) return;
      parms[element.substring(0, p)] = element.substring(p + 1);
    });

    // Quote embed: a reference to another post (rendered as a nested
    // card). Only ever produced by the feed's Quote Post action, which is
    // gated behind AreaStyle.feedCardActions.
    if (parms["type"] == "quote") {
      var el = md.Element.text("quote", "");
      el.attributes["from"] = parms["from"] ?? "";
      el.attributes["post"] = parms["post"] ?? "";
      parser.addNode(el);
      return true;
    }

    // Only accept valid download FIDs.
    var download = parms["download"] ?? "";
    if (!RegExp(r"^[0-9a-fA-F]{64}$").hasMatch(download)) {
      download = "";
    }

    // URL-decode alt text.
    var alt = parms["alt"] ?? "";
    if (alt != "") {
      try {
        alt = Uri.decodeComponent(alt);
      } catch (exception) {
        // Ignore decoding errors and just print a debug msg.
        debugPrint("Unable to decode alt: $exception");
      }
    }

    var data = parms["data"] ?? "";
    var localFilename = parms["localfilename"] ?? "";

    // Bare link without embedded data.
    if ((data == "" && localFilename == "") && download != "") {
      var el = md.Element.text(
          "download", alt != "" ? alt : "Download file $download");
      el.attributes["fid"] = download;
      parser.addNode(el);
      return true;
    }

    // Otherwise, we need data.
    if (data == "" && localFilename == "") {
      return true;
    }

    var tag = "";

    // If localFilename is specified, load from saved embedded dir.
    if (localFilename != "") {
      var filePath = path.join(dbRoot, localFilename);
      try {
        // Encode back to base64 becase ImageBuilder decodes it itself.
        data = base64Encode(File(filePath).readAsBytesSync());
      } catch (exception) {
        tag = "text";
        data = "Error opening embedded file '$filePath': $exception";
      }
    }

    if (tag == "") {
      switch (parms["type"]) {
        case "image/bmp":
        case "image/gif":
        case "image/jpeg":
        case "image/jxl":
        case "image/png":
        case "image/webp":
          tag = "image";
          break;
        case "image/avif":
          tag = "avif";
          break;
        case "text/plain":
          // Decode plain text directly.
          //
          // Its own tag, not "pre". A fenced code block parses to <pre>
          // too, so registering a builder for "pre" -- which is what an
          // attached text file needed -- took over every code block in
          // every post as well: they lost the monospaced face and the block
          // background, and each one grew a "View" button belonging to a
          // file that was not there. See MarkdownAreaModel.builders.
          tag = "embedtext";
          try {
            data = utf8.fuse(base64).decode(data);
          } catch (exception) {
            data = "Unable to decode plain text contents: $exception";
          }
          break;
        case "application/pdf":
          tag = "pdf";
          break;
        case "audio/ogg":
          tag = "audio";
          break;
        default:
          return true;
      }
    }
    md.Element el = md.Element.text(tag, data);

    if (download != "") {
      el.attributes["fid"] = download;
    }
    if (alt != "") {
      el.attributes["alt"] = alt;
    }

    if (parms["type"] != "") {
      el.attributes["type"] = parms["type"]!;
    }

    if (parms.containsKey("filename") && parms["filename"] != "") {
      el.attributes["filename"] = parms["filename"]!;
    }

    var name = parms["name"] ?? "";
    if (name != "") {
      el.attributes["name"] = name;
    }

    parser.addNode(el);
    return true;
  }
}

/*
class _VideoMarkdownDesktopElement extends StatefulWidget {
  final String filename;
  _VideoMarkdownDesktopElement(this.filename, {Key? key}) : super(key: key);

  @override
  __VideoMarkdownDesktopElementState createState() =>
      __VideoMarkdownDesktopElementState();
}


class __VideoMarkdownDesktopElementState
    extends State<_VideoMarkdownDesktopElement> {
  vlc.Player player = vlc.Player(id: 69420);
  vlc.Media? media;

  @override
  void initState() {
    super.initState();
    media = vlc.Media.file(File(widget.filename));
    if (media != null) {
      player.open(media!);
    }
  }

  @override
  void dispose() {
    player.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return vlc.Video(
      player: player,
      width: 320,
      height: 200,
    );
  }
}

class _VideoMarkdownMobileElement extends StatefulWidget {
  final String filename;
  _VideoMarkdownMobileElement(this.filename, {Key? key}) : super(key: key);

  @override
  __VideoMarkdownMobileElementState createState() =>
      __VideoMarkdownMobileElementState();
}

class __VideoMarkdownMobileElementState
    extends State<_VideoMarkdownMobileElement> {
  mbv.VideoPlayerController? controller;

  void initController() async {
    var f = File(widget.filename);
    var newController = await mbv.VideoPlayerController.file(f);
    await newController.initialize();
    mounted
        ? setState(() {
            controller = newController;
            controller?.play();
          })
        : null;
  }

  @override
  void initState() {
    super.initState();
    initController();
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    if (controller == null) {
      return Container(
        color: theme.cardColor,
        child: Center(
          child: Text("Loading..."),
        ),
      );
    }

    return AspectRatio(
        aspectRatio: controller!.value.aspectRatio,
        child: mbv.VideoPlayer(controller!));
  }
}

class VideoMarkdownElementBuilder extends MarkdownElementBuilder {
  final String basedir;
  VideoMarkdownElementBuilder(this.basedir);

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final bool useVLC =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    // Protect against trying to fetch from !basedir.
    String filename = p.canonicalize(p.join(this.basedir, element.textContent));
    if (!p.isWithin(basedir, filename)) {
      return Container(color: Colors.amber, width: 100, height: 100);
    }

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: useVLC
              ? _VideoMarkdownDesktopElement(filename)
              : _VideoMarkdownMobileElement(filename)),
    );
  }
}
*/

class MarkdownAreaModel extends ChangeNotifier {
  final extensionSet = md.ExtensionSet(
      md.ExtensionSet.gitHubFlavored.blockSyntaxes,
      [md.EmojiSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes]);

  final Map<String, MarkdownElementBuilder> builders = {
    // An attached text file, which EmbedInlineSyntax emits as "embedtext".
    // Deliberately not "pre": that is what a fenced code block parses to,
    // and a builder registered there renders every code block in the app as
    // a scrolling box with a "View" button, in the body face rather than the
    // code one -- flutter_markdown asks the builder for the block's tag
    // before it reaches its own code-block rendering.
    "embedtext": PreformattedElementBuilder(),
    "pdf": PDFMarkdownElementBuilder(),
    "audio": AudioElementBuilder(),
    //"video": VideoMarkdownElementBuilder(basedir),
    "codeblock": CodeblockMarkdownElementBuilder(),
    "image": ImageMarkdownElementBuilder(),
    "download": DownloadLinkElementBuilder(),
    "form": FormElementBuilder(),
    "lnpay": _LNPayURLElementBuilder(),
    "avif": AVIFElementBuilder(),
    "quote": QuoteMarkdownElementBuilder(),
    "columns": ColumnsMarkdownElementBuilder(),
    "cards": CardsMarkdownElementBuilder(),
    "grid": GridMarkdownElementBuilder(),
    "header": HeaderMarkdownElementBuilder(),
    "nav": NavMarkdownElementBuilder(),
    "panel": PanelMarkdownElementBuilder(),
    "button": ButtonMarkdownElementBuilder(),
    "listing": ListingMarkdownElementBuilder(),
  };

  final List<md.InlineSyntax> inlineSyntaxes = [
    LnpayURLSyntax(),
  ];
  final List<md.BlockSyntax> blockSyntaxes = [
    FormBlockSyntax(),
    ColumnsBlockSyntax(),
    CardsBlockSyntax(),
    GridBlockSyntax(),
    HeaderBlockSyntax(),
    NavBlockSyntax(),
    PageBlockSyntax(),
    PanelBlockSyntax(),
    ButtonBlockSyntax(),
    ListingBlockSyntax(),
  ];

  // _pluginExtensions is whatever the last setPluginExtensions call added,
  // kept so the next one can remove exactly those again.
  List<MarkdownExtension> _pluginExtensions = const [];

  MarkdownAreaModel(String dbroot) {
    inlineSyntaxes.add(EmbedInlineSyntax(dbroot));
  }

  /// setPluginExtensions replaces the markdown renderers contributed from
  /// outside this file -- see lib/plugin_system, which is the only caller.
  /// The built-in builders and syntaxes declared above are never touched by
  /// it, so a plugin can add a rendering but never remove or replace one of
  /// Bison Relay's own.
  ///
  /// Called whenever the set of enabled plugins changes. Markdown already
  /// rendered on screen keeps its old rendering until it rebuilds.
  void setPluginExtensions(List<MarkdownExtension> extensions) {
    var sameTags = _pluginExtensions.length == extensions.length &&
        _pluginExtensions.every((e) => extensions.any((n) => n.tag == e.tag));
    if (sameTags) return;

    for (var e in _pluginExtensions) {
      builders.remove(e.tag);
      if (e.inlineSyntax != null) inlineSyntaxes.remove(e.inlineSyntax);
    }
    _pluginExtensions = extensions;
    for (var e in extensions) {
      builders[e.tag] = e.builder;
      if (e.inlineSyntax != null) inlineSyntaxes.add(e.inlineSyntax!);
    }
    notifyListeners();
  }

  // _fence matches the start or end of a fenced code block.
  static final _fence = RegExp(r'^\s*(```|~~~)');

  /// isolate gives every standalone match a paragraph of its own.
  ///
  /// See MarkdownExtension.standalone for why. Applied to the text before it
  /// is parsed, and a no-op when no extension asks for it -- which is every
  /// case with no such plugin enabled, so text is left exactly as written.
  ///
  /// Code is left alone: a URL in a fenced block or between backticks is
  /// being shown, not linked, and breaking the block apart would stop it
  /// being code at all.
  String isolate(String text) {
    var patterns = [
      for (var e in _pluginExtensions)
        if (e.standalone != null) e.standalone!
    ];
    if (patterns.isEmpty) return text;

    var out = <String>[];
    var inFence = false;
    for (var line in text.split("\n")) {
      if (_fence.hasMatch(line)) {
        inFence = !inFence;
        out.add(line);
        continue;
      }
      if (inFence || line.contains("`")) {
        out.add(line);
        continue;
      }
      out.addAll(_split(line, patterns));
    }
    return out.join("\n");
  }

  /// _split breaks one line into the runs around its standalone matches,
  /// each separated by the blank line that makes a paragraph.
  static List<String> _split(String line, List<RegExp> patterns) {
    var out = <String>[];
    var rest = line;

    /// add appends one paragraph, with the blank line that separates it from
    /// whatever came before it.
    void add(String part) {
      if (part.isEmpty) return;
      if (out.isNotEmpty) out.add("");
      out.add(part);
    }

    while (true) {
      Match? first;
      for (var p in patterns) {
        var m = p.firstMatch(rest);
        if (m == null) continue;
        if (first == null || m.start < first.start) first = m;
      }
      if (first == null) {
        // A line with no match at all comes back exactly as it was written,
        // spaces and all -- only a line actually being broken up is rebuilt.
        //
        // Asked before the tail is added rather than after. Adding it first
        // put the trimmed line into `out`, so the emptiness test could never
        // be true and every line came back trimmed -- which quietly deleted
        // the two trailing spaces that make a markdown line break, for as
        // long as any plugin supplied a standalone pattern. Link previews
        // supplies one and ships enabled, so this was every post.
        if (out.isEmpty) return [line];
        add(rest.trim());
        return out;
      }
      add(rest.substring(0, first.start).trim());
      add(rest.substring(first.start, first.end));
      rest = rest.substring(first.end);
    }
  }
}

/// MarkdownExtension is one markdown rendering contributed from outside this
/// file. It is the whole of the app's markdown extension point: a tag to
/// render, the builder that renders it, and optionally an inline syntax that
/// produces that tag in the first place.
class MarkdownExtension {
  /// The markdown element tag [builder] renders.
  final String tag;
  final MarkdownElementBuilder builder;

  /// An optional syntax that emits [tag]. Needed when the extension renders
  /// something the markdown source doesn't already mark up -- a bare URL,
  /// say, which is otherwise just text.
  final md.InlineSyntax? inlineSyntax;

  /// An optional pattern whose matches want a paragraph to themselves.
  ///
  /// For an extension that draws a *block* out of something written inline.
  /// Markdown has no way to say "this is a block" about a run of text in the
  /// middle of a sentence, and flutter_markdown lays a paragraph out in a
  /// Wrap -- so a card built from a bare URL is seated beside the words
  /// around it, however wide it is drawn.
  ///
  /// Given this, the model puts each match in a paragraph of its own before
  /// the text is parsed, so the card becomes a block in its own right: on
  /// its own line, and no wider than it draws. The alternative -- having the
  /// card claim the full width of the line to push the words off it -- works
  /// on the line but makes every container it sits in full width too, which
  /// is what left a chat bubble running the width of the window around a
  /// half-width card.
  final RegExp? standalone;

  const MarkdownExtension({
    required this.tag,
    required this.builder,
    this.inlineSyntax,
    this.standalone,
  });
}

/// MarkdownGuideScope carries a style guide's picture rules down to the
/// embeds inside one piece of markdown.
///
/// An InheritedWidget rather than a parameter because the widget that draws
/// an embed is built by flutter_markdown from a builder, several layers
/// below whoever chose the guide, and there is no argument to thread down.
///
/// Absent means "as it was". Chat installs no scope, so a picture in a
/// message is drawn exactly as it was before guides existed -- which is what
/// keeps this a posts-only feature.
class MarkdownGuideScope extends InheritedWidget {
  final ImageRule image;
  final ColumnRule columns;
  final CardRule cards;
  final GridRule grid;
  final HeaderRule header;
  final NavRule nav;

  const MarkdownGuideScope(
      {required this.image,
      this.columns = const ColumnRule(),
      this.cards = const CardRule(),
      this.grid = const GridRule(),
      this.header = const HeaderRule(),
      this.nav = const NavRule(),
      required super.child,
      super.key});

  static ImageRule? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MarkdownGuideScope>()?.image;

  static ColumnRule? columnsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MarkdownGuideScope>()?.columns;

  static CardRule? cardsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MarkdownGuideScope>()?.cards;

  static GridRule? gridOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MarkdownGuideScope>()?.grid;

  static HeaderRule? headerOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MarkdownGuideScope>()?.header;

  static NavRule? navOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MarkdownGuideScope>()?.nav;

  @override
  bool updateShouldNotify(MarkdownGuideScope old) =>
      old.image != image || old.columns != columns || old.cards != cards;
}

/// followMarkdownLink opens what a link in rendered markdown points at.
///
/// Top-level rather than a method, because a bar of links draws its own
/// and still has to follow them the same way -- br:// and relative page
/// paths included. Two copies of this would be two behaviours.
Future<void> followMarkdownLink(BuildContext context, String url) async {
  var parsed = Uri.parse(url);
  var downSource = Provider.of<DownloadSource?>(context, listen: false);
  var pageSource = Provider.of<PagesSource?>(context, listen: false);
  var uid = downSource?.uid ?? pageSource?.uid ?? "";
  var snackbar = SnackBarModel.of(context);

  if (parsed.scheme != "" && parsed.scheme != "br") {
    if (!await launchUrl(Uri.parse(url))) {
      snackbar.error("Could not launch $url");
    }
    return;
  }

  // Handle absolute br:// link.
  if (parsed.host != "") {
    uid = parsed.host;
  }

  if (uid == "") {
    throw "Cannot follow br:// link without target UID";
  }

  var resources = Provider.of<ResourcesModel>(context, listen: false);
  var sessionID = pageSource?.sessionID ?? 0;
  var parentPageID = pageSource?.pageID ?? 0;
  try {
    await resources.fetchPage(
        uid, parsed.pathSegments, sessionID, parentPageID, null, "");
  } catch (exception) {
    snackbar.error("Unable to fetch page: $exception");
  }
}

/// blockBuilderTags are the builders that draw a whole block of a page
/// rather than something inside a line.
///
/// Named because the parser wraps each of them in a paragraph -- they are
/// tags it does not know, and an unknown tag is inline as far as it is
/// concerned -- and a paragraph carries the space that goes between
/// paragraphs. A banner or a panel sitting a paragraph's worth of space away
/// from the top of the page is not what anyone wrote, and it is invisible
/// until the block takes a background, at which point it reads as a band
/// above it.
const Set<String> blockBuilderTags = {
  "header",
  "button",
  "listing",
  "nav",
  "panel",
  "grid",
  "cards",
  "columns",
  "form",
};

/// _BlockParagraphPadding takes the paragraph spacing off a paragraph whose
/// only content is one of those blocks.
///
/// Only when that is all it holds: a paragraph with writing in it as well is
/// a real paragraph and keeps its spacing.
class _BlockParagraphPadding extends MarkdownPaddingBuilder {
  final EdgeInsets normal;
  _BlockParagraphPadding(this.normal);

  bool _wrapsBlockOnly = false;

  @override
  void visitElementBefore(md.Element element) {
    var kids = element.children ?? const <md.Node>[];
    var only = kids.where((k) => !(k is md.Text && k.text.trim().isEmpty));
    _wrapsBlockOnly = only.length == 1 &&
        only.first is md.Element &&
        blockBuilderTags.contains((only.first as md.Element).tag);
  }

  @override
  EdgeInsets getPadding() => _wrapsBlockOnly ? EdgeInsets.zero : normal;
}

class MarkdownArea extends StatelessWidget {
  static final _startTagBugRe = RegExp(r'^\s*(<[^>\s]+\s*>)$');

  static String _cleanupSrcText(String text) {
    // This renderer has a bug where a raw text "<foo>" needs escaping, otherwise
    // its not rendered.
    return text.replaceFirstMapped(_startTagBugRe, (m) => "\\${m[1]}");
  }

  final String text;
  final bool hasNick;
  // When true, links render with their normal styling but don't navigate on
  // tap. Used by the Feed page's AreaStyle.feedHideLinks toggle -- only
  // affects this MarkdownArea instance, not markdown rendering elsewhere
  // (chat, pages, etc).
  final bool disableLinks;
  // When true, headers/bold/italic/strikethrough all render with normal
  // body text styling instead of their usual formatting -- the markdown is
  // still parsed (embeds/links/etc still work), only the *visual*
  // formatting is flattened. Used by the Feed page's
  // AreaStyle.feedStripMarkdown toggle -- only affects this MarkdownArea
  // instance, not markdown rendering elsewhere (chat, pages, etc).
  final bool plainText;

  /// guide is the style guide to set this text in, or null for whichever
  /// the reader's theme is using.
  ///
  /// A guide rather than the name of one, which is what this used to take.
  /// Naming it meant looking it up among the built-ins, and a reader who had
  /// edited theirs has a guide that is not among them -- so every change
  /// made in Settings was saved correctly and then rendered by the built-in
  /// it had been forked from. Nothing the editor did appeared to work.
  ///
  /// Passed in only by the composer, which shows the writer the guide the
  /// post will carry rather than the one the reader happens to use.
  final MarkdownStyleGuide? guide;

  /// align is which side the writing sits on, or null for wherever the
  /// guide puts it -- which is the left.
  ///
  /// Passed in rather than written in the markdown, because it is a property
  /// of the box the writing is in rather than of the writing: a card whose
  /// plate is centred wants its title centred too, and a reader should not
  /// have to see that decision spelled out on every line.
  final WrapAlignment? align;

  /// blockSpacing is the room between one block of this markdown and the
  /// next, or null for whatever the reader's guide keeps.
  ///
  /// Passed in for the same reason [align] is: it is a property of the box
  /// the writing is in. A card whose picture sits directly on its caption
  /// needs the gap between those two blocks gone, and there is nothing a
  /// block can write about the space *between* itself and its neighbour --
  /// a margin of nought still leaves the renderer's own paragraph spacing,
  /// which is what made "sit flush" appear to do nothing.
  final double? blockSpacing;

  MarkdownArea(srcText, this.hasNick,
      {this.disableLinks = false,
      this.plainText = false,
      this.guide,
      this.align,
      this.blockSpacing,
      super.key})
      : text = MarkdownArea._cleanupSrcText(srcText);

  // Flattens header/bold/italic/strikethrough styles down to plain body
  // text, leaving everything else (code, blockquote, links, etc) alone.
  MarkdownStyleSheet _plainStyleSheet(
      MarkdownStyleSheet base, BuildContext context) {
    final plain = DefaultTextStyle.of(context).style;
    return base.copyWith(
      h1: plain,
      h2: plain,
      h3: plain,
      h4: plain,
      h5: plain,
      h6: plain,
      strong: plain,
      em: plain,
      del: plain,
    );
  }

  /// _guidedStyleSheet is the theme's own stylesheet with the style guide
  /// folded onto it.
  ///
  /// The theme's is returned untouched for Default, which is not an
  /// optimisation but the definition of it: Default is the guide that says
  /// nothing, so folding it on is a no-op with extra steps.
  MarkdownStyleSheet _guidedStyleSheet(
      ThemeNotifier theme, BuildContext context) {
    var guide = this.guide ?? theme.markdownGuide;
    if (guide.id == defaultGuideId && !_saysAnything(guide)) {
      return theme.mdStyleSheet;
    }

    // Folded onto the *effective* sheet, not the app's sparse one.
    //
    // The app's sheet names only the few things it overrides and leaves the
    // rest null, and MarkdownBody fills those in from the Material theme --
    // "fallbackStyleSheet.merge(widget.styleSheet)". A guide that writes
    // into a null field therefore replaces a value that had not been worked
    // out yet, and whatever it worked from becomes the answer.
    //
    // The first version worked from DefaultTextStyle, which is near-black
    // with a purple cast while the theme's own text is near-white -- so
    // every guide but Default rendered its paragraphs in dark purple, and
    // links lost the theme's styling the same way. Merging first means the
    // guide adjusts colours and sizes that are already right.
    var effective = MarkdownStyleSheet.fromTheme(Theme.of(context))
        .merge(theme.mdStyleSheet);
    return applyGuide(
      effective,
      guide,
      (role) => theme.markdownRoleColor(role),
      paletteColor: theme.markdownPaletteColor,
    );
  }

  /// _saysAnything reports whether a guide differs from the plain one.
  ///
  /// Default is the guide that changes nothing, so it can be skipped -- but
  /// only while it really is unchanged. A reader who edited Default has a
  /// guide still carrying its id, and skipping that would throw their work
  /// away every time a post was drawn.
  ///
  /// Compared against the built-in Default rather than against an empty
  /// guide. Default is not empty -- it states the heading ladder the app has
  /// always drawn, because a size in a guide is a share of the body and an
  /// unsaid one would mean "the same size as the body". An empty guide is no
  /// longer any guide the app can be using, so comparing with one made this
  /// answer yes every time.
  static bool _saysAnything(MarkdownStyleGuide guide) =>
      guide.toJson().toString() !=
      builtInGuideFor(defaultGuideId)!.toJson().toString();

  /// _checkBoxSize is how large a task list's box is drawn, bounded.
  static double _checkBoxSize(MarkdownStyleGuide guide) =>
      guide.listCheckSize.clamp(8.0, 48.0);

  /// _bulletBuilder draws a list's marker.
  ///
  /// Every marker is set the same way: hard against the right of the marker
  /// column, held off its text by [_markerGap]. So a bullet, a number and a
  /// check box all end at the same place and all their text begins at the
  /// same place, and the indent means one thing -- the space to the left of
  /// the marker -- whichever kind of list it is applied to.
  ///
  /// flutter_markdown's own arrangement is not that: it centres a bullet in
  /// the column and right-aligns a number hard against the text. Under one
  /// indent setting the two moved quite differently, and a list of each kind
  /// one after another did not line up down the page.
  /// _markerGap is the space kept between a list's marker and its text.
  ///
  /// A share of the indent, so the two move apart together. The same figure
  /// for the number and the check box, because they are aligned the same
  /// way: what the indent adds is space to the *left* of the marker, which
  /// is what it already did for a bullet.
  static double _markerGap(MarkdownStyleSheet sheet) =>
      ((sheet.listIndent ?? 24) * 0.25).clamp(4.0, 16.0);

  MarkdownBulletBuilder _bulletBuilder(
      BuildContext context, MarkdownStyleSheet sheet, double gap) {
    var marker = _markerStyle(context, sheet);
    return (index, style) => Padding(
          padding: EdgeInsets.only(right: gap),
          child: Text(
            style == BulletStyle.unorderedList ? "•" : "${index + 1}.",
            textAlign: TextAlign.right,
            // Never wrapped, whatever room the column turned out to have.
            //
            // Reported: every item from 10 onwards broke across two lines,
            // with the full stop alone on the second. The package puts this
            // in a SizedBox one indent wide, and a Text in a box too narrow
            // wraps -- so "10." became "10" and ".". _orderedMarkerIndent
            // below makes the column wide enough that this should not
            // happen, and this makes the failure a marker that reaches into
            // the margin rather than a list that comes apart.
            softWrap: false,
            maxLines: 1,
            overflow: TextOverflow.visible,
            style: marker,
          ),
        );
  }

  /// _orderedItem matches a numbered list item, capturing the number, so the
  /// marker column can be measured against the widest one actually written.
  static final _orderedItem = RegExp(r'^\s{0,3}(\d+)[.)]\s', multiLine: true);

  /// _orderedMarkerIndent is the room the widest number in [text] needs.
  ///
  /// A marker column sized for "9." is too narrow for "10.", and the list
  /// that overflows it is the long one -- exactly the list somebody wrote
  /// because they had a lot to say. Measured from the text rather than
  /// assumed, so a list of nine costs nothing and a list of a hundred and
  /// nine still fits.
  ///
  /// Returns null when there is no ordered list to measure.
  static double? _orderedMarkerIndent(
      String text, TextStyle? style, double gap) {
    var widest = 0;
    for (var m in _orderedItem.allMatches(text)) {
      var digits = m.group(1)!.length;
      if (digits > widest) widest = digits;
    }
    if (widest < 2) return null;

    var painter = TextPainter(
      text: TextSpan(text: "${"9" * widest}.", style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width + gap;
  }

  /// _markerStyle is what a list's bullet or number is set in.
  ///
  /// Merged onto the Material fallback rather than read straight off the
  /// app's sheet, because that is what MarkdownBody itself does with the
  /// sheet it is handed -- "fallbackStyleSheet.merge(widget.styleSheet)".
  /// The app's sheet names only what it overrides and leaves the rest null,
  /// so reading listBullet from it directly gave a style with no size and no
  /// colour, and every bullet and number came out small and dark against the
  /// page. The package was filling those in; a builder has to do it too.
  TextStyle? _markerStyle(BuildContext context, MarkdownStyleSheet sheet) =>
      MarkdownStyleSheet.fromTheme(Theme.of(context)).merge(sheet).listBullet;

  /// _checkboxBuilder draws the box on a markdown task list -- `- [ ]` for an
  /// open item, `- [x]` for a done one.
  ///
  /// A box with a mark in it rather than a character, so it does not depend
  /// on the reader's font having ☑ and ☒. The box is always drawn; what
  /// changes between the two states is what is inside it, which is what the
  /// guide chooses.
  MarkdownCheckboxBuilder _checkboxBuilder(
      BuildContext context,
      MarkdownStyleGuide guide,
      ThemeNotifier theme,
      MarkdownStyleSheet sheet,
      double gap) {
    // Falls back to the bullet's own colour, so an unset box is set in
    // whatever the rest of the list is rather than in a colour of its own.
    var ink = guide.listCheckInk.resolve(theme.markdownRoleColor,
            paletteColor: theme.markdownPaletteColor) ??
        _markerStyle(context, sheet)?.color ??
        theme.textColor(TextColor.onSurface);
    var size = _checkBoxSize(guide);

    return (checked) {
      var mark = checked ? guide.listCheckedMark : guide.listUncheckedMark;
      // Aligned to the right of the marker column, and not just padded.
      //
      // Two things are going on. flutter_markdown puts the marker in a
      // SizedBox as wide as the list indent, and a SizedBox constrains its
      // child *tightly* -- so a box asked to be 16px wide was stretched to
      // whatever the indent was. Align takes that tight width for itself and
      // hands the box loose constraints, so the box stays the size it was
      // asked for.
      //
      // Then it sits at the right of that column, as a bullet and a number
      // both effectively do. Left-aligned, the indent added its space
      // *between* the box and the text, while for every other kind of list
      // it added space to the left of the marker -- one setting measured two
      // different ways, depending on the list.
      return Align(
        alignment: Alignment.topRight,
        child: Padding(
          // Nudged down so the box sits on the line of text beside it
          // rather than riding above it, and held off the text by the same
          // gap a number keeps -- plus the bullet padding, which
          // flutter_markdown adds around a bullet or a number but not around
          // a check box. Without it the box ended four pixels to the right
          // of every other marker on the page.
          padding: EdgeInsets.only(
              top: 2, right: gap + (sheet.listBulletPadding?.right ?? 0)),
          child: SizedBox(
            width: size,
            height: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: ink, width: size / 12),
                borderRadius: BorderRadius.circular(size / 6),
              ),
              child: mark.icon == null
                  ? null
                  : Icon(mark.icon, size: size * 0.78, color: ink),
            ),
          ),
        ),
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<ThemeNotifier, PaymentsModel, MarkdownAreaModel>(
        builder: (context, theme, payments, mk, _) {
      // Plain text wins over a guide: it is the Feed's "strip markdown"
      // setting, which is a decision not to show formatting at all, and a
      // guide is only ever about how formatting looks.
      var sheet = plainText
          ? _plainStyleSheet(theme.mdStyleSheet, context)
          : _guidedStyleSheet(theme, context);
      var effectiveGuide = guide ?? theme.markdownGuide;

      // Every kind of line, not only paragraphs: a centred plate holding a
      // heading and a price with the heading left and the price centred is
      // not centred, it is broken.
      if (blockSpacing != null) {
        sheet = sheet.copyWith(blockSpacing: blockSpacing);
      }

      if (align != null) {
        sheet = sheet.copyWith(
          textAlign: align,
          h1Align: align,
          h2Align: align,
          h3Align: align,
          h4Align: align,
          h5Align: align,
          h6Align: align,
        );
      }

      // The gap every marker keeps from its text, worked out once from the
      // indent the guide actually asks for.
      //
      // Once, because widening the column below would otherwise widen the
      // gap with it, leaving less room for the box than the widening was
      // meant to provide -- the two chased each other and the box still came
      // out a pixel or two short.
      var gap = _markerGap(sheet);

      // The marker column is the list indent wide plus the bullet padding
      // the package adds around it, and a check box is sized in its own
      // right -- so a box larger than the column had nowhere to be drawn and
      // came out squashed to whatever room was left. The list makes room for
      // it instead: the indent is the space to the left of the marker, and
      // it can only do that job once the marker itself fits.
      var pad = sheet.listBulletPadding ?? EdgeInsets.zero;
      var needed =
          _checkBoxSize(effectiveGuide) + gap + pad.right - pad.horizontal;
      // The same job for a two- or three-digit number, which outgrows the
      // column the same way a check box does and came apart more visibly:
      // the marker wrapped and left the full stop on a line of its own.
      var numbered = _orderedMarkerIndent(
          text, _markerStyle(context, sheet), gap + pad.horizontal);
      if (numbered != null && numbered > needed) needed = numbered;
      if ((sheet.listIndent ?? 24) < needed) {
        sheet = sheet.copyWith(listIndent: needed);
      }
      return _withGuide(
        context,
        theme,
        MarkdownBody(
          paddingBuilders: {
            "p": _BlockParagraphPadding(sheet.pPadding ?? EdgeInsets.zero),
          },
          // Keyed by the checkbox settings, so changing one redraws the list.
          //
          // MarkdownBody parses its markdown into widgets once and re-parses
          // only when the text or the stylesheet changes -- and a checkbox is
          // neither: it is baked into the children at parse time by
          // checkboxBuilder. Changing only a mark therefore left the list
          // exactly as it was already built, and the setting looked dead
          // until something else about the guide was touched as well. A key
          // that changes with them makes the state fresh, which is the parse.
          key: ValueKey((
            effectiveGuide.listCheckedMark,
            effectiveGuide.listUncheckedMark,
            effectiveGuide.listCheckSize,
            effectiveGuide.listCheckInk.toJson(),
          )),
          codeBlockMaxHeight: 200,
          styleSheet: sheet,
          checkboxBuilder:
              _checkboxBuilder(context, effectiveGuide, theme, sheet, gap),
          bulletBuilder: _bulletBuilder(context, sheet, gap),
          data: mk.isolate(text.trim()),
          extensionSet: mk.extensionSet,
          builders: mk.builders,
          // A Markdown image with a path -- ![A banner](assets/banner.png)
          // -- is a file of the site's own, fetched on its own and kept. See
          // page_image.dart. Anything with a scheme is somebody else's and
          // is left to the default.
          imageBuilder: (uri, title, alt) => isPageAssetPath(uri.toString())
              ? PageImage(path: uri.toString(), alt: alt ?? title)
              : const SizedBox.shrink(),
          onTapLink: (text, url, _) {
            if (disableLinks) return;
            followMarkdownLink(context, url ?? "");
          },
          inlineSyntaxes: mk.inlineSyntaxes,
          blockSyntaxes: mk.blockSyntaxes,
        ),
      );
    });
  }

  /// _withGuide puts the guide's picture rules where the embeds can see
  /// them, and nothing at all around text that has no guide.
  Widget _withGuide(BuildContext context, ThemeNotifier theme, Widget child) {
    // Never in a chat message.
    //
    // A style guide is how *posts* are set -- that is what the Markdown area
    // says it is and what a post carries the name of. A message has no guide
    // and never asked for one, so its pictures are drawn the way they always
    // were: by the Chat area's Image size.
    //
    // This was the intent from the start (see MarkdownGuideScope: "Chat
    // installs no scope"), but nothing enforced it, and the scope goes on
    // whenever the guide is not the untouched Default. So the moment a
    // reader edited any guide setting at all -- a list indent, a check box
    // -- every picture in every message quietly switched from the Chat
    // area's Image size to the guide's own 100%-of-the-column rule, and the
    // Image size setting appeared to stop working.
    //
    // Chat is the case with a width handed down from the message:
    // ChatImageWidth is installed by the chat message path and by nothing
    // else.
    if (ChatImageWidth.of(context) != null) return child;

    var guide = this.guide ?? theme.markdownGuide;
    // Default with nothing changed is the app as it was, so it gets no scope
    // at all rather than one that happens to match.
    if (guide.id == defaultGuideId &&
        guide.image == const ImageRule() &&
        guide.columns == const ColumnRule() &&
        guide.cards == const CardRule()) {
      return child;
    }
    return MarkdownGuideScope(
        image: guide.image,
        columns: guide.columns,
        cards: guide.cards,
        grid: guide.grid,
        header: guide.header,
        nav: guide.nav,
        child: child);
  }
}

class Downloadable extends StatelessWidget {
  final String tip;
  final String fid;
  final Widget child;
  const Downloadable(this.tip, this.fid, this.child, {super.key});

  void download(BuildContext context) async {
    var snackbar = SnackBarModel.of(context);
    try {
      var downloads = Provider.of<DownloadsModel>(context, listen: false);
      var source = Provider.of<DownloadSource?>(context, listen: false);
      var page = Provider.of<PagesSource?>(context, listen: false);
      var uid = source?.uid ?? page?.uid ?? "";
      if (uid == "") {
        throw "UID in parent DownloadsSource/PagesSource not found";
      }
      await downloads.getUnknownUserFile(uid, fid);
      snackbar.success("Added $fid to download queue");
    } catch (exception) {
      snackbar.error("Unable to start download: $exception");
    }
  }

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: fid != "" ? () => download(context) : null,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: child,
          ),
        ),
      );
}

// chatImageConstraints resolves the configured chat image size setting into
// concrete BoxConstraints, given the width available to the image within its
// chat bubble (as reported by an enclosing LayoutBuilder).
// ChatImageWidth carries the width a chat message has to draw in down to the
// pictures inside it.
//
// It has to be handed down rather than measured, because a picture in a
// message is *inline* markdown (see ImageInlineSyntax/EmbedInlineSyntax) and
// flutter_markdown renders an inline builder's widget inside a WidgetSpan --
// which lays its child out with an unbounded width. A LayoutBuilder around
// the picture is therefore told it has infinite room and can take no share
// of anything, which is why every Image size behaved identically: with no
// finite width to take a fraction of, they all fell through to the same 250
// bound. Nothing about the picture itself was wrong; it simply never knew
// how much room it had.
class ChatImageWidth extends InheritedWidget {
  final double width;
  const ChatImageWidth({required this.width, required super.child, super.key});

  static double? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatImageWidth>()?.width;

  @override
  bool updateShouldNotify(ChatImageWidth old) => old.width != width;
}

// chatImageFraction is the share of the available width a chat image size
// asks for, or null for "Default" -- which is a bound on how large a picture
// may be drawn rather than a proportion of anything.
double? chatImageFraction(String size) => switch (size) {
      "quarter" => 0.25,
      "third" => 1 / 3,
      "half" => 0.5,
      "twoThirds" => 2 / 3,
      "full" => 1.0,
      _ => null,
    };

// chatImageWidth is the width a chat image should actually be drawn at, or
// null to leave it at its natural size (the "Default" bound, and any case
// with no finite width to take a share of).
//
// A width, not a maximum width -- the same lesson the style guide's pictures
// already learned (see ImageMd.build). An Image set to contain draws at its
// natural size whenever that fits, so as a cap these settings did nothing at
// all to any picture already smaller than the share: "Full width" meant only
// "up to the full width", which every small picture was under, and half of a
// narrow bubble is narrower still. That is why the setting looked broken,
// and why it looked *differently* broken under each Message layout -- the
// layouts change the width, and so change whether the cap binds at all.
double? chatImageWidth(String size, double availableWidth) {
  var fraction = chatImageFraction(size);
  if (fraction == null || !availableWidth.isFinite) return null;
  return availableWidth * fraction;
}

// chatImageSized draws a chat picture at whatever its size setting asks for:
// a real width for the proportional sizes, and for "Default" the 250pt box
// it has always been bounded to, natural size below that.
Widget chatImageSized(String size, double availableWidth, Widget child) {
  var width = chatImageWidth(size, availableWidth);
  if (width == null) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 250, maxWidth: 250),
      child: child,
    );
  }
  return SizedBox(width: width, child: child);
}

/// isSvgMime is whether a declared type is a vector image.
///
/// Its own function because two places need the same answer -- an ordinary
/// picture and a header's background -- and a second spelling of it would be
/// a format that worked in one place and not the other.
bool isSvgMime(String type) {
  var t = type.toLowerCase();
  return t == "image/svg+xml" || t == "image/svg";
}

class ImageMd extends StatelessWidget {
  final String tip;
  final Uint8List imgContent;
  final String type;
  final String? name;
  const ImageMd(this.tip, this.imgContent, this.type, {this.name, super.key});

  @override
  Widget build(BuildContext context) {
    var theme = ThemeNotifier.of(context);
    var chatImageSize = theme.chatImageSize;
    // The style guide's picture rules, when this markdown has one. Null is
    // every other case -- chat, and posts read under Default -- and keeps
    // the sizes and corners this drew before guides existed.
    var rule = MarkdownGuideScope.of(context);

    // SVG is drawn by a different decoder: Image.memory reads raster
    // formats and hands back nothing for a vector, which is why a logo
    // saved as one appeared as a gap. Matched on the type the embed
    // declares rather than by sniffing the bytes, since that is what the
    // writer's client already worked out.
    Widget image = isSvgMime(type)
        ? SvgPicture.memory(
            imgContent,
            fit: BoxFit.contain,
            placeholderBuilder: (context) => const SizedBox.shrink(),
          )
        : Image.memory(
            imgContent,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              debugPrint("ImageMd unable to decode image: $error");
              return const SizedBox.shrink();
            },
          );

    var corners = BorderRadius.all(
        Radius.circular(rule == null ? 8.0 : rule.boundedRadius));
    var border = rule == null || rule.boundedBorder == 0
        ? null
        : Border.all(
            color: theme.markdownInk(rule.borderInk) ??
                theme.colors.outlineVariant,
            width: rule.boundedBorder);

    Widget sized = LayoutBuilder(
      builder: (context, constraints) {
        // Chat, which has no guide: a bound on how large a picture may be
        // drawn, exactly as it always was.
        if (rule == null) {
          // The message's own width when one has been handed down (see
          // ChatImageWidth); the measured one otherwise, for the places a
          // picture is laid out with real constraints.
          var available = ChatImageWidth.of(context) ?? constraints.maxWidth;
          return chatImageSized(chatImageSize, available,
              ClipRRect(borderRadius: corners, child: image));
        }

        // The guide's share of the column it is in, so a picture keeps its
        // proportion of the page at any window size.
        //
        // A width, not a maximum width. As a maximum it was only ever a cap:
        // an Image set to contain draws at its natural size whenever that
        // fits, so a picture narrower than the column ignored the setting
        // entirely and 100% did not fill the post -- it meant "up to the
        // full width", which every picture smaller than the column was
        // already under. The height follows from the width, the aspect
        // ratio being the picture's own.
        //
        // Unbounded width has no share to take, so the picture is left at
        // its natural size rather than given an infinite one.
        return SizedBox(
          width: constraints.maxWidth.isFinite
              ? constraints.maxWidth * rule.boundedWidth / 100
              : null,
          child: ClipRRect(borderRadius: corners, child: image),
        );
      },
    );

    if (border != null) {
      sized = Container(
        decoration: BoxDecoration(border: border, borderRadius: corners),
        child: sized,
      );
    }

    // A gesture rather than an InkWell: the picture is the thing you are
    // looking at, and it needs no highlight drawn under it to say so.
    //
    // The highlight was drawn over the whole tappable area, which includes
    // the space above and below the picture that the style guide's Gap
    // setting puts there -- so it stood off the picture by the gap at the
    // top and bottom and by two pixels at the sides, a lopsided box that
    // grew as the gap was widened. The pointer still turns to a hand, which
    // is what actually says the picture can be opened.
    return Tooltip(
      message: tip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            showDialog(
                context: context,
                builder: (_) => ImageDialog(imgContent, type, name: name));
          },
          child: Container(
            margin: rule == null
                ? const EdgeInsets.symmetric(horizontal: 2, vertical: 2)
                : EdgeInsets.symmetric(horizontal: 2, vertical: rule.gap),
            alignment: rule == null ? null : _alignOf(rule.align),
            child: sized,
          ),
        ),
      ),
    );
  }

  static Alignment _alignOf(MarkdownAlign align) => switch (align) {
        MarkdownAlign.center => Alignment.topCenter,
        MarkdownAlign.right => Alignment.topRight,
        MarkdownAlign.left || MarkdownAlign.inherit => Alignment.topLeft,
      };
}

class AvifMd extends StatelessWidget {
  final String tip;
  final Uint8List imgContent;
  const AvifMd(this.tip, this.imgContent, {super.key});

  @override
  Widget build(BuildContext context) {
    var chatImageSize = ThemeNotifier.of(context).chatImageSize;
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(30)),
        onTap: () {
          showDialog(context: context, builder: (_) => AvifDialog(imgContent));
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(8.0)),
            child: LayoutBuilder(
              builder: (context, constraints) => chatImageSized(
                chatImageSize,
                ChatImageWidth.of(context) ?? constraints.maxWidth,
                Image(
                  image: AvifImage.memory(imgContent).image,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint("AvifMd unable to decode image: $error");
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PreformattedElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitText(md.Text text, TextStyle? preferredStyle) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: SingleChildScrollView(
            controller: ScrollController(keepScrollOffset: false),
            child: Consumer<ThemeNotifier>(
                builder: (context, theme, child) => Text.rich(
                      TextSpan(text: text.text),

                      // Overwrite <pre> style to use the same as code
                      // (Markdown component uses same as <p> by default).
                      style: theme.mdStyleSheet.code,
                    ))),
      ),
      const SizedBox(height: 10),
      Builder(
          builder: (context) => TextButton(
              onPressed: () => showDialog(
                  context: context,
                  builder: (context) => TextDialog(text.text)),
              child: const Text("View"))),
    ]);
  }
}

/// CodeblockMarkdownElementBuilder draws the inside of a fenced block: the
/// code, optionally numbered down the side and optionally coloured.
///
/// Both are style-guide settings (see MarkdownStyleGuide.codeLineNumbers and
/// .codeHighlight) and both are off unless a guide asks for them, so a post
/// reads exactly as it did unless somebody chooses otherwise.
///
/// The padding and the background are not here -- they are the stylesheet's
/// codeblockPadding and codeblockDecoration, applied by the markdown builder
/// around whatever this returns.
class CodeblockMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitText(md.Text text, TextStyle? preferredStyle) =>
      Consumer<ThemeNotifier>(
        builder: (context, theme, _) {
          // The theme's own guide, which is also the one the editor's
          // preview shows: an unsaved edit is written straight onto the
          // active preset, so this is live while the sliders are moving.
          var guide = theme.markdownGuide;
          var style = preferredStyle;

          var code = text.text;
          // A fenced block usually arrives with the trailing newline the
          // closing fence sat on, which would otherwise number an empty
          // last line.
          if (code.endsWith("\n")) code = code.substring(0, code.length - 1);

          Widget body = guide.codeHighlight
              ? Text.rich(TextSpan(
                  children: highlightCode(code, markdownCodeInk(theme), style)))
              : Text.rich(TextSpan(text: code), style: style);

          if (!guide.codeLineNumbers) return body;

          // The gutter is its own column beside the code rather than
          // numbers pasted onto each line, so selecting and copying the
          // block gives back the code and not the numbering.
          var lines = code.split("\n");
          var muted = theme.colors.onSurfaceVariant;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                    text: [
                  for (var n = 1; n <= lines.length; n++)
                    n.toString().padLeft(lines.length.toString().length),
                ].join("\n")),
                textAlign: TextAlign.right,
                style: (style ?? const TextStyle()).copyWith(color: muted),
              ),
              const SizedBox(width: 12),
              Flexible(child: body),
            ],
          );
        },
      );
}

/// markdownCodeInk is the palette a highlighted block is coloured from.
///
/// The theme's own colours rather than a fixed scheme, so a block belongs to
/// the post it sits in: comments take the muted text colour, strings and
/// numbers the success and error hues, keywords the accent. Those four are
/// already held apart from each other and from the background by the
/// palette's own contrast rules, which is what a highlighter needs.
CodeInk markdownCodeInk(ThemeNotifier theme) => CodeInk(
      text: theme.colors.onSurface,
      comment: theme.colors.onSurfaceVariant,
      string: theme.activePreset?.success ?? theme.extraColors.successOnSurface,
      number: theme.colors.error,
      keyword: theme.activePreset?.navAccent ?? theme.colors.primary,
    );

class PDFMarkdownElementBuilder extends MarkdownElementBuilder {
  Future<String> _tempPDFDir() async {
    bool isMobile = Platform.isIOS || Platform.isAndroid;
    String base = isMobile
        ? (await getApplicationCacheDirectory()).path
        : (await getDownloadsDirectory())?.path ?? "";
    return path.join(base, "feedimages");
  }

  void _handleItemTap(BuildContext context, String value, Uint8List pdfBytes,
      String filename) async {
    switch (value) {
      case "save":
        var fname = await FilePicker.platform.saveFile(
              dialogTitle: "Select filename",
              fileName: filename != "" ? filename : "document.pdf",
            ) ??
            "";

        if (fname == "") {
          return;
        }

        File(fname).writeAsBytesSync(pdfBytes);
        context.mounted
            ? showSuccessSnackbar(context, "Written PDF file $fname")
            : null;
        break;

      case "share":
        var fname = filename != "" ? filename : "document.pdf";
        var dir = await _tempPDFDir();
        if (!Directory(dir).existsSync()) {
          Directory(dir).createSync(recursive: true);
        }
        fname = path.join(dir, fname);
        File(fname).writeAsBytesSync(pdfBytes);
        SharePlus.instance
            .share(ShareParams(files: [XFile(fname)], text: "Pdf"));
        break;
    }
  }

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    Uint8List pdfBytes;
    String filename = element.attributes["filename"] ?? "";
    try {
      pdfBytes = const Base64Decoder().convert(element.textContent);
      if (pdfBytes.isEmpty) throw "Empty PDF";
    } catch (exception) {
      return Text("Unable to decode pdf: $exception");
    }

    try {
      return Builder(
          builder: (context) => ContextMenu(
              handleItemTap: (value) {
                _handleItemTap(context, value, pdfBytes, filename);
              },
              items: [
                if (!Platform.isAndroid)
                  const PopupMenuItem(
                      value: "save", child: Text("Save to file")),
                if (Platform.isAndroid || Platform.isIOS)
                  const PopupMenuItem(value: "share", child: Text("Share")),
              ],
              child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: 400, maxHeight: 400),
                  child: PdfViewer(
                    PdfDocumentRefData(pdfBytes, sourceName: "data"),
                  ))));
    } catch (exception) {
      debugPrint("Unable to decode pdf: $exception");
      return Image.asset(
        "assets/images/invalidimg.png",
        width: 300,
        height: 300,
        fit: BoxFit.cover,
      );
    }
  }
}

class AudioElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    Uint8List audioBytes;
    try {
      audioBytes = const Base64Decoder().convert(element.textContent);
    } catch (exception) {
      return Text("Unable to decode pdf: $exception");
    }

    // return Text("Audio bytes ${audioBytes.length}");
    return Consumer<AudioModel>(
        builder: (context, audio, child) => AudioElement(
            mimeType: element.attributes["type"] ?? "audio/ogg",
            audioBytes: audioBytes,
            audio: audio));
  }
}

class DownloadLinkElementBuilder extends MarkdownElementBuilder {
  DownloadLinkElementBuilder();

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var download = element.attributes["fid"] ?? "";
    var tip = "Click to download file $download";
    // Set as the link it is. With no style of its own it fell through to
    // Material's stock text colour -- the seed purple, which is not in the
    // palette and appears nowhere else in the app on purpose.
    return Downloadable(
      tip,
      download,
      Builder(
        builder: (context) => Text(
          element.textContent,
          style: ThemeNotifier.of(context).markdownLinkStyle(preferredStyle),
        ),
      ),
    );
  }
}

class QuoteMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return _QuotedPostCard(
      from: element.attributes["from"] ?? "",
      postId: element.attributes["post"] ?? "",
    );
  }
}

class _QuotedPostCard extends StatefulWidget {
  final String from;
  final String postId;
  const _QuotedPostCard({required this.from, required this.postId});
  @override
  State<_QuotedPostCard> createState() => _QuotedPostCardState();
}

class _QuotedPostCardState extends State<_QuotedPostCard> {
  bool _requested = false;

  Widget _shell(BuildContext context, Widget child, VoidCallback? onTap) {
    final theme = ThemeNotifier.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: theme.surfaceColor(SurfaceColor.surfaceContainer),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: theme.surfaceColor(SurfaceColor.surfaceContainerHigh)),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feed = Provider.of<FeedModel>(context);
    final client = Provider.of<ClientModel>(context, listen: false);
    final post = feed.getPost(widget.from, widget.postId);
    final theme = ThemeNotifier.of(context);

    if (post == null) {
      if (!_requested && widget.from.isNotEmpty && widget.postId.isNotEmpty) {
        _requested = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          feed.getUserPost(widget.from, widget.postId);
        });
      }
      return _shell(
        context,
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text("Loading quoted post...",
              style: TextStyle(
                  fontSize: 13,
                  color: theme.textColor(TextColor.onSurfaceVariant))),
        ),
        null,
      );
    }

    var nick = client.getNick(widget.from);
    if (nick == "") nick = post.summ.authorNick;
    if (nick == "") nick = widget.from;

    // A quoted post is a post, so the Feed area's settings for how a post is
    // presented apply to it as well: no links means none in here either, a
    // text limit cuts this text too, and its own first picture is placed in
    // whatever layout the reader chose. Outside the feed there is no scope
    // and the card is rendered exactly as it always was.
    //
    // The card itself is not made narrower for Left/Right. Those put the
    // *picture* in a column beside the text -- and a quoted post is part of
    // the text, so it sits in the wide column, not the 140px one. What
    // follows the layout is the picture inside this card, which is the thing
    // the setting is about.
    final scope = FeedRenderScope.of(context);
    var content = scope?.constrain(post.content) ?? post.content;

    ExtractedImage? firstImage;
    var imageLayout = FeedImageLayout.standard;
    if (scope != null &&
        scope.imageLayout != FeedImageLayout.standard &&
        !scope.imagesHidden) {
      final (extracted, stripped) = extractFirstImage(content);
      if (extracted != null) {
        firstImage = extracted;
        content = stripped;
        imageLayout = scope.imageLayout;
      }
    }

    Widget body = Provider<DownloadSource>(
      create: (_) => DownloadSource(widget.from),
      child: MarkdownArea(content, false,
          disableLinks: scope?.linksDisabled ?? false,
          plainText: scope?.stripMarkdown ?? false),
    );

    if (firstImage != null) {
      final image = FeedFirstImage(
        bytes: firstImage.bytes,
        tip: firstImage.tip,
        layout: imageLayout,
        cropHeight: scope!.cropHeight,
        onTap: () => FeedScreen.showPost(context, post),
      );
      body = switch (imageLayout) {
        FeedImageLayout.left =>
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 110, child: image),
            const SizedBox(width: 10),
            Expanded(child: body),
          ]),
        FeedImageLayout.right =>
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: body),
            const SizedBox(width: 10),
            SizedBox(width: 110, child: image),
          ]),
        _ => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            body,
            const SizedBox(height: 8),
            image,
          ]),
      };
    }

    return _shell(
      context,
      Padding(
        padding: const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              SizedBox(
                  width: 22,
                  height: 22,
                  child: UserAvatarFromID(client, widget.from, nick: nick)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(nick,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.textColor(TextColor.onSurface))),
              ),
            ]),
            const SizedBox(height: 6),
            body,
          ],
        ),
      ),
      () => FeedScreen.showPost(context, post),
    );
  }
}

class ImageMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    Uint8List imgBytes;
    try {
      imgBytes = const Base64Decoder().convert(element.textContent);
    } catch (exception) {
      return Text("Unable to decode image: $exception");
    }

    var alt = element.attributes["alt"] ?? "";
    var download = element.attributes["fid"] ?? "";
    var tip = "";
    if (alt != "") {
      tip = alt;
      if (download != "") {
        tip += "\n\n";
      }
    }
    if (download != "") {
      tip += "Click to download file $download";
    }
    var type = element.attributes["type"] ?? "";
    var name = element.attributes["name"];

    try {
      return ImageMd(tip, imgBytes, type, name: name);
    } catch (exception) {
      debugPrint("Unable to decode image: $exception");
      return Image.asset(
        "assets/images/invalidimg.png",
        width: 300,
        height: 300,
        fit: BoxFit.cover,
      );
    }
  }
}

class AVIFElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    Uint8List imgBytes;
    try {
      imgBytes = const Base64Decoder().convert(element.textContent);
    } catch (exception) {
      return Text("Unable to decode avif: $exception");
    }

    var alt = element.attributes["alt"] ?? "";
    var download = element.attributes["fid"] ?? "";
    var tip = "";
    if (alt != "") {
      tip = alt;
      if (download != "") {
        tip += "\n\n";
      }
    }
    if (download != "") {
      tip += "Click to download file $download";
    }

    try {
      return AvifMd(tip, imgBytes);
    } catch (exception) {
      debugPrint("Unable to decode avif: $exception");
      return Image.asset(
        "assets/images/invalidimg.png",
        width: 300,
        height: 300,
        fit: BoxFit.cover,
      );
    }
  }
}

class _PayReqBtn extends StatefulWidget {
  final PaymentsModel payments;
  final String invoice;
  const _PayReqBtn(this.payments, this.invoice);

  @override
  State<_PayReqBtn> createState() => __PayReqBtnState();
}

class __PayReqBtnState extends State<_PayReqBtn> {
  late PaymentInfo info;

  void payInfoChanged() {
    setState(() {});
  }

  void attemptPayment() {
    info.attemptPayment();
  }

  @override
  void initState() {
    super.initState();
    info = widget.payments.decodedInvoice(widget.invoice);
    info.addListener(payInfoChanged);
  }

  @override
  void dispose() {
    info.removeListener(payInfoChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (info.decoded == null) {
      return const ElevatedButton(
          onPressed: null, child: Text("Decoding invoice..."));
    }

    String amt = formatDCR(info.decoded?.amount ?? 0);

    if (info.status == PaymentStatus.succeeded) {
      return ElevatedButton(
          onPressed: null, child: Text("Succeeded paying $amt"));
    }

    if (info.status == PaymentStatus.errored) {
      return ElevatedButton(
          onPressed: null, child: Text("Errored paying $amt: ${info.err}"));
    }

    if (info.status == PaymentStatus.inflight) {
      return ElevatedButton(onPressed: null, child: Text("Paying $amt"));
    }

    if (info.decoded?.expired ?? false) {
      return ElevatedButton(
          onPressed: null, child: Text("Invoice $amt expired"));
    }

    return ElevatedButton(onPressed: attemptPayment, child: Text("Pay $amt"));
  }
}

class _LNPayURLElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return Consumer<PaymentsModel>(
        builder: (context, payments, child) =>
            _PayReqBtn(payments, element.textContent));
  }
}
