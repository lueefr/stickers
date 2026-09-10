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

  static Color defaultForeground(BuildContext context) => Theme.of(context).brightness == Brightness.light
      ? Color.lerp(Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.surface, .8)!
      : Color.lerp(Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.surface, .9)!;

  static Color defaultBackground(BuildContext context) => Theme.of(context).brightness == Brightness.light
      ? Color.lerp(Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.surface, .9)!
      : Color.lerp(Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.surface, .95)!;

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
    final maxX = rect.right;
    final maxY = rect.bottom;

    int row = 0;
    for (double y = max(rect.top, 0); y < maxY; y += size) {
      for (double x = max(rect.left, 0) + row * size; x < maxX; x += size * 2) {
        Rect r = Rect.fromLTWH(x, y, size, size);
        canvas.drawRect(r, checkerPaint);
      }
      row++;
      row &= 1;
    }
  }
}
