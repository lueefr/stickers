import 'dart:io';
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

  bool _isCropping = false;

  Widget _ratioChip(String label, double? ratio) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _aspectRatio == ratio,
        onSelected: (_) {
          _editorController.updateCropAspectRatio(ratio);
          setState(() => _aspectRatio = ratio);
          HapticFeedback.lightImpact();
        },
      ),
    );
  }

  void _resetCrop() {
    _editorController.reset();
    setState(() => _aspectRatio = null);
  }

  Future<void> _finishCrop() async {
    if (_isCropping) return;
    final editor = widget.editorKey.currentState;
    final rect = editor?.getCropRect();
    if (editor == null || rect == null) return;

    final l10n = AppLocalizations.of(context)!;
    if (rect.width < .5 || rect.height < .5) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.cropTooSmall),
          content: Text(l10n.cropTooSmallDetails),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.done)),
          ],
        ),
      );
      return;
    }

    setState(() => _isCropping = true);
    try {
      final result = await cropSticker(
        rect, editor.rawImageData, widget.pack, widget.index, _editorController.rotateDegrees,
      );
      final file = await saveTemp(result);
      if (!mounted) return;
      await Navigator.of(context).pushNamed(
        "/edit",
        arguments: EditArguments(
          pack: widget.pack,
          index: widget.index,
          mediaPath: file.path,
        ),
      );
    } catch (e) {
      debugPrint("Couldn't finish the crop: $e");
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => ErrorDialog(
          title: l10n.cropYourSticker,
          message: l10n.errorMessage + e.toString(),
        ),
      );
    } finally {
      if (mounted) setState(() => _isCropping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;

    return DefaultActivity(
      appBar: AppBar(
        title: Text(l10n.cropYourSticker),
        actions: [
          IconButton(
            tooltip: l10n.cropReset,
            icon: const Icon(Icons.restart_alt),
            onPressed: _resetCrop,
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(),
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
                    initEditorConfigHandler: (state) => EditorConfig(
                      editorMaskColorHandler: (ctx, pointerDown) {
                        if (_previousPtrVal && !pointerDown) {
                          _maskColorController.animateTo(1, duration: const Duration(milliseconds: 150));
                        }
                        if (!_previousPtrVal && pointerDown) {
                          _maskColorController.animateTo(0, duration: const Duration(milliseconds: 150));
                        }
                        _previousPtrVal = pointerDown;
                        return Color.lerp(
                          colors.surface.withAlpha(50),
                          colors.surface.withAlpha(200),
                          _maskColorAnimation.value,
                        )!;
                      },
                      animationCurve: Curves.ease,
                      tickerDuration: const Duration(),
                      lineHeight: 3,
                      lineColor: colors.primary.withAlpha(160),
                      animationDuration: const Duration(milliseconds: 350),
                      maxScale: 12,
                      cropRectPadding: const EdgeInsets.all(24),
                      hitTestSize: 80,
                      cropAspectRatio: _aspectRatio,
                      cornerColor: colors.primary,
                      cornerSize: const Size(30, 5),
                      controller: _editorController,
                    ),
                  ),
                ),
              ),
            ),
            Material(
              color: colors.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.cropDragHint,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _ratioChip(l10n.cropFree, null),
                          _ratioChip(l10n.cropSquare, 1),
                          _ratioChip(l10n.cropPortrait, 3 / 4),
                          _ratioChip(l10n.cropLandscape, 4 / 3),
                          _ratioChip("16:9", 16 / 9),
                          _ratioChip("9:16", 9 / 16),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          tooltip: "Undo",
                          onPressed: () => _editorController.undo(),
                          icon: const Icon(Icons.undo),
                        ),
                        IconButton(
                          tooltip: "Rotate left",
                          onPressed: () => _editorController.rotate(degree: -90, animation: true),
                          icon: const Icon(Icons.rotate_left),
                        ),
                        IconButton(
                          tooltip: "Rotate right",
                          onPressed: () => _editorController.rotate(degree: 90, animation: true),
                          icon: const Icon(Icons.rotate_right),
                        ),
                        IconButton(
                          tooltip: "Rotate -1°",
                          onPressed: () => _editorController.rotate(
                            degree: -1, animation: true, rotateCropRect: false,
                          ),
                          icon: const Icon(Icons.rotate_90_degrees_ccw),
                        ),
                        IconButton(
                          tooltip: "Rotate +1°",
                          onPressed: () => _editorController.rotate(
                            degree: 1, animation: true, rotateCropRect: false,
                          ),
                          icon: const Icon(Icons.rotate_90_degrees_cw),
                        ),
                        IconButton(
                          tooltip: "Flip",
                          onPressed: () => _editorController.flip(animation: true),
                          icon: const Icon(Icons.flip),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      onPressed: _isStretching || _isCropping ? null : _stretchToSquare,
                      icon: const Icon(Icons.aspect_ratio),
                      label: Text(l10n.stretchToSquare),
                    ),
                    const SizedBox(height: 6),
                    FilledButton.icon(
                      onPressed: _isCropping || _isStretching ? null : _finishCrop,
                      icon: _isCropping
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check),
                      label: Text(l10n.done),
                    ),
                  ],
                ),
              ),
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
