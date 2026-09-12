import 'package:flutter/material.dart';
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

  // Keep the path in sticker coordinates. The painter scales the canvas once
  // for all strokes, which means adding a point is O(1) instead of rebuilding
  // the whole path on every pointer event. The old implementation rebuilt a
  // long stroke from its first point for every new point, making a large
  // drawing quadratic and eventually causing visible input lag.
  Path? _path;
  int _pathPointCount = -1;

  // Kept for callers that need a path in physical canvas coordinates. Drawing
  // itself uses [path] and a single canvas transform, so it never allocates
  // this scaled copy during a stroke.
  Path? _scaledPath;
  double _scaledPathFactor = double.nan;
  int _scaledPathPointCount = -1;

  Stroke(this.color, this.width);

  Path get path {
    _ensurePath();
    return _path!;
  }

  void addPoint(Offset point) {
    _ensurePath();
    if (points.isEmpty) {
      _path!.moveTo(point.dx, point.dy);
    } else {
      _path!.lineTo(point.dx, point.dy);
    }
    points.add(point);
    _pathPointCount = points.length;
    // A scaled path is only a compatibility convenience and is not used by
    // the hot painting path. Invalidate it cheaply when the stroke grows.
    _scaledPath = null;
  }

  void _ensurePath() {
    if (_path != null && _pathPointCount == points.length) return;
    final rebuilt = Path();
    if (points.isNotEmpty) {
      rebuilt.moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        rebuilt.lineTo(points[i].dx, points[i].dy);
      }
    }
    _path = rebuilt;
    _pathPointCount = points.length;
    _scaledPath = null;
  }

  /// Returns this stroke's path scaled by [scaleFactor].
  ///
  /// This is intentionally retained as a public helper for compatibility;
  /// the editor painter uses [path] with a canvas scale to avoid this work on
  /// every frame.
  Path pathFor(double scaleFactor) {
    _ensurePath();
    if (scaleFactor == 1) return _path!;
    if (_scaledPath == null ||
        _scaledPathFactor != scaleFactor ||
        _scaledPathPointCount != points.length) {
      final scaled = Path();
      if (points.isNotEmpty) {
        scaled.moveTo(points.first.dx * scaleFactor, points.first.dy * scaleFactor);
        for (var i = 1; i < points.length; i++) {
          scaled.lineTo(points[i].dx * scaleFactor, points[i].dy * scaleFactor);
        }
      }
      _scaledPath = scaled;
      _scaledPathFactor = scaleFactor;
      _scaledPathPointCount = points.length;
    }
    return _scaledPath!;
  }
}

class DrawingPainter extends CustomPainter {
  final List<Stroke> strokes = [];

  final _RepaintNotifier _repaintNotifier;
  double _scaleFactor = 1;

  DrawingPainter._(this._repaintNotifier) : super(repaint: _repaintNotifier);

  factory DrawingPainter() => DrawingPainter._(_RepaintNotifier());

  double get scaleFactor => _scaleFactor;

  set scaleFactor(double value) {
    if (_scaleFactor == value) return;
    _scaleFactor = value;
    _repaintNotifier.notify();
  }

  final Paint _strokePaint = Paint()
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  final Paint _fillPaint = Paint()..style = PaintingStyle.fill;

  /// Adds a point to the current stroke and repaints only this layer.
  /// Unlike `setState`, this doesn't rebuild the editor page, so drawing
  /// stays responsive even when the editor contains expensive image/text
  /// layers.
  void addPoint(Offset point) {
    if (strokes.isEmpty) return;
    strokes.last.addPoint(point);
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
    // Transform the canvas once rather than multiplying every point in every
    // stroke. This also makes a resize of the editor cheap.
    canvas.save();
    canvas.scale(_scaleFactor, _scaleFactor);
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      if (stroke.points.length == 1) {
        // A tap without movement draws a single dot.
        _fillPaint.color = stroke.color;
        canvas.drawCircle(stroke.points.first, stroke.width / 2, _fillPaint);
        continue;
      }
      _strokePaint.color = stroke.color;
      _strokePaint.strokeWidth = stroke.width;
      canvas.drawPath(stroke.path, _strokePaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DrawingPainter oldDelegate) {
    // The painter owns a repaint Listenable and mutates its paths in place.
    // Returning true here would make every parent rebuild repaint the whole
    // drawing again; notifier events already cover all content changes.
    return false;
  }
}
