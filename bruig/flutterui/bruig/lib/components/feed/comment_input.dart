import 'package:bruig/theming_system/theme_preset.dart';
import 'package:bruig/components/inputs.dart';
import 'dart:math';

import 'package:bruig/components/attach_file.dart';
import 'package:bruig/models/emoji.dart';
import 'package:bruig/models/uistate.dart';
import 'package:bruig/screens/chats.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:bruig/components/chat/types.dart';
import 'package:bruig/writing_tools/writing_tools.dart';
import 'package:bruig/theming_system/theme_manager.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:bruig/models/client.dart';

class CommentInput extends StatefulWidget {
  final SendMsg commentReply;
  final String label;
  final String hintText;
  final CustomInputFocusNode inputFocusNode;
  final ChatModel chat;
  const CommentInput(this.commentReply, this.label, this.hintText,
      this.inputFocusNode, this.chat,
      {super.key});

  @override
  State<CommentInput> createState() => _CommentInputState();
}

class _CommentInputState extends State<CommentInput> {
  // Paints the writing marks; a plain controller otherwise.
  final controller = WritingTextEditingController();

  List<AttachmentEmbed> embeds = [];
  bool isAttaching = false;
  // Whether the collapsed tool menu is open, when the Chat area's
  // "Collapse composer icons" is on.
  bool _toolsOpen = false;
  Uint8List? initialAttachData;
  String? initialAttachMime;

  void replaceTextSelection(String s) {
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

  @override
  void initState() {
    super.initState();
    widget.inputFocusNode.noModEnterKeyHandler = sendMsg;
    widget.inputFocusNode.pasteEventHandler = pasteEvent;
    widget.inputFocusNode.addEmojiHandler = addEmoji;
  }

  @override
  void didUpdateWidget(CommentInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    var workingMsg = controller.text;
    if (workingMsg != controller.text) {
      isAttaching = false;
      controller.text = workingMsg;
      controller.selection = TextSelection(
          baseOffset: workingMsg.length, extentOffset: workingMsg.length);
      widget.inputFocusNode.inputFocusNode.requestFocus();
    }
    oldWidget.inputFocusNode.pasteEventHandler = null;
    widget.inputFocusNode.pasteEventHandler = pasteEvent;
    oldWidget.inputFocusNode.addEmojiHandler = null;
    widget.inputFocusNode.addEmojiHandler = addEmoji;
  }

  @override
  void dispose() {
    widget.inputFocusNode.noModEnterKeyHandler = null;
    widget.inputFocusNode.pasteEventHandler = null;
    widget.inputFocusNode.addEmojiHandler = null;
    super.dispose();
  }

  void sendAttachment(String msg) {
    setState(() {
      isAttaching = false;
      initialAttachData = null;
      initialAttachMime = null;
    });
    widget.commentReply(msg);
  }

  void sendMsg() {
    final messageWithoutNewLine = controller.text.trim();
    controller.value = const TextEditingValue(
        text: "", selection: TextSelection.collapsed(offset: 0));
    final String withEmbeds =
        embeds.fold(messageWithoutNewLine, (s, e) => e.replaceInString(s));
    /*
          if (withEmbeds.length > 1024 * 1024) {
            showErrorSnackbar(context,
                "Message is larger than maximum allowed (limit: 1MiB)");
            return;
          }
          */
    if (withEmbeds != "") {
      widget.commentReply(withEmbeds);
      setState(() {
        embeds = [];
      });
    }

    Provider.of<TypingEmojiSelModel>(context, listen: false).clearSelection();
  }

  void addEmoji(Emoji? e) {
    if (e != null) {
      // Selected emoji from panel eidget.
      var oldPos = controller.selection.start;
      var newText = controller.selection.textBefore(controller.text) +
          e.emoji +
          controller.selection.textAfter(controller.text);
      controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: oldPos + e.emoji.length));
      return;
    }

    // Selected emoji from typing panel.
    var typingEmoji = Provider.of<TypingEmojiSelModel>(context, listen: false);
    var newText = typingEmoji.replaceTypedEmojiCode(controller);
    if (newText == "") return;

    var oldPos =
        controller.selection.start - typingEmoji.lastEmojiCode.length + 1;
    controller.value = TextEditingValue(
        text: newText, selection: TextSelection.collapsed(offset: oldPos));
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

  Widget _attachBtn() => IconButton(
      padding: const EdgeInsets.all(0),
      iconSize: 25,
      onPressed: attachFile,
      icon: const Icon(Icons.add_outlined));

  Widget _emojiBtn(BuildContext context) => IconButton(
      padding: const EdgeInsets.all(0),
      iconSize: 25,
      onPressed: () {
        var emojiModel = TypingEmojiSelModel.of(context, listen: false);
        emojiModel.showAddEmojiPanel.value =
            !emojiModel.showAddEmojiPanel.value;
      },
      icon: const Icon(Icons.emoji_emotions_outlined));

  @override
  Widget build(BuildContext context) {
    bool isScreenSmall = checkIsScreenSmall(context);
    // The comment box follows the chat composer's collapse setting (see
    // AreaStyle.collapseComposerIcons): the same two tools, behind the
    // same button, so a theme doesn't collapse one composer and leave the
    // other spread out.
    var collapse = ThemeNotifier.of(context)
        .areaStyle(ThemeArea.chat)
        .collapseComposerIcons;
    return Consumer<ThemeNotifier>(
        builder: (context, theme, _) => isAttaching
            ? Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.start, children: [
                  IconButton(
                      padding: const EdgeInsets.all(0),
                      iconSize: 25,
                      onPressed: cancelAttach,
                      icon: const Icon(Icons.keyboard_arrow_left_outlined))
                ]),
                AttachFileScreen(sendAttachment, initialAttachData,
                    initialAttachMime, widget.chat, cancelAttach)
              ])
            : Row(children: [
                // Collapsed, these move inside the field as its prefix, so
                // the box itself runs the full width.
                if (!collapse) ...[
                  _attachBtn(),
                  const SizedBox(width: 5),
                  _emojiBtn(context),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: TextField(
                    onChanged: (value) {
                      // Check if user is typing an emoji code (:foo:).
                      TypingEmojiSelModel.of(context, listen: false)
                          .maybeSelectEmojis(controller);
                    },
                    autofocus: isScreenSmall ? false : true,
                    focusNode: widget.inputFocusNode.inputFocusNode,
                    controller: controller,
                    minLines: 1,
                    maxLines: null,
                    // Whatever an enabled plugin capability offers for the
                    // text under the pointer, falling back to this composer's
                    // own menu: paste alone, as before.
                    contextMenuBuilder: (BuildContext context,
                            EditableTextState editableTextState) =>
                        writingContextMenu(context, editableTextState,
                            fallbackItems: [
                          ContextMenuButtonItem(
                              onPressed: pasteEvent,
                              type: ContextMenuButtonType.paste),
                        ]),
                    style: theme.textStyleFor(context, TextSize.medium, null),
                    keyboardType: TextInputType.multiline,
                    decoration: themedInputDecoration(
                      context,
                      hintText: widget.hintText,
                      prefixIcon: collapse
                          ? ClipRect(
                              child: AnimatedSize(
                                duration: const Duration(milliseconds: 160),
                                curve: Curves.easeOut,
                                alignment: Alignment.centerLeft,
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        padding: const EdgeInsets.all(0),
                                        iconSize: 25,
                                        tooltip: _toolsOpen ? "Hide" : "More",
                                        onPressed: () => setState(
                                            () => _toolsOpen = !_toolsOpen),
                                        icon: Icon(_toolsOpen
                                            ? Icons.chevron_left
                                            : Icons.more_horiz),
                                      ),
                                      if (_toolsOpen) ...[
                                        const SizedBox(width: 5),
                                        _attachBtn(),
                                        const SizedBox(width: 5),
                                        _emojiBtn(context),
                                      ],
                                    ]),
                              ),
                            )
                          : null,
                      fallbackBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(30.0)),
                        borderSide: BorderSide(width: 2.0),
                      ),
                      suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                                tooltip: widget.label,
                                padding: const EdgeInsets.all(0),
                                iconSize: 20,
                                onPressed: sendMsg,
                                icon: const Icon(Icons.send))
                          ]),
                    ),
                  ),
                ),
              ]));
  }
}
