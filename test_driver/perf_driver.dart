// Host side of `flutter drive` for integration_test/perf_flight_test.dart:
// writes each level's frame-timing summary to build/perf_device_<key>.json.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        if (data == null) return;
        for (final key in data.keys) {
          await writeResponseData(
            data[key] as Map<String, dynamic>,
            testOutputFilename: 'perf_device_$key',
            destinationDirectory: 'build',
          );
        }
      },
    );
