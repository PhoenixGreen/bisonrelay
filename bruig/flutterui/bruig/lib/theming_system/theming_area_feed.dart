import 'package:bruig/theming_system/area_options.dart';
import 'package:bruig/theming_system/theming_areas_section.dart';
import 'package:flutter/material.dart';

// theming_area_feed.dart is the "Feed" area's own settings: the post card
// redesign and its dependent features, the inline composer, and how each
// post's text/images/links are presented.
List<Widget> feedAreaEditor(AreaEditorContext ctx) {
  var style = ctx.style;
  return [
    ctx.toggle(
      "Feed card redesign",
      subtitle: "X-style borderless post cards, live comment count, a "
          "height-clamped body with \"Show more\", and a centered "
          "post-detail view",
      value: style.feedCardRedesign,
      onChanged: (v) => ctx.setStyle((s) => s.copyWith(feedCardRedesign: v)),
    ),
    ctx.toggle(
      "Post actions: relay, tip, quote",
      subtitle: "Relay, tip, quote, bookmark and hide, on each card's "
          "action bar, with nested quote-post rendering (requires Feed "
          "card redesign)",
      value: style.feedCardActions,
      onChanged: (v) => ctx.setStyle((s) => s.copyWith(feedCardActions: v)),
    ),
    ctx.toggle(
      "Feed side panel",
      subtitle: "Search, sort, and an unread-only filter in a nav rail, "
          "replacing the plain tab bar on the main feed tab. Follows the "
          "Sidebar area's Visibility, Sidebar Accent and Sidebar "
          "Background",
      value: style.feedSidePanel,
      onChanged: (v) => ctx.setStyle((s) => s.copyWith(feedSidePanel: v)),
    ),
    ctx.toggle(
      "Inline composer",
      subtitle: "A \"What's happening?\" composer at the top of the feed. "
          "Collapsed to a single line until you start typing, then it "
          "opens up with formatting, attachments and drafts",
      value: style.feedInlineComposer,
      onChanged: (v) => ctx.setStyle((s) => s.copyWith(feedInlineComposer: v)),
    ),
    ctx.toggle(
      "Hide sidebar when reading a post",
      subtitle: "Drops the feed sidebar while viewing a single post, for "
          "a more focused reading experience (requires Feed side "
          "panel)",
      value: style.feedHideSidebarOnPost,
      onChanged: (v) =>
          ctx.setStyle((s) => s.copyWith(feedHideSidebarOnPost: v)),
    ),
    ctx.choice<FeedImageLayout>(
      "First image display",
      value: style.feedImageLayout,
      options: FeedImageLayout.values,
      labelOf: feedImageLayoutLabel,
      onChanged: (m) => ctx.setStyle((s) => s.copyWith(feedImageLayout: m)),
    ),
    // Also applies to posts randomly assigned "cropped" by
    // FeedImageLayout.random, not just an explicit "cropped" pick.
    if (style.feedImageLayout == FeedImageLayout.cropped ||
        style.feedImageLayout == FeedImageLayout.random)
      ctx.slider("feedImageCropHeight", style.feedImageCropHeight,
          label: (v) => "Cropped image max height: ${v.toStringAsFixed(0)}",
          min: 100,
          max: 800,
          onCommit: (v) =>
              ctx.setStyle((s) => s.copyWith(feedImageCropHeight: v))),
    ctx.choice<FeedTextOrder>(
      "Text order",
      value: style.feedTextOrder,
      options: FeedTextOrder.values,
      labelOf: feedTextOrderLabel,
      onChanged: (o) => ctx.setStyle((s) => s.copyWith(feedTextOrder: o)),
    ),
    ctx.note("Only affects Default, Full width, and Full width cropped "
        "(text before or after the image); Left/Right are unaffected."),
    ctx.choice<FeedLinksMode>(
      "Links",
      value: style.feedLinksMode,
      options: FeedLinksMode.values,
      labelOf: feedLinksModeLabel,
      onChanged: (m) => ctx.setStyle((s) => s.copyWith(feedLinksMode: m)),
    ),
    ctx.note("Strips links out of post bodies on the feed page, either "
        "always or only for posts that have an image."),
    ctx.slider("feedTextLimit", style.feedTextLimit,
        label: (v) => v == 0
            ? "Limit text: No limit"
            : "Limit text: ${v.toStringAsFixed(0)} characters",
        max: 2000,
        divisions: 40,
        onCommit: (v) => ctx.setStyle((s) => s.copyWith(feedTextLimit: v))),
    ctx.toggle(
      "Strip markdown formatting",
      subtitle: "Renders post text as plain text -- headers, bold, italic, "
          "and strikethrough all look like normal text",
      value: style.feedStripMarkdown,
      onChanged: (v) => ctx.setStyle((s) => s.copyWith(feedStripMarkdown: v)),
    ),
  ];
}
