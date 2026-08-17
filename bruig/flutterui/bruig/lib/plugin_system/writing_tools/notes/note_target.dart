import 'package:flutter/foundation.dart';

// note_target.dart is what "the page you are on" means to a note.
//
// One note button serves the whole app, and what it opens depends on where it
// is pressed: a note about the document being previewed, the chat being read,
// the post being looked at. That question has exactly one answer at any
// moment, and this is the type of the answer.
//
// A target is three things, and it is worth being clear which is which,
// because they change independently:
//
//   key    identity, and the only thing notes are filed against. Must be
//          stable across restarts and across renames of whatever it names.
//   kind   which sort of thing this is, which is the first word of the title.
//   label  what the thing is called *right now*, purely to be read.
//
// The label can change -- a group gets renamed, a file is moved -- and when it
// does the note stays where it was rather than being re-filed, because the key
// did not change. That is the right way round: a note about a group is about
// the group, not about what it was called the day it was written.

/// NoteScope is which of the two notes the panel is showing.
enum NoteScope {
  /// The note for the page you are on.
  local,

  /// The app-wide note, the same one everywhere. What it is for is the
  /// writing that does not belong to any one page -- a thought that spans
  /// three chats and a file, or somewhere to put something while you decide
  /// where it goes.
  global,
}

@immutable
class NoteTarget {
  /// kind is the first word of the title: "Document", "Chat", "Post", "Page".
  final String kind;

  /// key identifies the thing this note is about, for the lifetime of the
  /// thing. Prefixed by kind so a chat and a document can never collide on a
  /// shared id.
  final String key;

  /// label is the thing's current name, for reading only.
  final String label;

  const NoteTarget._(this.kind, this.key, this.label);

  /// global is the app-wide note. A constant rather than something looked up:
  /// there is one of it, always, and it is what the panel falls back to on
  /// every page that has nothing of its own.
  static const global = NoteTarget._("Global", "global", "Notes");

  bool get isGlobal => key == global.key;

  /// document is a note about a file on disk, keyed by its path.
  ///
  /// The path and not the contents: a file that is edited is still the same
  /// file, and hashing it would mean re-reading every document to find its
  /// notes. The cost is that moving a file loses its note, which is the same
  /// bargain the reading-position sidecar makes.
  factory NoteTarget.document(String filePath, {String? name}) => NoteTarget._(
      "Document", "document:$filePath", name ?? _basename(filePath));

  /// chat is a note about one conversation, keyed by the chat's own id.
  ///
  /// Group chats get "Group" after the name -- a note titled "Chat - Trading"
  /// does not say whether that is a person or a room -- unless the name
  /// already ends in it, which would otherwise read "Trading Group Group".
  factory NoteTarget.chat(String id, String nick, {bool isGC = false}) {
    var label = nick.trim().isEmpty ? id : nick.trim();
    if (isGC && !label.toLowerCase().endsWith("group")) label = "$label Group";
    return NoteTarget._("Chat", "chat:$id", label);
  }

  /// post is a note about one post in the feed, keyed by its author and id
  /// together -- a post id is unique to its author, not to the network.
  factory NoteTarget.post(String from, String id, String title) => NoteTarget._(
      "Post",
      "post:$from/$id",
      title.trim().isEmpty ? "Untitled" : title.trim());

  /// page is a note about a screen rather than about anything on it -- the
  /// Downloads list, the Shared list. Keyed by the route, which is what makes
  /// it the same note every time you come back to that page.
  factory NoteTarget.page(String route, String label) =>
      NoteTarget._("Page", "page:$route", label);

  /// title is what the note is called when it is first written, and the name
  /// its file is given.
  ///
  /// A dash rather than the colon it reads better with: this becomes a
  /// filename, and PostStorage.sanitizeName drops a colon -- rightly, since it
  /// is not legal in a path on Windows. One name that is both the row in the
  /// sidebar and the file on disk is worth more than the punctuation.
  String get title => isGlobal ? "Global Notes" : "$kind - $label";

  /// _basename is a path reduced to what the document is called: no folders,
  /// and no extension.
  ///
  /// The extension goes because the title becomes a filename, and
  /// PostStorage.sanitizeName turns a dot into a dash -- so "Mastering Go.pdf"
  /// would file itself as "Document - Mastering Go-pdf", which is nobody's
  /// idea of a title. Dropping it reads better anyway: a note is about the
  /// book, not about the PDF of it.
  ///
  /// Two files in one folder differing only by extension are still two
  /// different targets and still get two different notes -- the second is
  /// suffixed rather than merged. See NoteStorage.
  static String _basename(String filePath) {
    var cut = filePath.lastIndexOf(RegExp(r"[/\\]"));
    var name = cut < 0 ? filePath : filePath.substring(cut + 1);
    var dot = name.lastIndexOf(".");
    // Not a leading dot: ".bashrc" is a name, not an extension on nothing.
    return dot > 0 ? name.substring(0, dot) : name;
  }

  @override
  bool operator ==(Object other) => other is NoteTarget && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => "NoteTarget($key)";
}
