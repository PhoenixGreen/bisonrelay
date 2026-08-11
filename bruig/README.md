# bruig - Bison Relay UI (graphical)

# Building

Requires [flutter](https://wwww.flutter.dev). Requires xcode for macos/ios.
Requires Android NDK to build for android. 

## Native Desktop

This will build the desktop version for the current system (no cross-compiling
yet).

```shell
$ bruig/build_desktop.sh          # build
$ bruig/build_desktop.sh run      # build, then flutter run
```

Both steps matter and the order is not optional. `flutter run` and `flutter
build` rebuild the Dart and *copy* golib into the bundle, but neither rebuilds
golib itself -- so after any change under `client/` or `bruig/golib/`, running
Flutter alone gives you new Dart talking to a stale Go library, silently. The
script does the two in order and checks the library was actually rewritten.

By hand, if you prefer (replace `linux` with `macos` or `windows`):

```shell
$ go generate ./golibbuilder
$ cd flutterui/bruig
$ flutter build linux
```

## Mobile Builds

Use the applicable tags (android, ios):

```shell
$ go generate -tags android ./golibbuilder
$ go generate -tags ios ./golibbuilder
$ cd fd/fd
$ flutter build android
$ flutter build ios
```
