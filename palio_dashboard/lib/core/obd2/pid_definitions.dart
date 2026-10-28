import 'marelli_protocol.dart';

/// PIDs de monitoramento para o Fiat Palio (Marelli IAW 4AF / 4EF / 59F / 5AF).
/// Extraídos via engenharia reversa do AlfaOBD (ECU IAW 4AF EOBD, Service 21 KWP2000).
/// Com o ELM327 configurado via ATSH 82 10 F1, o adaptador empacota o header KWP2000
/// (82 = physical 2 bytes, 10 = ECU Marelli, F1 = Scanner) e calcula o checksum automaticamente.
enum MarelliPid {
  rpm(
    command: '21 30', // Service 21 Local ID 0x30: Engine speed (rpm)
    label: 'RPM',
    unit: 'rpm',
    min: 0,
    max: 8000,
    formula: MarelliFormulas.rpm,
  ),
  speed(
    command: '21 53', // Service 21 Local ID 0x53: Vehicle speed (km/h)
    label: 'Velocidade',
    unit: 'km/h',
    min: 0,
    max: 260,
    formula: MarelliFormulas.speed,
  ),
  coolantTemp(
    command: '21 33', // Service 21 Local ID 0x33: Water temperature (°C)
    label: 'Temp. motor',
    unit: '°C',
    min: -40,
    max: 150,
    formula: MarelliFormulas.temp,
  ),
  intakeTemp(
    command: '21 32', // Service 21 Local ID 0x32: Air temperature (°C)
    label: 'Temp. admissão',
    unit: '°C',
    min: -40,
    max: 120,
    formula: MarelliFormulas.temp,
  ),
  map(
    command: '21 31', // Service 21 Local ID 0x31: Intake pressure (mbar/kPa)
    label: 'MAP',
    unit: 'kPa',
    min: 0,
    max: 255,
    formula: MarelliFormulas.map,
  ),
  tps(
    command: '21 34', // Service 21 Local ID 0x34: Throttle angle (%)
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
    command: '21 39', // Service 21 Local ID 0x39: Injection time (usec)
    label: 'Injeção',
    unit: 'ms',
    min: 0,
    max: 30,
    formula: MarelliFormulas.injection,
  ),
  ignitionAdvance(
    command: '21 37', // Service 21 Local ID 0x37: Spark advance (°)
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

  /// PIDs lidos no loop principal do dashboard do Palio (sensores essenciais).
  static const List<MarelliPid> dashboardLoop = [
    rpm,
    speed,
    coolantTemp,
    map,
    tps,
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
