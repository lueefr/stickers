import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/checker_painter.dart';
import 'package:stickers/src/data/load_store.dart';
import 'package:stickers/src/data/sticker_pack.dart';
import 'package:stickers/src/dialogs/error_dialog.dart';
import 'package:stickers/src/pages/default_page.dart';

class CropPage extends StatefulWidget {
  final StickerPack pack;
  final int index;
  final String imagePath;
  final GlobalKey<ExtendedImageEditorState> editorKey = GlobalKey<ExtendedImageEditorState>();

  CropPage({
    required this.pack,
    required this.index,
    required this.imagePath,
    super.key,
  });

  static const routeName = "/crop";

  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> with TickerProviderStateMixin {
  late final AnimationController _maskColorController;
  late final CurvedAnimation _maskColorAnimation;
  final ImageEditorController _editorController = ImageEditorController();

  bool _previousPtrVal = false;

  @override
  void initState() {
    super.initState();
    _maskColorController = AnimationController(vsync: this);
    _maskColorAnimation = CurvedAnimation(
      parent: _maskColorController,
      curve: Curves.ease,
      reverseCurve: Curves.ease,
    );
  }

  @override
  void dispose() {
    _maskColorAnimation.dispose();
    _maskColorController.dispose();
    super.dispose();
  }

  double? _aspectRatio;
  bool _isStretching = false;

  Future<void> _stretchToSquare() async {
    if (_isStretching) return;
    setState(() => _isStretching = true);
    try {
      final state = widget.editorKey.currentState!;
      final double rotation = _editorController.rotateDegrees;
      final ui.Image? image = state.image;

      // The crop box is what the user selected, if they selected anything:
      // [stretchRegion] keeps it and otherwise falls back to the visible content
      // of the sticker, because a sticker is a square canvas whose content sits
      // in the middle with transparent margins around it. Stretching that whole
      // canvas would leave the sticker exactly as it is.
      Rect? region;
      if (image != null) {
        region = await stretchRegion(
          state.rawImageData,
          Size(image.width.toDouble(), image.height.toDouble()),
          cropRect: state.getCropRect(),
          rotation: rotation,
        );
      }
      if (region == null && _alreadyFillsSquare(image, rotation)) {
        // Nothing to stretch: say so instead of leaving the user with a button
        // that appears to do nothing.
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.stickerAlreadyFillsSquare)),
        );
        return;
      }

      final stretched = await stretchStickerToSquare(state.rawImageData, rotation, region);
      final output = await saveTemp(stretched);
      // `context` here is `State.context`, so it has to be guarded with the
      // State's own `mounted` flag.
      if (!mounted) return;
      Navigator.of(context).pushNamed(
        "/edit",
        arguments: EditArguments(
          pack: widget.pack,
          index: widget.index,
          mediaPath: output.path,
        ),
      );
    } catch (e) {
      // Do not leave the user with a button that looks like it did nothing.
      debugPrint("Couldn't stretch the sticker to 1:1: $e");
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => ErrorDialog(
            title: AppLocalizations.of(context)!.stretchToSquare,
            message: AppLocalizations.of(context)!.errorMessage + e.toString(),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isStretching = false);
      }
    }
  }

  /// Whether stretching cannot change the sticker: a square image stretched as
  /// it is (no rotation, no selection, no transparent margin to trim) is already
  /// a filled 1:1 canvas.
  bool _alreadyFillsSquare(ui.Image? image, double rotation) =>
      image != null && image.width == image.height && rotation.truncate() % 360 == 0;

  @override
  Widget build(BuildContext context) {
    return DefaultActivity(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.cropYourSticker),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          //TODO make loading less abrupt
          children: [
            Expanded(
              child: Container(
                // The clip and empty BoxDecoration is intentional, sometimes the done button doesn't appear otherwise
                // See: https://github.com/lolocomotive/stickers/issues/1
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(),
                // The mask animation used to call setState on this entire page
                // for every tick, rebuilding all controls and the editor. Keep
                // the animation confined to the image editor subtree.
                child: AnimatedBuilder(
                  animation: _maskColorAnimation,
                  builder: (context, _) => ExtendedImage.file(
                    File(widget.imagePath),
                  fit: BoxFit.contain,
                  beforePaintImage: (canvas, rect, image, paint) {
                    CheckerPainter.checkerPainter(canvas, rect, context);
                    return false;
                  },
                  mode: ExtendedImageMode.editor,
                  extendedImageEditorKey: widget.editorKey,
                  cacheRawData: true,
                  initEditorConfigHandler: (state) {
                    return EditorConfig(
                      editorMaskColorHandler: (ctx, pointerDown) {
                        if (_previousPtrVal && !pointerDown) {
                          _maskColorController.animateTo(1, duration: const Duration(milliseconds: 150));
                        }
                        if (!_previousPtrVal && pointerDown) {
                          _maskColorController.animateTo(0, duration: const Duration(milliseconds: 150));
                        }
                        _previousPtrVal = pointerDown;
                        return Color.lerp(
                          Theme.of(context).colorScheme.surface.withAlpha(50),
                          Theme.of(context).colorScheme.surface.withAlpha(200),
                          _maskColorAnimation.value,
                        )!;
                      },
                      animationCurve: Curves.ease,
                      tickerDuration: const Duration(),
                      lineHeight: 3,
                      lineColor: Theme.of(context).colorScheme.primary.withAlpha(100),
                      animationDuration: const Duration(milliseconds: 400),
                      maxScale: double.infinity,
                      cropRectPadding: const EdgeInsets.all(40.0),
                      hitTestSize: 80.0,
                      cropAspectRatio: _aspectRatio,
                      cornerColor: Theme.of(context).colorScheme.primary,
                      cornerSize: const Size(30, 5),
                      controller: _editorController,
                    );
                  },
                ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: "Undo",
                      onPressed: () {
                        _editorController.undo();
                        setState(() {});
                      },
                      icon: const Icon(Icons.undo),
                    ),
                    IconButton(
                      tooltip: "Rotate left",
                      onPressed: () {
                        _editorController.rotate(degree: -90, animation: true);
                        setState(() {});
                      },
                      icon: const Icon(Icons.rotate_left),
                    ),
                    IconButton(
                      tooltip: "Rotate -1°",
                      onPressed: () {
                        _editorController.rotate(degree: -1, animation: true, rotateCropRect: false);
                        setState(() {});
                      },
                      icon: const Icon(Icons.rotate_90_degrees_ccw),
                    ),
                    IconButton(
                      tooltip: "Rotate +1°",
                      onPressed: () {
                        _editorController.rotate(degree: 1, animation: true, rotateCropRect: false);
                        setState(() {});
                      },
                      icon: const Icon(Icons.rotate_90_degrees_cw),
                    ),
                    IconButton(
                      tooltip: "Rotate right",
                      onPressed: () {
                        _editorController.rotate(degree: 90, animation: true);
                        setState(() {});
                      },
                      icon: const Icon(Icons.rotate_right),
                    ),
                    IconButton(
                      tooltip: "Flip",
                      onPressed: () {
                        _editorController.flip(animation: true);
                        setState(() {});
                      },
                      icon: const Icon(Icons.flip),
                    ),
                    IconButton(
                      tooltip: "Reset",
                      onPressed: () {
                        _editorController.reset();
                        setState(() {
                          _aspectRatio = null;
                        });
                      },
                      icon: const Icon(Icons.restart_alt),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: SegmentedButton<double>(
                    showSelectedIcon: false,
                    emptySelectionAllowed: true,
                    multiSelectionEnabled: false,
                    segments: [
                      ButtonSegment(
                          value: 0,
                          icon: Column(children: [
                            const Icon(Icons.crop_free),
                            const Text(
                              "Free",
                              style: TextStyle(fontSize: 10),
                            )
                          ])),
                      ButtonSegment(
                          value: 16 / 9,
                          icon: Column(children: [
                            const Icon(Icons.crop_16_9),
                            const Text(
                              "16:9",
                              style: TextStyle(fontSize: 10),
                            )
                          ])),
                      ButtonSegment(
                          value: 3 / 2,
                          icon: Column(children: [
                            const Icon(Icons.crop_3_2),
                            const Text(
                              "3:2",
                              style: TextStyle(fontSize: 10),
                            )
                          ])),
                      ButtonSegment(
                          value: 1,
                          icon: Column(children: [
                            const Icon(Icons.crop_din),
                            const Text(
                              "1:1",
                              style: TextStyle(fontSize: 10),
                            )
                          ])),
                      ButtonSegment(
                          value: 2 / 3,
                          icon: Column(children: [
                            Transform.rotate(
                              angle: pi / 2,
                              child: Icon(Icons.crop_3_2),
                            ),
                            const Text(
                              "2:3",
                              style: TextStyle(fontSize: 10),
                            )
                          ])),
                      ButtonSegment(
                          value: 9 / 16,
                          icon: Column(children: [
                            Transform.rotate(
                              angle: pi / 2,
                              child: Icon(Icons.crop_16_9),
                            ),
                            const Text(
                              "9:16",
                              style: TextStyle(fontSize: 10),
                            )
                          ])),
                    ],
                    selected: {_aspectRatio == null ? 0 : _aspectRatio!},
                    onSelectionChanged: (v) {
                      setState(() {
                        final selected = v.firstOrNull;
                        _aspectRatio = selected == 0 ? null : selected;
                        _editorController.updateCropAspectRatio(_aspectRatio);
                        HapticFeedback.lightImpact();
                      });
                    },
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _isStretching ? null : _stretchToSquare,
                            icon: const Icon(Icons.aspect_ratio),
                            label: Text(
                                AppLocalizations.of(context)!.stretchToSquare),
                          ),
                          const SizedBox(height: 8),
                          FilledButton(
                            onPressed: () async {
                              final state = widget.editorKey.currentState!;
                              if (state.getCropRect()!.height < .5 || state.getCropRect()!.width < .5) {
                                showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                          title: Text(AppLocalizations.of(context)!.cropTooSmall),
                                          content:
                                              Text(AppLocalizations.of(context)!.cropTooSmallDetails),
                                          actions: [
                                            TextButton(
                                                onPressed: () => Navigator.of(context).pop(),
                                                child: Text("Okay 💗")),
                                            FilledButton(
                                                onPressed: () => Navigator.of(context).pop(),
                                                child: Text("Yay 💗")),
                                          ],
                                        ));
                                return;
                              }
                              final cropped = await cropSticker(
                                  state.getCropRect()!,
                                  state.rawImageData,
                                  widget.pack,
                                  widget.index,
                                  _editorController.rotateDegrees);
                              final output = await saveTemp(cropped);
                              if (!context.mounted) return;
                              Navigator.of(context).pushNamed(
                                "/edit",
                                arguments: EditArguments(
                                  pack: widget.pack,
                                  index: widget.index,
                                  mediaPath: output.path,
                                ),
                              );
                            },
                            child: Text(AppLocalizations.of(context)!.done),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum MediaType {
  video,
  picture,
}

class EditArguments {
  StickerPack pack;

  // Index 30 is tray icon
  int index;
  String mediaPath;
  MediaType type;

  /// Number of pages the editor should close after saving.
  /// Cropped media closes both the editor and crop page; direct editing closes only the editor.
  int popCount;

  EditArguments({
    required this.pack,
    required this.index,
    required this.mediaPath,
    this.type = MediaType.picture,
    this.popCount = 2,
  });
}
