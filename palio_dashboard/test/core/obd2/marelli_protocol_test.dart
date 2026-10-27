import 'package:flutter_test/flutter_test.dart';
import 'package:palio_dashboard/core/obd2/marelli_protocol.dart';

void main() {
  group('parseMarelliResponse', () {
    test('parseia resposta KWP2000 Fiat com header 84 F1 10 41 0C', () {
      // 84 F1 10 41 0C 1F 40 (dados 1F 40 = 2000 RPM)
      // Checksum: (0x84 + 0xF1 + 0x10 + 0x41 + 0x0C + 0x1F + 0x40) & 0xFF = 0x31
      final result = parseMarelliResponse('84 F1 10 41 0C 1F 40 31\r\n>');

      expect(result, isNotNull);
      expect(result!.dataBytes, [0x1F, 0x40]);
      expect(MarelliFormulas.rpm(result.dataBytes), 2000.0);
    });

    test('parseia resposta de tensao direta do ATRV', () {
      final result = parseMarelliResponse('12.6V\r\n>');

      expect(result, isNotNull);
      expect(MarelliFormulas.voltage(result!.dataBytes), closeTo(12.6, 0.1));
    });

    test('parseia resposta valida e extrai bytes de dados (legado)', () {
      // header 48 6B 10, modo+pid 61 01, dados 1F 40, checksum 84
      final result = parseMarelliResponse('48 6B 10 61 01 1F 40 84\r\n>');

      expect(result, isNotNull);
      expect(result!.dataBytes, [0x1F, 0x40]);
      expect(MarelliFormulas.rpm(result.dataBytes), 2000.0);
    });

    test('retorna null para checksum inválido', () {
      final result = parseMarelliResponse('48 6B 10 61 01 1F 40 FF\r\n>');
      expect(result, isNull);
    });

    test('retorna null para header inesperado', () {
      final result = parseMarelliResponse('00 00 10 61 01 1F 40 84\r\n>');
      expect(result, isNull);
    });

    test('retorna null para NO DATA', () {
      expect(parseMarelliResponse('NO DATA\r\n>'), isNull);
    });

    test('retorna null para resposta vazia', () {
      expect(parseMarelliResponse('\r\n>'), isNull);
    });
  });

  group('MarelliFormulas', () {
    test('temp converte byte único com offset -40', () {
      expect(MarelliFormulas.temp([90]), 50.0);
    });

    test('tps converte para percentual', () {
      expect(MarelliFormulas.tps([255]), 100.0);
    });

    test('lambda converte para faixa 0-2', () {
      expect(MarelliFormulas.lambda([128, 0]), closeTo(2.0, 0.001));
    });

    test('ignition converte com offset -64', () {
      expect(MarelliFormulas.ignition([128]), 0.0);
    });
  });
}
