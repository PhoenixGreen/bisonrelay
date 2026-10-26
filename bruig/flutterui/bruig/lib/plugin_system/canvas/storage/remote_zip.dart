import 'dart:io';
import 'dart:typed_data';

// remote_zip.dart reads files out of a zip on a web server without
// downloading the whole of it: the table of contents at its end first, then
// only the files wanted, each by its own range of bytes. What makes a
// collection of a few hundred megabytes cost the few that are used.

/// RemoteZip is a zip at [url], its table of contents read.
class RemoteZip {
  final String url;
  final Map<String, ({int method, int size, int offset})> entries;
  RemoteZip._(this.url, this.entries);

  static Future<Uint8List> _range(String url, int from, int to) async {
    var client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      var request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.rangeHeader, "bytes=$from-$to");
      var response = await request.close();
      if (response.statusCode != 206 && response.statusCode != 200) {
        throw "The server answered ${response.statusCode}.";
      }
      var b = BytesBuilder();
      await for (var chunk in response) {
        b.add(chunk);
      }
      var bytes = b.takeBytes();
      // A server that ignores ranges sends the whole file.
      if (response.statusCode == 200) {
        return Uint8List.sublistView(bytes, from, to + 1);
      }
      return bytes;
    } finally {
      client.close();
    }
  }

  /// open reads the table of contents of the zip at [url].
  static Future<RemoteZip> open(String url) async {
    var client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    int size;
    try {
      var response = await (await client.headUrl(Uri.parse(url))).close();
      await response.drain<void>();
      size = response.contentLength;
    } finally {
      client.close();
    }
    if (size <= 22) throw "The collection could not be found.";
    var tailFrom = size > 65558 ? size - 65558 : 0;
    var tail = await _range(url, tailFrom, size - 1);
    var t = ByteData.sublistView(tail);
    var end = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (t.getUint32(i, Endian.little) == 0x06054b50) {
        end = i;
        break;
      }
    }
    if (end < 0) throw "The collection is not a zip that can be read.";
    var cdSize = t.getUint32(end + 12, Endian.little);
    var cdOffset = t.getUint32(end + 16, Endian.little);
    var cd = await _range(url, cdOffset, cdOffset + cdSize - 1);
    var c = ByteData.sublistView(cd);
    var entries = <String, ({int method, int size, int offset})>{};
    var p = 0;
    while (p + 46 <= cd.length && c.getUint32(p, Endian.little) == 0x02014b50) {
      var method = c.getUint16(p + 10, Endian.little);
      var compressed = c.getUint32(p + 20, Endian.little);
      var nameLength = c.getUint16(p + 28, Endian.little);
      var extra = c.getUint16(p + 30, Endian.little);
      var comment = c.getUint16(p + 32, Endian.little);
      var local = c.getUint32(p + 42, Endian.little);
      var name = String.fromCharCodes(cd.sublist(p + 46, p + 46 + nameLength));
      entries[name] = (method: method, size: compressed, offset: local);
      p += 46 + nameLength + extra + comment;
    }
    return RemoteZip._(url, entries);
  }

  /// read is the file [name] in the zip, uncompressed.
  Future<Uint8List> read(String name) async {
    var e = entries[name];
    if (e == null) throw "$name is not in the collection.";
    var head = await _range(url, e.offset, e.offset + 29);
    var h = ByteData.sublistView(head);
    var start = e.offset + 30 + h.getUint16(26, Endian.little) + h.getUint16(28, Endian.little);
    var data = e.size == 0 ? Uint8List(0) : await _range(url, start, start + e.size - 1);
    return switch (e.method) {
      0 => data,
      8 => Uint8List.fromList(ZLibDecoder(raw: true).convert(data)),
      _ => throw "$name is packed in a way that cannot be read.",
    };
  }
}
