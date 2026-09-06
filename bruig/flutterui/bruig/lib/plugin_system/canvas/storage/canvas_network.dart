import 'package:bruig/config.dart';
import 'package:flutter/foundation.dart';

// canvas_network.dart answers one question: has this app been told to reach
// the network through a proxy?
//
// It is one file so that the whole of the canvas's knowledge of the app's
// network settings is in one place and can be seen at a glance. Everything
// else about fetching -- see storage/canvas_data.dart -- takes the answer as
// an argument.
//
// The question matters because of what this app is. Somebody who has set a
// proxy here has said how they want their machine to reach the internet, and
// very often that proxy is Tor. A request made from the canvas would not go
// through it: Dart's own client speaks to HTTP proxies and not to SOCKS, which
// is what Tor listens on. So rather than make a connection that quietly does
// the opposite of what the reader asked for, a canvas with a proxy configured
// refuses to fetch and says why.

/// networkIsProxied is whether a proxy has been configured.
///
/// True on any failure to find out. The cost of being wrong in that direction
/// is a refused refresh and a message; the cost of being wrong the other way
/// is a connection somebody had arranged not to make.
Future<bool> networkIsProxied() async {
  try {
    var config = await loadConfig(mainConfigFilename);
    return config.proxyaddr.trim().isNotEmpty;
  } catch (exception) {
    debugPrint("Unable to read the network settings: $exception");
    return true;
  }
}
