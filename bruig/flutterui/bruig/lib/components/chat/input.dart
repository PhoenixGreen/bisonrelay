import 'package:bruig/components/inputs.dart';
import 'dart:math';

import 'package:bruig/components/attach_file.dart';
import 'package:bruig/components/pay_tip.dart';
import 'package:bruig/components/snackbars.dart';
import 'package:bruig/models/emoji.dart';
import 'package:bruig/components/icons.dart';
import 'package:bruig/components/chat/record_audio.dart';
import 'package:bruig/models/audio.dart';
import 'package:bruig/models/uistate.dart';
import 'package:bruig/screens/chats.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:bruig/components/chat/types.dart';
import 'package:bruig/models/client.dart';
import 'package:bruig/plugin_system/plugin_system.dart';
import 'package:bruig/theming_system/theme_preset.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/services.dart';
import 'package:golib_plugin/golib_plugin.dart';
import 'package:provider/provider.dart';
import 'package:super_clipboard/super_clipboard.dart';

final _crToLfRegexp = RegExp(r'\r\n|\r');

class ChatInput extends StatefulWidget {
  final SendMsg _send;
  final ChatModel chat;
  final CustomInputFocusNode inputFocusNode;
  final bool allowAudio;
  const ChatInput(this._send, this.chat, this.inputFocusNode,
      {this.allowAudio = true, super.key});

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final controller = TextEditingController();
  final MenuController _fmtMenuCtl = MenuController();

  // Whether the collapsed tool menu is open (see
  // AreaStyle.collapseComposerIcons). Closed on every rebuild would fight
  // the user; it stays open until they close it or leave the chat.
  bool _toolsOpen = false;

  late AudioModel audio;
  List<AttachmentEmbed> embeds = [];
  bool isAttaching = false;
  bool isRecordingAudio = false;
  Uint8List? initialAttachData;
  String? initialAttachMime;
  bool wasEmptyText = true;

  void replaceTextSelection(String s) {
    s = s.replaceAll(_crToLfRegexp, '\n'); // Switch CRLF to LF.
    var sel = controller.selection.copyWith();
    if (controller.selection.start == -1 && controller.selection.end == -1) {
      controller.text = controller.text + s;
    } else if (sel.isCollapsed) {
      controller.text = controller.text.substring(0, sel.start) +
          s +
          controller.text.substring(min(controller.text.length, sel.start));
      var newPos = sel.baseOffset + s.length;
      controller.selection =
          sel.copyWith(baseOffset: newPos, extentOffset: newPos);
    } else {
      controller.text =
          controller.text.substring(0, controller.selection.start) +
              s +
              controller.text.substring(controller.selection.end);
      var newPos = sel.baseOffset + s.length;
      controller.selection =
          sel.copyWith(baseOffset: newPos, extentOffset: newPos);
    }
  }

  Future<void> pasteEvent() async {
    final clip = SystemClipboard.instance;
    if (clip == null) {
      // Clipboard API is not supported on this platform. Use the standard.
      replaceTextSelection(Clipboard.kTextPlain);
      return;
    }
    final reader = await clip.read();

    /// Binary formats need to be read as streams
    if (reader.canProvide(Formats.png)) {
      reader.getFile(Formats.png, (file) async {
        final stream = await file.readAll();
        setState(() {
          initialAttachData = stream;
          initialAttachMime = "image/png";
          isAttaching = true;
        });
      });
      return;
    }

    // Automatically convert to markdown?
    // if (reader.canProvide(Formats.htmlText)) {
    //   final html = await reader.readValue(Formats.htmlText);
    //   print("XXXX clip is html $html");
    // }

    if (reader.canProvide(Formats.plainText)) {
      final text = await reader.readValue(Formats.plainText);
      replaceTextSelection(text ?? "");
      return;
    }
  }

  void controllerUpdated() {
    bool changedEmpty = (wasEmptyText && controller.text != "") ||
        (!wasEmptyText && controller.text == "");
    if (changedEmpty) {
      setState(() {
        wasEmptyText = controller.text == "";
      });
    }
  }

  bool containsUnkxdMembers = false;

  void containsUnxkdChanged() async {
    setState(() {
      containsUnkxdMembers =
          widget.chat.unkxdMembers.value?.isNotEmpty ?? false;
    });
  }

  bool _wasReplying = false;

  // Focus the input the moment a reply gets set, so typing can start at
  // once. Only meaningful when AreaStyle.enableMessageActions is on --
  // replyToMsg is otherwise never set.
  void _onChatReplyChanged() {
    final replying = widget.chat.replyToMsg != null;
    if (replying && !_wasReplying) {
      widget.inputFocusNode.inputFocusNode.requestFocus();
    }
    _wasReplying = replying;
  }

  @override
  void initState() {
    super.initState();
    controller.addListener(() {
      // Snapshot last good caret while user is typing/moving it.
      widget.inputFocusNode.saveSelection();
    });
    widget.inputFocusNode.controller = controller;
    controller.text = widget.chat.workingMsg;
    widget.inputFocusNode.noModEnterKeyHandler = sendMsg;
    widget.inputFocusNode.pasteEventHandler = pasteEvent;
    widget.inputFocusNode.addEmojiHandler = addEmoji;
    widget.chat.unkxdMembers.addListener(containsUnxkdChanged);
    containsUnkxdMembers = widget.chat.unkxdMembers.value?.isNotEmpty ?? false;
    controller.addListener(controllerUpdated);
    widget.chat.addListener(_onChatReplyChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    audio = Provider.of<AudioModel>(context);
  }

  @override
  void didUpdateWidget(ChatInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    var workingMsg = widget.chat.workingMsg;
    if (workingMsg != controller.text) {
      cancelAttach(callSetState: false);
      controller.text = workingMsg;
      controller.selection = TextSelection(
          baseOffset: workingMsg.length, extentOffset: workingMsg.length);
      widget.inputFocusNode.inputFocusNode.requestFocus();
    }
    oldWidget.inputFocusNode.pasteEventHandler = null;
    widget.inputFocusNode.pasteEventHandler = pasteEvent;
    oldWidget.inputFocusNode.addEmojiHandler = null;
    widget.inputFocusNode.addEmojiHandler = addEmoji;
    if (oldWidget.chat != widget.chat) {
      oldWidget.chat.unkxdMembers.removeListener(containsUnxkdChanged);
      widget.chat.unkxdMembers.addListener(containsUnxkdChanged);
      oldWidget.chat.removeListener(_onChatReplyChanged);
      widget.chat.addListener(_onChatReplyChanged);
      containsUnkxdMembers =
          widget.chat.unkxdMembers.value?.isNotEmpty ?? false;
      cancelAttach(callSetState: false);
    }
  }

  @override
  void dispose() {
    widget.inputFocusNode.controller = null;
    widget.inputFocusNode.noModEnterKeyHandler = null;
    widget.inputFocusNode.pasteEventHandler = null;
    widget.inputFocusNode.addEmojiHandler = null;
    widget.chat.unkxdMembers.removeListener(containsUnxkdChanged);
    widget.chat.removeListener(_onChatReplyChanged);
    super.dispose();
  }

  void sendAttachment(String msg) {
    cancelAttach();
    widget._send(msg);
  }

  void sendMsg() {
    final messageWithoutNewLine = controller.text.trim();
    controller.value = const TextEditingValue(
        text: "", selection: TextSelection.collapsed(offset: 0));
    final String withEmbeds =
        embeds.fold(messageWithoutNewLine, (s, e) => e.replaceInString(s));
    if (withEmbeds.length > Golib.maxPayloadSize) {
      showErrorSnackbar(context,
          "Message is larger than maximum allowed (limit: ${Golib.maxPayloadSizeStr})");
      return;
    }
    if (withEmbeds != "") {
      var toSend = withEmbeds;
      final rNick = widget.chat.replyToNick;
      final rMsg = widget.chat.replyToMsg;
      if (rNick != null && rMsg != null) {
        var quoted = rMsg.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (quoted.contains('--embed[')) quoted = '[attachment]';
        if (quoted.length > 120) quoted = '${quoted.substring(0, 120)}...';
        toSend = '> **$rNick:** $quoted\n\n$withEmbeds';
        widget.chat.clearReplyTo();
      }
      widget._send(toSend);
      widget.chat.workingMsg = "";
      setState(() {
        embeds = [];
      });
    }

    Provider.of<TypingEmojiSelModel>(context, listen: false).clearSelection();
  }

  void addEmoji(Emoji? e) {
    if (e != null) {
      // Insert emoji at current caret/selection; move caret after it.
      var sel = controller.selection;
      if (!sel.isValid) {
        // Fallback to last saved caret, or end of text.
        sel = widget.inputFocusNode.takeSavedSelection() ??
            TextSelection.collapsed(offset: controller.text.length);
      }

      final text = controller.text;
      final len = text.length;
      final start = sel.start.clamp(0, len);
      final end = sel.end.clamp(0, len);

      final before = text.substring(0, start);
      final after = text.substring(end);
      final newText = before + e.emoji + after;
      final newOff = before.length + e.emoji.length; // caret after emoji

      widget.chat.workingMsg = newText;
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newOff),
        composing: TextRange.empty,
      );

      widget.inputFocusNode.inputFocusNode.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.inputFocusNode
            .saveSelection(); // so closing picker restores here
      });
      return;
    }

    widget.inputFocusNode.inputFocusNode.requestFocus();
    // Selected emoji from typing panel.
    final typingEmoji =
        Provider.of<TypingEmojiSelModel>(context, listen: false);
    final oldText = controller.text;
    final caret = controller.selection.start;
    final codeLen =
        typingEmoji.lastEmojiCode.length; // length of shortcut including ':'

    // Replace the shortcode; this returns the full updated text.
    final newText = typingEmoji.replaceTypedEmojiCode(controller);
    if (newText == "") return;

    // Emoji length = newText - (oldText - codeLen) in UTF-16 units.
    final emojiLen = newText.length - (oldText.length - codeLen);
    final newCaret = caret + (emojiLen - codeLen); // move caret after the emoji

    widget.chat.workingMsg = newText;
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCaret),
      composing: TextRange.empty,
    );
  }

  void attachFile() {
    setState(() {
      isAttaching = true;
    });
  }

  void cancelAttach({callSetState = true}) {
    void doCancel() {
      isAttaching = false;
      initialAttachData = null;
      initialAttachMime = null;
      widget.inputFocusNode.inputFocusNode.requestFocus();
    }

    if (callSetState) {
      setState(doCancel);
    } else {
      doCancel();
    }
  }

  void recordAudioNote() {
    setState(() => isRecordingAudio = true);
  }

  void cancelAudioNote() {
    setState(() => isRecordingAudio = false);
  }

  void _toggleEmojiPanel() {
    final emojiModel = TypingEmojiSelModel.of(context, listen: false);

    final wasOpen = emojiModel.showAddEmojiPanel.value;

    emojiModel.showAddEmojiPanel.value = !wasOpen;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final saved = widget.inputFocusNode.takeSavedSelection();
      if (saved != null) {
        final len = controller.text.length;
        final clamped = TextSelection(
          baseOffset: saved.start.clamp(0, len),
          extentOffset: saved.end.clamp(0, len),
          affinity: saved.affinity,
          isDirectional: saved.isDirectional,
        );
        controller.value = controller.value.copyWith(
          selection: clamped,
          composing: TextRange.empty,
        );
      }
    });
  }

  // Wrap the current selection (or insert at the cursor) with markdown
  // markers, then place the cursor sensibly and keep focus in the input.
  // Only reachable when AreaStyle.formattingToolbar is on.
  void wrapSelection(String left, String right) {
    final text = controller.text;
    final sel = controller.selection;
    var start = sel.start;
    var end = sel.end;
    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }
    final selected = text.substring(start, end);
    final newText = text.substring(0, start) +
        left +
        selected +
        right +
        text.substring(end);
    final innerStart = start + left.length;
    final innerEnd = innerStart + selected.length;
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection(baseOffset: innerStart, extentOffset: innerEnd),
    );
    widget.chat.workingMsg = newText;
    setState(() {});
    widget.inputFocusNode.inputFocusNode.requestFocus();
  }

  // Insert a markdown link [label](url), selecting the url placeholder.
  void insertLink() {
    final text = controller.text;
    final sel = controller.selection;
    var start = sel.start;
    var end = sel.end;
    if (start < 0 || end < 0) {
      start = text.length;
      end = text.length;
    }
    final selected = text.substring(start, end);
    final label = selected.isEmpty ? "text" : selected;
    const url = "url";
    final newText =
        "${text.substring(0, start)}[$label]($url)${text.substring(end)}";
    final urlStart = start + 1 + label.length + 2;
    final urlEnd = urlStart + url.length;
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection(baseOffset: urlStart, extentOffset: urlEnd),
    );
    widget.chat.workingMsg = newText;
    setState(() {});
    widget.inputFocusNode.inputFocusNode.requestFocus();
  }

  void _fmt(void Function() apply) {
    apply();
    _fmtMenuCtl.close();
  }

  // _buildReplyChip renders the dismissible "Replying to <nick>" chip above
  // the composer, when AreaStyle.enableMessageActions is on and a reply
  // target is set.
  Widget _buildReplyChip() {
    return AnimatedBuilder(
      animation: widget.chat,
      builder: (context, _) {
        final rNick = widget.chat.replyToNick;
        final rMsg = widget.chat.replyToMsg;
        if (rNick == null || rMsg == null) return const SizedBox.shrink();
        var preview = rMsg.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (preview.contains('--embed[')) preview = '[attachment]';
        if (preview.length > 80) preview = '${preview.substring(0, 80)}...';
        var theme = Provider.of<ThemeNotifier>(context);
        var accent =
            theme.activePreset?.sidebarAccent ?? const Color(0xFF2C6BED);
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: theme.activePreset?.fourth ?? const Color(0xFF171A1F),
            border: Border(left: BorderSide(color: accent, width: 3)),
          ),
          padding: const EdgeInsets.fromLTRB(9, 6, 6, 6),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Replying to $rNick",
                      style: TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                  Text(preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFF9A9A9A), fontSize: 12)),
                ],
              ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              iconSize: 18,
              onPressed: widget.chat.clearReplyTo,
              icon: const Icon(Icons.close, color: Color(0xFF6B6B6B)),
            ),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isScreenSmall = checkIsScreenSmall(context);

    if (isAttaching) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IconButton(
            padding: const EdgeInsets.all(0),
            iconSize: 25,
            onPressed: cancelAttach,
            icon: const Icon(Icons.keyboard_arrow_left_outlined)),
        AttachFileScreen(sendAttachment, initialAttachData, initialAttachMime,
            widget.chat, cancelAttach)
      ]);
    }

    var theme = Provider.of<ThemeNotifier>(context, listen: false);

    if (audio.recording || audio.hasRecord) {
      return Row(children: [
        Expanded(
            child:
                RecordAudioInputPanel(audio: audio, sendMsg: sendAttachment)),
        const RecordAudioInputButton(),
      ]);
    }

    var chatStyle = theme.areaStyle(ThemeArea.chat);
    var enableMessageActions = chatStyle.enableMessageActions;
    var formattingToolbar = chatStyle.formattingToolbar;
    var composerPolish = chatStyle.composerPolish;

    // The composer's tools, built once and placed either along the input
    // row (the original layout) or inside the collapsed menu.
    var emojiBtn = IconButton(
      focusNode: FocusNode(canRequestFocus: false, skipTraversal: true),
      onPressed: _toggleEmojiPanel,
      icon: const Icon(Icons.emoji_emotions_outlined),
    );
    var formatBtn = MenuAnchor(
      controller: _fmtMenuCtl,
      builder: (context, ctl, child) => IconButton(
        padding: const EdgeInsets.all(0),
        tooltip: "Formatting",
        onPressed: () => ctl.isOpen ? ctl.close() : ctl.open(),
        icon: const Icon(Icons.text_format),
      ),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
                tooltip: "Bold",
                icon: const Icon(Icons.format_bold),
                onPressed: () => _fmt(() => wrapSelection("**", "**"))),
            IconButton(
                tooltip: "Italic",
                icon: const Icon(Icons.format_italic),
                onPressed: () => _fmt(() => wrapSelection("_", "_"))),
            IconButton(
                tooltip: "Code",
                icon: const Icon(Icons.code),
                onPressed: () => _fmt(() => wrapSelection("`", "`"))),
            IconButton(
                tooltip: "Strikethrough",
                icon: const Icon(Icons.format_strikethrough),
                onPressed: () => _fmt(() => wrapSelection("~~", "~~"))),
            IconButton(
                tooltip: "Link",
                icon: const Icon(Icons.link),
                onPressed: () => _fmt(insertLink)),
          ]),
        ),
      ],
    );
    var attachBtn =
        IconButton(onPressed: attachFile, icon: const Icon(Icons.attach_file));
    var tipBtn = IconButton(
        padding: const EdgeInsets.all(0),
        tooltip: "Pay tip",
        onPressed: () => showPayTipModalBottom(context, widget.chat),
        icon: Icon(Icons.bolt, color: const Color(0xFF1DFF8C), shadows: [
          Shadow(
            color: const Color(0xFF1DFF8C).withValues(alpha: 0.55),
            blurRadius: 8,
          ),
        ]));
    const unkxdWarning = Tooltip(
        message: "There are un-kx'd members in this GC.\n"
            "These members won't receive messages from you until the KX "
            "process completes.\nThis usually happens automatically, after "
            "they come back online.",
        child:
            ColoredIcon(Icons.warning_amber_outlined, color: TextColor.error));
    var sendBtn = IconButton(
        padding: const EdgeInsets.all(0),
        iconSize: 20,
        onPressed: sendMsg,
        icon: Icon(Icons.send,
            color: composerPolish && controller.text.trim().isNotEmpty
                ? const Color(0xFF1DFF8C)
                : null));

    // Collapsed, every tool lives behind one button that opens them to the
    // right (see AreaStyle.collapseComposerIcons). The microphone comes
    // inside with them, which is what lets the field have the whole row --
    // it otherwise sits outside the box entirely. Send stays where it is:
    // it's the one button that shouldn't take two taps.
    var collapse = chatStyle.collapseComposerIcons;
    var collapsedTools = <Widget>[
      emojiBtn,
      if (formattingToolbar) formatBtn,
      attachBtn,
      if (composerPolish && !widget.chat.isGC) tipBtn,
      if (widget.allowAudio) const RecordAudioInputButton(),
    ];

    var inputRow = Row(children: [
      Expanded(
        child: SpellcheckedFieldScope(
          child: TextField(
            onChanged: (value) {
              widget.chat.workingMsg = value;

              // Check if user is typing an emoji code (:foo:).
              TypingEmojiSelModel.of(context, listen: false)
                  .maybeSelectEmojis(controller);
            },
            autofocus: isScreenSmall ? false : true,
            focusNode: widget.inputFocusNode.inputFocusNode,
            controller: controller,
            minLines: 1,
            maxLines: null,
            contextMenuBuilder:
                (BuildContext context, EditableTextState editableTextState) =>
                    AdaptiveTextSelectionToolbar.buttonItems(
              anchors: editableTextState.contextMenuAnchors,
              buttonItems: [
                // Corrections lead: on a word flagged as misspelled they are
                // the reason the menu was opened.
                ...spellingContextMenuItems(context, editableTextState),
                // Paste alone, as before -- the other standard entries were
                // deliberately left out of this composer.
                ContextMenuButtonItem(
                    onPressed: pasteEvent, type: ContextMenuButtonType.paste),
                // Whatever an enabled plugin capability adds; empty when none
                // does, which is why nothing here names one.
                ...thesaurusContextMenuItems(context, editableTextState),
              ],
            ),
            style: theme.textStyleFor(context, TextSize.medium, null),
            keyboardType: TextInputType.multiline,
            key: Provider.of<SpellcheckCapability>(context).fieldKey,
            spellCheckConfiguration:
                Provider.of<SpellcheckCapability>(context).configuration,
            decoration: themedInputDecoration(
              context,
              hintText: composerPolish
                  ? "Message ${widget.chat.nick}"
                  : "Start a message",
              fallbackBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(30.0)),
                borderSide: BorderSide(width: 2.0),
              ),
              prefixIcon: collapse
                  ? ClipRect(
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        alignment: Alignment.centerLeft,
                        // Capped at half the window and scrollable inside
                        // that: five tool buttons are wider than a phone's
                        // composer, and the point of collapsing them is to
                        // leave the field room, not to take it all back the
                        // moment the menu opens.
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width * 0.5),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                focusNode: FocusNode(
                                    canRequestFocus: false,
                                    skipTraversal: true),
                                tooltip: _toolsOpen ? "Hide tools" : "More",
                                onPressed: () =>
                                    setState(() => _toolsOpen = !_toolsOpen),
                                icon: Icon(_toolsOpen
                                    ? Icons.chevron_left
                                    : Icons.more_horiz),
                              ),
                              if (_toolsOpen) ...collapsedTools,
                            ]),
                          ),
                        ),
                      ),
                    )
                  : emojiBtn,
              suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!collapse) ...[
                      if (formattingToolbar) formatBtn,
                      if (!isScreenSmall || controller.text == "") attachBtn,
                      if (composerPolish &&
                          !widget.chat.isGC &&
                          (!isScreenSmall || controller.text == ""))
                        tipBtn,
                    ],
                    if (containsUnkxdMembers &&
                        (!isScreenSmall || controller.text == "" || collapse))
                      unkxdWarning,
                    sendBtn,
                  ]),
            ),
          ),
        ),
      ),
      // Collapsed, the microphone is inside the menu instead (above).
      if (!collapse &&
          (!isScreenSmall || controller.text == "") &&
          widget.allowAudio) ...[
        const SizedBox(width: 5),
        const RecordAudioInputButton(),
      ],
    ]);

    if (!enableMessageActions) return inputRow;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_buildReplyChip(), inputRow],
    );
  }
}
