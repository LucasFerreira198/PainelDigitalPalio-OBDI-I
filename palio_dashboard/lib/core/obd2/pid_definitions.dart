import 'marelli_protocol.dart';

/// PIDs de monitoramento para o Fiat Palio (Marelli IAW 4AF / 4SF / 59F / 4GF).
/// Com o ELM327 configurado via ATSH 81 10 F1 (padrão AlfaOBD), o adaptador
/// empacota o header KWP2000 e calcula o checksum automaticamente.
enum MarelliPid {
  rpm(
    command: '01 0C',
    label: 'RPM',
    unit: 'rpm',
    min: 0,
    max: 8000,
    formula: MarelliFormulas.rpm,
  ),
  speed(
    command: '01 0D',
    label: 'Velocidade',
    unit: 'km/h',
    min: 0,
    max: 260,
    formula: MarelliFormulas.speed,
  ),
  coolantTemp(
    command: '01 05',
    label: 'Temp. motor',
    unit: '°C',
    min: -40,
    max: 150,
    formula: MarelliFormulas.temp,
  ),
  intakeTemp(
    command: '01 0F',
    label: 'Temp. admissão',
    unit: '°C',
    min: -40,
    max: 120,
    formula: MarelliFormulas.temp,
  ),
  map(
    command: '01 0B',
    label: 'MAP',
    unit: 'kPa',
    min: 0,
    max: 255,
    formula: MarelliFormulas.map,
  ),
  tps(
    command: '01 11',
    label: 'TPS',
    unit: '%',
    min: 0,
    max: 100,
    formula: MarelliFormulas.tps,
  ),
  lambda(
    command: '01 14',
    label: 'Lambda',
    unit: 'λ',
    min: 0,
    max: 2,
    formula: MarelliFormulas.lambda,
  ),
  injectionTime(
    command: '21 01', // Local ID 01 Marelli
    label: 'Injeção',
    unit: 'ms',
    min: 0,
    max: 30,
    formula: MarelliFormulas.injection,
  ),
  ignitionAdvance(
    command: '01 0E',
    label: 'Avanço ignição',
    unit: '°',
    min: -64,
    max: 64,
    formula: MarelliFormulas.ignition,
  ),
  fuelLevel(
    command: '01 2F',
    label: 'Combustível',
    unit: '%',
    min: 0,
    max: 100,
    formula: MarelliFormulas.fuelLevel,
  ),
  batteryVoltage(
    command: 'ATRV',
    label: 'Bateria',
    unit: 'V',
    min: 0,
    max: 20,
    formula: MarelliFormulas.voltage,
  );

  const MarelliPid({
    required this.command,
    required this.label,
    required this.unit,
    required this.min,
    required this.max,
    required this.formula,
  });

  final String command;
  final String label;
  final String unit;
  final double min;
  final double max;
  final double Function(List<int> bytes) formula;

  /// PIDs lidos no loop principal do dashboard do Palio.
  static const List<MarelliPid> dashboardLoop = [
    rpm,
    speed,
    coolantTemp,
    map,
    tps,
    fuelLevel,
    intakeTemp,
    ignitionAdvance,
    lambda,
    injectionTime,
    batteryVoltage,
  ];

  /// PIDs reais emitidos pela ECU usados para validar a conexão ativa com o motor.
  /// NÃO inclui [batteryVoltage] porque o comando ATRV responde diretamente do
  /// microcontrolador ELM327 mesmo quando a ECU está desligada/desconectada.
  static const List<MarelliPid> ecuHandshakePids = [
    rpm,
    coolantTemp,
    speed,
    map,
  ];
}
