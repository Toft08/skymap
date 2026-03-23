import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:astronomia/astronomia.dart' as astro;
import 'package:astronomia/solar.dart' as solar;
import 'package:astronomia/moonposition.dart' as moonpos;
import 'package:astronomia/elliptic.dart' as elliptic;
import 'package:astronomia/planetposition.dart' as pp;
import '../models/celestial_object.dart';

class SkyProvider extends ChangeNotifier {
  /// Device pointing direction in degrees (compass bearing, 0 = North).
  double azimuth = 0;

  /// Observer location — stays at 0,0 until GPS resolves.
  double longitude = 0.0;
  double latitude = 0.0;

  List<CelestialObject> objects = [];
  List<Constellation> constellations = [];

  StreamSubscription? _compassSub;
  StreamSubscription? _accelSub;
  Timer? _notifyTimer;

  double _smoothAzimuth = 0;
  static const double _alpha = 0.15;

  // Device tilt: 0° = phone vertical (horizon), 90° = face-down (zenith).
  double _deviceAltitude = 0;

  // Reuse the Earth VSOP87 object — creating it is cheap but no need to repeat.
  final _earth = pp.Planet(pp.planetEarth);

  // Maps planet name → astronomia planet ID for VSOP87 geocentric computation.
  // Pluto is absent (dwarf planet; not in VSOP87) so its JSON position is used.
  static const Map<String, int> _planetIds = {
    'Mercury': pp.planetMercury,
    'Venus': pp.planetVenus,
    'Mars': pp.planetMars,
    'Jupiter': pp.planetJupiter,
    'Saturn': pp.planetSaturn,
    'Uranus': pp.planetUranus,
    'Neptune': pp.planetNeptune,
  };

  SkyProvider() {
    _loadData();
    _startSensors();
    _getLocation();
  }

  // ─── Data ──────────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    final raw = await rootBundle.loadString('assets/celestial_data.json');
    final Map<String, dynamic> json = jsonDecode(raw);

    objects = [
      ...(json['special'] as List).map((e) => CelestialObject(
            name: e['name'],
            symbol: e['symbol'],
            description: e['description'],
            mass: e['mass'],
            ra: (e['ra'] as num).toDouble(),
            dec: (e['dec'] as num).toDouble(),
            type: e['name'] == 'Sun' ? ObjectType.sun : ObjectType.moon,
          )),
      ...(json['planets'] as List).map((e) => CelestialObject(
            name: e['name'],
            symbol: e['symbol'],
            description: e['description'],
            mass: e['mass'],
            ra: (e['ra'] as num).toDouble(),
            dec: (e['dec'] as num).toDouble(),
            type: ObjectType.planet,
          )),
    ];

    constellations = (json['constellations'] as List).map((c) {
      return Constellation(
        name: c['name'],
        description: c['description'],
        stars: (c['stars'] as List)
            .map((s) => ConstellationStar(
                  name: s['name'],
                  ra: (s['ra'] as num).toDouble(),
                  dec: (s['dec'] as num).toDouble(),
                ))
            .toList(),
        lines: (c['lines'] as List)
            .map<List<int>>(
                (l) => (l as List).map<int>((i) => i as int).toList())
            .toList(),
      );
    }).toList();

    notifyListeners();
  }

  // ─── Sensors ───────────────────────────────────────────────────────────────

  void _startSensors() {
    _compassSub = FlutterCompass.events?.listen((CompassEvent event) {
      final raw = event.heading;
      if (raw == null) return;
      double dAz = raw - _smoothAzimuth;
      while (dAz > 180) dAz -= 360;
      while (dAz < -180) dAz += 360;
      _smoothAzimuth = (_smoothAzimuth + _alpha * dAz) % 360;
      if (_smoothAzimuth < 0) _smoothAzimuth += 360;
      azimuth = _smoothAzimuth;
    });

    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 80),
    ).listen((AccelerometerEvent e) {
      _deviceAltitude = atan2(-e.z, e.y) * 180 / pi;
    });

    // 10 Hz repaint timer (task requirement).
    _notifyTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      notifyListeners();
    });
  }

  // ─── Location ──────────────────────────────────────────────────────────────

  Future<void> _getLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return;

    final pos = await Geolocator.getCurrentPosition();
    latitude = pos.latitude;
    longitude = pos.longitude;
    notifyListeners();
  }

  // ─── Astronomy ─────────────────────────────────────────────────────────────

  /// Julian Day for the current UTC time via astronomia.
  double _getJulianDay() {
    final now = DateTime.now().toUtc();
    final dayFraction =
        now.day + now.hour / 24.0 + now.minute / 1440.0 + now.second / 86400.0;
    return astro.calendarGregorianToJD(now.year, now.month, dayFraction);
  }

  /// Equatorial (RA°, Dec°) → horizontal (alt°, az°) using astronomia.
  ///
  /// Key conventions of [astro.eqToHz]:
  ///   • All angles are in radians.
  ///   • [psi] (longitude) is positive-west, so we negate east longitude.
  ///   • [st] is Greenwich Sidereal Time in radians.
  ///     astro.mean(jd) returns GST in seconds → multiply by 2π/86400.
  ///   • The returned azimuth is measured westward from south.
  ///     Add 180° to get a standard compass bearing (N = 0°, clockwise).
  (double alt, double az) _equatorialToHorizontal(double raDeg, double decDeg) {
    final jd = _getJulianDay();
    // GST: sidereal seconds → radians
    final gstRad = (astro.mean(jd) / 86400.0) * 2 * pi;
    final hz = astro.eqToHz(
      astro.toRad(raDeg), // right ascension in radians
      astro.toRad(decDeg), // declination in radians
      astro.toRad(latitude), // phi: observer latitude, north-positive
      astro.toRad(-longitude), // psi: positive-west → negate east longitude
      gstRad, // Greenwich Sidereal Time in radians
    );
    final altDeg = astro.toDeg(hz.alt);
    // Convert westward-from-south → compass bearing (north = 0°, clockwise).
    final azDeg = (astro.toDeg(hz.az) + 180.0) % 360.0;
    return (altDeg, azDeg);
  }

  /// Sun RA/Dec in degrees — Meeus Ch. 25, apparent place (nutation + aberration).
  (double ra, double dec) _computeSunRaDec() {
    final eq = solar.apparentEquatorial(_getJulianDay()); // radians
    return (astro.toDeg(eq.ra), astro.toDeg(eq.dec));
  }

  /// Moon RA/Dec in degrees — Meeus Ch. 47, ecliptic → equatorial.
  (double ra, double dec) _computeMoonRaDec() {
    final jd = _getJulianDay();
    final pos = moonpos.position(jd); // ecliptic lon/lat in radians
    final eps = astro.meanObliquity(jd); // obliquity in radians
    final eq = astro.eclToEq(pos.lon, pos.lat, sin(eps), cos(eps));
    return (astro.toDeg(eq.ra), astro.toDeg(eq.dec));
  }

  /// Planet RA/Dec in degrees — VSOP87 with geocentric light-time correction.
  (double ra, double dec) _computePlanetRaDec(int planetId) {
    final eq = elliptic.position(pp.Planet(planetId), _earth, _getJulianDay());
    return (astro.toDeg(eq.ra), astro.toDeg(eq.dec));
  }

  // ─── Projection ────────────────────────────────────────────────────────────

  /// Projects a CelestialObject to a screen pixel.
  /// Sun, Moon, and planets get live-computed positions; constellation stars
  /// use their fixed catalogue RA/Dec.
  Offset? projectObject(CelestialObject obj, Size screenSize) {
    double ra = obj.ra, dec = obj.dec;
    if (obj.type == ObjectType.sun) {
      (ra, dec) = _computeSunRaDec();
    } else if (obj.type == ObjectType.moon) {
      (ra, dec) = _computeMoonRaDec();
    } else if (obj.type == ObjectType.planet) {
      final id = _planetIds[obj.name];
      if (id != null) (ra, dec) = _computePlanetRaDec(id);
    }
    return project(ra, dec, screenSize);
  }

  /// Projects equatorial (RA°, Dec°) to a screen pixel.
  ///
  /// Horizontal FOV: 90° centred on compass heading.
  /// Vertical FOV:   90° centred on device tilt.
  Offset? project(double ra, double dec, Size screenSize) {
    final (objAlt, objAz) = _equatorialToHorizontal(ra, dec);

    double dAz = objAz - azimuth;
    while (dAz > 180) dAz -= 360;
    while (dAz < -180) dAz += 360;

    const hFov = 90.0;
    if (dAz.abs() > hFov / 2) return null;

    const vFov = 90.0;
    final dAlt = objAlt - _deviceAltitude;
    if (dAlt.abs() > vFov / 2) return null;

    final x = screenSize.width / 2 - (dAz / hFov) * screenSize.width;
    final y = screenSize.height / 2 - (dAlt / vFov) * screenSize.height;
    return Offset(x, y);
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _accelSub?.cancel();
    _notifyTimer?.cancel();
    super.dispose();
  }
}
