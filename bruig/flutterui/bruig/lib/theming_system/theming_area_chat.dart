import 'package:bruig/components/text.dart';
import 'package:bruig/theming_system/area_options.dart';
import 'package:bruig/theming_system/area_sides.dart';
import 'package:bruig/theming_system/theme_editor.dart';
import 'package:flutter/material.dart';

// theming_area_chat.dart is the "Chat" area's own settings: the chat list's
// styling, the conversation's message layout, the composer's extras, and
// the app-wide avatar theme (which lives here because chat is where avatars
// are most visible -- see AreaStyle.avatarTheme).
List<Widget> chatAreaEditor(AreaEditorContext ctx) {
  var style = ctx.style;
  var layout = style.messageLayoutMode ?? MessageLayoutMode.standard;
  return [
    ctx.choice<AvatarTheme>(
      "Avatar theme",
      value: style.avatarTheme,
      options: AvatarTheme.values,
      labelOf: avatarThemeLabel,
      onChanged: (v) => ctx.setStyle((s) => s.copyWith(avatarTheme: v)),
    ),
    ctx.note("Colors the fallback circle behind a user's initial, for every "
        "avatar in the app. Users with an avatar image of their own are "
        "unaffected."),
    const SizedBox(height: 8),
    ctx.toggle(
      "Reply & pin messages",
      subtitle: "Adds Reply and Pin to the message context menu, with a "
          "reply chip and pinned-message bar in the conversation",
      value: style.enableMessageActions,
      onChanged: (v) => ctx.setStyle((s) => s.copyWith(enableMessageActions: v)),
    ),
    ctx.toggle(
      "Show last message & timestamp",
      subtitle: "Shows a last-message preview and relative timestamp on "
          "each contact/GC row",
      value: style.showChatListLastMessage,
      onChanged: (v) =>
          ctx.setStyle((s) => s.copyWith(showChatListLastMessage: v)),
    ),
    ctx.toggle(
      "Chat list design",
      subtitle: "Rounded, glowing rows with a highlighted selected chat, "
          "instead of the plain list",
      value: style.chatListDesignEnabled,
      onChanged: (v) =>
          ctx.setStyle((s) => s.copyWith(chatListDesignEnabled: v)),
    ),
    // Outside the block below: this one colors the selected chat whether
    // that design is on or off, so hiding it with the design's own settings
    // would put it out of reach in half the cases it applies to.
    ctx.colorPick(
      "Chat selected background color",
      value: style.resolveChatListSelectedColor(ctx.theme),
      valueIndex: style.chatListSelectedColorIndex,
      onChanged: (c, i) => ctx.setStyle((s) => c == null
          ? s.copyWith(
              clearChatListSelectedColor: true,
              clearChatListSelectedColorIndex: true)
          : s.copyWith(
              chatListSelectedColor: c,
              chatListSelectedColorIndex: i,
              clearChatListSelectedColorIndex: i == null)),
    ),
    ctx.note("The selected chat's row, defaulting to Speech Background "
        "(Send)."),
    if (style.chatListDesignEnabled) ...[
      ctx.slider("chatListCornerRadius", style.chatListCornerRadius ?? 14,
          label: (v) => "Row corner radius: ${v.toStringAsFixed(1)}",
          max: 28,
          onCommit: (v) =>
              ctx.setStyle((s) => s.copyWith(chatListCornerRadius: v))),
      ctx.colorPick(
        "Chat items background color",
        value: style.resolveChatListBackgroundColor(ctx.theme),
        valueIndex: style.chatListBackgroundColorIndex,
        onChanged: (c, i) => ctx.setStyle((s) => c == null
            ? s.copyWith(
                clearChatListBackgroundColor: true,
                clearChatListBackgroundColorIndex: true)
            : s.copyWith(
                chatListBackgroundColor: c,
                chatListBackgroundColorIndex: i,
                clearChatListBackgroundColorIndex: i == null)),
      ),
      ctx.note("The row background, defaulting to Content Background. "
          "The hover and top highlights are shaded from it."),
      ctx.colorPick(
        "Accent color",
        value: style.resolveChatListAccentColor(ctx.theme),
        valueIndex: style.chatListAccentColorIndex,
        onChanged: (c, i) => ctx.setStyle((s) => c == null
            ? s.copyWith(
                clearChatListAccentColor: true,
                clearChatListAccentColorIndex: true)
            : s.copyWith(
                chatListAccentColor: c,
                chatListAccentColorIndex: i,
                clearChatListAccentColorIndex: i == null)),
      ),
      // 0 turns the selected-row glow off entirely; 1.0 (the default when
      // unset) matches the original design; above 1 exaggerates it.
      ctx.slider("chatListGlowIntensity", style.chatListGlowIntensity ?? 1.0,
          label: (v) => v <= 0.05
              ? "Selected glow: Off"
              : "Selected glow: ${v.toStringAsFixed(1)}",
          max: 2,
          onCommit: (v) =>
              ctx.setStyle((s) => s.copyWith(chatListGlowIntensity: v))),
      ctx.toggle(
        "Row top highlight",
        subtitle: "Top-left ambient glow and lit hairline on unselected "
            "rows, instead of a flat background",
        value: style.chatListTopHighlight,
        onChanged: (v) =>
            ctx.setStyle((s) => s.copyWith(chatListTopHighlight: v)),
      ),
    ],
    ctx.toggle(
      "Chat backdrop glow",
      subtitle: "Adds a subtle gradient wash behind messages",
      value: style.chatBackdropWash,
      onChanged: (v) => ctx.setStyle((s) => s.copyWith(chatBackdropWash: v)),
    ),
    ctx.toggle(
      "In-chat search",
      subtitle: "Adds a search button to the chat title bar for "
          "searching loaded messages",
      value: style.enableChatSearch,
      onChanged: (v) => ctx.setStyle((s) => s.copyWith(enableChatSearch: v)),
    ),
    ctx.toggle(
      "Formatting toolbar",
      subtitle: "Adds a Bold/Italic/Code/Strikethrough/Link toolbar to "
          "the message composer",
      value: style.formattingToolbar,
      onChanged: (v) => ctx.setStyle((s) => s.copyWith(formattingToolbar: v)),
    ),
    ctx.toggle(
      "Composer polish",
      subtitle: "Inline tip button on 1:1 chats, a glowing send button, "
          "and a per-contact message hint",
      value: style.composerPolish,
      onChanged: (v) => ctx.setStyle((s) => s.copyWith(composerPolish: v)),
    ),
    ctx.toggle(
      "Message bubble corners",
      subtitle: "Sets the corner radius of sent and received bubbles "
          "separately, and how those corners are shaped",
      value: style.bubbleCorners,
      onChanged: (v) => ctx.setStyle((s) => s.copyWith(bubbleCorners: v)),
    ),
    if (style.bubbleCorners) ...[
      ctx.choice<BubbleCornerStyle>(
        "Corner style",
        value: style.bubbleCornerStyle,
        options: BubbleCornerStyle.values,
        labelOf: bubbleCornerStyleLabel,
        onChanged: (v) => ctx.setStyle((s) => s.copyWith(bubbleCornerStyle: v)),
      ),
      const SizedBox(height: 8),
      // Both radii are per *corner* rather than per side, so the split
      // sliders are labelled with corner names.
      ...ctx.spacing(
        key: "bubbleRadiusSent",
        name: "Sent bubble radius",
        max: 28,
        single: style.bubbleRadiusSent,
        sides: style.bubbleRadiusSentSides,
        slotLabels: cornerLabels,
        onSingle: (v) => ctx.setStyle((s) => s.copyWith(bubbleRadiusSent: v)),
        updateSides: (f) => ctx.setStyle((s) {
          var next = f(s.bubbleRadiusSentSides, s.bubbleRadiusSent);
          return s.copyWith(
              bubbleRadiusSentSides: next,
              clearBubbleRadiusSentSides: next == null);
        }),
      ),
      ...ctx.spacing(
        key: "bubbleRadiusReceived",
        name: "Received bubble radius",
        max: 28,
        single: style.bubbleRadiusReceived,
        sides: style.bubbleRadiusReceivedSides,
        slotLabels: cornerLabels,
        onSingle: (v) =>
            ctx.setStyle((s) => s.copyWith(bubbleRadiusReceived: v)),
        updateSides: (f) => ctx.setStyle((s) {
          var next = f(s.bubbleRadiusReceivedSides, s.bubbleRadiusReceived);
          return s.copyWith(
              bubbleRadiusReceivedSides: next,
              clearBubbleRadiusReceivedSides: next == null);
        }),
      ),
    ],
    ctx.choice<MessageLayoutMode>(
      "Message layout",
      value: layout,
      options: MessageLayoutMode.values,
      labelOf: messageLayoutModeLabel,
      onChanged: (m) => ctx.setStyle((s) => m == MessageLayoutMode.standard
          ? s.copyWith(clearMessageLayoutMode: true)
          : s.copyWith(messageLayoutMode: m)),
    ),
    if (layout != MessageLayoutMode.standard)
      ctx.toggle(
        "Expand to fill panel",
        subtitle: "Uses the full conversation panel width instead of "
            "margining the message list in",
        value: style.expandMessageWidth,
        onChanged: (v) =>
            ctx.setStyle((s) => s.copyWith(expandMessageWidth: v)),
      ),
    // The space around the whole conversation viewport (top, sides, and
    // before the input bar); 0 (the default) fills the panel edge-to-edge.
    if (style.expandMessageWidth)
      ...ctx.spacing(
        key: "expandMessagePadding",
        name: "Panel padding",
        max: 48,
        single: style.expandMessagePadding ?? 0,
        sides: style.expandMessagePaddingSides,
        onSingle: (v) =>
            ctx.setStyle((s) => s.copyWith(expandMessagePadding: v)),
        updateSides: (f) => ctx.setStyle((s) {
          var next =
              f(s.expandMessagePaddingSides, s.expandMessagePadding ?? 0);
          return s.copyWith(
              expandMessagePaddingSides: next,
              clearExpandMessagePaddingSides: next == null);
        }),
      ),
    // Chat image size is a global preference (ThemeNotifier.chatImageSize),
    // not a per-preset AreaStyle field, but it belongs with the rest of the
    // chat settings.
    Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        const Txt("Image size: "),
        const SizedBox(width: 8),
        ImageSizeDropdown(ctx.theme),
      ]),
    ),
  ];
}
