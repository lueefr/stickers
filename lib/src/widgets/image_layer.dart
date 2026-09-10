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
  ImageStickerLayerState? state;
  final Function(ImageStickerLayer)? onDelete;

  ImageStickerLayer(
    this.image, {
    super.key,
    this.onDelete,
  });

  @override
  State<ImageStickerLayer> createState() {
    state = ImageStickerLayerState();
    return state!;
  }

  void update(Matrix4 matrix) {
    state?.update(matrix);
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
    widget.image.transform = matrix;
    setState(() {});
  }
}
