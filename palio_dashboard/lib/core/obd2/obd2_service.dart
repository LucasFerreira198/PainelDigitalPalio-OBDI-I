import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/models/obd_data_model.dart';
import '../bluetooth/bt_manager.dart';
import '../diagnostics/remote_log_service.dart';
import 'dtc_decoder.dart';
import 'marelli_protocol.dart';
import 'pid_definitions.dart';
import 'standard_obd2_pid_definitions.dart';
import 'standard_obd2_protocol.dart';

/// Camadas de protocolo tentadas, em ordem, por [Obd2Service.connectEcuAutoDetect].
/// [kwp2000FastInit] e [kwp2000SlowInit] diferem só no handshake de
/// inicialização do ELM327 (ATSP5 vs ATSP4) — algumas ECUs Marelli só
/// aceitam um dos dois.
enum EcuProtocol { obd2Standard, kwp2000FastInit, kwp2000SlowInit, iso9141 }

extension EcuProtocolLabel on EcuProtocol {
  String get displayLabel => switch (this) {
    EcuProtocol.obd2Standard => 'OBD-II padrão',
    EcuProtocol.kwp2000FastInit => 'KWP2000 (fast init)',
    EcuProtocol.kwp2000SlowInit => 'KWP2000 (slow init)',
    EcuProtocol.iso9141 => 'ISO9141-2',
  };
}

/// Orquestra a inicialização do ELM327 e o loop de leitura de PIDs,
/// emitindo snapshots de [OBDDataModel] conforme os dados chegam. Suporta
/// quatro camadas de protocolo para falar com a ECU (ver [EcuProtocol]) —
/// nenhum carro precisa de todas, mas qual delas funciona varia por
/// modelo/ano de ECU, e a forma confiável de descobrir é tentar em ordem.
class Obd2Service {
  final BtManager btManager;
  final LogSink? _logSink;

  Obd2Service(this.btManager, {LogSink? logSink}) : _logSink = logSink;

  static const _lastLayerKey = 'obd2_last_ecu_protocol';

  /// PIDs cuja última leitura falhou — evita logar a mesma falha a cada
  /// ciclo (50ms) enquanto o problema persiste.
  final Set<MarelliPid> _loggedFailures = {};
  final Set<StandardObd2Pid> _loggedStandardFailures = {};

  final StreamController<OBDDataModel> _dataController =
      StreamController<OBDDataModel>.broadcast();

  Stream<OBDDataModel> get dataStream => _dataController.stream;

  OBDDataModel _last = OBDDataModel.empty();

  bool _running = false;
  int _loopSessionId = 0;

  EcuProtocol? _activeLayer;
  Future<EcuProtocol?>? _activeConnection;

  /// Camada de protocolo que respondeu na última conexão bem-sucedida, ou
  /// null se nenhuma conexão com a ECU foi estabelecida ainda.
  EcuProtocol? get activeProtocol => _activeLayer;

  bool get lastEcuResponding => _last.ecuResponding;

  bool get isLoopRunning => _running;

  /// Configura apenas o ELM327 (ATZ/ATE0/.../ATST96) para a camada de
  /// protocolo [protocol] — não tenta falar com a ECU do carro. Lança
  /// [BtCommandTimeoutException] se o próprio chip não responder à
  /// configuração, indicando problema no adaptador/Bluetooth, não na ECU.
  Future<void> setupAdapter({
    EcuProtocol protocol = EcuProtocol.kwp2000FastInit,
  }) async {
    final setupSequence = switch (protocol) {
      EcuProtocol.obd2Standard => kElm327SetupObd2Standard,
      EcuProtocol.kwp2000FastInit => kElm327SetupKwp2000FastInit,
      EcuProtocol.kwp2000SlowInit => kElm327SetupKwp2000SlowInit,
      EcuProtocol.iso9141 => kElm327SetupIso9141,
    };
    for (final command in setupSequence) {
      final timeout = command == 'ATZ'
          ? kAtzTimeout
          : BtManager.defaultTimeout;
      await btManager.sendCommand(command, timeout: timeout);
    }
    _activeLayer = protocol;
    _last = _last.copyWith(
      btStatus: ConnectionStatus.connected,
      ecuProtocolLabel: 'IAW 4AF EOBD (KWP2000 Fast Init)',
    );
  }

  /// Valida se a ECU responde via protocolo Marelli KWP2000 (Fiat Palio IAW 4AF / 4EF / 59F / 5AF).
  /// Envia primeiro o comando de despertar (wake-up) do AlfaOBD: '1A 97' (ReadEcuIdentification).
  /// Se a ECU responder (contendo '5A' ou '97'), a sessão KWP2000 está aberta.
  /// Em seguida testa leitura de RPM (01 0C) e temperatura (01 05).
  Future<bool> connectEcu({
    List<MarelliPid> pids = MarelliPid.ecuHandshakePids,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    _logSink?.call(
      LogLevel.info,
      'obd2',
      'Despertando ECU Marelli IAW 4AF (Fast Init 1A 97)...',
    );

    // 1. Wake-up handshake oficial AlfaOBD para IAW 4AF: '1A 97'
    try {
      final idRaw = await btManager.sendCommand('1A 97', timeout: const Duration(milliseconds: 3500));
      if (!isElmFailureResponse(idRaw) && (idRaw.contains('5A') || idRaw.contains('97'))) {
        _logSink?.call(
          LogLevel.info,
          'obd2',
          'ECU Marelli IAW 4AF despertada com sucesso (resposta 1A 97: $idRaw)',
        );
        // Após acordar, lê RPM e tensão para alimentar os mostradores
        await _readPid(MarelliPid.batteryVoltage);
        await _readPid(MarelliPid.rpm, timeout: const Duration(seconds: 2));
        _last = _last.copyWith(
          ecuResponding: true,
          ecuProtocolLabel: 'IAW 4AF EOBD (KWP2000)',
        );
        _dataController.add(_last);
        return true;
      }
    } catch (e) {
      _logSink?.call(LogLevel.warn, 'obd2', 'Tentativa 1A 97: $e');
    }

    // 2. Teste direto de RPM Marelli (21 30)
    if (await _readPid(MarelliPid.rpm, timeout: const Duration(seconds: 2))) {
      await _readPid(MarelliPid.batteryVoltage);
      _last = _last.copyWith(
        ecuResponding: true,
        ecuProtocolLabel: 'IAW 4AF EOBD (KWP2000)',
      );
      _dataController.add(_last);
      return true;
    }

    // 3. Fallback: temperatura do motor (21 33)
    if (await _readPid(MarelliPid.coolantTemp, timeout: const Duration(seconds: 2))) {
      await _readPid(MarelliPid.batteryVoltage);
      _last = _last.copyWith(
        ecuResponding: true,
        ecuProtocolLabel: 'IAW 4AF EOBD (KWP2000)',
      );
      _dataController.add(_last);
      return true;
    }

    // 4. Fallback: comando Marelli Service 21 Status (21 01) para confirmar ECU acordada
    try {
      final locRaw = await btManager.sendCommand('21 01', timeout: const Duration(seconds: 2));
      if (!isElmFailureResponse(locRaw) && (locRaw.contains('61') || locRaw.contains('01'))) {
        // ECU confirmou comunicação KWP2000! Agora lê os sensores reais (RPM e Bateria)
        await _readPid(MarelliPid.rpm, timeout: const Duration(milliseconds: 1000));
        await _readPid(MarelliPid.batteryVoltage);
        _last = _last.copyWith(
          ecuResponding: true,
          ecuProtocolLabel: 'IAW 4AF EOBD (KWP2000)',
        );
        _dataController.add(_last);
        return true;
      }
    } catch (_) {}

    // Sempre tenta ler a bateria mesmo que a ECU não responda
    await _readPid(MarelliPid.batteryVoltage);

    _logSink?.call(
      LogLevel.warn,
      'obd2',
      'ECU Marelli não respondeu aos comandos de despertar (ignição pode estar desligada)',
    );
    _last = _last.copyWith(ecuResponding: false);
    _dataController.add(_last);
    return false;
  }

  /// Equivalente a [connectEcu], mas usando PIDs OBD-II padrão (modo $01).
  /// Envia PID 01 0C (RPM) com timeout de 4.5s para conceder ao ELM327 o
  /// tempo de varredura de barramento do ATSP0 (SEARCHING...). Se responder,
  /// valida a ECU de imediato sem esperas desnecessárias.
  Future<bool> connectStandardObd2({
    List<StandardObd2Pid> pids = StandardObd2Pid.ecuHandshakePids,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (await _readStandardPid(StandardObd2Pid.rpm, timeout: const Duration(milliseconds: 4500))) {
      _last = _last.copyWith(ecuResponding: true);
      _dataController.add(_last);
      unawaited(_logSupportedStandardPids());
      return true;
    }

    // Fallback: temperatura do motor (PID 01 05)
    if (await _readStandardPid(StandardObd2Pid.coolantTemp, timeout: const Duration(seconds: 2))) {
      _last = _last.copyWith(ecuResponding: true);
      _dataController.add(_last);
      unawaited(_logSupportedStandardPids());
      return true;
    }

    _logSink?.call(
      LogLevel.warn,
      'obd2',
      'ECU OBD-II padrão não respondeu aos comandos de handshake rápido',
    );
    _last = _last.copyWith(ecuResponding: false);
    _dataController.add(_last);
    return false;
  }

  /// Todas as camadas de protocolo conhecidas, na ordem usada por
  /// [connectEcuAutoDetect] quando não há nenhuma lembrada/preferida.
  static const List<EcuProtocol> allProtocolsInOrder = [
    EcuProtocol.kwp2000FastInit,
    EcuProtocol.obd2Standard,
    EcuProtocol.kwp2000SlowInit,
    EcuProtocol.iso9141,
  ];

  /// Configura o adaptador para [protocol] e tenta ler os PIDs
  /// correspondentes uma única vez (sem passar para outra camada em caso
  /// de falha). Limpa a fila Bluetooth antes de iniciar para evitar comandos
  /// pendentes ou atrasados.
  Future<bool> connectEcuViaProtocol(
    EcuProtocol protocol, {
    Duration timeout = const Duration(seconds: 5),
    bool rememberOnSuccess = true,
  }) async {
    _logSink?.call(
      LogLevel.info,
      'obd2',
      'Tentando ECU via ${protocol.displayLabel}...',
    );
    btManager.clearQueue();
    try {
      await setupAdapter(protocol: protocol);
    } catch (e) {
      _logSink?.call(
        LogLevel.error,
        'obd2',
        'Falha ao configurar adaptador para ${protocol.displayLabel}: $e',
      );
      return false;
    }
    final ok = protocol == EcuProtocol.obd2Standard
        ? await connectStandardObd2(timeout: timeout)
        : await connectEcu(timeout: timeout);
    if (ok) {
      _activeLayer = protocol;
      _last = _last.copyWith(ecuProtocolLabel: protocol.displayLabel);
      _dataController.add(_last);
      _logSink?.call(
        LogLevel.info,
        'obd2',
        'ECU conectada via ${protocol.displayLabel}',
      );
      if (rememberOnSuccess) await _saveLastLayer(protocol);
    } else {
      _logSink?.call(
        LogLevel.warn,
        'obd2',
        '${protocol.displayLabel} não respondeu',
      );
    }
    return ok;
  }

  /// Tenta conectar à ECU percorrendo as camadas de protocolo em ordem.
  /// Possui mutex interno (_activeConnection) para garantir que chamadas
  /// concorrentes da UI ou de background compartilhem a mesma tentativa em
  /// andamento, impedindo enfileiramento duplo de comandos no Bluetooth.
  Future<EcuProtocol?> connectEcuAutoDetect({
    Duration perLayerTimeout = const Duration(seconds: 5),
    bool rememberSuccess = true,
  }) async {
    if (_activeConnection != null) {
      return _activeConnection;
    }
    final future = _performAutoDetect(
      perLayerTimeout: perLayerTimeout,
      rememberSuccess: rememberSuccess,
    );
    _activeConnection = future;
    try {
      return await future;
    } finally {
      _activeConnection = null;
    }
  }

  Future<EcuProtocol?> _performAutoDetect({
    required Duration perLayerTimeout,
    required bool rememberSuccess,
  }) async {
    final remembered = rememberSuccess ? await _loadLastLayer() : null;
    final tryOrder = remembered == null
        ? allProtocolsInOrder
        : [remembered, ...allProtocolsInOrder.where((p) => p != remembered)];

    for (final protocol in tryOrder) {
      final ok = await connectEcuViaProtocol(
        protocol,
        timeout: perLayerTimeout,
        rememberOnSuccess: rememberSuccess,
      );
      if (ok) return protocol;
    }
    _activeLayer = null;
    _logSink?.call(LogLevel.error, 'obd2', 'Nenhuma camada de protocolo respondeu');
    return null;
  }

  Future<EcuProtocol?> _loadLastLayer() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_lastLayerKey);
    if (name == null) return null;
    return EcuProtocol.values.asNameMap()[name];
  }

  Future<void> _saveLastLayer(EcuProtocol protocol) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastLayerKey, protocol.name);
  }

  /// Retorna a última camada de protocolo gravada com sucesso nas preferências.
  Future<EcuProtocol?> loadRememberedProtocol() => _loadLastLayer();

  /// Reconfigura o chip ELM327 para um novo protocolo [protocol]
  /// em tempo real, mantendo o socket Bluetooth conectado sem interrupções.
  Future<bool> switchProtocolLive(EcuProtocol protocol) async {
    _logSink?.call(
      LogLevel.info,
      'obd2',
      'Reconfigurando adaptador ao vivo para ${protocol.displayLabel}...',
    );
    final wasRunning = _running;
    if (wasRunning) {
      _running = false;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    btManager.clearQueue();
    try {
      await setupAdapter(protocol: protocol);
      _activeLayer = protocol;
      _last = _last.copyWith(
        ecuProtocolLabel: protocol.displayLabel,
        ecuResponding: false,
      );
      _dataController.add(_last);
      await _saveLastLayer(protocol);
      _logSink?.call(
        LogLevel.info,
        'obd2',
        'Protocolo ${protocol.displayLabel} aplicado ao vivo com sucesso!',
      );
      if (wasRunning) {
        unawaited(startLoop());
      }
      return true;
    } catch (e) {
      _logSink?.call(
        LogLevel.error,
        'obd2',
        'Falha ao trocar protocolo ao vivo: $e',
      );
      if (wasRunning) {
        unawaited(startLoop());
      }
      return false;
    }
  }

  /// Inicia o loop contínuo de telemetria otimizado para o Palio Fire.
  /// Para máxima responsividade dos mostradores analógicos/digitais, o RPM é
  /// consultado a cada ciclo (~50ms) com prioridade máxima, enquanto os demais
  /// sensores de menor variação dinâmica (temperatura, bateria, MAP) são escalonados.
  Future<void> startLoop({
    Duration cycleDelay = const Duration(milliseconds: 30),
  }) async {
    if (_running) return;
    _running = true;
    final sessionId = ++_loopSessionId;
    var loopCounter = 0;
    while (_running && _loopSessionId == sessionId) {
      loopCounter++;

      // Sempre lê a bateria a cada ~2s (ou a cada 2 ciclos se a ECU estiver desligada)
      final shouldReadBattery = !_last.ecuResponding || (loopCounter % 15 == 0);
      if (shouldReadBattery) {
        await _readPid(MarelliPid.batteryVoltage, timeout: const Duration(milliseconds: 600));
        await Future.delayed(const Duration(milliseconds: 25));
      }

      // Se a ECU não está respondendo, tenta o despertar AlfaOBD (1A 97) a cada 10 ciclos
      if (!_last.ecuResponding && (loopCounter % 10 == 0)) {
        try {
          final idRaw = await btManager.sendCommand('1A 97', timeout: const Duration(milliseconds: 1500));
          if (!isElmFailureResponse(idRaw) && (idRaw.contains('5A') || idRaw.contains('97'))) {
            _last = _last.copyWith(ecuResponding: true);
            _dataController.add(_last);
          }
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 25));
      }

      if (!_running || _loopSessionId != sessionId) break;

      final anyPidSucceeded = _activeLayer == EcuProtocol.obd2Standard
          ? await _runStandardCycle(StandardObd2Pid.dashboardLoop)
          : await _runMarelliAdaptiveCycle(loopCounter);

      if (anyPidSucceeded) {
        _last = _last.copyWith(
          ecuResponding: true,
          ecuProtocolLabel: _activeLayer?.displayLabel ?? 'IAW 4AF EOBD (KWP2000)',
        );
        _dataController.add(_last);
      }
      await Future.delayed(cycleDelay);
    }
  }

  void stopLoop() {
    _running = false;
    _loopSessionId++;
    btManager.clearQueue();
  }

  /// Ciclo adaptativo de alta performance para Palio Fire:
  /// - RPM (21 30) lido a cada ciclo com prioridade máxima;
  /// - Sensores secundários (MAP 21 31, TPS 21 34, Temperatura 21 33) rotacionados
  ///   1 a cada ciclo, respeitando o tempo de recuperação P3 (30ms) da linha K;
  /// - Velocidade (21 53) consultada a cada 15 ciclos com timeout seguro.
  Future<bool> _runMarelliAdaptiveCycle(int loopCounter) async {
    var anyEcuPidSucceeded = false;
    const pidTimeout = Duration(milliseconds: 1000);
    const p3Delay = Duration(milliseconds: 30);

    // 1. RPM (Prioridade máxima: lido em absolutamente todos os ciclos)
    final rpmOk = await _readPid(MarelliPid.rpm, timeout: pidTimeout);
    if (rpmOk) anyEcuPidSucceeded = true;

    await Future.delayed(p3Delay);

    // 2. Rotaciona um sensor secundário por ciclo para evitar colisões na linha K
    final secondarySlot = loopCounter % 3;
    if (secondarySlot == 0) {
      final mapOk = await _readPid(MarelliPid.map, timeout: pidTimeout);
      if (mapOk) anyEcuPidSucceeded = true;
    } else if (secondarySlot == 1) {
      final tpsOk = await _readPid(MarelliPid.tps, timeout: pidTimeout);
      if (tpsOk) anyEcuPidSucceeded = true;
    } else {
      final tempOk = await _readPid(MarelliPid.coolantTemp, timeout: pidTimeout);
      if (tempOk) anyEcuPidSucceeded = true;
    }

    // 3. Velocidade do veículo (21 53): consultada a cada 15 ciclos
    if (loopCounter % 15 == 0) {
      await Future.delayed(p3Delay);
      final spdOk = await _readPid(MarelliPid.speed, timeout: const Duration(milliseconds: 700));
      if (spdOk) anyEcuPidSucceeded = true;
    }

    return anyEcuPidSucceeded;
  }

  /// Lê todos os [pids] Marelli sequencialmente (usado em handshakes/diagnósticos).
  Future<bool> _runMarelliCycle(List<MarelliPid> pids) async {
    var anyEcuPidSucceeded = false;
    const timeout = Duration(milliseconds: 800);
    for (final pid in pids) {
      final ok = await _readPid(pid, timeout: timeout);
      if (ok && pid != MarelliPid.batteryVoltage) {
        anyEcuPidSucceeded = true;
      }
      await Future.delayed(const Duration(milliseconds: 30));
    }
    return anyEcuPidSucceeded;
  }

  /// Lê todos os [pids] OBD-II padrão uma vez; retorna true se algum
  /// respondeu.
  Future<bool> _runStandardCycle(List<StandardObd2Pid> pids) async {
    var anySucceeded = false;
    for (final pid in pids) {
      if (await _readStandardPid(pid)) anySucceeded = true;
      await Future.delayed(const Duration(milliseconds: 25));
    }
    return anySucceeded;
  }

  /// Retorna true se o PID Marelli foi lido e parseado com sucesso.
  /// Atualiza e emite imediatamente o novo [OBDDataModel] para o stream
  /// para sincronização em tempo real dos ponteiros do dashboard.
  Future<bool> _readPid(MarelliPid pid, {Duration? timeout}) async {
    try {
      final raw = await btManager.sendCommand(
        pid.command,
        timeout: timeout ?? const Duration(milliseconds: 1000),
      );
      final parsed = parseMarelliResponse(raw);
      if (parsed == null) {
        if (_loggedFailures.add(pid)) {
          _logSink?.call(
            LogLevel.warn,
            'obd2',
            'Falha ao parsear resposta do PID Marelli ${pid.name}',
            raw: raw,
          );
        }
        return false;
      }
      _loggedFailures.remove(pid);
      final value = pid.formula(parsed.dataBytes);
      _last = _applyPidValue(pid, value).copyWith(
        ecuResponding: pid != MarelliPid.batteryVoltage ? true : _last.ecuResponding,
        ecuProtocolLabel: _last.ecuProtocolLabel.isEmpty ? 'IAW 4AF EOBD (KWP2000)' : _last.ecuProtocolLabel,
      );
      _dataController.add(_last);
      return true;
    } on BtCommandTimeoutException {
      return false;
    } on BtCommandCancelledException {
      return false;
    }
  }

  /// Consulta o PID $00 (PIDs suportados $01-$20) e loga o resultado — só
  /// para diagnóstico remoto, não muda o que é lido. Útil para descobrir
  /// se a ECU sequer expõe RPM/velocidade/temperatura em modo $01: uma
  /// resposta negativa "7F 01 .." aos PIDs do dashboard, mas válida aqui,
  /// indicaria que a ECU fala OBD-II padrão mas não tem esses PIDs
  /// específicos implementados.
  Future<void> _logSupportedStandardPids() async {
    try {
      final raw = await btManager.sendCommand('01 00');
      final parsed = parseStandardObd2Response(raw, expectedPid: 0x00);
      if (parsed == null || parsed.dataBytes.length < 4) {
        _logSink?.call(
          LogLevel.warn,
          'obd2',
          'PID 01 00 (PIDs suportados) não respondeu de forma válida',
          raw: raw,
        );
        return;
      }
      final b = parsed.dataBytes;
      final bitmap = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
      final supported = [
        for (var i = 0; i < 32; i++)
          if (bitmap & (1 << (31 - i)) != 0) i + 1,
      ];
      _logSink?.call(
        LogLevel.info,
        'obd2',
        'PIDs OBD-II padrão suportados pela ECU: '
            '${supported.map((p) => '0x${p.toRadixString(16).padLeft(2, '0').toUpperCase()}').join(', ')}',
      );
    } on BtCommandTimeoutException {
      _logSink?.call(
        LogLevel.warn,
        'obd2',
        'PID 01 00 (PIDs suportados) deu timeout',
      );
    }
  }

  /// Retorna true se o PID OBD-II padrão foi lido e parseado com sucesso.
  Future<bool> _readStandardPid(StandardObd2Pid pid, {Duration? timeout}) async {
    try {
      final raw = await btManager.sendCommand(
        pid.command,
        timeout: timeout ?? BtManager.defaultTimeout,
      );
      final parsed = parseStandardObd2Response(raw, expectedPid: pid.pidByte);
      if (parsed == null) {
        if (_loggedStandardFailures.add(pid)) {
          _logSink?.call(
            LogLevel.warn,
            'obd2',
            'Falha ao parsear resposta do PID padrão ${pid.name}',
            raw: raw,
          );
        }
        return false;
      }
      _loggedStandardFailures.remove(pid);
      final value = pid.formula(parsed.dataBytes);
      _last = _applyStandardPidValue(pid, value).copyWith(
        ecuResponding: pid != StandardObd2Pid.batteryVoltage ? true : _last.ecuResponding,
      );
      _dataController.add(_last);
      return true;
    } on BtCommandTimeoutException {
      return false;
    } on BtCommandCancelledException {
      return false;
    }
  }

  OBDDataModel _applyPidValue(MarelliPid pid, double value) {
    switch (pid) {
      case MarelliPid.rpm:
        return _last.copyWith(rpm: value, timestamp: DateTime.now());
      case MarelliPid.speed:
        return _last.copyWith(speedKmh: value, timestamp: DateTime.now());
      case MarelliPid.coolantTemp:
        return _last.copyWith(coolantTempC: value, timestamp: DateTime.now());
      case MarelliPid.intakeTemp:
        return _last.copyWith(intakeTempC: value, timestamp: DateTime.now());
      case MarelliPid.map:
        return _last.copyWith(mapKpa: value, timestamp: DateTime.now());
      case MarelliPid.tps:
        return _last.copyWith(tpsPercent: value, timestamp: DateTime.now());
      case MarelliPid.lambda:
        return _last.copyWith(lambda: value, timestamp: DateTime.now());
      case MarelliPid.injectionTime:
        return _last.copyWith(injectionMs: value, timestamp: DateTime.now());
      case MarelliPid.ignitionAdvance:
        return _last.copyWith(ignitionDeg: value, timestamp: DateTime.now());
      case MarelliPid.fuelLevel:
        return _last.copyWith(
          fuelLevelPercent: value,
          timestamp: DateTime.now(),
        );
      case MarelliPid.batteryVoltage:
        return _last.copyWith(batteryV: value, timestamp: DateTime.now());
    }
  }

  OBDDataModel _applyStandardPidValue(StandardObd2Pid pid, double value) {
    switch (pid) {
      case StandardObd2Pid.rpm:
        return _last.copyWith(rpm: value, timestamp: DateTime.now());
      case StandardObd2Pid.speed:
        return _last.copyWith(speedKmh: value, timestamp: DateTime.now());
      case StandardObd2Pid.coolantTemp:
        return _last.copyWith(coolantTempC: value, timestamp: DateTime.now());
      case StandardObd2Pid.map:
        return _last.copyWith(mapKpa: value, timestamp: DateTime.now());
      case StandardObd2Pid.tps:
        return _last.copyWith(tpsPercent: value, timestamp: DateTime.now());
      case StandardObd2Pid.fuelLevel:
        return _last.copyWith(
          fuelLevelPercent: value,
          timestamp: DateTime.now(),
        );
      case StandardObd2Pid.intakeTemp:
        return _last.copyWith(intakeTempC: value, timestamp: DateTime.now());
      case StandardObd2Pid.ignitionAdvance:
        return _last.copyWith(ignitionDeg: value, timestamp: DateTime.now());
      case StandardObd2Pid.batteryVoltage:
        return _last.copyWith(batteryV: value, timestamp: DateTime.now());
    }
  }

  /// Lê códigos de falha (DTC) da ECU via KWP2000 (Service 18 00 FF 00)
  /// ou fallback padrão OBD2 Modo 03.
  Future<List<String>> readDtcs() async {
    if (!btManager.isConnected) return [];

    // 1. Tenta Modo KWP2000 Service 18
    try {
      final raw = await btManager.sendCommand(
        '18 00 FF 00',
        timeout: const Duration(seconds: 4),
      );
      if (!isElmFailureResponse(raw) && (raw.contains('58') || raw.contains('18'))) {
        final parsed = parseMarelliResponse(raw);
        if (parsed != null && parsed.dataBytes.isNotEmpty) {
          // No Service 18, o primeiro byte após o SID/LocalID pode ser o contador
          final dBytes = parsed.dataBytes.length > 1
              ? parsed.dataBytes.sublist(1)
              : parsed.dataBytes;
          final dtcs = decodeDtcBytes(dBytes);
          _last = _last.copyWith(activeDtcs: dtcs);
          _dataController.add(_last);
          return dtcs;
        }
      }
    } catch (_) {}

    // 2. Fallback Modo 03 OBD2 Padrão
    try {
      final raw03 = await btManager.sendCommand('03', timeout: const Duration(seconds: 4));
      if (!isElmFailureResponse(raw03) && raw03.contains('43')) {
        final parsed03 = parseMarelliResponse(raw03);
        if (parsed03 != null && parsed03.dataBytes.isNotEmpty) {
          final dtcs = decodeDtcBytes(parsed03.dataBytes);
          _last = _last.copyWith(activeDtcs: dtcs);
          _dataController.add(_last);
          return dtcs;
        }
      }
    } catch (_) {}

    return [];
  }

  /// Limpa os códigos de falha da ECU via KWP2000 Service 14 FF 00 ou Modo 04.
  Future<bool> clearDtcs() async {
    if (!btManager.isConnected) return false;
    try {
      final raw14 = await btManager.sendCommand('14 FF 00', timeout: const Duration(seconds: 4));
      if (!isElmFailureResponse(raw14) && (raw14.contains('54') || raw14.contains('OK'))) {
        _last = _last.copyWith(activeDtcs: const []);
        _dataController.add(_last);
        return true;
      }
    } catch (_) {}

    try {
      final raw04 = await btManager.sendCommand('04', timeout: const Duration(seconds: 4));
      if (!isElmFailureResponse(raw04) && (raw04.contains('44') || raw04.contains('OK'))) {
        _last = _last.copyWith(activeDtcs: const []);
        _dataController.add(_last);
        return true;
      }
    } catch (_) {}

    return false;
  }

  Future<void> dispose() async {
    stopLoop();
    await _dataController.close();
  }
}
