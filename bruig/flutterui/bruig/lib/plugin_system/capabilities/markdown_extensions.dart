import 'package:bruig/components/md_elements.dart';
import 'package:bruig/plugin_system/capabilities/link_card.dart';
import 'package:bruig/plugin_system/plugin_capability.dart';
import 'package:bruig/plugin_system/plugin_manager.dart';

// markdown_extensions.dart is where capabilities that change how a message
// renders meet Bison Relay's markdown pipeline. It is the only file that
// knows both sides, and it adds nothing unless a plugin providing the
// capability is enabled.

// _linkCardTag is the markdown element the link-card capability renders.
// It is private here because nothing outside this file needs to know it --
// the tag, its builder and the syntax that emits it are registered together
// or not at all.
const _linkCardTag = "linkcard";

/// markdownExtensionsFor returns the markdown renderers the currently
/// enabled plugins contribute, for MarkdownAreaModel.setPluginExtensions.
///
/// Returning a whole list (rather than toggling each one) is what keeps the
/// core model's extension point singular: it is handed the complete set
/// every time, and never has to reason about which capability added what.
List<MarkdownExtension> markdownExtensionsFor(PluginManagerModel plugins) => [
      if (plugins.hasCapability(PluginCapability.linkCard))
        MarkdownExtension(
          tag: _linkCardTag,
          builder: LinkCardElementBuilder(),
          // Bare URLs aren't markup, so without a syntax emitting the tag
          // there would be nothing for the builder to render.
          inlineSyntax: BareLinkSyntax(tag: _linkCardTag),
        ),
    ];
