import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../diagnostics/remote_log_service.dart';
import 'bt_device_model.dart';
import 'bt_permissions.dart';

class BtCommandTimeoutException implements Exception {
  final String command;
  const BtCommandTimeoutException(this.command);

  @override
  String toString() => 'Timeout aguardando resposta para "$command"';
}

class BtCommandCancelledException implements Exception {
  @override
  String toString() => 'BtCommandCancelledException: comando cancelado';
}

enum BtTrafficType { tx, rx, info, error }

class BtTrafficLog {
  final DateTime timestamp;
  final BtTrafficType type;
  final String text;

  const BtTrafficLog({
    required this.timestamp,
    required this.type,
    required this.text,
  });

  bool get isTx => type == BtTrafficType.tx;
  bool get isRx => type == BtTrafficType.rx;
  bool get isError => type == BtTrafficType.error;
}

class _QueuedCommand {
  final String command;
  final Duration timeout;
  final Completer<String> completer = Completer<String>();

  _QueuedCommand(this.command, this.timeout);
}

/// Gerencia a conexão Bluetooth Classic (SPP) com o adaptador ELM327.
///
/// O ELM327 é half-duplex: só pode haver um comando em voo por vez, e a
/// resposta termina com o prompt '>'. Por isso os comandos passam por uma
/// fila e são processados sequencialmente.
class BtManager {
  static const String _lastAddressKey = 'bt_last_device_address';

  // ATST96 (enviado na configuração do adaptador) define o timeout interno
  // do próprio ELM327 para aguardar a ECU em 0x96 * 4ms = 600ms — mas isso
  // só cobre a espera pela resposta DEPOIS do barramento já inicializado.
  // O primeiro comando de cada protocolo costuma disparar um handshake de
  // inicialização (5-baud slow init, etc.) que pode levar bem mais que
  // isso. Logs reais de carro mostraram "STOPPED" mesmo com 1000ms — sinal
  // de que o app ainda mandava o próximo comando enquanto o adaptador
  // seguia no meio de uma tentativa anterior. Por isso a margem é generosa.
  static const Duration defaultTimeout = Duration(milliseconds: 2000);

  BtManager({LogSink? logSink}) : _logSink = logSink;

  final LogSink? _logSink;

  BluetoothConnection? _connection;
  StreamSubscription<List<int>>? _inputSubscription;

  final Queue<_QueuedCommand> _queue = Queue<_QueuedCommand>();
  _QueuedCommand? _inFlight;
  Timer? _timeoutTimer;

  final List<int> _buffer = [];

  final StreamController<BtTrafficLog> _trafficController =
      StreamController<BtTrafficLog>.broadcast();
  final List<BtTrafficLog> _trafficHistory = [];
  static const int _maxTrafficHistory = 300;

  Stream<BtTrafficLog> get trafficStream => _trafficController.stream;
  List<BtTrafficLog> get trafficHistory => List.unmodifiable(_trafficHistory);

  void logTraffic(BtTrafficType type, String text) {
    final entry = BtTrafficLog(
      timestamp: DateTime.now(),
      type: type,
      text: text,
    );
    if (_trafficHistory.length >= _maxTrafficHistory) {
      _trafficHistory.removeAt(0);
    }
    _trafficHistory.add(entry);
    if (!_trafficController.isClosed) {
      _trafficController.add(entry);
    }
  }

  void clearTrafficLogs() {
    _trafficHistory.clear();
  }

  bool get isConnected => _connection?.isConnected ?? false;

  Future<List<BtDeviceModel>> getBondedDevices() async {
    await ensureBluetoothPermissions();
    final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
    return devices.map(BtDeviceModel.fromBluetoothDevice).toList();
  }

  Future<void> connect(String address) async {
    await ensureBluetoothPermissions();
    await disconnect();
    logTraffic(BtTrafficType.info, 'Conectando ao Bluetooth ($address)...');
    try {
      _connection = await BluetoothConnection.toAddress(address);
    } catch (e) {
      logTraffic(BtTrafficType.error, 'Falha ao conectar via Bluetooth: $e');
      _logSink?.call(LogLevel.error, 'bt', 'Falha ao conectar a $address: $e');
      rethrow;
    }
    _buffer.clear();
    logTraffic(BtTrafficType.info, 'Bluetooth conectado com sucesso a $address');
    _inputSubscription = _connection!.input?.listen(
      _onBytesReceived,
      onDone: () {
        logTraffic(BtTrafficType.error, 'Conexão Bluetooth perdida/fechada');
        _logSink?.call(LogLevel.warn, 'bt', 'Conexão Bluetooth perdida');
        unawaited(disconnect());
      },
    );
    await _saveLastAddress(address);
    _logSink?.call(LogLevel.info, 'bt', 'Conectado a $address');
  }

  Future<void> disconnect() async {
    clearQueue();
    await _inputSubscription?.cancel();
    _inputSubscription = null;
    await _connection?.finish();
    _connection = null;
    logTraffic(BtTrafficType.info, 'Bluetooth desconectado');
  }

  /// Descarta imediatamente qualquer comando em voo e esvazia a fila de
  /// comandos pendentes, completando seus futuros com erro de cancelamento.
  /// Essencial para evitar que dezenas de comandos obsoletos bloqueiem novas
  /// tentativas de conexão à ECU ou mudanças de protocolo.
  void clearQueue() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    final cancelError = BtCommandCancelledException();
    var cancelledCount = 0;
    if (_inFlight != null) {
      final current = _inFlight!;
      _inFlight = null;
      cancelledCount++;
      if (!current.completer.isCompleted) {
        current.completer.completeError(cancelError);
      }
    }
    while (_queue.isNotEmpty) {
      final next = _queue.removeFirst();
      cancelledCount++;
      if (!next.completer.isCompleted) {
        next.completer.completeError(cancelError);
      }
    }
    _buffer.clear();
    if (cancelledCount > 0) {
      logTraffic(BtTrafficType.info, 'Fila de comandos limpa ($cancelledCount comandos)');
    }
  }

  /// Envia um comando AT/Marelli e aguarda a resposta completa (até o '>').
  /// Comandos são enfileirados — o ELM327 não aceita o próximo enquanto o
  /// anterior não terminar.
  Future<String> sendCommand(
    String command, {
    Duration timeout = defaultTimeout,
  }) {
    if (!isConnected) {
      logTraffic(BtTrafficType.error, 'Falha ao enviar "$command": Bluetooth desconectado');
      return Future.error(StateError('Bluetooth não conectado'));
    }
    final queued = _QueuedCommand(command, timeout);
    _queue.add(queued);
    _pumpQueue();
    return queued.completer.future;
  }

  void _pumpQueue() {
    if (_inFlight != null || _queue.isEmpty) return;
    final next = _queue.removeFirst();
    _inFlight = next;
    _buffer.clear();

    try {
      logTraffic(BtTrafficType.tx, next.command);
      _connection!.output.add(ascii.encode('${next.command}\r'));
    } catch (e) {
      _inFlight = null;
      logTraffic(BtTrafficType.error, 'Erro de escrita serial Bluetooth: $e');
      if (!next.completer.isCompleted) {
        next.completer.completeError(e);
      }
      unawaited(disconnect());
      return;
    }

    _timeoutTimer = Timer(next.timeout, () {
      if (_inFlight == next) {
        _inFlight = null;
        logTraffic(
          BtTrafficType.error,
          'TIMEOUT (${next.timeout.inMilliseconds}ms) aguardando resposta para "${next.command}"',
        );
        _logSink?.call(
          LogLevel.warn,
          'bt',
          'Timeout aguardando resposta',
          raw: next.command,
        );
        next.completer.completeError(BtCommandTimeoutException(next.command));
        // Descarta bytes residuais e dá 60ms para a linha serial estabilizar
        _buffer.clear();
        Future.delayed(const Duration(milliseconds: 60), () {
          _buffer.clear();
          _pumpQueue();
        });
      }
    });
  }

  void _onBytesReceived(List<int> bytes) {
    _buffer.addAll(bytes);
    final text = ascii.decode(_buffer, allowInvalid: true);
    if (!text.contains('>')) return;

    _timeoutTimer?.cancel();
    final current = _inFlight;
    _inFlight = null;
    _buffer.clear();

    if (current == null) {
      // Resposta residual atrasada (ex: STOPPED de comando abortado) - descarta
      _pumpQueue();
      return;
    }

    final cleanedResponse = text.replaceAll('\r', ' ').replaceAll('\n', ' ').trim();
    logTraffic(BtTrafficType.rx, cleanedResponse);

    current.completer.complete(text);
    _pumpQueue();
  }

  Future<void> _saveLastAddress(String address) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastAddressKey, address);
  }

  Future<String?> getLastAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastAddressKey);
  }

  /// Marca [address] como o dispositivo preferido para reconexão automática,
  /// sem conectar imediatamente — usado ao selecionar um adaptador na tela
  /// de Settings antes de alternar para o modo live.
  Future<void> setPreferredAddress(String address) => _saveLastAddress(address);
}
