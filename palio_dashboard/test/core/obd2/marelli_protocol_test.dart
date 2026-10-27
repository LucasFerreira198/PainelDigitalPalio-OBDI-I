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

    test('parseia resposta KWP2000 Fiat de temperatura (PID 05)', () {
      // 83 F1 10 41 05 82 (0x82 = 130 -> 130 - 40 = 90 °C)
      // Checksum: (0x83 + 0xF1 + 0x10 + 0x41 + 0x05 + 0x82) & 0xFF = 0x4C
      final result = parseMarelliResponse('83 F1 10 41 05 82 4C\r\n>');

      expect(result, isNotNull);
      expect(result!.dataBytes, [0x82]);
      expect(MarelliFormulas.temp(result.dataBytes), 90.0);
    });

    test('parseia resposta KWP2000 Fiat de MAP (PID 0B)', () {
      // 83 F1 10 41 0B 64 (0x64 = 100 kPa)
      // Checksum: (0x83 + 0xF1 + 0x10 + 0x41 + 0x0B + 0x64) & 0xFF = 0x34
      final result = parseMarelliResponse('83 F1 10 41 0B 64 34\r\n>');

      expect(result, isNotNull);
      expect(result!.dataBytes, [0x64]);
      expect(MarelliFormulas.map(result.dataBytes), 100.0);
    });

    test('parseia resposta KWP2000 Fiat de Velocidade (PID 0D)', () {
      // 83 F1 10 41 0D 50 (0x50 = 80 km/h)
      // Checksum: (0x83 + 0xF1 + 0x10 + 0x41 + 0x0D + 0x50) & 0xFF = 0x22
      final result = parseMarelliResponse('83 F1 10 41 0D 50 22\r\n>');

      expect(result, isNotNull);
      expect(result!.dataBytes, [0x50]);
      expect(MarelliFormulas.speed(result.dataBytes), 80.0);
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

    test('parseia resposta de modo padrão OBD2 sem header ELM', () {
      // Ex: 41 0C 1F 40
      final result = parseMarelliResponse('41 0C 1F 40\r\n>');

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

    test('retorna null para SEARCHING... ou BUS INIT', () {
      expect(parseMarelliResponse('SEARCHING...\r\n>'), isNull);
      expect(parseMarelliResponse('BUS INIT: ERROR\r\n>'), isNull);
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
      expect(MarelliFormulas.tps([0]), 0.0);
    });

    test('lambda converte para faixa 0-2', () {
      expect(MarelliFormulas.lambda([128, 0]), closeTo(2.0, 0.001));
    });

    test('ignition converte com offset -64', () {
      expect(MarelliFormulas.ignition([128]), 0.0);
      expect(MarelliFormulas.ignition([148]), 10.0);
    });

    test('map retorna valor exato em kPa', () {
      expect(MarelliFormulas.map([98]), 98.0);
    });

    test('speed retorna valor exato em km/h', () {
      expect(MarelliFormulas.speed([110]), 110.0);
    });
  });
}
