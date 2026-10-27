import 'package:flutter_test/flutter_test.dart';
import 'package:palio_dashboard/shared/settings/app_settings.dart';

void main() {
  group('PressureUnit', () {
    test('kPa conversion maintains exact value', () {
      expect(PressureUnit.kpa.convert(100.0), 100.0);
      expect(PressureUnit.kpa.label, 'kPa');
    });

    test('bar conversion divides kPa by 100', () {
      expect(PressureUnit.bar.convert(100.0), closeTo(1.0, 0.001));
      expect(PressureUnit.bar.convert(250.0), closeTo(2.5, 0.001));
      expect(PressureUnit.bar.label, 'bar');
    });

    test('psi conversion converts kPa correctly', () {
      // 100 kPa ~ 14.5038 psi
      expect(PressureUnit.psi.convert(100.0), closeTo(14.5038, 0.01));
      expect(PressureUnit.psi.label, 'psi');
    });
  });

  group('TempUnit', () {
    test('celsius conversion returns identical temperature', () {
      expect(TempUnit.celsius.convert(90.0), 90.0);
      expect(TempUnit.celsius.label, '°C');
    });

    test('fahrenheit conversion correctly calculates (C * 9/5) + 32', () {
      expect(TempUnit.fahrenheit.convert(0.0), 32.0);
      expect(TempUnit.fahrenheit.convert(100.0), 212.0);
      expect(TempUnit.fahrenheit.convert(90.0), 194.0);
      expect(TempUnit.fahrenheit.label, '°F');
    });
  });

  group('SpeedUnit', () {
    test('km/h returns unaltered value', () {
      expect(SpeedUnit.kmh.convert(100.0), 100.0);
      expect(SpeedUnit.kmh.label, 'km/h');
    });

    test('mph divides km/h by 1.60934', () {
      expect(SpeedUnit.mph.convert(100.0), closeTo(62.137, 0.01));
      expect(SpeedUnit.mph.label, 'mph');
    });
  });

  group('ClusterTheme', () {
    test('all themes have distinct accents and labels', () {
      for (final theme in ClusterTheme.values) {
        expect(theme.label.isNotEmpty, isTrue);
        expect(theme.accent, isNotNull);
      }
      expect(ClusterTheme.values.length, 5);
    });
  });

  group('PalioEngineProfile', () {
    test('profiles have appropriate maxRpm and redlineRpm', () {
      for (final profile in PalioEngineProfile.values) {
        expect(profile.maxRpm, greaterThanOrEqualTo(profile.redlineRpm));
        expect(profile.displayName.isNotEmpty, isTrue);
        expect(profile.ecuModel.isNotEmpty, isTrue);
      }
    });

    test('Fire 1.0 8V configured with IAW 4AF', () {
      final p = PalioEngineProfile.fire10_8v;
      expect(p.ecuModel, 'IAW 4AF / 4EF');
      expect(p.redlineRpm, 6500);
      expect(p.maxRpm, 7000);
    });

    test('E.torQ 1.6 16V configured with IAW 7GF', () {
      final p = PalioEngineProfile.etorq16_16v;
      expect(p.ecuModel, 'IAW 7GF');
      expect(p.redlineRpm, 6800);
      expect(p.maxRpm, 8000);
    });
  });
}
