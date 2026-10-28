import 'package:flutter_test/flutter_test.dart';
import 'package:palio_dashboard/core/obd2/marelli_protocol.dart';
import 'package:palio_dashboard/core/obd2/pid_definitions.dart';

void main() {
  group('parseMarelliResponse', () {
    test('parseia resposta KWP2000 Fiat Marelli Service 21 RPM (21 30) - Caso Real AlfaOBD 866 RPM', () {
      // 84 F1 10 61 30 03 62 (dados 03 62 = 866 -> 866.0 RPM direto no protocolo KWP Marelli IAW 4AF)
      // Checksum: (0x84 + 0xF1 + 0x10 + 0x61 + 0x30 + 0x03 + 0x62) & 0xFF = 0x85
      final result = parseMarelliResponse('84 F1 10 61 30 03 62 85\r\n>');

      expect(result, isNotNull);
      expect(result!.dataBytes, [0x03, 0x62]);
      expect(MarelliFormulas.rpm(result.dataBytes), 866.0);
    });

    test('parseia resposta KWP2000 Fiat Marelli Service 21 Temperatura (21 33) 85 °C (1 byte)', () {
      // 83 F1 10 61 33 7D (dados 0x7D = 125 -> 125 - 40 = 85 °C)
      // Checksum: (0x83 + 0xF1 + 0x10 + 0x61 + 0x33 + 0x7D) & 0xFF = 0x95
      final result = parseMarelliResponse('83 F1 10 61 33 7D 95\r\n>');

      expect(result, isNotNull);
      expect(result!.dataBytes, [0x7D]);
      expect(MarelliFormulas.temp(result.dataBytes), 85.0);
    });

    test('parseia resposta KWP2000 Fiat Marelli Service 21 Temperatura (21 33) 85 °C (2 bytes com MSB=0)', () {
      // 84 F1 10 61 33 00 7D (dados 00 7D -> 125 - 40 = 85 °C, previne o bug de -40°C)
      // Checksum: (0x84 + 0xF1 + 0x10 + 0x61 + 0x33 + 0x00 + 0x7D) & 0xFF = 0x96
      final result = parseMarelliResponse('84 F1 10 61 33 00 7D 96\r\n>');

      expect(result, isNotNull);
      expect(result!.dataBytes, [0x00, 0x7D]);
      expect(MarelliFormulas.temp(result.dataBytes), 85.0);
    });

    test('parseia resposta KWP2000 Fiat Marelli Service 21 Velocidade (21 53) 45 km/h', () {
      // 83 F1 10 61 53 2D (dados 0x2D = 45 km/h)
      // Checksum: (0x83 + 0xF1 + 0x10 + 0x61 + 0x53 + 0x2D) & 0xFF = 0x65
      final result = parseMarelliResponse('83 F1 10 61 53 2D 65\r\n>');

      expect(result, isNotNull);
      expect(result!.dataBytes, [0x2D]);
      expect(MarelliFormulas.speed(result.dataBytes), 45.0);
    });

    test('parseia resposta KWP2000 Fiat Marelli Service 21 MAP (21 31) 360 mbar / 36 kPa', () {
      // 84 F1 10 61 31 01 68 (dados 01 68 = 360 mbar -> 36.0 kPa)
      // Checksum: (0x84 + 0xF1 + 0x10 + 0x61 + 0x31 + 0x01 + 0x68) & 0xFF = 0x80
      final result = parseMarelliResponse('84 F1 10 61 31 01 68 80\r\n>');

      expect(result, isNotNull);
      expect(result!.dataBytes, [0x01, 0x68]);
      expect(MarelliFormulas.map(result.dataBytes), 36.0);
    });

    test('parseia resposta KWP2000 Fiat Marelli Service 21 TPS (21 34)', () {
      // 83 F1 10 61 34 19 (dados 0x19 = 25 -> 25 * 100 / 255 = 9.8%)
      // Checksum: (0x83 + 0xF1 + 0x10 + 0x61 + 0x34 + 0x19) & 0xFF = 0x32
      final result = parseMarelliResponse('83 F1 10 61 34 19 32\r\n>');

      expect(result, isNotNull);
      expect(result!.dataBytes, [0x19]);
      expect(MarelliFormulas.tps(result.dataBytes), closeTo(9.8, 0.1));
    });

    test('rejeita resposta negativa 7F 01 11 (serviceNotSupported da ECU IAW 4AF)', () {
      // 83 F1 10 7F 01 11 15 (exatamente a resposta do Palio Fire ao comando 01 0C)
      expect(parseMarelliResponse('83 F1 10 7F 01 11 15\r\n>'), isNull);
      expect(parseMarelliResponse('83F1107F011115>'), isNull);
    });

    test('parseia resposta KWP2000 Fiat com header 84 F1 10 41 0C (Modo 01 fallback)', () {
      // 84 F1 10 41 0C 07 D0 (dados 07 D0 = 2000 RPM)
      // Checksum: (0x84 + 0xF1 + 0x10 + 0x41 + 0x0C + 0x07 + 0xD0) & 0xFF = 0x49
      final result = parseMarelliResponse('84 F1 10 41 0C 07 D0 49\r\n>');

      expect(result, isNotNull);
      expect(result!.dataBytes, [0x07, 0xD0]);
      expect(MarelliFormulas.rpm(result.dataBytes), 2000.0);
    });

    test('parseia resposta de tensao direta do ATRV', () {
      final result = parseMarelliResponse('12.6V\r\n>');

      expect(result, isNotNull);
      expect(MarelliFormulas.voltage(result!.dataBytes), closeTo(12.6, 0.1));
    });

    test('parseia resposta sem headers (ATH0) 61 30 03 6C', () {
      final result = parseMarelliResponse('61 30 03 6C\r\n>');

      expect(result, isNotNull);
      expect(result!.dataBytes, [0x03, 0x6C]);
      expect(MarelliFormulas.rpm(result.dataBytes), 876.0);
    });

    test('parseia resposta de despertar KWP2000 Marelli 1A 97 (5A 97 com header)', () {
      // 84 F1 10 5A 97 01 02 (CS: (0x84 + 0xF1 + 0x10 + 0x5A + 0x97 + 0x01 + 0x02) & 0xFF = 0x79)
      final result = parseMarelliResponse('84 F1 10 5A 97 01 02 79\r\n>');

      expect(result, isNotNull);
      expect(result!.dataBytes, [0x01, 0x02]);
    });

    test('retorna null para checksum inválido quando header formato desconhecido', () {
      final result = parseMarelliResponse('48 6B 10 61 01 1F 40 FF\r\n>');
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
    test('rpm converte 16-bit com slope 1.0 direto do KWP2000 Marelli (Casos reais Palio Fire)', () {
      // Marcha lenta real do Palio Fire (foto 9915): 876 RPM (antes mostrava erroneamente 219)
      expect(MarelliFormulas.rpm([0x03, 0x6C]), 876.0);
      // Aceleração real do Palio Fire (foto 9909): 1076 RPM (antes mostrava erroneamente 269)
      expect(MarelliFormulas.rpm([0x04, 0x34]), 1076.0);
      // Rotação alta: 2500 RPM
      expect(MarelliFormulas.rpm([0x09, 0xC4]), 2500.0);
    });

    test('temp converte byte único com offset -40 e payload de 16-bit com MSB=0', () {
      expect(MarelliFormulas.temp([90]), 50.0);
      expect(MarelliFormulas.temp([125]), 85.0);
      // Caso 2-byte MSB=0 (evita -40°C quando ECU responde com 2 bytes)
      expect(MarelliFormulas.temp([0x00, 125]), 85.0);
      expect(MarelliFormulas.temp([0x00, 90]), 50.0);
      // Caso 16-bit com escala 1/32°C (4000/32 - 40 = 85°C)
      expect(MarelliFormulas.temp([0x0F, 0xA0]), 85.0);
    });

    test('speed retorna valor em km/h tanto para 1 byte quanto para 2 bytes com MSB=0', () {
      expect(MarelliFormulas.speed([45]), 45.0);
      expect(MarelliFormulas.speed([0x00, 45]), 45.0);
    });

    test('map converte mbar para kPa quando > 255', () {
      expect(MarelliFormulas.map([0x01, 0x68]), 36.0); // 360 mbar -> 36.0 kPa
      expect(MarelliFormulas.map([98]), 98.0);
    });

    test('tps converte para percentual', () {
      expect(MarelliFormulas.tps([255]), 100.0);
      expect(MarelliFormulas.tps([0]), 0.0);
    });

    test('voltage converte para Volts', () {
      expect(MarelliFormulas.voltage([126]), 12.6);
    });
  });

  group('MarelliPid comandos oficiais AlfaOBD IAW 4AF', () {
    test('comandos configurados para Service 21 proprietário Marelli', () {
      expect(MarelliPid.rpm.command, '21 30');
      expect(MarelliPid.speed.command, '21 53');
      expect(MarelliPid.coolantTemp.command, '21 33');
      expect(MarelliPid.intakeTemp.command, '21 32');
      expect(MarelliPid.map.command, '21 31');
      expect(MarelliPid.tps.command, '21 34');
      expect(MarelliPid.batteryVoltage.command, 'ATRV');
    });

    test('ecuHandshakePids contém rpm e coolantTemp via Service 21', () {
      expect(MarelliPid.ecuHandshakePids.contains(MarelliPid.batteryVoltage), isFalse);
      expect(MarelliPid.ecuHandshakePids.contains(MarelliPid.rpm), isTrue);
    });

    test('dashboardLoop contém monitoramento ágil de sensores essenciais', () {
      expect(MarelliPid.dashboardLoop.contains(MarelliPid.rpm), isTrue);
      expect(MarelliPid.dashboardLoop.contains(MarelliPid.speed), isTrue);
      expect(MarelliPid.dashboardLoop.contains(MarelliPid.coolantTemp), isTrue);
      expect(MarelliPid.dashboardLoop.contains(MarelliPid.map), isTrue);
      expect(MarelliPid.dashboardLoop.contains(MarelliPid.tps), isTrue);
      expect(MarelliPid.dashboardLoop.contains(MarelliPid.batteryVoltage), isTrue);
    });
  });
}
