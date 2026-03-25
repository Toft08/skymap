import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sky_map/models/celestial_object.dart';
import 'package:sky_map/providers/sky_provider.dart';
import 'package:sky_map/screens/sky_screen.dart';

void main() {
  // ── Unit: model ────────────────────────────────────────────────────────────

  test('CelestialObject stores all fields correctly', () {
    final obj = CelestialObject(
      name: 'Mars',
      symbol: '♂',
      description: 'The red planet.',
      mass: '6.39 × 10²³ kg',
      ra: 123.4,
      dec: -5.6,
      type: ObjectType.planet,
    );
    expect(obj.name, 'Mars');
    expect(obj.type, ObjectType.planet);
    expect(obj.ra, closeTo(123.4, 0.001));
    expect(obj.dec, closeTo(-5.6, 0.001));
  });

  test('Constellation stores stars and lines correctly', () {
    final star = ConstellationStar(name: 'Betelgeuse', ra: 88.79, dec: 7.41);
    final c = Constellation(
      name: 'Orion',
      description: 'The hunter.',
      stars: [star],
      lines: [
        [0, 0],
      ],
    );
    expect(c.name, 'Orion');
    expect(c.stars.first.name, 'Betelgeuse');
    expect(c.lines.first, [0, 0]);
  });

  // ── Unit: provider data loading ────────────────────────────────────────────

  testWidgets(
    'SkyProvider loads Sun, Moon, all 7 planets and ≥3 constellations',
    (WidgetTester tester) async {
      // testWidgets initialises ServicesBinding so rootBundle works.
      final provider = SkyProvider.forTest();
      await provider.loadDataForTest();

      final names = provider.objects.map((o) => o.name).toList();
      expect(names, contains('Sun'));
      expect(names, contains('Moon'));
      for (final planet in [
        'Mercury',
        'Venus',
        'Mars',
        'Jupiter',
        'Saturn',
        'Uranus',
        'Neptune',
      ]) {
        expect(
          names,
          contains(planet),
          reason: '$planet must be present in the object list',
        );
      }
      expect(provider.constellations.length, greaterThanOrEqualTo(3));
    },
  );

  // ── Widget: smoke test ─────────────────────────────────────────────────────

  testWidgets('SkyScreen renders a black Scaffold', (
    WidgetTester tester,
  ) async {
    final provider = SkyProvider.forTest();

    await tester.pumpWidget(
      ChangeNotifierProvider<SkyProvider>.value(
        value: provider,
        child: const MaterialApp(home: SkyScreen()),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, Colors.black);
  });
}
