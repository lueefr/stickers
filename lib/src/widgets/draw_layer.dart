import 'package:flutter/cupertino.dart';
import 'package:stickers/src/pages/edit_page.dart';

class DrawLayer extends StatelessWidget implements EditorLayer {
  final DrawingPainter painter = DrawingPainter();

  DrawLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // Own layer so a stroke repaint never touches sibling layers.
      child: RepaintBoundary(
        child: CustomPaint(
          painter: painter,
        ),
      ),
    );
  }
}

/// [ChangeNotifier.notifyListeners] is protected, so the repaint notifier of
/// [DrawingPainter] gets its own subclass with a public way to wake listeners.
class _RepaintNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

class Stroke {
  final Color color;
  final double width;
  final List<Offset> points = [];

  // Cached path, rebuilt only when the points (or the scale) change, so a
  // long stroke paints in a single drawPath instead of hundreds of drawLine.
  Path? _path;
  int _pathPointCount = -1;
  double _pathScale = -1;

  Stroke(this.color, this.width);

  Path pathFor(double scaleFactor) {
    if (_path == null || _pathPointCount != points.length || _pathScale != scaleFactor) {
      final path = Path();
      if (points.isNotEmpty) {
        path.moveTo(points.first.dx * scaleFactor, points.first.dy * scaleFactor);
        for (var i = 1; i < points.length; i++) {
          path.lineTo(points[i].dx * scaleFactor, points[i].dy * scaleFactor);
        }
      }
      _path = path;
      _pathPointCount = points.length;
      _pathScale = scaleFactor;
    }
    return _path!;
  }
}

class DrawingPainter extends CustomPainter {
  List<Stroke> strokes = [];
  double scaleFactor = 1;

  final _RepaintNotifier _repaintNotifier;

  DrawingPainter._(this._repaintNotifier) : super(repaint: _repaintNotifier);

  factory DrawingPainter() => DrawingPainter._(_RepaintNotifier());

  final Paint _strokePaint = Paint()
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  final Paint _fillPaint = Paint()..style = PaintingStyle.fill;

  /// Adds a point to the current stroke and repaints only this layer.
  /// Unlike `setState`, this doesn't rebuild the editor page, so drawing
  /// stays at 60fps no matter how complex the rest of the UI is.
  void addPoint(Offset point) {
    strokes.last.points.add(point);
    _repaintNotifier.notify();
  }

  void addStroke(Stroke stroke) {
    strokes.add(stroke);
    _repaintNotifier.notify();
  }

  Stroke removeLastStroke() {
    final stroke = strokes.removeLast();
    _repaintNotifier.notify();
    return stroke;
  }

  void repaint() => _repaintNotifier.notify();

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      if (stroke.points.length == 1) {
        // A tap without movement draws a single dot.
        _fillPaint.color = stroke.color;
        canvas.drawCircle(stroke.points.first * scaleFactor, stroke.width * scaleFactor / 2, _fillPaint);
        continue;
      }
      _strokePaint.color = stroke.color;
      _strokePaint.strokeWidth = stroke.width * scaleFactor;
      canvas.drawPath(stroke.pathFor(scaleFactor), _strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
