import 'dart:io';
import 'dart:typed_data';

import 'package:bruig/config.dart';
import 'package:flutter/foundation.dart';

// canvas_network.dart is how the canvas reaches the network: whether it may,
// and the one way a request is made. A configured proxy (often Tor) is how
// somebody has said their machine reaches the internet; Dart's client speaks
// HTTP proxies, not SOCKS, so a canvas request would bypass it. With a proxy
// configured, the canvas refuses to fetch and says why.

/// proxiedForTest stands in for the answer in a test, which has no config
/// file to read -- and no config reads as proxied, which refuses everything.
@visibleForTesting
bool? proxiedForTest;

/// networkIsProxied is whether a proxy has been configured. True on any
/// failure to find out: wrong that way costs a refused refresh, wrong the
/// other way a connection somebody arranged not to make.
Future<bool> networkIsProxied() async {
  var fixed = proxiedForTest;
  if (fixed != null) return fixed;
  try {
    var config = await loadConfig(mainConfigFilename);
    return config.proxyaddr.trim().isNotEmpty;
  } catch (exception) {
    debugPrint("Unable to read the network settings: $exception");
    return true;
  }
}

/// loopbackHttpForTest lets a test's own server, plain http on 127.0.0.1,
/// stand in for https.
@visibleForTesting
bool loopbackHttpForTest = false;

/// canvasHttpClient is a client with a connection timeout, for [canvasGet].
HttpClient canvasHttpClient() =>
    HttpClient()..connectionTimeout = const Duration(seconds: 20);

/// canvasGet is one GET, as every fetch from the canvas makes it: https
/// only, redirects followed only to https, and [headers] -- which may carry
/// a key -- sent only to [uri]'s own host. Null where it could not be made.
Future<HttpClientResponse?> canvasGet(HttpClient client, Uri uri,
    {Map<String, String> headers = const {}}) async {
  var at = uri;
  for (var hop = 0; hop < 5; hop++) {
    var loopback = loopbackHttpForTest && at.host == "127.0.0.1";
    if (!at.isScheme("https") && !(loopback && at.isScheme("http"))) {
      return null;
    }
    var request = await client.getUrl(at)
      ..followRedirects = false;
    if (at.host == uri.host) headers.forEach(request.headers.set);
    var response = await request.close();
    if (!response.isRedirect) return response;
    var location = response.headers.value(HttpHeaders.locationHeader);
    await response.drain<void>();
    if (location == null) return null;
    at = at.resolve(location);
  }
  return null;
}

/// readCapped is [response]'s body, or null where it is more than
/// [maxBytes], goes quiet for a minute, or takes longer than [total] -- a
/// server sending a byte every fifty-nine seconds would otherwise hold it
/// open for as long as it liked.
Future<Uint8List?> readCapped(HttpClientResponse response, int maxBytes,
    {Duration total = const Duration(minutes: 10)}) async {
  var out = BytesBuilder(copy: false);
  var took = Stopwatch()..start();
  await for (var chunk in response.timeout(const Duration(seconds: 60))) {
    out.add(chunk);
    if (out.length > maxBytes || took.elapsed > total) return null;
  }
  return out.toBytes();
}
