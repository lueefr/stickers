import 'package:flutter/material.dart' hide Image;

/// Paints the transparency checkerboard used behind sticker previews.
///
/// Checkerboards are present in almost every image cell and the crop editor
/// repaints them while the image is being manipulated. Cache the geometry by
/// size so scrolling or an editor animation only changes the color fill; it no
/// longer allocates hundreds of rectangles and a new [Path] on every paint.
class CheckerPainter extends CustomPainter {
  CheckerPainter(BuildContext context, {this.sizeCallback, Color? fg, Color? bg})
      : fg = fg ?? defaultForeground(context),
        bg = bg ?? defaultBackground(context);

  Function(Size)? sizeCallback;

  final Color fg;
  final Color bg;

  static final Map<_CheckerSize, Path> _pathCache = <_CheckerSize, Path>{};
  static const int _maxCachedSizes = 24;

  static Color defaultForeground(BuildContext context) {
    final theme = Theme.of(context);
    return Color.lerp(
      theme.colorScheme.primary,
      theme.colorScheme.surface,
      theme.brightness == Brightness.light ? .8 : .9,
    )!;
  }

  static Color defaultBackground(BuildContext context) {
    final theme = Theme.of(context);
    return Color.lerp(
      theme.colorScheme.primary,
      theme.colorScheme.surface,
      theme.brightness == Brightness.light ? .9 : .95,
    )!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    sizeCallback?.call(size);
    checkerPainter(canvas, Rect.fromLTWH(0, 0, size.width, size.height), null, bg, fg);
  }

  @override
  bool shouldRepaint(covariant CheckerPainter oldDelegate) {
    return oldDelegate.fg != fg || oldDelegate.bg != bg;
  }

  static void checkerPainter(Canvas canvas, Rect rect, BuildContext? context, [Color? bg, Color? fg]) {
    // Paint a checkerboard below the image to indicate transparency.
    assert(context != null || (fg != null && bg != null), 'Either colors or a BuildContext must be provided');
    final foreground = fg ?? defaultForeground(context!);
    final background = bg ?? defaultBackground(context!);

    final backgroundPaint = Paint()
      ..blendMode = BlendMode.srcOver
      ..style = PaintingStyle.fill
      ..color = background;
    canvas.drawRect(rect, backgroundPaint);

    final foregroundPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = foreground;

    // Draw the cached path in local checker coordinates. Translating once
    // supports the crop editor's arbitrary rect without putting offsets into
    // every square in the path.
    canvas.save();
    canvas.clipRect(rect);
    canvas.translate(rect.left, rect.top);
    canvas.drawPath(_pathFor(rect.size), foregroundPaint);
    canvas.restore();
  }

  static Path _pathFor(Size size) {
    // Sub-pixel sizes are quantized to half a logical pixel. There are only a
    // handful of sizes in the app, while this prevents a resize animation from
    // growing an unbounded cache.
    final key = _CheckerSize((size.width * 2).round(), (size.height * 2).round());
    final cached = _pathCache[key];
    if (cached != null) return cached;

    final width = key.width / 2;
    final height = key.height / 2;
    const squareSize = 10.0;
    final squares = Path();
    var oddRow = false;
    for (double y = 0; y < height; y += squareSize) {
      for (double x = oddRow ? squareSize : 0; x < width; x += squareSize * 2) {
        squares.addRect(Rect.fromLTWH(x, y, squareSize, squareSize));
      }
      oddRow = !oddRow;
    }

    if (_pathCache.length >= _maxCachedSizes) {
      _pathCache.remove(_pathCache.keys.first);
    }
    _pathCache[key] = squares;
    return squares;
  }
}

class _CheckerSize {
  const _CheckerSize(this.width, this.height);

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is _CheckerSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}
