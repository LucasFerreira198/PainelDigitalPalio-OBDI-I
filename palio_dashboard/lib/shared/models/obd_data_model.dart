import 'dart:math';

enum ConnectionStatus { disconnected, connecting, connected }

class OBDDataModel {
  final double rpm;
  final double speedKmh;
  final double coolantTempC;
  final double intakeTempC;
  final double mapKpa;
  final double tpsPercent;
  final double lambda;
  final double injectionMs;
  final double ignitionDeg;
  final double batteryV;
  final double fuelLevelPercent;
  final DateTime timestamp;
  final List<String> activeDtcs;
  final bool engineRunning;
  final ConnectionStatus btStatus;

  /// true quando ao menos um PID Marelli foi lido com sucesso no ciclo mais
  /// recente — indica que a ECU está respondendo, distinto de [btStatus]
  /// que só reflete se o adaptador ELM327 está conectado via Bluetooth.
  final bool ecuResponding;

  /// Qual camada de protocolo respondeu ('OBD-II padrão', 'KWP2000',
  /// 'ISO9141-2'), ou null se a ECU ainda não respondeu em nenhuma. Apenas
  /// para exibição — a lógica de conexão em si vive em EcuProtocol
  /// (core/obd2), não importado aqui de propósito para manter a separação
  /// de camadas.
  final String? ecuProtocolLabel;

  const OBDDataModel({
    required this.rpm,
    required this.speedKmh,
    required this.coolantTempC,
    required this.intakeTempC,
    required this.mapKpa,
    required this.tpsPercent,
    required this.lambda,
    required this.injectionMs,
    required this.ignitionDeg,
    required this.batteryV,
    this.fuelLevelPercent = 0.0,
    required this.timestamp,
    required this.activeDtcs,
    required this.engineRunning,
    required this.btStatus,
    required this.ecuResponding,
    this.ecuProtocolLabel,
  });

  OBDDataModel copyWith({
    double? rpm,
    double? speedKmh,
    double? coolantTempC,
    double? intakeTempC,
    double? mapKpa,
    double? tpsPercent,
    double? lambda,
    double? injectionMs,
    double? ignitionDeg,
    double? batteryV,
    double? fuelLevelPercent,
    DateTime? timestamp,
    List<String>? activeDtcs,
    bool? engineRunning,
    ConnectionStatus? btStatus,
    bool? ecuResponding,
    String? ecuProtocolLabel,
  }) {
    return OBDDataModel(
      rpm: rpm ?? this.rpm,
      speedKmh: speedKmh ?? this.speedKmh,
      coolantTempC: coolantTempC ?? this.coolantTempC,
      intakeTempC: intakeTempC ?? this.intakeTempC,
      mapKpa: mapKpa ?? this.mapKpa,
      tpsPercent: tpsPercent ?? this.tpsPercent,
      lambda: lambda ?? this.lambda,
      injectionMs: injectionMs ?? this.injectionMs,
      ignitionDeg: ignitionDeg ?? this.ignitionDeg,
      batteryV: batteryV ?? this.batteryV,
      fuelLevelPercent: fuelLevelPercent ?? this.fuelLevelPercent,
      timestamp: timestamp ?? this.timestamp,
      activeDtcs: activeDtcs ?? this.activeDtcs,
      engineRunning: engineRunning ?? this.engineRunning,
      btStatus: btStatus ?? this.btStatus,
      ecuResponding: ecuResponding ?? this.ecuResponding,
      ecuProtocolLabel: ecuProtocolLabel ?? this.ecuProtocolLabel,
    );
  }

  Map<String, dynamic> toJson() => {
        'rpm': rpm,
        'speedKmh': speedKmh,
        'coolantTempC': coolantTempC,
        'intakeTempC': intakeTempC,
        'mapKpa': mapKpa,
        'tpsPercent': tpsPercent,
        'lambda': lambda,
        'injectionMs': injectionMs,
        'ignitionDeg': ignitionDeg,
        'batteryV': batteryV,
        'fuelLevelPercent': fuelLevelPercent,
        'timestamp': timestamp.toIso8601String(),
        'activeDtcs': activeDtcs,
        'engineRunning': engineRunning,
        'btStatus': btStatus.name,
        'ecuResponding': ecuResponding,
        'ecuProtocolLabel': ecuProtocolLabel,
      };

  factory OBDDataModel.fromJson(Map<String, dynamic> json) => OBDDataModel(
        rpm: (json['rpm'] as num).toDouble(),
        speedKmh: (json['speedKmh'] as num).toDouble(),
        coolantTempC: (json['coolantTempC'] as num).toDouble(),
        intakeTempC: (json['intakeTempC'] as num).toDouble(),
        mapKpa: (json['mapKpa'] as num).toDouble(),
        tpsPercent: (json['tpsPercent'] as num).toDouble(),
        lambda: (json['lambda'] as num).toDouble(),
        injectionMs: (json['injectionMs'] as num).toDouble(),
        ignitionDeg: (json['ignitionDeg'] as num).toDouble(),
        batteryV: (json['batteryV'] as num).toDouble(),
        fuelLevelPercent: (json['fuelLevelPercent'] as num?)?.toDouble() ?? 0.0,
        timestamp: DateTime.parse(json['timestamp'] as String),
        activeDtcs: List<String>.from(json['activeDtcs'] as List),
        engineRunning: json['engineRunning'] as bool,
        btStatus: ConnectionStatus.values.byName(json['btStatus'] as String),
        ecuResponding: json['ecuResponding'] as bool? ?? false,
        ecuProtocolLabel: json['ecuProtocolLabel'] as String?,
      );

  factory OBDDataModel.empty() => OBDDataModel(
        rpm: 0,
        speedKmh: 0,
        coolantTempC: 0,
        intakeTempC: 0,
        mapKpa: 0,
        tpsPercent: 0,
        lambda: 0,
        injectionMs: 0,
        ignitionDeg: 0,
        batteryV: 0,
        fuelLevelPercent: 0,
        timestamp: DateTime.now(),
        activeDtcs: const [],
        engineRunning: false,
        btStatus: ConnectionStatus.disconnected,
        ecuResponding: false,
      );

  /// Gera um snapshot fake a partir do tempo decorrido [elapsed] desde o
  /// início da simulação. Usado pelo modo simulação do PC dashboard.
  factory OBDDataModel.simulated(Duration elapsed) {
    final t = elapsed.inMilliseconds / 1000.0;
    final rpm = 1500 + 1500 * sin(t / 3);
    final speed = (t * 4) % 130;
    final coolant = min(90.0, 20.0 + t * (70.0 / 60.0));
    return OBDDataModel(
      rpm: rpm.clamp(800, 6500),
      speedKmh: speed,
      coolantTempC: coolant,
      intakeTempC: 25 + 10 * sin(t / 10),
      mapKpa: 40 + 30 * sin(t / 4).abs(),
      tpsPercent: (20 + 20 * sin(t / 2)).clamp(0, 100),
      lambda: 1.0 + 0.1 * sin(t / 5),
      injectionMs: 3 + 2 * sin(t / 3).abs(),
      ignitionDeg: 10 + 8 * sin(t / 4),
      batteryV: 13.8 + 0.3 * sin(t / 7),
      fuelLevelPercent: (65.0 - (t / 12) % 20).clamp(0, 100),
      timestamp: DateTime.now(),
      activeDtcs: const [],
      engineRunning: true,
      btStatus: ConnectionStatus.connected,
      ecuResponding: true,
    );
  }
}
