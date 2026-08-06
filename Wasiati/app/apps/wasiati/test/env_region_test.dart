import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/core/config/env.dart';

// Each region ships its own build. If REGION is not passed at build time the app
// falls back to US — safe (Nafath hidden) but wrong for the KSA build, so CI passes
// --dart-define=REGION per matrix entry. Run with:
//   flutter test --dart-define=REGION=KSA test/env_region_test.dart
void main() {
  test('Nafath is offered only on the KSA build', () {
    expect(Env.supportsNafath, Env.region == 'KSA');
  });

  test('an unset REGION fails closed to US, never showing Nafath elsewhere', () {
    if (Env.region != 'KSA') expect(Env.supportsNafath, isFalse);
  });
}
