/// Comandos oficiais KWP2000 Fiat Marelli IAW 4AF para ler e limpar falhas.
const String kReadDtcsCommand = '18 00 FF 00';
const String kClearDtcsCommand = '14 FF 00';

/// Descrições resumidas dos códigos DTC mais comuns. Não é uma lista
/// exaustiva — qualquer código fora deste mapa é exibido sem descrição.
const Map<String, String> dtcDescriptions = {
  'P0100': 'Defeito no circuito do sensor de massa de ar (MAF)',
  'P0105': 'Defeito no circuito do sensor de pressão (MAP)',
  'P0110': 'Defeito no circuito do sensor de temp. do ar de admissão',
  'P0115': 'Defeito no circuito do sensor de temp. do motor',
  'P0130': 'Defeito no circuito da sonda lambda',
  'P0135': 'Defeito no aquecimento da sonda lambda',
  'P0171': 'Sistema muito pobre (mistura ar/combustível)',
  'P0172': 'Sistema muito rico (mistura ar/combustível)',
  'P0200': 'Defeito no circuito do injetor',
  'P0220': 'Defeito no circuito B do sensor de posição do acelerador (TPS)',
  'P0230': 'Defeito no circuito primário da bomba de combustível',
  'P0300': 'Falha de combustão detectada (randômica/múltiplos cilindros)',
  'P0301': 'Falha de combustão no cilindro 1',
  'P0302': 'Falha de combustão no cilindro 2',
  'P0303': 'Falha de combustão no cilindro 3',
  'P0304': 'Falha de combustão no cilindro 4',
  'P0335': 'Defeito no sensor de rotação (CKP)',
  'P0340': 'Defeito no sensor de fase (CMP)',
  'P0420': 'Eficiência do catalisador abaixo do limite',
  'P0500': 'Defeito no sensor de velocidade do veículo',
};

/// Decodifica pares de bytes em códigos DTC no formato padrão OBD-II
/// (ex.: "P0300"). Pares "0000" são ignorados (posição sem falha).
///
/// Formato por par de bytes [A, B]:
///   A bits 7-6: letra (00=P, 01=C, 10=B, 11=U)
///   A bits 5-4: primeiro dígito (0-3)
///   A bits 3-0: segundo dígito (hex)
///   B bits 7-4: terceiro dígito (hex)
///   B bits 3-0: quarto dígito (hex)
List<String> decodeDtcBytes(List<int> bytes) {
  const letters = ['P', 'C', 'B', 'U'];
  final codes = <String>[];

  for (var i = 0; i + 1 < bytes.length; i += 2) {
    final a = bytes[i];
    final b = bytes[i + 1];
    if (a == 0 && b == 0) continue;

    final letter = letters[(a >> 6) & 0x3];
    final firstDigit = (a >> 4) & 0x3;
    final secondDigit = a & 0xF;
    final thirdDigit = (b >> 4) & 0xF;
    final fourthDigit = b & 0xF;

    final code = '$letter$firstDigit'
        '${secondDigit.toRadixString(16)}'
        '${thirdDigit.toRadixString(16)}'
        '${fourthDigit.toRadixString(16)}'
        .toUpperCase();
    codes.add(code);
  }

  return codes;
}

String describeDtc(String code) =>
    dtcDescriptions[code] ?? 'Descrição não disponível';
