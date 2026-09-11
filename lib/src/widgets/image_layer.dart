import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stickers/src/pages/edit_page.dart';

class EditorImageLayerData {
  EditorImageLayerData({
    required this.source,
    required this.transform,
    this.width = 260,
  });

  String source;
  Matrix4 transform;
  double width;
}

class ImageStickerLayer extends StatefulWidget implements EditorLayer {
  final EditorImageLayerData image;

  /// Owned by this widget instance, so the editor can push transform updates
  /// into the mounted state without going through a [GlobalKey]. It is kept
  /// final because widgets have to stay immutable.
  final ImageStickerLayerState state = ImageStickerLayerState();
  final Function(ImageStickerLayer)? onDelete;

  ImageStickerLayer(
    this.image, {
    super.key,
    this.onDelete,
  });

  @override
  // ignore: no_logic_in_create_state
  State<ImageStickerLayer> createState() => state;

  void update(Matrix4 matrix) {
    state.update(matrix);
  }
}

class ImageStickerLayerState extends State<ImageStickerLayer> {
  @override
  Widget build(BuildContext context) {
    return Transform(
      origin: const Offset(0, 0),
      transform: widget.image.transform,
      child: Center(
        child: GestureDetector(
          onLongPress: () => widget.onDelete?.call(widget),
          child: Image.file(
            File(widget.image.source),
            width: widget.image.width,
            // Gallery photos can be huge; decode at ~3x the display width.
            cacheWidth: 780,
            gaplessPlayback: true,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  void update(Matrix4 matrix) {
    // The editor can keep pushing transform updates to a layer that is not
    // mounted (or is already disposed), and such a state cannot rebuild.
    if (!mounted) return;
    widget.image.transform = matrix;
    setState(() {});
  }
}
