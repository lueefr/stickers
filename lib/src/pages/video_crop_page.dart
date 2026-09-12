import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/constants.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/pages/crop_page.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/video/common.dart';
import 'package:stickers/src/video/crop_scale.dart';
import 'package:video_player/video_player.dart';

class VideoCropPage extends StatefulWidget {
  final StickerPack pack;
  final int index;
  final String imagePath;

  const VideoCropPage({
    required this.pack,
    required this.index,
    required this.imagePath,
    super.key,
  });

  static const routeName = "/crop_video";

  @override
  State<VideoCropPage> createState() => _VideoCropPageState();
}

class _VideoCropPageState extends State<VideoCropPage> {
  late final VideoPlayerController _controller;
  final ValueNotifier<double> _buttonOpacity = ValueNotifier<double>(1);
  final ValueNotifier<RangeValues> _rangeNotifier = ValueNotifier<RangeValues>(RangeValues(0, 1));
  final ValueNotifier<bool> _editingNotifier = ValueNotifier<bool>(false);

  bool _ready = false;
  bool _exporting = false;
  int _rotationDegrees = 0;
  bool _cropToSquare = true;
  RangeValues _range = RangeValues(0, 1);
  Duration _seekTarget = Duration.zero;
  bool _canSeek = true;
  bool _editing = false;
  final CropAndScaleService service = CropAndScaleService();

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(
      File(widget.imagePath),
      // Texture composition avoids the extra platform-view layer while the
      // trim controls are being dragged. It also matches the editor preview.
      viewType: VideoViewType.textureView,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _controller.setVolume(0);
    _controller.addListener(_videoListener);
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => ErrorDialog(
          title: AppLocalizations.of(context)!.couldntLoadVideo,
          message: e.toString(),
        ),
      );
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    }
  }

  void _videoListener() {
    if (_editing) return;
    // No setState here on purpose: the player fires this listener on every
    // video frame. The play button and progress indicator listen directly to
    // the controller and rebuild only their small subtrees.
    if (_controller.value.position > _controller.value.duration * _range.end) {
      _requestSeek(_controller.value.duration * _range.start);
    }
  }

  @override
  void dispose() {
    // Dispose the controllers before super.dispose() so pending video
    // callbacks can no longer hit setState() on a disposed State.
    _controller.removeListener(_videoListener);
    _controller.dispose();
    _buttonOpacity.dispose();
    _rangeNotifier.dispose();
    _editingNotifier.dispose();
    service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultActivity(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.trimVideo),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                // The clip and empty BoxDecoration is intentional, sometimes the done button doesn't appear otherwise
                // See: https://github.com/lolocomotive/stickers/issues/1
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(),
                child: Stack(
                  children: [
                    Center(
                      child: _ready
                          ? Container(
                              decoration: BoxDecoration(
                                border: _cropToSquare
                                    ? Border.all(color: Theme.of(context).colorScheme.primary, width: 3)
                                    : null,
                              ),
                              width: _cropToSquare
                                  ? min(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height)
                                  : null,
                              height: _cropToSquare
                                  ? min(MediaQuery.of(context).size.width, MediaQuery.of(context).size.height)
                                  : null,
                              clipBehavior: Clip.antiAlias,
                              child: Transform.rotate(
                                angle: _rotationDegrees * pi / 180,
                                child: AspectRatio(
                                  aspectRatio: _rotationDegrees % 180 == 0
                                      ? _controller.value.aspectRatio
                                      : 1 / _controller.value.aspectRatio,
                                  child: VideoPlayer(_controller),
                                ),
                              ),
                            )
                          : const CircularProgressIndicator(),
                    ),
                    if (_ready)
                      Center(
                        child: ValueListenableBuilder<VideoPlayerValue>(
                          valueListenable: _controller,
                          builder: (context, value, _) {
                            final button = value.isPlaying
                                ? IconButton(
                                    onPressed: _controller.pause,
                                    icon: const Icon(
                                      Icons.pause,
                                      color: Colors.white,
                                      shadows: [Shadow(color: Colors.black, blurRadius: 32)],
                                    ),
                                    iconSize: 100,
                                  )
                                : IconButton(
                                    onPressed: _play,
                                    icon: const Icon(
                                      Icons.play_arrow,
                                      color: Colors.white,
                                      shadows: [Shadow(color: Colors.black, blurRadius: 32)],
                                    ),
                                    iconSize: 100,
                                  );
                            return ValueListenableBuilder<double>(
                              valueListenable: _buttonOpacity,
                              builder: (context, opacity, _) => value.isPlaying
                                  ? AnimatedOpacity(
                                      opacity: opacity,
                                      duration: const Duration(milliseconds: 300),
                                      child: button,
                                    )
                                  : button,
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: "Rotate left",
                        onPressed: () => setState(() {
                          _rotationDegrees = (_rotationDegrees - 90) % 360;
                        }),
                        icon: const Icon(Icons.rotate_left),
                      ),
                      FilterChip(
                        selected: _cropToSquare,
                        label: const Text("Square crop"),
                        avatar: const Icon(Icons.crop_square),
                        onSelected: (value) => setState(() {
                          _cropToSquare = value;
                        }),
                      ),
                      IconButton(
                        tooltip: "Rotate right",
                        onPressed: () => setState(() {
                          _rotationDegrees = (_rotationDegrees + 90) % 360;
                        }),
                        icon: const Icon(Icons.rotate_right),
                      ),
                    ],
                  ),
                ),
                Stack(
                  children: [
                    // Range changes are isolated from the video preview. The
                    // old implementation rebuilt the platform view for every
                    // pointer event, which made trimming visibly stutter.
                    ValueListenableBuilder<RangeValues>(
                      valueListenable: _rangeNotifier,
                      builder: (context, range, _) => RangeSlider(
                        values: range,
                        onChangeStart: (_) {
                          _controller.pause();
                          _editing = true;
                          _editingNotifier.value = true;
                        },
                        onChanged: _onRangeChanged,
                        onChangeEnd: (_) => _finishRangeEdit(),
                      ),
                    ),
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: _controller,
                      builder: (context, value, _) => ValueListenableBuilder<bool>(
                        valueListenable: _editingNotifier,
                        builder: (context, editing, _) {
                          if (editing || !_ready) return const SizedBox.shrink();
                          final durationMs = value.duration.inMilliseconds;
                          if (durationMs <= 0) return const SizedBox.shrink();
                          final progress =
                              (value.position.inMilliseconds / durationMs).clamp(0.0, 1.0);
                          return IgnorePointer(
                            child: Slider(
                              thumbColor: Theme.of(context).colorScheme.onSurface,
                              activeColor: Colors.transparent,
                              inactiveColor: Colors.transparent,
                              value: progress,
                              onChanged: (_) {},
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
                  child: FilledButton(
                    clipBehavior: Clip.antiAlias,
                    style: ButtonStyle(
                      padding: WidgetStateProperty.all(EdgeInsets.zero),
                    ),
                    onPressed: _exporting ? null : doCrop,
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        Text(AppLocalizations.of(context)!.done),
                        const SizedBox(height: 8),
                        if (_exporting)
                          StreamBuilder<Progress>(
                            stream: service.progressStream,
                            builder: (context, asyncSnapshot) => LinearProgressIndicator(
                              value: asyncSnapshot.data?.progress,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _onRangeChanged(RangeValues values) {
    final Duration seekTarget;
    if (_range.start != values.start) {
      seekTarget = _controller.value.duration * values.start;
    } else if (_range.end != values.end) {
      seekTarget = _controller.value.duration * values.end;
    } else {
      return;
    }
    _requestSeek(seekTarget);
    _range = values;
    _rangeNotifier.value = values;
  }

  Future<void> _finishRangeEdit() async {
    if (_seekTarget == _controller.value.duration * _range.end) {
      _requestSeek(_controller.value.duration * _range.end - const Duration(seconds: 1));
      if (_seekTarget < _controller.value.duration * _range.start) {
        _seekTarget = _controller.value.duration * _range.start;
      }
    }
    _play();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    _editing = false;
    _editingNotifier.value = false;
  }

  void _requestSeek(Duration time) async {
    _seekTarget = time;
    if (_canSeek) {
      _canSeek = false;
      await _controller.seekTo(time);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      _canSeek = true;
      if (_seekTarget != time) {
        _requestSeek(_seekTarget);
      }
    }
  }

  void _play() {
    _controller.play();
    _buttonOpacity.value = 1;
    Future<void>.delayed(const Duration(seconds: 1)).then((_) {
      if (!mounted) return;
      _buttonOpacity.value = 0;
    });
  }

  Future<void> doCrop() async {
    if (!_ready || _exporting) return;
    setState(() => _exporting = true);
    try {
      _controller.pause();
      final output = "$mediaCacheDir/import_${DateTime.now().millisecondsSinceEpoch}.mp4";
      await service.start(
        inputFile: widget.imagePath,
        outputFile: output,
        start: _controller.value.duration * _range.start,
        end: _controller.value.duration * _range.end,
        rotationDegrees: _rotationDegrees,
        cropToSquare: _cropToSquare,
      );
      await for (final s in service.progressStream) {
        if (s.status == Status.success) {
          break;
        } else if (s.status == Status.failed) {
          debugPrint("Transcoding failed!");
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => ErrorDialog(
                title: AppLocalizations.of(context)!.trimFailed,
                message: AppLocalizations.of(context)!.trimFailedMsg,
              ),
            );
          }
          throw Exception();
        }
      }
      if (!mounted) return;
      Navigator.of(context).pushNamed(
        "/edit",
        arguments: EditArguments(
          pack: widget.pack,
          index: widget.index,
          mediaPath: output,
          type: MediaType.video,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}
