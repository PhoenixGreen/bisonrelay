import 'dart:convert';
import 'dart:io';

import 'package:bruig/plugin_system/writing_tools/post_library/embed_store.dart';
import 'package:bruig/plugin_system/writing_tools/post_library/post_library.dart';
import 'package:flutter_test/flutter_test.dart';

// page_publish_embeds_test.dart covers the pictures in a published page.
//
// A document being written carries "data=[content abc]" and keeps the bytes
// in the embed store, so the text stays small while it is edited. What is
// published has to have them put back -- publishing the reference gave every
// visitor a page with a hole where the picture was, and the writer no way to
// tell, since their own preview substitutes them before rendering.

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp("bruig-embeds-test");
    PostStorage.rootOverride = root.path;
  });

  tearDown(() async {
    PostStorage.rootOverride = null;
    if (await root.exists()) await root.delete(recursive: true);
  });

  const id = "abcdefghijkl";
  var data = base64Encode(utf8.encode("a picture"));

  test('a reference becomes the picture it stands for', () async {
    await EmbedStore.save(id, data);

    var got = await resolveEmbeds(
        "# Home\n--embed[type=image/png,data=[content $id]]--");

    expect(got, contains("data=$data"));
    expect(got, isNot(contains("[content")));
    // Everything around it is left alone.
    expect(got, contains("# Home"));
  });

  test('a reference with nothing behind it is left as it stands', () async {
    // Publishing a page with one picture missing is a page with one picture
    // missing. Refusing to publish is a site that cannot be updated because
    // of something the writer may not remember adding.
    var src = "--embed[type=image/png,data=[content zzzzzzzzzzzz]]--";
    expect(await resolveEmbeds(src), src);
  });

  test('text with no pictures is returned untouched', () async {
    expect(await resolveEmbeds("# Just words"), "# Just words");
  });

  test('several references are all filled in', () async {
    const other = "mnopqrstuvwx";
    await EmbedStore.save(id, data);
    await EmbedStore.save(other, data);

    var got = await resolveEmbeds(
        "--embed[type=image/png,data=[content $id]]--\n"
        "--embed[type=image/svg+xml,data=[content $other]]--");
    expect("data=$data".allMatches(got).length, 2);
  });
}
