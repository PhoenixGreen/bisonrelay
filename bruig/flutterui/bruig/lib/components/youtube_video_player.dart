import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Inline YouTube video player. Resolves a direct, muxed (audio+video)
/// stream URL via youtube_explode_dart and plays it with video_player.
///
/// Note: resolving/playing the actual video stream is a direct connection
/// to Google's servers -- unlike the metadata/thumbnail fetch (which is
/// proxied Go-side through the app's Tor/SOCKS client), there is no way to
/// route video playback through that same proxy, since video_player uses
/// the platform's native media stack. This widget is only ever shown after
/// an explicit user tap on the play button.
class YoutubeInlineVideo extends StatefulWidget {
  final String url;
  const YoutubeInlineVideo(this.url, {super.key});

  @override
  State<YoutubeInlineVideo> createState() => _YoutubeInlineVideoState();
}

// Matches the /live/<id> URL form (e.g. for premieres/livestreams), which
// youtube_explode_dart's VideoId parser doesn't recognize on its own.
final _liveMatchExp = RegExp(r'youtube\..+?/live/([A-Za-z0-9_-]{11})');

class _YoutubeInlineVideoState extends State<YoutubeInlineVideo> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolveAndInit();
  }

  void _resolveAndInit() async {
    try {
      final yt = YoutubeExplode();
      final liveId = _liveMatchExp.firstMatch(widget.url)?.group(1);
      final videoId = VideoId(liveId ?? widget.url);
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      yt.close();
      if (manifest.muxed.isEmpty) {
        throw "No playable stream found for this video";
      }
      final stream = manifest.muxed.withHighestBitrate();
      final controller = VideoPlayerController.networkUrl(stream.url);
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
      });
      controller.play();
      controller.addListener(() {
        if (mounted) setState(() {});
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        _error = "Unable to play video: $exception";
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _openFullscreen() {
    var controller = _controller;
    if (controller == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _FullscreenVideoPage(controller),
      fullscreenDialog: true,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_error!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center),
          ),
        ),
      );
    }

    var controller = _controller;
    if (controller == null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: Stack(alignment: Alignment.bottomCenter, children: [
        VideoPlayer(controller),
        Positioned.fill(
          child: GestureDetector(
            onTap: () => setState(() {
              controller.value.isPlaying
                  ? controller.pause()
                  : controller.play();
            }),
            child: Container(color: Colors.transparent),
          ),
        ),
        Container(
          color: Colors.black45,
          child: Row(children: [
            IconButton(
              icon: Icon(
                  controller.value.isPlaying
                      ? Icons.pause
                      : Icons.play_arrow,
                  color: Colors.white),
              onPressed: () => setState(() {
                controller.value.isPlaying
                    ? controller.pause()
                    : controller.play();
              }),
            ),
            Expanded(
              child: VideoProgressIndicator(controller, allowScrubbing: true),
            ),
            IconButton(
              icon: const Icon(Icons.fullscreen, color: Colors.white),
              onPressed: _openFullscreen,
            ),
          ]),
        ),
      ]),
    );
  }
}

class _FullscreenVideoPage extends StatelessWidget {
  final VideoPlayerController controller;
  const _FullscreenVideoPage(this.controller);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            bottom: 8,
            left: 8,
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (context, value, child) => IconButton(
                icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white),
                onPressed: () {
                  value.isPlaying ? controller.pause() : controller.play();
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
