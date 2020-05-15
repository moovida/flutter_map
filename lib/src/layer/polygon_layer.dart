import 'dart:math';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map/src/map/map.dart';
import 'package:latlong/latlong.dart' hide Path;

class PolygonLayerOptions extends LayerOptions {
  final List<Polygon> polygons;
  final bool polygonCulling;
  final bool simplify;

  /// screen space culling of polygons based on bounding box
  PolygonLayerOptions({
    this.polygons = const [],
    this.polygonCulling = false,
    this.simplify = false,
    rebuild,
  }) : super(rebuild: rebuild) {
    if (polygonCulling) {
      for (var polygon in polygons) {
        polygon.boundingBox = LatLngBounds.fromPoints(polygon.points);
      }
    }
  }
}

class Polygon {
  final List<LatLng> points;
  final List<Offset> offsets = [];
  final List<List<LatLng>> holePointsList;
  final List<List<Offset>> holeOffsetsList;
  final Color color;
  final double borderStrokeWidth;
  final Color borderColor;
  final bool disableHolesBorder;
  final bool isDotted;
  LatLngBounds boundingBox;

  Polygon({
    this.points,
    this.holePointsList,
    this.color = const Color(0xFF00FF00),
    this.borderStrokeWidth = 0.0,
    this.borderColor = const Color(0xFFFFFF00),
    this.disableHolesBorder = false,
    this.isDotted = false,
  }) : holeOffsetsList = null == holePointsList || holePointsList.isEmpty
            ? null
            : List.generate(holePointsList.length, (_) => []);
}

class PolygonLayer extends StatelessWidget {
  final PolygonLayerOptions polygonOpts;
  final MapState map;
  final Stream stream;

  PolygonLayer(this.polygonOpts, this.map, this.stream);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints bc) {
        // TODO unused BoxContraints should remove?
        final size = Size(bc.maxWidth, bc.maxHeight);
        return _build(context, size);
      },
    );
  }

  Widget _build(BuildContext context, Size size) {
    return StreamBuilder(
      stream: stream, // a Stream<void> or null
      builder: (BuildContext context, _) {
        var polygons = <Widget>[];

        for (var polygon in polygonOpts.polygons) {
          polygon.offsets.clear();

          if (null != polygon.holeOffsetsList) {
            for (var offsets in polygon.holeOffsetsList) {
              offsets.clear();
            }
          }

          if (polygonOpts.polygonCulling &&
              !polygon.boundingBox.isOverlapping(map.bounds)) {
            // skip this polygon as it's offscreen
            continue;
          }

          var points = polygon.points;
          if (polygonOpts.simplify) {
            points = Simplification.simplifyByZoom(points, map.zoom);
          }
          _fillOffsets(polygon.offsets, points);

          if (null != polygon.holePointsList) {
            for (var i = 0, len = polygon.holePointsList.length; i < len; ++i) {
              _fillOffsets(
                  polygon.holeOffsetsList[i], polygon.holePointsList[i]);
            }
          }

          polygons.add(
            CustomPaint(
              painter: PolygonPainter(polygon),
              size: size,
            ),
          );
        }

        return Container(
          child: Stack(
            children: polygons,
          ),
        );
      },
    );
  }

  void _fillOffsets(final List<Offset> offsets, final List<LatLng> points) {
    for (var i = 0, len = points.length; i < len; ++i) {
      var point = points[i];

      var pos = map.project(point);
      pos = pos.multiplyBy(map.getZoomScale(map.zoom, map.zoom)) -
          map.getPixelOrigin();
      offsets.add(Offset(pos.x.toDouble(), pos.y.toDouble()));
      if (i > 0) {
        offsets.add(Offset(pos.x.toDouble(), pos.y.toDouble()));
      }
    }
  }
}

class PolygonPainter extends CustomPainter {
  final Polygon polygonOpt;

  PolygonPainter(this.polygonOpt);

  @override
  void paint(Canvas canvas, Size size) {
    if (polygonOpt.offsets.isEmpty) {
      return;
    }
    final rect = Offset.zero & size;
    _paintPolygon(canvas, rect);
  }

  void _paintBorder(Canvas canvas) {
    if (polygonOpt.borderStrokeWidth > 0.0) {
      var borderRadius = (polygonOpt.borderStrokeWidth / 2);

      final borderPaint = Paint()
        ..color = polygonOpt.borderColor
        ..strokeWidth = polygonOpt.borderStrokeWidth;

      if (polygonOpt.isDotted) {
        var spacing = polygonOpt.borderStrokeWidth * 1.5;
        _paintDottedLine(
            canvas, polygonOpt.offsets, borderRadius, spacing, borderPaint);

        if (!polygonOpt.disableHolesBorder &&
            null != polygonOpt.holeOffsetsList) {
          for (var offsets in polygonOpt.holeOffsetsList) {
            _paintDottedLine(
                canvas, offsets, borderRadius, spacing, borderPaint);
          }
        }
      } else {
        _paintLine(canvas, polygonOpt.offsets, borderRadius, borderPaint);

        if (!polygonOpt.disableHolesBorder &&
            null != polygonOpt.holeOffsetsList) {
          for (var offsets in polygonOpt.holeOffsetsList) {
            _paintLine(canvas, offsets, borderRadius, borderPaint);
          }
        }
      }
    }
  }

  void _paintDottedLine(Canvas canvas, List<Offset> offsets, double radius,
      double stepLength, Paint paint) {
    var startDistance = 0.0;
    for (var i = 0; i < offsets.length - 1; i++) {
      var o0 = offsets[i];
      var o1 = offsets[i + 1];
      var totalDistance = _dist(o0, o1);
      var distance = startDistance;
      while (distance < totalDistance) {
        var f1 = distance / totalDistance;
        var f0 = 1.0 - f1;
        var offset = Offset(o0.dx * f0 + o1.dx * f1, o0.dy * f0 + o1.dy * f1);
        canvas.drawCircle(offset, radius, paint);
        distance += stepLength;
      }
      startDistance = distance < totalDistance
          ? stepLength - (totalDistance - distance)
          : distance - totalDistance;
    }
    canvas.drawCircle(offsets.last, radius, paint);
  }

  void _paintLine(
      Canvas canvas, List<Offset> offsets, double radius, Paint paint) {
    canvas.drawPoints(PointMode.lines, [...offsets, offsets[0]], paint);
    for (var offset in offsets) {
      canvas.drawCircle(offset, radius, paint);
    }
  }

  void _paintPolygon(Canvas canvas, Rect rect) {
    final paint = Paint();

    if (null != polygonOpt.holeOffsetsList) {
      canvas.saveLayer(rect, paint);
      paint.style = PaintingStyle.fill;

      for (var offsets in polygonOpt.holeOffsetsList) {
        var path = Path();
        path.addPolygon(offsets, true);
        canvas.drawPath(path, paint);
      }

      paint
        ..color = polygonOpt.color
        ..blendMode = BlendMode.srcOut;

      var path = Path();
      path.addPolygon(polygonOpt.offsets, true);
      canvas.drawPath(path, paint);

      _paintBorder(canvas);

      canvas.restore();
    } else {
      canvas.clipRect(rect);
      paint
        ..style = PaintingStyle.fill
        ..color = polygonOpt.color;

      var path = Path();
      path.addPolygon(polygonOpt.offsets, true);
      canvas.drawPath(path, paint);

      _paintBorder(canvas);
    }
  }

  @override
  bool shouldRepaint(PolygonPainter other) => false;

  double _dist(Offset v, Offset w) {
    return sqrt(_dist2(v, w));
  }

  double _dist2(Offset v, Offset w) {
    return _sqr(v.dx - w.dx) + _sqr(v.dy - w.dy);
  }

  double _sqr(double x) {
    return x * x;
  }
}

class Simplification {
  /// Code ported from  (c) 2017, Vladimir Agafonkin
  /// Simplify.js, a high-performance JS polyline simplification library
  /// mourner.github.io/simplify-js

// square distance between 2 points
  static double getSqDist(LatLng p1, LatLng p2) {
    var dx = p1.longitude - p2.longitude, dy = p1.latitude - p2.latitude;

    return dx * dx + dy * dy;
  }

// square distance from a point to a segment
  static double getSqSegDist(LatLng p, LatLng p1, LatLng p2) {
    var x = p1.longitude,
        y = p1.latitude,
        dx = p2.longitude - x,
        dy = p2.latitude - y;

    if (dx != 0 || dy != 0) {
      var t = ((p.longitude - x) * dx + (p.latitude - y) * dy) /
          (dx * dx + dy * dy);

      if (t > 1) {
        x = p2.longitude;
        y = p2.latitude;
      } else if (t > 0) {
        x += dx * t;
        y += dy * t;
      }
    }

    dx = p.longitude - x;
    dy = p.latitude - y;

    return dx * dx + dy * dy;
  }
// rest of the code doesn't care about point format

// basic distance-based simplification
  static List<LatLng> simplifyRadialDist(List<LatLng> points, sqTolerance) {
    var prevPoint = points[0], newPoints = [prevPoint], point;

    for (var i = 1, len = points.length; i < len; i++) {
      point = points[i];

      if (getSqDist(point, prevPoint) > sqTolerance) {
        newPoints.add(point);
        prevPoint = point;
      }
    }

    if (prevPoint != point) newPoints.add(point);

    return newPoints;
  }

  static void simplifyDPStep(
      List<LatLng> points, first, last, sqTolerance, simplified) {
    var maxSqDist = sqTolerance, index;

    for (var i = first + 1; i < last; i++) {
      var sqDist = getSqSegDist(points[i], points[first], points[last]);

      if (sqDist > maxSqDist) {
        index = i;
        maxSqDist = sqDist;
      }
    }

    if (maxSqDist > sqTolerance) {
      if (index - first > 1) {
        simplifyDPStep(points, first, index, sqTolerance, simplified);
      }
      simplified.add(points[index]);
      if (last - index > 1) {
        simplifyDPStep(points, index, last, sqTolerance, simplified);
      }
    }
  }

// simplification using Ramer-Douglas-Peucker algorithm
  static List<LatLng> simplifyDouglasPeucker(points, sqTolerance) {
    var last = points.length - 1;

    var simplified = [points[0]];
    simplifyDPStep(points, 0, last, sqTolerance, simplified);
    simplified.add(points[last]);

    return simplified;
  }

// both algorithms combined for awesome performance
  static List<LatLng> simplify(points,
      {tolerance = 1, highestQuality = false}) {
    if (points.length <= 2) return points;

    var sqTolerance = tolerance != null ? tolerance * tolerance : 1;

    points = highestQuality ? points : simplifyRadialDist(points, sqTolerance);
    points = simplifyDouglasPeucker(points, sqTolerance);

    return points;
  }

  static List<LatLng> simplifyByZoom(points, zoom) {
    var tolerance = 0.0;
    if (zoom >= 0 && zoom < 3) {
      tolerance = 0.5;
    } else if (zoom >= 3 && zoom < 5) {
      tolerance = 0.1;
    } else if (zoom >= 5 && zoom < 7) {
      tolerance = 0.05;
    } else if (zoom == 7) {
      tolerance = 0.01;
    } else if (zoom == 8) {
      tolerance = 0.005;
    } else if (zoom >= 9 && zoom < 12) {
      tolerance = 0.001;
    } else if (zoom > 12 && zoom < 17) {
      tolerance = 0.0001;
    }
    return Simplification.simplify(points, tolerance: tolerance);
  }
}
