import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sky_provider.dart';
import '../models/celestial_object.dart';
import '../widgets/sky_painter.dart';

class SkyScreen extends StatefulWidget {
  const SkyScreen({super.key});
  @override
  State<SkyScreen> createState() => _SkyScreenState();
}

class _SkyScreenState extends State<SkyScreen> {
  CelestialObject? _selected;
  Offset? _tapPosition;

  void _onObjectTapped(CelestialObject obj, Offset pos) {
    setState(() => _selected = obj);
  }

  @override
  Widget build(BuildContext context) {
    final sky = context.watch<SkyProvider>();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Sky canvas — full screen
          GestureDetector(
            onTapDown: (d) {
              setState(() => _tapPosition = d.localPosition);
              Future.delayed(const Duration(milliseconds: 50), () {
                setState(() => _tapPosition = null);
              });
            },
            child: CustomPaint(
              painter: SkyPainter(
                provider: sky,
                onObjectTapped: _onObjectTapped,
                tapPosition: _tapPosition,
              ),
              child: const SizedBox.expand(),
            ),
          ),

          // HUD — compass & altitude
          Positioned(
            top: 48,
            left: 16,
            child: _HudOverlay(sky: sky),
          ),

          // Object info card
          if (_selected != null)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: _InfoCard(
                obj: _selected!,
                onClose: () => setState(() => _selected = null),
              ),
            ),
        ],
      ),
    );
  }
}

class _HudOverlay extends StatelessWidget {
  final SkyProvider sky;
  const _HudOverlay({required this.sky});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_cardinalDirection(sky.azimuth),
              style: const TextStyle(color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.bold)),
          Text('Azimuth: ${sky.azimuth.toStringAsFixed(1)}°',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text('Lat: ${sky.latitude.toStringAsFixed(2)}°',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  String _cardinalDirection(double az) {
    const dirs = ['N','NE','E','SE','S','SW','W','NW','N'];
    return dirs[((az + 22.5) / 45).floor() % 8];
  }
}

class _InfoCard extends StatelessWidget {
  final CelestialObject obj;
  final VoidCallback onClose;
  const _InfoCard({required this.obj, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0d0d2b).withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Text(obj.symbol, style: const TextStyle(fontSize: 36)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(obj.name,
                    style: const TextStyle(color: Colors.white, fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(obj.description,
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text('Mass: ${obj.mass}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white38),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}