import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/diagnostics_provider.dart';
import '../../core/diagnostics/remote_log_service.dart';
import '../../core/obd2/obd2_service.dart';
import '../../shared/models/obd_data_model.dart';
import '../settings/settings_provider.dart';

enum DataSourceMode { simulation, live }

final dataSourceModeProvider = StateProvider<DataSourceMode>(
  (ref) => DataSourceMode.simulation,
);

/// Instância do [Obd2Service] da conexão live atual, para que a UI (botão
/// "Conectar à ECU" no Dashboard) consiga acionar [Obd2Service.connectEcu]
/// como uma etapa separada da conexão com o adaptador OBD2.
final currentObd2ServiceProvider = StateProvider<Obd2Service?>((ref) => null);

/// true enquanto o botão "Conectar à ECU" está aguardando resposta.
final connectingEcuProvider = StateProvider<bool>((ref) => false);

/// Incrementado pela tela de Configurações sempre que o usuário tenta
/// conectar a um dispositivo, para forçar `_liveObdStream` a reiniciar do
/// zero mesmo quando [dataSourceModeProvider] já estava em `live` (uma
/// segunda tentativa de conexão na mesma sessão não muda esse valor, então
/// sem este token o Riverpod não reconstruiria o stream e o Dashboard
/// ficaria preso no estado da tentativa anterior).
final obdReconnectTokenProvider = StateProvider<int>((ref) => 0);

/// Protocolo escolhido manualmente em Configurações para o botão "Conectar
/// à ECU" usar, ou null para tentar todas as camadas automaticamente (via
/// [Obd2Service.connectEcuAutoDetect]).
final manualEcuProtocolProvider = StateProvider<EcuProtocol?>((ref) => null);

/// Emite um [OBDDataModel] a cada 100ms. Em modo simulação gera dados fake;
/// em modo live, reconecta automaticamente ao último adaptador ELM327
/// pareado (MAC salvo em SharedPreferences) e inicia o loop de PIDs.
final obdDataProvider = StreamProvider<OBDDataModel>((ref) {
  final mode = ref.watch(dataSourceModeProvider);
  ref.watch(obdReconnectTokenProvider);
  final source = mode == DataSourceMode.live
      ? _liveObdStream(ref)
      : _simulatedObdStream();

  return source.map((data) {
    if (ref.read(wsServerRunningProvider)) {
      ref.read(wsServerProvider).broadcast(data);
    }
    final cloudCode = ref.read(cloudRelayCodeProvider);
    if (cloudCode != null) {
      ref.read(cloudRelayServiceProvider).update(data);
    }
    return data;
  });
});

Stream<OBDDataModel> _simulatedObdStream() {
  final start = DateTime.now();
  return Stream.periodic(
    const Duration(milliseconds: 100),
    (_) => OBDDataModel.simulated(DateTime.now().difference(start)),
  );
}

Stream<OBDDataModel> _liveObdStream(Ref ref) async* {
  final btManager = ref.watch(btManagerProvider);
  final obd2Service = Obd2Service(
    btManager,
    logSink: ref.read(remoteLogServiceProvider).log,
  );
  ref.read(currentObd2ServiceProvider.notifier).state = obd2Service;
  ref.onDispose(() {
    ref.read(currentObd2ServiceProvider.notifier).state = null;
    obd2Service.dispose();
  });

  final lastAddress = await btManager.getLastAddress();
  if (lastAddress == null) {
    yield OBDDataModel.empty().copyWith(
      btStatus: ConnectionStatus.disconnected,
    );
    return;
  }

  yield OBDDataModel.empty().copyWith(btStatus: ConnectionStatus.connecting);

  try {
    // Se a tela de Configurações já testou e deixou conectado ao mesmo
    // endereço, não desconecta e reconecta de novo aqui — em adaptadores
    // ELM327 mais baratos, reconectar imediatamente após desconectar pode
    // falhar ou ficar pendurado, deixando o Dashboard sem nunca chegar a
    // "conectado" mesmo com o OBD2 funcionando.
    if (!btManager.isConnected) {
      await btManager.connect(lastAddress);
    }
    final manualProtocol = ref.read(manualEcuProtocolProvider);
    final targetProtocol = manualProtocol ?? EcuProtocol.kwp2000FastInit;
    await obd2Service.setupAdapter(protocol: targetProtocol);
  } catch (e) {
    ref.read(remoteLogServiceProvider).log(
      LogLevel.error,
      'dashboard',
      'Falha ao conectar/configurar o adaptador OBD2: $e',
    );
    yield OBDDataModel.empty().copyWith(
      btStatus: ConnectionStatus.disconnected,
    );
    return;
  }

  // Adaptador conectado — emite status e inicia detecção da ECU em background
  yield OBDDataModel.empty().copyWith(
    btStatus: ConnectionStatus.connected,
    ecuResponding: false,
  );

  // Inicia handshake e autoconexão com a ECU automaticamente
  unawaited(() async {
    try {
      final manualProtocol = ref.read(manualEcuProtocolProvider);
      final connectedProtocol = manualProtocol != null
          ? ((await obd2Service.connectEcuViaProtocol(manualProtocol))
              ? manualProtocol
              : null)
          : await obd2Service.connectEcuAutoDetect();
      if (connectedProtocol != null) {
        await obd2Service.startLoop();
      }
    } catch (e) {
      ref.read(remoteLogServiceProvider).log(
            LogLevel.warn,
            'dashboard',
            'Tentativa automática de conexão com a ECU: $e',
          );
    }
  }());

  yield* obd2Service.dataStream;
}
