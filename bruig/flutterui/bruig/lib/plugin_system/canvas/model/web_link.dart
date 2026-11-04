/// webLink is [url] as a link that may be opened or written into an export:
/// http, https or mailto only. A canvas comes from other people, and a
/// file:, javascript: or app-specific address would do something other than
/// show a page. Null for anything else.
Uri? webLink(String url) {
  var uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  return switch (uri.scheme.toLowerCase()) {
    "http" || "https" when uri.host.isNotEmpty => uri,
    "mailto" => uri,
    _ => null,
  };
}
