import 'dart:io';

// kaykit_packs.dart is KayKit's 3D characters, by Kay Lousberg: rigged,
// animated, CC0, and too large to come with the app -- so each pack is
// offered to download, saying first how much room it takes. The files are
// fetched from KayKit's own GitHub releases at a fixed commit, so the sizes
// said are the sizes fetched.

class KayKitCharacter {
  final String name;
  final String file;

  /// bytes is the file's size at the commit below.
  final int bytes;
  const KayKitCharacter(this.name, this.file, this.bytes);
}

class KayKitPack {
  final String id;
  final String title;
  final String about;
  final String repo;
  final String commit;
  final String folder;
  final List<KayKitCharacter> characters;

  const KayKitPack({
    required this.id,
    required this.title,
    required this.about,
    required this.repo,
    required this.commit,
    required this.folder,
    required this.characters,
  });

  int get bytes => characters.fold(0, (n, c) => n + c.bytes);

  /// page is the pack's home, for the credit each character keeps.
  String get page => "https://github.com/KayKit-Game-Assets/$repo";

  /// url is where [c]'s file is, at the pinned commit.
  String url(KayKitCharacter c) =>
      "https://raw.githubusercontent.com/KayKit-Game-Assets/$repo/$commit/"
      "addons/$folder/Characters/gltf/${c.file}";
}

const kayKitPacks = [
  KayKitPack(
    id: "adventurers",
    title: "Adventurers",
    about: "A barbarian, a knight, a mage and two rogues, low-poly, each "
        "rigged with some 75 animations.",
    repo: "KayKit-Character-Pack-Adventures-1.0",
    commit: "672074b73ba276876a19e8816ecdc5241817ab47",
    folder: "kaykit_character_pack_adventures",
    characters: [
      KayKitCharacter("Barbarian", "Barbarian.glb", 3613268),
      KayKitCharacter("Knight", "Knight.glb", 3659532),
      KayKitCharacter("Mage", "Mage.glb", 3589240),
      KayKitCharacter("Rogue", "Rogue.glb", 3616284),
      KayKitCharacter("Hooded rogue", "Rogue_Hooded.glb", 3597652),
    ],
  ),
  KayKitPack(
    id: "skeletons",
    title: "Skeletons",
    about: "A skeleton mage, minion, rogue and warrior, low-poly, rigged and "
        "animated.",
    repo: "KayKit-Character-Pack-Skeletons-1.0",
    commit: "15b62b9bad122f72926c10fb14d622c73819fa54",
    folder: "kaykit_character_pack_skeletons",
    characters: [
      KayKitCharacter("Skeleton mage", "Skeleton_Mage.glb", 4761048),
      KayKitCharacter("Skeleton minion", "Skeleton_Minion.glb", 4814296),
      KayKitCharacter("Skeleton rogue", "Skeleton_Rogue.glb", 4827024),
      KayKitCharacter("Skeleton warrior", "Skeleton_Warrior.glb", 4863620),
    ],
  ),
];

/// megabytes is [bytes] as people say it: "18.1 MB".
String megabytes(int bytes) => bytes >= 1024 * 1024 * 1024
    ? "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB"
    : "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";

/// freeBytesAt is the room left on the disk holding [dir], or null where
/// it cannot be found out (Windows, or df missing).
Future<int?> freeBytesAt(String dir) async {
  if (Platform.isWindows) return null;
  try {
    var r = await Process.run("df", ["-k", dir]);
    if (r.exitCode != 0) return null;
    return freeBytesFromDf("${r.stdout}");
  } catch (_) {
    return null;
  }
}

/// freeBytesFromDf reads the room left from `df -k`'s answer: the fourth
/// column of its last line, in kilobytes, on macOS and Linux alike.
int? freeBytesFromDf(String out) {
  var lines = out.trim().split("\n").where((l) => l.trim().isNotEmpty).toList();
  if (lines.length < 2) return null;
  var cols = lines.last.trim().split(RegExp(r"\s+"));
  if (cols.length < 4) return null;
  var kb = int.tryParse(cols[3]);
  return kb == null ? null : kb * 1024;
}
