import 'package:flutter_test/flutter_test.dart';
import 'package:palio_dashboard/core/obd2/standard_obd2_pid_definitions.dart';
import 'package:palio_dashboard/core/obd2/standard_obd2_protocol.dart';

void main() {
  group('parseStandardObd2Response', () {
    test('parseia resposta válida sem header (ATH0)', () {
      final result = parseStandardObd2Response(
        '41 0C 1F 40\r\n>',
        expectedPid: 0x0C,
      );

      expect(result, isNotNull);
      expect(result!.dataBytes, [0x1F, 0x40]);
      expect(StandardObd2Formulas.rpm(result.dataBytes), 2000.0);
    });

    test('encontra o par 41+PID mesmo com header espúrio na frente', () {
      // Simula um adaptador que ignora ATH0 e manda cabeçalho mesmo assim
      // (formato K-line de byte único, não CAN — esse carro não usa CAN).
      final result = parseStandardObd2Response(
        '48 6B 11 41 0C 1F 40\r\n>',
        expectedPid: 0x0C,
      );

      expect(result, isNotNull);
      expect(result!.dataBytes, [0x1F, 0x40]);
    });

    test('retorna null para NO DATA', () {
      expect(
        parseStandardObd2Response('NO DATA\r\n>', expectedPid: 0x0C),
        isNull,
      );
    });

    test('retorna null para ERROR', () {
      expect(
        parseStandardObd2Response('ERROR\r\n>', expectedPid: 0x0C),
        isNull,
      );
    });

    test('retorna null para resposta vazia', () {
      expect(parseStandardObd2Response('\r\n>', expectedPid: 0x0C), isNull);
    });

    test('retorna null quando o PID ecoado não é o esperado', () {
      final result = parseStandardObd2Response(
        '41 0D 50\r\n>',
        expectedPid: 0x0C,
      );
      expect(result, isNull);
    });

    test('retorna null quando não há bytes de dados após o par 41+PID', () {
      final result = parseStandardObd2Response('41 0C\r\n>', expectedPid: 0x0C);
      expect(result, isNull);
    });

    test('parseia resposta ATRV para bateria', () {
      final result = parseStandardObd2Response('12.6V\r\n>', expectedPid: 0x00);
      expect(result, isNotNull);
      expect(StandardObd2Formulas.voltage(result!.dataBytes), closeTo(12.6, 0.1));
    });

    test('parseia resposta de combustivel (PID 2F)', () {
      final result = parseStandardObd2Response('41 2F 80\r\n>', expectedPid: 0x2F);
      expect(result, isNotNull);
      expect(StandardObd2Formulas.fuelLevel(result!.dataBytes), closeTo(50.2, 0.1));
    });
  });

  group('StandardObd2Formulas', () {
    test('rpm converte dois bytes', () {
      expect(StandardObd2Formulas.rpm([0x1F, 0x40]), 2000.0);
    });

    test('speed retorna o byte direto', () {
      expect(StandardObd2Formulas.speed([80]), 80.0);
    });

    test('temp converte byte único com offset -40', () {
      expect(StandardObd2Formulas.temp([130]), 90.0);
    });

    test('map retorna o byte direto em kPa', () {
      expect(StandardObd2Formulas.map([95]), 95.0);
    });

    test('tps converte para percentual 0 a 100', () {
      expect(StandardObd2Formulas.tps([0]), 0.0);
      expect(StandardObd2Formulas.tps([255]), 100.0);
    });

    test('fuelLevel converte para percentual 0 a 100', () {
      expect(StandardObd2Formulas.fuelLevel([0]), 0.0);
      expect(StandardObd2Formulas.fuelLevel([255]), 100.0);
      expect(StandardObd2Formulas.fuelLevel([128]), closeTo(50.19, 0.05));
    });

    test('advance converte com offset -64', () {
      expect(StandardObd2Formulas.advance([128]), 0.0);
      expect(StandardObd2Formulas.advance([148]), 10.0);
    });
  });

  group('StandardObd2Pid loop & handshake configuration', () {
    test('ecuHandshakePids não contém batteryVoltage', () {
      expect(StandardObd2Pid.ecuHandshakePids.contains(StandardObd2Pid.batteryVoltage), isFalse);
      expect(StandardObd2Pid.ecuHandshakePids.contains(StandardObd2Pid.rpm), isTrue);
    });

    test('dashboardLoop contém monitoramento de combustível e sensores essenciais', () {
      expect(StandardObd2Pid.dashboardLoop.contains(StandardObd2Pid.rpm), isTrue);
      expect(StandardObd2Pid.dashboardLoop.contains(StandardObd2Pid.fuelLevel), isTrue);
      expect(StandardObd2Pid.dashboardLoop.contains(StandardObd2Pid.map), isTrue);
      expect(StandardObd2Pid.dashboardLoop.contains(StandardObd2Pid.tps), isTrue);
    });
  });
}
