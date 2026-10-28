import 'package:flutter_test/flutter_test.dart';
import 'package:palio_dashboard/core/ota/ota_service.dart';

void main() {
  group('isNewerVersion', () {
    test('detecta versão major mais nova', () {
      expect(isNewerVersion(latest: 'v2.0.0', current: '1.0.0'), isTrue);
    });

    test('detecta versão minor mais nova', () {
      expect(isNewerVersion(latest: 'v1.2.0', current: '1.1.5'), isTrue);
    });

    test('detecta versão patch mais nova', () {
      expect(isNewerVersion(latest: 'v1.0.1', current: '1.0.0'), isTrue);
    });

    test('retorna false para mesma versão', () {
      expect(isNewerVersion(latest: 'v1.0.0', current: '1.0.0'), isFalse);
    });

    test('retorna false quando a atual é mais nova', () {
      expect(isNewerVersion(latest: 'v1.0.0', current: '1.2.0'), isFalse);
    });

    test('ignora sufixo de build number', () {
      expect(isNewerVersion(latest: 'v1.0.0', current: '1.0.0+5'), isFalse);
    });

    test('funciona sem prefixo "v"', () {
      expect(isNewerVersion(latest: '1.3.0', current: '1.2.9'), isTrue);
    });
  });

  group('OtaService security validation', () {
    test('rejeita download com URL não-HTTPS', () async {
      final ota = OtaService();
      expect(
        () => ota.downloadApk('http://github.com/LucasFerreira198/app/update.apk'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejeita download de domínio não-autorizado', () async {
      final ota = OtaService();
      expect(
        () => ota.downloadApk('https://malicious-site.com/update.apk'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejeita download de arquivo sem extensão .apk', () async {
      final ota = OtaService();
      expect(
        () => ota.downloadApk('https://github.com/LucasFerreira198/app/update.exe'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
