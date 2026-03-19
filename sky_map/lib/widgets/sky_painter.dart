import 'package:flutter/material.dart';
import '../models/celestial_object.dart';
import '../providers/sky_provider.dart';

class SkyPainter extends CustomPainter {
  final SkyProvider provider;
  final Function(CelestialObject obj, Offset pos) onObjectTapped;
  final Offset? tapPosition;

  SkyPainter({required this.provider, required this.onObjectTapped, this.tapPosition});

  // Store hit targets for tap detection
  final List<MapEntry<CelestialObject, Offset>> _hitTargets = [];

  @override
  void paint(Canvas canvas, Size size) {
    _hitTargets.clear();
    _drawBackground(canvas, size);
    _drawConstellations(canvas, size);
    _drawObjects(canvas, size);

    // Tap detection
    if (tapPosition != null) {
      for (final entry in _hitTargets) {
        if ((entry.value - tapPosition!).distance < 30) {
          onObjectTapped(entry.key, entry.value);
          break;
        }
      }
    }
  }

  void _drawBackground(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    canvas.drawRect(Offset.zero & size, paint);

    // Subtle gradient — slightly lighter near horizon
    final grad = RadialGradient(
      center: Alignment.bottomCenter,
      radius: 1.2,
      colors: [const Color(0xFF0a0a2e), Colors.black],
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = grad.createShader(Offset.zero & size),
    );
  }

  void _drawConstellations(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.blue.withOpacity(0.3)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final starPaint = Paint()..color = Colors.lightBlueAccent.withOpacity(0.8);
    final labelStyle = TextStyle(color: Colors.blue.shade200, fontSize: 9);

    for (final c in provider.constellations) {
      final positions = c.stars.map((s) => provider.project(s.ra, s.dec, size)).toList();

      // Draw lines
      for (final line in c.lines) {
        final p1 = positions[line[0]];
        final p2 = positions[line[1]];
        if (p1 != null && p2 != null) {
          canvas.drawLine(p1, p2, linePaint);
        }
      }

      // Draw stars
      for (int i = 0; i < c.stars.length; i++) {
        final pos = positions[i];
        if (pos == null) continue;
        canvas.drawCircle(pos, 2.5, starPaint);
      }

      // Label constellation name near first star
      if (positions.isNotEmpty && positions[0] != null) {
        _drawLabel(canvas, c.name, positions[0]!, labelStyle);
      }
    }
  }

  void _drawObjects(Canvas canvas, Size size) {
    for (final obj in provider.objects) {
      // Use projectObject() so Sun/Moon get dynamically computed positions.
      final pos = provider.projectObject(obj, size);
      if (pos == null) continue;

      _hitTargets.add(MapEntry(obj, pos));

      switch (obj.type) {
        case ObjectType.sun:
          _drawSun(canvas, pos);
        case ObjectType.moon:
          _drawMoon(canvas, pos);
        case ObjectType.planet:
          _drawPlanet(canvas, pos, obj);
        case ObjectType.star:
          canvas.drawCircle(pos, 3, Paint()..color = Colors.white);
      }

      // Name label
      _drawLabel(canvas, obj.name, pos + const Offset(10, -8),
          const TextStyle(color: Colors.white70, fontSize: 10));
    }
  }

  void _drawSun(Canvas canvas, Offset pos) {
    final paint = Paint()
      ..shader = RadialGradient(colors: [Colors.yellow, Colors.orange]).createShader(
          Rect.fromCircle(center: pos, radius: 18));
    canvas.drawCircle(pos, 18, paint);
    // Glow
    canvas.drawCircle(pos, 24, Paint()..color = Colors.yellow.withOpacity(0.15));
  }

  void _drawMoon(Canvas canvas, Offset pos) {
    canvas.drawCircle(pos, 12, Paint()..color = const Color(0xFFDDDDB0));
    // Crescent shadow
    canvas.drawCircle(pos + const Offset(5, 0), 10,
        Paint()..color = Colors.black.withOpacity(0.7));
  }

  void _drawPlanet(Canvas canvas, Offset pos, CelestialObject obj) {
    final colors = {
      'Mercury': Colors.grey,
      'Venus':   Colors.orange.shade200,
      'Mars':    Colors.red.shade400,
      'Jupiter': Colors.orange.shade300,
      'Saturn':  Colors.yellow.shade700,
      'Uranus':  Colors.cyan.shade300,
      'Neptune': Colors.blue.shade600,
    };
    final color = colors[obj.name] ?? Colors.white;
    canvas.drawCircle(pos, 7, Paint()..color = color);

    if (obj.name == 'Saturn') {
      final ringPaint = Paint()
        ..color = Colors.yellow.shade700.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawOval(Rect.fromCenter(center: pos, width: 22, height: 7), ringPaint);
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset pos, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(SkyPainter old) => true;
}