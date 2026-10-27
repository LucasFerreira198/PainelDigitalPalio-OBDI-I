/// Fórmulas de conversão dos PIDs OBD-II padrão (SAE J1979, modo $01) —
/// idênticas em qualquer carro do mundo que suporte o modo, ao contrário
/// das fórmulas proprietárias Fiat/Marelli (MarelliFormulas).
class StandardObd2Formulas {
  StandardObd2Formulas._();

  static double rpm(List<int> bytes) => (bytes[0] * 256 + bytes[1]) / 4;

  static double speed(List<int> bytes) => bytes[0].toDouble();

  static double temp(List<int> bytes) => (bytes[0] - 40).toDouble();

  static double map(List<int> bytes) => bytes[0].toDouble();

  static double tps(List<int> bytes) => bytes[0] * 100.0 / 255.0;

  static double fuelLevel(List<int> bytes) => (bytes[0] * 100.0) / 255.0;

  static double advance(List<int> bytes) => (bytes[0] / 2.0) - 64.0;

  static double voltage(List<int> bytes) => bytes[0] / 10.0;
}

/// PIDs OBD-II padrão (modo $01) usados como primeira camada de tentativa
/// de conexão com a ECU — mais simples e confiável que o protocolo
/// proprietário Marelli quando o veículo suporta (ex.: carros brasileiros
/// no mandato OBDBr-1, lançamentos 2007-2009 em diante).
enum StandardObd2Pid {
  rpm(
    command: '01 0C',
    pidByte: 0x0C,
    label: 'RPM',
    unit: 'rpm',
    min: 0,
    max: 8000,
    formula: StandardObd2Formulas.rpm,
  ),
  speed(
    command: '01 0D',
    pidByte: 0x0D,
    label: 'Velocidade',
    unit: 'km/h',
    min: 0,
    max: 260,
    formula: StandardObd2Formulas.speed,
  ),
  coolantTemp(
    command: '01 05',
    pidByte: 0x05,
    label: 'Temp. motor',
    unit: '°C',
    min: -40,
    max: 150,
    formula: StandardObd2Formulas.temp,
  ),
  map(
    command: '01 0B',
    pidByte: 0x0B,
    label: 'MAP',
    unit: 'kPa',
    min: 0,
    max: 255,
    formula: StandardObd2Formulas.map,
  ),
  tps(
    command: '01 11',
    pidByte: 0x11,
    label: 'TPS',
    unit: '%',
    min: 0,
    max: 100,
    formula: StandardObd2Formulas.tps,
  ),
  fuelLevel(
    command: '01 2F',
    pidByte: 0x2F,
    label: 'Combustível',
    unit: '%',
    min: 0,
    max: 100,
    formula: StandardObd2Formulas.fuelLevel,
  ),
  intakeTemp(
    command: '01 0F',
    pidByte: 0x0F,
    label: 'Temp. admissão',
    unit: '°C',
    min: -40,
    max: 120,
    formula: StandardObd2Formulas.temp,
  ),
  ignitionAdvance(
    command: '01 0E',
    pidByte: 0x0E,
    label: 'Avanço ignição',
    unit: '°',
    min: -64,
    max: 64,
    formula: StandardObd2Formulas.advance,
  ),
  batteryVoltage(
    command: 'ATRV',
    pidByte: 0x00,
    label: 'Bateria',
    unit: 'V',
    min: 0,
    max: 20,
    formula: StandardObd2Formulas.voltage,
  );

  const StandardObd2Pid({
    required this.command,
    required this.pidByte,
    required this.label,
    required this.unit,
    required this.min,
    required this.max,
    required this.formula,
  });

  final String command;
  final int pidByte;
  final String label;
  final String unit;
  final double min;
  final double max;
  final double Function(List<int> bytes) formula;

  /// PIDs lidos no loop principal do dashboard quando conectado via OBD-II padrão.
  static const List<StandardObd2Pid> dashboardLoop = [
    rpm,
    speed,
    coolantTemp,
    map,
    tps,
    fuelLevel,
    intakeTemp,
    ignitionAdvance,
    batteryVoltage,
  ];

  /// PIDs reais para validação de comunicação com a ECU (exclui ATRV).
  static const List<StandardObd2Pid> ecuHandshakePids = [
    rpm,
    speed,
    coolantTemp,
    map,
  ];
}
