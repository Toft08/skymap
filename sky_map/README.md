# Sky Map — Flutter app

Real-time augmented sky map. Displays the Sun, Moon, all 8 planets, and three constellations (Orion, Big Dipper, Ursa Minor) projected onto the screen based on the device's GPS position and physical orientation.

## Architecture

- **State management** — Provider (`SkyProvider extends ChangeNotifier`)
- **Sensors** — `flutter_compass` (magnetometer), `sensors_plus` (accelerometer), `geolocator` (GPS)
- **Astronomy** — [`astronomia`](https://pub.dev/packages/astronomia) package (Meeus algorithms)
  - Sun: `solar.apparentEquatorial` — nutation + aberration (Ch. 25/27)
  - Moon: `moonpos.position` + `eclToEq` (Ch. 47)
  - Planets: `elliptic.position` — VSOP87 with light-time correction (Ch. 33)
  - Coordinate transform: `astro.eqToHz` — equatorial → horizontal (Ch. 13)
- **Data** — `assets/celestial_data.json` (static catalogue for stars/constellations; positions for solar-system bodies are computed live)
- **Rendering** — `CustomPainter` (`SkyPainter`), repainted at 10 Hz

## Project structure

```
lib/
  main.dart                 # App entry point, Provider setup
  models/celestial_object.dart
  providers/sky_provider.dart   # All sensor + astronomy logic
  screens/sky_screen.dart       # UI, tap-to-inspect dialogs
  widgets/sky_painter.dart      # Canvas rendering
assets/
  celestial_data.json
test/
  widget_test.dart
```

## Running

```bash
flutter pub get
flutter run          # requires a physical device for compass/GPS
flutter test         # unit + widget tests
```
