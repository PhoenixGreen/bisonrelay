import 'dart:convert';
import 'dart:io';
// import 'package:dart_vlc/dart_vlc.dart' as vlc;
import 'package:bruig/components/context_menu.dart';
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

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text(tag, match.group(0) ?? ""));
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
          tag = "pre";
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
    "pre": PreformattedElementBuilder(),
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
  };

  final List<md.InlineSyntax> inlineSyntaxes = [
    LnpayURLSyntax(),
  ];
  final List<FormBlockSyntax> blockSyntaxes = [
    FormBlockSyntax(),
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

  const MarkdownExtension({
    required this.tag,
    required this.builder,
    this.inlineSyntax,
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

  const MarkdownGuideScope(
      {required this.image, required super.child, super.key});

  static ImageRule? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MarkdownGuideScope>()?.image;

  @override
  bool updateShouldNotify(MarkdownGuideScope old) => old.image != image;
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

  /// guideId names the style guide to set this text in, or null to use
  /// whichever the reader has chosen for posts.
  ///
  /// Passed in only where a caller has a reason to override the reader's
  /// choice -- the Settings preview, which has to show a guide that is not
  /// the one in force, and the composer, which shows the writer what the
  /// guide they picked will look like.
  final String? guideId;

  MarkdownArea(srcText, this.hasNick,
      {this.disableLinks = false,
      this.plainText = false,
      this.guideId,
      super.key})
      : text = MarkdownArea._cleanupSrcText(srcText);

  Future<void> launchUrlAwait(context, url) async {
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
    var guide = builtInGuideFor(guideId ?? theme.markdownGuideId);
    if (guide == null || guide.id == defaultGuideId) return theme.mdStyleSheet;

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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<ThemeNotifier, PaymentsModel, MarkdownAreaModel>(
        builder: (context, theme, payments, mk, _) => _withGuide(
              theme,
              MarkdownBody(
                codeBlockMaxHeight: 200,
                // Plain text wins over a guide: it is the Feed's "strip
                // markdown" setting, which is a decision not to show
                // formatting at all, and a guide is only ever about how
                // formatting looks.
                styleSheet: plainText
                    ? _plainStyleSheet(theme.mdStyleSheet, context)
                    : _guidedStyleSheet(theme, context),
                data: text.trim(),
                extensionSet: mk.extensionSet,
                builders: mk.builders,
                onTapLink: (text, url, _) {
                  if (disableLinks) return;
                  launchUrlAwait(context, url);
                },
                inlineSyntaxes: mk.inlineSyntaxes,
                blockSyntaxes: mk.blockSyntaxes,
              ),
            ));
  }

  /// _withGuide puts the guide's picture rules where the embeds can see
  /// them, and nothing at all around text that has no guide.
  Widget _withGuide(ThemeNotifier theme, Widget child) {
    var guide = builtInGuideFor(guideId ?? theme.markdownGuideId);
    if (guide == null || guide.id == defaultGuideId) return child;
    return MarkdownGuideScope(image: guide.image, child: child);
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
BoxConstraints chatImageConstraints(String size, double availableWidth) {
  switch (size) {
    case "half":
      return BoxConstraints(
          maxWidth: availableWidth.isFinite ? availableWidth * 0.5 : 250);
    case "full":
      return BoxConstraints(
          maxWidth: availableWidth.isFinite ? availableWidth : 250);
    default:
      return const BoxConstraints(maxHeight: 250, maxWidth: 250);
  }
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

    var image = Image.memory(
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
            color: rule.borderInk.resolve(theme.markdownRoleColor) ??
                theme.colors.outlineVariant,
            width: rule.boundedBorder);

    Widget sized = LayoutBuilder(
      builder: (context, constraints) => ConstrainedBox(
        // The guide's width is a share of the column it is in, so a picture
        // keeps its proportion of the page at any window size.
        constraints: rule == null
            ? chatImageConstraints(chatImageSize, constraints.maxWidth)
            : BoxConstraints(
                maxWidth: constraints.maxWidth * rule.boundedWidth / 100),
        child: ClipRRect(borderRadius: corners, child: image),
      ),
    );

    if (border != null) {
      sized = Container(
        decoration: BoxDecoration(border: border, borderRadius: corners),
        child: sized,
      );
    }

    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: const BorderRadius.all(Radius.circular(30)),
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
              builder: (context, constraints) => ConstrainedBox(
                constraints:
                    chatImageConstraints(chatImageSize, constraints.maxWidth),
                child: Image(
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

class CodeblockMarkdownElementBuilder extends MarkdownElementBuilder {
  @override
  Widget visitText(md.Text text, TextStyle? preferredStyle) {
    return Text.rich(
      TextSpan(text: text.text),
      style: preferredStyle,
    );
  }
}

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
        Share.shareXFiles([XFile(fname)], text: "Pdf");
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
    return Downloadable(tip, download, Text(element.textContent));
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
            Provider<DownloadSource>(
              create: (_) => DownloadSource(widget.from),
              child: MarkdownArea(post.content, false),
            ),
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
