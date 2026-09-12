import 'dart:io';

import 'package:flutter/material.dart';
import 'package:stickers/src/checker_painter.dart';

/// A cached, isolated sticker preview.
///
/// Sticker libraries show the same decoded image while scrolling and opening a
/// pack. Keeping the checkerboard and image behind a repaint boundary prevents
/// parent list/grid repaints from repainting both for every scroll tick.
class StickerThumbnail extends StatelessWidget {
  const StickerThumbnail(
    this.source, {
    super.key,
    this.cacheWidth = 256,
    this.cacheHeight = 256,
    this.onTap,
    this.onLongPress,
    this.width,
    this.height,
  });

  final String source;
  final int cacheWidth;
  final int cacheHeight;
  final GestureTapCallback? onTap;
  final GestureLongPressCallback? onLongPress;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    Widget image = Image.file(
      File(source),
      width: width ?? double.infinity,
      height: height ?? double.infinity,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      gaplessPlayback: true,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.low,
    );
    if (onTap != null || onLongPress != null) {
      image = GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: image,
      );
    }

    return RepaintBoundary(
      child: CustomPaint(
        painter: CheckerPainter(context),
        child: image,
      ),
    );
  }
}
