class CelestialObject {
  final String name;
  final String symbol;
  final String description;
  final String mass;
  final double ra; // Right Ascension in deg(0-360)
  final double dec; // Declination in degress (-90 to 90)
  final ObjectType type;

  CelestialObject({
    required this.name,
    required this.symbol,
    required this.description,
    required this.mass,
    required this.ra,
    required this.dec,
    required this.type,
  });
}

enum ObjectType { planet, sun, moon, star }

class ConstellationStar {
  final String name;
  final double ra;
  final double dec;
  ConstellationStar({required this.name, required this.ra, required this.dec});
}


class Constellation {
  final String name;
  final String description;
  final List<ConstellationStar> stars;
  final List<List<int>> lines; // indices into stars list

  Constellation({
    required this.name,
    required this.description,
    required this.stars,
    required this.lines,
  });
}