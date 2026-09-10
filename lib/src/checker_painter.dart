import 'dart:math';

import 'package:flutter/material.dart' hide Image;

class CheckerPainter extends CustomPainter {
  Function(Size)? sizeCallback;

  final Color fg;
  final Color bg;

  /// The theme-dependent colors are resolved at construction time (i.e. during
  /// `build`) so that [shouldRepaint] can compare them instead of repainting
  /// every frame, while still picking up theme changes on rebuild.
  CheckerPainter(BuildContext context, {this.sizeCallback, Color? fg, Color? bg})
      : fg = fg ?? defaultForeground(context),
        bg = bg ?? defaultBackground(context);

  static Color defaultForeground(BuildContext context) {
    final theme = Theme.of(context);
    return Color.lerp(theme.colorScheme.primary, theme.colorScheme.surface,
        theme.brightness == Brightness.light ? .8 : .9)!;
  }

  static Color defaultBackground(BuildContext context) {
    final theme = Theme.of(context);
    return Color.lerp(theme.colorScheme.primary, theme.colorScheme.surface,
        theme.brightness == Brightness.light ? .9 : .95)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (sizeCallback != null) sizeCallback!(size);
    checkerPainter(canvas, Rect.fromLTWH(0, 0, size.width, size.height), null, bg, fg);
  }

  @override
  bool shouldRepaint(covariant CheckerPainter oldDelegate) {
    return oldDelegate.fg != fg || oldDelegate.bg != bg;
  }

  static void checkerPainter(Canvas canvas, Rect rect, BuildContext? context, [Color? bg, Color? fg]) {
    // Paint a checkerboard below the image to indicate transparency
    assert(context != null || (fg != null && bg != null), 'Either colors or a BuildContext must be provided');
    fg ??= defaultForeground(context!);
    bg ??= defaultBackground(context!);

    double size = 10;
    final checkerPaint = Paint();
    checkerPaint.blendMode = BlendMode.srcOver;
    checkerPaint.style = PaintingStyle.fill;

    checkerPaint.color = bg;
    canvas.drawRect(rect, checkerPaint);
    checkerPaint.color = fg;
    canvas.clipRect(rect);

    // The canvas is clipped to the widget bounds anyway, so iterating over
    // the rect is enough and works no matter where the widget is on screen.
    // All squares are batched into a single path so the whole pattern paints
    // in one draw call instead of hundreds.
    final maxX = rect.right;
    final maxY = rect.bottom;
    final Path squares = Path();

    int row = 0;
    for (double y = max(rect.top, 0); y < maxY; y += size) {
      for (double x = max(rect.left, 0) + row * size; x < maxX; x += size * 2) {
        squares.addRect(Rect.fromLTWH(x, y, size, size));
      }
      row++;
      row &= 1;
    }
    canvas.drawPath(squares, checkerPaint);
  }
}
