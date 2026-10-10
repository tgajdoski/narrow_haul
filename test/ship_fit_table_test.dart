import 'package:flutter_test/flutter_test.dart';
import 'package:narrow_haul/game/level/ship_fit_table.dart';

import '../tool/gen_ship_fit.dart';

void main() {
  test('the ship fit table matches the validator '
      '(stale: dart run tool/gen_ship_fit.dart)', () {
    expect(renderShipFitTable(kShipFitTable), renderShipFitTable(computeShipFitTable()));
  });

  test('every ship flies more than its own world', () {
    for (final id in ['kestrel', 'hopper', 'mule', 'skate', 'vector', 'talon']) {
      final extra = kShipFitTable.values.where((r) => r[id]?.flies ?? false).length;
      expect(extra, greaterThan(8), reason: id);
    }
  });
}
