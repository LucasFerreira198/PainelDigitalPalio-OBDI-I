/// Fórmulas de conversão dos PIDs proprietários Fiat/Marelli.
/// Fatores baseados em engenharia reversa documentada pela comunidade
/// (AlfaOBD / MultiECUScan / FiatECUScan) para ECUs Magneti Marelli IAW 4AF / 4EF / 59F / 5AF.
class MarelliFormulas {
  MarelliFormulas._();

  /// Rotação do motor (RPM): Service 21 Local ID 0x30.
  /// No protocolo KWP2000 Marelli IAW 4AF, o payload de 16-bit já entrega o valor
  /// real diretamente em RPM (slope 1.0, 1 RPM por bit).
  static double rpm(List<int> bytes) {
    if (bytes.length >= 2) {
      return (bytes[0] * 256 + bytes[1]).toDouble();
    }
    return 0.0;
  }

  /// Velocidade do veículo (km/h): Service 21 Local ID 0x53.
  /// Payload de 8-bit com slope 1.0 (ou byte único).
  static double speed(List<int> bytes) {
    if (bytes.length >= 2 && bytes[0] == 0) {
      return bytes[1].toDouble();
    }
    if (bytes.isNotEmpty) {
      return bytes[0].toDouble();
    }
    return 0.0;
  }

  /// Temperatura do líquido de arrefecimento (°C): Service 21 Local ID 0x33.
  /// Trata payloads de 16-bit (MSB=0 com dado em LSB) e 8-bit com offset -40.
  static double temp(List<int> bytes) {
    if (bytes.length >= 2) {
      // Se bytes[0] for 0, o byte significativo de temperatura é bytes[1]
      if (bytes[0] == 0) {
        final val = bytes[1];
        return val >= 40 ? (val - 40).toDouble() : val.toDouble();
      }
      final raw16 = bytes[0] * 256 + bytes[1];
      // Se formato KWP 16-bit com escala 1/32°C (comum em ECUs Marelli)
      if (raw16 > 500) {
        final t32 = (raw16 / 32.0) - 40.0;
        if (t32 >= -40 && t32 <= 150) return t32;
      }
      // Se formato com escala 0.1°C
      final t10 = (raw16 * 0.1) - 40.0;
      if (t10 >= -40 && t10 <= 150) return t10;
      return (bytes[1] - 40).toDouble();
    }
    if (bytes.isNotEmpty) {
      final val = bytes[0];
      return val >= 40 ? (val - 40).toDouble() : val.toDouble();
    }
    return 0.0;
  }

  /// Pressão absoluta no coletor (MAP): Service 21 Local ID 0x31.
  /// Retornado em mbar (16-bit); convertido para kPa se > 255.
  static double map(List<int> bytes) {
    if (bytes.length >= 2) {
      final mbar = bytes[0] * 256 + bytes[1];
      return mbar > 255 ? mbar / 10.0 : mbar.toDouble();
    }
    if (bytes.isNotEmpty) {
      return bytes[0].toDouble();
    }
    return 0.0;
  }

  /// Posição da borboleta de aceleração (TPS, %): Service 21 Local ID 0x34.
  /// Payload de 8-bit (0 a 255 -> 0% a 100%).
  static double tps(List<int> bytes) {
    if (bytes.isNotEmpty) {
      return (bytes[0] * 100.0) / 255.0;
    }
    return 0.0;
  }

  static double lambda(List<int> bytes) {
    if (bytes.length >= 2) {
      return (bytes[0] * 256 + bytes[1]) / 32768.0 * 2.0;
    }
    return 1.0;
  }

  static double injection(List<int> bytes) {
    if (bytes.length >= 2) {
      return (bytes[0] * 256 + bytes[1]) / 1000.0;
    }
    return 0.0;
  }

  static double ignition(List<int> bytes) {
    if (bytes.isNotEmpty) {
      return bytes[0] / 2.0 - 64.0;
    }
    return 0.0;
  }

  static double voltage(List<int> bytes) {
    if (bytes.isNotEmpty) {
      return bytes[0] / 10.0;
    }
    return 0.0;
  }

  /// Nível de combustível do tanque em porcentagem (0 a 100%).
  /// Fórmula padrão SAE J1979 PID 0x2F (A * 100 / 255).
  static double fuelLevel(List<int> bytes) {
    if (bytes.isNotEmpty) {
      return (bytes[0] * 100.0) / 255.0;
    }
    return 0.0;
  }
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
  if (upper.contains('NO DATA') ||
      upper.contains('ERROR') ||
      upper.contains('UNABLE TO CONNECT') ||
      upper.contains('STOPPED') ||
      upper.contains('BUS BUSY') ||
      upper.contains('FB ERROR') ||
      upper.contains('DATA ERROR') ||
      upper.contains('?') ||
      upper.contains('7F ') ||
      upper.contains('7F01') ||
      upper.contains('7F21') ||
      upper.contains('7F1A') ||
      upper.contains('107F')) {
    return true;
  }
  return false;
}

/// Resultado do parsing de uma resposta da ECU (KWP2000 ou ISO 9141) do ELM327.
class MarelliParseResult {
  final List<int> dataBytes;

  const MarelliParseResult(this.dataBytes);
}

/// Parseia a resposta do ELM327 para leituras do Fiat Palio:
/// Suporta os 3 formatos retornados por adaptadores em veículos Fiat:
/// 1. Resposta KWP2000 física Fiat (AlfaOBD):
///    "8X F1 10 41/61 <PID/LOCAL_ID> <DADOS...> <CS>\r\n>"
///    8X = Formato (0x80 + comprimento), F1 = Destino (Scanner), 10 = Origem (ECU Marelli)
/// 2. Resposta legada ISO 9141 funcional:
///    "48 6B 10 41/61 <PID> <DADOS...> <CS>\r\n>"
/// 3. Resposta direta do comando ATRV para tensão de bateria:
///    "12.6V\r\n>"
/// 4. Resposta sem cabeçalho (se o adaptador omitir headers):
///    "41/61 <PID/LOCAL_ID> <DADOS...>\r\n>"
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
  // Procura padrão [FMT] [0xF1] [0x10] [41|61|5A|7F] para ser imune a ecos ou lixo anterior
  for (var i = 1; i <= bytes.length - 4; i++) {
    if (bytes[i] == 0xF1 && bytes[i + 1] == 0x10) {
      final sResp = bytes[i + 2];
      if (sResp == 0x7F) {
        // Resposta negativa ISO 14230 (ex: 83 F1 10 7F 01 11 15)
        return null;
      }
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
        // Se clone do ELM327 omitiu ou divergiu no byte de checksum:
        final expectedPayloadLen = bytes[headerStart] & 0x3F;
        if (expectedPayloadLen >= 2) {
          final dataStart = i + 4; // pula FMT, F1, 10, SID, LOCAL_ID/PID
          final dataEnd = headerStart + 3 + expectedPayloadLen;
          if (dataStart <= dataEnd && dataEnd <= bytes.length) {
            final dataBytes = bytes.sublist(dataStart, dataEnd);
            if (dataBytes.isNotEmpty) {
              return MarelliParseResult(dataBytes);
            }
          }
        }
      }
    }
  }

  // 2. Resposta legada ISO 9141 funcional (48 6B 10 ...)
  for (var i = 0; i <= bytes.length - 6; i++) {
    if (bytes[i] == 0x48 && bytes[i + 1] == 0x6B && bytes[i + 2] == 0x10) {
      if (bytes[i + 3] == 0x7F) return null;
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

  // 3. Resposta com cabeçalho de 3 bytes para ECU Marelli (xx xx 10 41/5A/61...), mas header desconhecido ou checksum inválido
  if (bytes.length >= 5 &&
      bytes[2] == 0x10 &&
      (bytes[3] == 0x41 || bytes[3] == 0x61 || bytes[3] == 0x5A || bytes[3] == 0x7F)) {
    return null;
  }

  // 4. Resposta padrão OBD2 sem cabeçalhos (41 <PID> <DADOS...> ou 61 <ID> <DADOS...> ou 5A <ID> <DADOS...>)
  for (var i = 0; i <= bytes.length - 2; i++) {
    if (bytes[i] == 0x7F) return null;
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
