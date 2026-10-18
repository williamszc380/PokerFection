// Runs the tests in integration_test/ through flutter drive, which can build
// the app in profile mode (closer to what players run than flutter test's
// debug build, so its memory and processor numbers mean more):
//
//   flutter drive --profile -d windows --driver integration_test/driver.dart --target integration_test/rtc_loopback_test.dart
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
