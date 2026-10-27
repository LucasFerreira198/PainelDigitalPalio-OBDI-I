import 'package:flutter_test/flutter_test.dart';
import 'package:palio_dashboard/core/obd2/obd2_service.dart';
import 'package:palio_dashboard/shared/settings/app_settings.dart';

void main() {
  group('Palio Profiles and Protocol Order', () {
    test('Obd2Service.allProtocolsInOrder prioritizes KWP2000 Fast Init', () {
      final protocols = Obd2Service.allProtocolsInOrder;
      expect(protocols.first, EcuProtocol.kwp2000FastInit);
      expect(protocols.contains(EcuProtocol.kwp2000SlowInit), isTrue);
      expect(protocols.contains(EcuProtocol.iso9141), isTrue);
      expect(protocols.contains(EcuProtocol.obd2Standard), isTrue);
    });

    test('PalioEngineProfile has valid redline and max RPM for all configurations', () {
      for (final profile in PalioEngineProfile.values) {
        expect(profile.redlineRpm, greaterThanOrEqualTo(5000));
        expect(profile.redlineRpm, lessThanOrEqualTo(7500));
        expect(profile.maxRpm, greaterThan(profile.redlineRpm));
      }
    });

    test('EcuProtocol labels identify Fiat protocols correctly', () {
      expect(
        EcuProtocol.kwp2000FastInit.displayLabel,
        'KWP2000 (fast init)',
      );
      expect(
        EcuProtocol.kwp2000SlowInit.displayLabel,
        'KWP2000 (slow init)',
      );
      expect(
        EcuProtocol.obd2Standard.displayLabel,
        'OBD-II padrão',
      );
    });
  });
}
