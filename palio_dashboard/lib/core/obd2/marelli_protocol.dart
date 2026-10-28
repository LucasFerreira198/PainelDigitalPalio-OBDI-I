/// Fórmulas de conversão dos PIDs proprietários Fiat/Marelli.
/// Fatores baseados em engenharia reversa documentada pela comunidade
/// (FiatECUScan/MultiECUScan) — precisam ser validados no carro real.
class MarelliFormulas {
  MarelliFormulas._();

  static double rpm(List<int> bytes) => (bytes[0] * 256 + bytes[1]) / 4;

  static double speed(List<int> bytes) => bytes[0].toDouble();

  static double temp(List<int> bytes) => (bytes[0] - 40).toDouble();

  static double map(List<int> bytes) => bytes[0].toDouble();

  static double tps(List<int> bytes) => bytes[0] * 100 / 255;

  static double lambda(List<int> bytes) =>
      (bytes[0] * 256 + bytes[1]) / 32768 * 2;

  static double injection(List<int> bytes) =>
      (bytes[0] * 256 + bytes[1]) / 1000;

  static double ignition(List<int> bytes) => bytes[0] / 2 - 64;

  static double voltage(List<int> bytes) => bytes[0] / 10;

  /// Nível de combustível do tanque em porcentagem (0 a 100%).
  /// Fórmula padrão SAE J1979 PID 0x2F (A * 100 / 255).
  static double fuelLevel(List<int> bytes) => (bytes[0] * 100.0) / 255.0;
}

/// Comandos AT que configuram apenas o chip ELM327 em si — não dependem da
/// ECU do carro estar ligada/respondendo. Baseados na sequência exata
/// extraída via engenharia reversa do AlfaOBD para veículos Fiat Palio.
///
/// Números de protocolo do ELM327:
///   ATSP3 = ISO 9141-2 (5-baud init)
///   ATSP4 = ISO 14230-4 KWP2000 (5-baud init)
///   ATSP5 = ISO 14230-4 KWP2000 (fast init) — protocolo nativo do Palio Fire!
const List<String> kElm327SetupIso9141 = [
  'ATZ',
  'ATE0',
  'ATL0',
  'ATS0',
  'ATAT0',
  'ATSP3',
  'ATIB48',
  'ATH1',
  'ATSH8210F1',
  'ATIIA10',
  'ATST96',
];

const List<String> kElm327SetupKwp2000SlowInit = [
  'ATZ',
  'ATE0',
  'ATL0',
  'ATS0',
  'ATAT0',
  'ATSP4',
  'ATIB10',
  'ATH1',
  'ATSH8210F1',
  'ATIIA10',
  'ATST96',
];

/// Sequência de inicialização para o Palio Fire (Marelli IAW 4AF / 4EF / 59F / 5AF)
/// extraída do AlfaOBD (opção "Marelli IAW 4AF/4EF/59F/5AF EOBD"):
/// - ATSP5: Fast Init ISO 14230-4 KWP
/// - ATIB10: Baudrate 10400 bps (crítico para handshake Marelli)
/// - ATH1: Headers ativados para validação de origem da ECU (10 = Marelli)
/// - ATSH8210F1: Header KWP físico (82 = formato físico para 2 bytes de dados como 01 0C, 21 01, 1A 97; 10 = ECU Motor; F1 = Scanner)
const List<String> kElm327SetupKwp2000FastInit = [
  'ATZ',
  'ATE0',
  'ATL0',
  'ATS0',
  'ATAT0',
  'ATSP5',
  'ATIB10',
  'ATH1',
  'ATSH8210F1',
  'ATST96',
];

/// ATZ reinicia o microcontrolador do ELM327 — no hardware real isso demora
/// bem mais que os outros comandos AT (até ~2s em adaptadores genéricos).
const Duration kAtzTimeout = Duration(seconds: 3);

/// true se [raw] contém alguma mensagem de erro textual do ELM327 — usado
/// tanto para validar respostas de PID quanto a resposta do ATSI (que pode
/// "responder" rapidamente com texto de erro em vez de dar timeout quando a
/// ECU está desligada/não conectada).
bool isElmFailureResponse(String raw) {
  final upper = raw.toUpperCase();
  return upper.contains('NO DATA') ||
      upper.contains('ERROR') ||
      upper.contains('UNABLE TO CONNECT') ||
      upper.contains('STOPPED') ||
      upper.contains('BUS BUSY') ||
      upper.contains('FB ERROR') ||
      upper.contains('DATA ERROR') ||
      upper.contains('7F ') ||
      upper.contains('?');
}

/// Resultado do parsing de uma resposta da ECU (KWP2000 ou ISO 9141) do ELM327.
class MarelliParseResult {
  final List<int> dataBytes;

  const MarelliParseResult(this.dataBytes);
}

/// Parseia a resposta do ELM327 para leituras do Fiat Palio:
/// Suporta os 3 formatos retornados por adaptadores em veículos Fiat:
/// 1. Resposta KWP2000 física Fiat (AlfaOBD):
///    "8X F1 10 41/61 <PID> <DADOS...> <CS>\r\n>"
///    8X = Formato (0x80 + comprimento), F1 = Destino (Scanner), 10 = Origem (ECU Marelli)
/// 2. Resposta legada ISO 9141 funcional:
///    "48 6B 10 41/61 <PID> <DADOS...> <CS>\r\n>"
/// 3. Resposta direta do comando ATRV para tensão de bateria:
///    "12.6V\r\n>"
/// 4. Resposta sem cabeçalho (se o adaptador omitir headers):
///    "41/61 <PID> <DADOS...>\r\n>"
MarelliParseResult? parseMarelliResponse(String raw) {
  final cleaned = raw.replaceAll('>', '').trim();
  if (cleaned.isEmpty) return null;
  if (isElmFailureResponse(cleaned)) return null;

  // Caso especial: leitura de tensão direta da bateria via comando ATRV (ex: "12.8V")
  final vMatch = RegExp(r'(\d+\.?\d*)\s*V', caseSensitive: false).firstMatch(cleaned);
  if (vMatch != null && !cleaned.contains('41') && !cleaned.contains('61')) {
    final vVal = double.tryParse(vMatch.group(1)!);
    if (vVal != null) {
      return MarelliParseResult([(vVal * 10).round()]);
    }
  }

  final tokens = cleaned.toUpperCase()
      .split(RegExp(r'[\s\r\n]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return null;

  final bytes = <int>[];
  for (final token in tokens) {
    if (token.length > 2 && token.length % 2 == 0) {
      for (var i = 0; i < token.length; i += 2) {
        final val = int.tryParse(token.substring(i, i + 2), radix: 16);
        if (val != null) bytes.add(val);
      }
    } else {
      final value = int.tryParse(token, radix: 16);
      if (value != null && value >= 0 && value <= 0xFF) {
        bytes.add(value);
      }
    }
  }
  if (bytes.isEmpty) return null;

  // 1. Resposta KWP2000 Fiat com cabeçalho ATH1 em qualquer posição dos bytes
  // Procura padrão [FMT] [0xF1] [0x10] [41|61|5A] para ser imune a ecos ou lixo anterior
  for (var i = 1; i <= bytes.length - 4; i++) {
    if (bytes[i] == 0xF1 && bytes[i + 1] == 0x10) {
      final sResp = bytes[i + 2];
      if (sResp == 0x41 || sResp == 0x61 || sResp == 0x5A) {
        final headerStart = i - 1;
        final checksum = bytes.last;
        final computed = bytes
                .sublist(headerStart, bytes.length - 1)
                .fold<int>(0, (sum, b) => sum + b) &
            0xFF;
        if (computed == checksum) {
          final dataBytes = bytes.sublist(i + 4, bytes.length - 1);
          if (dataBytes.isNotEmpty) {
            return MarelliParseResult(dataBytes);
          }
          if (i + 3 < bytes.length - 1) {
            return MarelliParseResult([bytes[i + 3]]);
          }
        }
        // Se clone do ELM327 omitiu o byte de checksum:
        final expectedPayloadLen = bytes[headerStart] & 0x3F;
        if (expectedPayloadLen > 0 &&
            (bytes.length - headerStart - 3) == expectedPayloadLen) {
          final dataBytes = bytes.sublist(i + 4);
          if (dataBytes.isNotEmpty) {
            return MarelliParseResult(dataBytes);
          }
          if (i + 3 < bytes.length) {
            return MarelliParseResult([bytes[i + 3]]);
          }
        }
      }
    }
  }

  // 2. Resposta legada ISO 9141 funcional (48 6B 10 ...)
  for (var i = 0; i <= bytes.length - 6; i++) {
    if (bytes[i] == 0x48 && bytes[i + 1] == 0x6B && bytes[i + 2] == 0x10) {
      final checksum = bytes.last;
      final computed = bytes
              .sublist(i, bytes.length - 1)
              .fold<int>(0, (sum, b) => sum + b) &
          0xFF;
      if (computed == checksum) {
        final dataBytes = bytes.sublist(i + 5, bytes.length - 1);
        if (dataBytes.isNotEmpty) {
          return MarelliParseResult(dataBytes);
        }
      }
    }
  }

  // 3. Resposta padrão OBD2 sem cabeçalhos (41 <PID> <DADOS...> ou 61 <ID> <DADOS...> ou 5A <ID> <DADOS...>)
  for (var i = 0; i <= bytes.length - 2; i++) {
    if (bytes[i] == 0x41 || bytes[i] == 0x61 || bytes[i] == 0x5A) {
      final dataBytes = bytes.sublist(i + 2);
      if (dataBytes.isNotEmpty) {
        return MarelliParseResult(dataBytes);
      }
      return MarelliParseResult([bytes[i + 1]]);
    }
  }

  return null;
}
