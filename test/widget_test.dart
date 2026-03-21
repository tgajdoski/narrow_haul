import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/tiled_level_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('level_01.tmx parses walls, cargo_zone, and random cargo', () async {
    final data = await loadLevelFromTmx(
      'assets/tiles/level_01.tmx',
      levelIndex: 0,
    );
    expect(data.walls.length, 4);
    expect(data.cargoZoneSize.x, greaterThan(0));
    expect(data.ropeMaxLength, greaterThan(0));
  });
}
