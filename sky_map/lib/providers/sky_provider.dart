import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vector_math/vector_math.dart' hide Colors;
import '../models/celestial_object.dart';

class SkyProvider extends ChangeNotifier {
  /// Device pointing direction in degrees.
  double azimuth = 0;

  /// Observer location — stays at 0,0 until GPS resolves.
  double longitude = 0.0;
  double latitude = 0.0;

  List<CelestialObject> objects = [];
  List<Constellation> constellations = [];

  StreamSubscription? _compassSub;
  StreamSubscription? _accelSub;
  Timer? _notifyTimer;

  // Heading smoothing — flutter_compass gives tilt-compensated heading.
  double _smoothAzimuth = 0;
  static const double _alpha = 0.15;

  // Device tilt: 0° = phone vertical (camera at horizon),
  //             90° = phone flat face-down (camera at zenith),
  //            −90° = phone flat face-up  (camera at nadir).
  double _deviceAltitude = 0;

  SkyProvider() {
    _loadData();
    _startSensors();
    _getLocation();
  }

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

    // Parse constellations (previously missing — fixed).
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
    // ── Heading (azimuth) ──────────────────────────────────────────────────
    // flutter_compass uses CLLocationManager on iOS and TYPE_ROTATION_VECTOR
    // on Android — both are hardware-level tilt-compensated heading sources
    // equivalent to the system compass app.
    _compassSub = FlutterCompass.events?.listen((CompassEvent event) {
      final raw = event.heading;
      if (raw == null) return;
      double dAz = raw - _smoothAzimuth;
      while (dAz >  180) dAz -= 360;
      while (dAz < -180) dAz += 360;
      _smoothAzimuth = (_smoothAzimuth + _alpha * dAz) % 360;
      if (_smoothAzimuth < 0) _smoothAzimuth += 360;
      azimuth = _smoothAzimuth;
    });

    // ── Device tilt / altitude (accelerometer via sensors_plus) ────────────
    // We read the raw accelerometer directly to compute how far the phone is
    // tilted up or down.  This controls the vertical centre of the sky view:
    // tilt the phone up → see objects higher in the sky.
    //
    // Axes for a portrait-held phone:
    //   Y+ = toward top of device (long axis)
    //   Z+ = out through the screen (toward user's face)
    // When the phone is held vertically: gravity ≈ (0, 9.8, 0)
    //   → atan2(0, 9.8) = 0°  (camera pointing at horizon) ✓
    // Tilted back 90° (flat, face-down): gravity ≈ (0, 0, −9.8)
    //   → atan2(−9.8, 0) = −90°  (camera pointing at zenith) ✓
    //   … so we negate az to get a positive altitude when looking up.
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 80),
    ).listen((AccelerometerEvent e) {
      // Elevation of the camera direction (−Z axis of plane perpendicular
      // to gravity) relative to the horizontal plane:
      //   0°  → phone vertical  → looking at horizon
      //  90°  → phone tilted back (face-down) → looking at zenith
      // −90°  → phone tilted forward (face-up) → looking at nadir
      _deviceAltitude = atan2(-e.z, e.y) * 180 / pi;
    });

    // ── 10 Hz repaint timer (task requirement) ─────────────────────────────
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

  /// Julian Date for a UTC DateTime.
  double _julianDate(DateTime dt) {
    final a = (14 - dt.month) ~/ 12;
    final y = dt.year + 4800 - a;
    final m = dt.month + 12 * a - 3;
    final jdn = dt.day +
        (153 * m + 2) ~/ 5 +
        365 * y +
        y ~/ 4 -
        y ~/ 100 +
        y ~/ 400 -
        32045;
    return jdn.toDouble() +
        (dt.hour - 12) / 24.0 +
        dt.minute / 1440.0 +
        dt.second / 86400.0;
  }

  /// Local Sidereal Time in degrees (accounts for observer longitude).
  double _computeLST() {
    final now = DateTime.now().toUtc();
    final jd = _julianDate(now);
    final T = (jd - 2451545.0) / 36525.0;
    // Greenwich Mean Sidereal Time
    double gmst = 280.46061837 +
        360.98564736629 * (jd - 2451545.0) +
        0.000387933 * T * T -
        T * T * T / 38710000.0;
    gmst = gmst % 360;
    if (gmst < 0) gmst += 360;
    double lst = (gmst + longitude) % 360;
    if (lst < 0) lst += 360;
    return lst;
  }

  /// Convert equatorial (RA°, Dec°) → horizontal (altitude°, azimuth°).
  /// Uses current LST and observer latitude.
  (double alt, double az) _equatorialToHorizontal(double raDeg, double decDeg) {
    final lst = _getLst();
    double ha = (lst - raDeg) % 360;
    if (ha < 0) ha += 360;

    final H = radians(ha);
    final d = radians(decDeg);
    final phi = radians(latitude);

    final sinAlt = sin(d) * sin(phi) + cos(d) * cos(phi) * cos(H);
    final altRad = asin(sinAlt.clamp(-1.0, 1.0));

    // Avoid division by zero near zenith/nadir.
    final cosAlt = cos(altRad);
    final cosAz = cosAlt.abs() < 1e-10
        ? 0.0
        : (sin(d) - sin(altRad) * sin(phi)) / (cosAlt * cos(phi));
    double azRad = acos(cosAz.clamp(-1.0, 1.0));
    if (sin(H) > 0) azRad = 2 * pi - azRad;

    return (degrees(altRad), degrees(azRad));
  }

  /// Cached LST so every object in the same frame uses the same time value.
  double? _cachedLst;
  DateTime? _cachedLstTime;

  double _getLst() {
    final now = DateTime.now().toUtc();
    // Reuse cached value if less than 100 ms old (one render frame).
    if (_cachedLst != null &&
        _cachedLstTime != null &&
        now.difference(_cachedLstTime!).inMilliseconds < 100) {
      return _cachedLst!;
    }
    _cachedLst = _computeLST();
    _cachedLstTime = now;
    return _cachedLst!;
  }

  // ─── Dynamic body positions ────────────────────────────────────────────────

  /// Sun's RA/Dec computed from current date using USNO simplified formula.
  /// Accurate to ~1°. The Sun moves ~1°/day through the ecliptic, so hardcoding
  /// RA/Dec in the JSON would be wrong within weeks.
  (double ra, double dec) _computeSunRaDec() {
    final jd = _julianDate(DateTime.now().toUtc());
    final n = jd - 2451545.0;
    double L = (280.460 + 0.9856474 * n) % 360;
    double g = (357.528 + 0.9856003 * n) % 360;
    if (L < 0) L += 360;
    if (g < 0) g += 360;
    final lambda = L + 1.915 * sin(radians(g)) + 0.020 * sin(radians(2 * g));
    final epsilon = 23.439 - 0.0000004 * n;
    double ra = degrees(atan2(
      cos(radians(epsilon)) * sin(radians(lambda)), cos(radians(lambda))));
    if (ra < 0) ra += 360;
    final dec =
        degrees(asin((sin(radians(epsilon)) * sin(radians(lambda))).clamp(-1.0, 1.0)));
    return (ra, dec);
  }

  /// Moon's RA/Dec computed from current date using simplified lunar theory.
  /// Accurate to ~1–2°.
  (double ra, double dec) _computeMoonRaDec() {
    final jd = _julianDate(DateTime.now().toUtc());
    final n = jd - 2451545.0;
    double L0 = (218.316 + 13.176396 * n) % 360;
    double M  = (134.963 + 13.064993 * n) % 360;
    double F  = (93.272  + 13.229350 * n) % 360;
    if (L0 < 0) L0 += 360;
    if (M  < 0) M  += 360;
    if (F  < 0) F  += 360;
    final lambda  = radians(L0 + 6.289 * sin(radians(M)));
    final beta    = radians(5.128 * sin(radians(F)));
    final epsilon = radians(23.439 - 0.0000004 * n);
    double ra = degrees(atan2(
      sin(lambda) * cos(epsilon) - tan(beta) * sin(epsilon), cos(lambda)));
    if (ra < 0) ra += 360;
    final dec = degrees(
        asin((sin(beta) * cos(epsilon) + cos(beta) * sin(epsilon) * sin(lambda))
            .clamp(-1.0, 1.0)));
    return (ra, dec);
  }

  /// Project a CelestialObject onto the screen.
  /// Sun and Moon get dynamically computed RA/Dec (they move daily).
  /// Planets and constellation stars use their stored values from the data file.
  Offset? projectObject(CelestialObject obj, Size screenSize) {
    double ra = obj.ra, dec = obj.dec;
    if (obj.type == ObjectType.sun) {
      (ra, dec) = _computeSunRaDec();
    } else if (obj.type == ObjectType.moon) {
      (ra, dec) = _computeMoonRaDec();
    }
    return project(ra, dec, screenSize);
  }

  /// Project equatorial (RA°, Dec°) to a screen pixel.
  ///
  /// Horizontal axis: 90° FOV centred on compass heading — rotate phone left/right.
  /// Vertical axis:   90° FOV centred on device tilt (_deviceAltitude) —
  ///                  tilt phone up/down to scan the sky vertically.
  Offset? project(double ra, double dec, Size screenSize) {
    final (objAlt, objAz) = _equatorialToHorizontal(ra, dec);

    // Horizontal: angular distance from current bearing.
    double dAz = objAz - azimuth;
    while (dAz >  180) dAz -= 360;
    while (dAz < -180) dAz += 360;

    const hFov = 90.0;
    if (dAz.abs() > hFov / 2) return null;

    // Vertical: angular distance from where the phone is currently pointing.
    const vFov = 90.0;
    final dAlt = objAlt - _deviceAltitude;
    if (dAlt.abs() > vFov / 2) return null;

    // x: negative dAz → turning left pans sky left.
    final x = screenSize.width  / 2 - (dAz  / hFov) * screenSize.width;
    // y: positive dAlt → object above centre → smaller y (higher on screen).
    final y = screenSize.height / 2 - (dAlt  / vFov) * screenSize.height;
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