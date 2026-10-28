import 'dart:convert';
import 'dart:io';

import '../../shared/models/obd_data_model.dart';

/// Servidor WebSocket rodando no celular Android. O PC/web conecta como
/// cliente em ws://IP_CELULAR:porta para receber os dados do OBD2 em tempo
/// real, transmitidos a cada novo snapshot via [broadcast].
class WsServer {
  HttpServer? _server;
  final Set<WebSocket> _clients = {};

  /// Limite máximo de clientes simultâneos para evitar exaustão de memória/soquetes.
  static const int maxClients = 5;

  bool get isRunning => _server != null;
  int? get port => _server?.port;
  int get clientCount => _clients.length;

  Future<void> start({int port = 8765}) async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen((HttpRequest request) async {
      // Rejeita requisições HTTP que não sejam WebSocket upgrade
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      // Limita conexões simultâneas para mitigar negação de serviço (DoS)
      if (_clients.length >= maxClients) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.write('Max connections reached');
        await request.response.close();
        return;
      }

      // Valida IP de origem: aceita apenas rede local privada (LAN) ou loopback
      final remoteAddr = request.connectionInfo?.remoteAddress;
      if (remoteAddr != null && !_isAllowedClient(remoteAddr)) {
        request.response.statusCode = HttpStatus.forbidden;
        request.response.write('Forbidden: only local network allowed');
        await request.response.close();
        return;
      }

      try {
        final ws = await WebSocketTransformer.upgrade(request);
        _clients.add(ws);
        ws.listen(
          (_) {},
          onError: (_) {
            _clients.remove(ws);
            try {
              ws.close();
            } catch (_) {}
          },
          onDone: () {
            _clients.remove(ws);
          },
          cancelOnError: true,
        );
      } catch (_) {
        // Handshake falhou ou cliente desconectou abruptamente
      }
    });
  }

  static bool _isAllowedClient(InternetAddress addr) {
    if (addr.isLoopback) return true;
    return _isPrivateLanAddress(addr.address);
  }

  void broadcast(OBDDataModel data) {
    if (_clients.isEmpty) return;
    final json = jsonEncode(data.toJson());
    for (final ws in _clients.toList()) {
      try {
        if (ws.readyState == WebSocket.open) {
          ws.add(json);
        } else {
          _clients.remove(ws);
        }
      } catch (_) {
        _clients.remove(ws);
      }
    }
  }

  Future<void> stop() async {
    for (final ws in _clients.toList()) {
      try {
        await ws.close();
      } catch (_) {}
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
  }
}

/// Retorna o endereço IPv4 da rede Wi-Fi local, usado para exibir ao usuário
/// o endereço ws://IP:porta a ser digitado no PC.
///
/// Android expõe várias interfaces de rede ao mesmo tempo (Wi-Fi, dados
/// móveis, VPN...). Pegar a primeira "qualquer" pode mostrar o IP da
/// interface de dados móveis — inalcançável pelo PC mesmo que ambos estejam
/// na mesma Wi-Fi — fazendo a conexão ficar "conectando" para sempre. Por
/// isso priorizamos a interface chamada "wlan" (padrão do Wi-Fi no Android)
/// e, como reforço, endereços em faixas privadas típicas de rede doméstica.
Future<String?> getLocalIpAddress() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );

  for (final interface in interfaces) {
    if (!interface.name.toLowerCase().contains('wlan')) continue;
    for (final addr in interface.addresses) {
      if (!addr.isLoopback) return addr.address;
    }
  }

  for (final interface in interfaces) {
    for (final addr in interface.addresses) {
      if (!addr.isLoopback && _isPrivateLanAddress(addr.address)) {
        return addr.address;
      }
    }
  }

  for (final interface in interfaces) {
    for (final addr in interface.addresses) {
      if (!addr.isLoopback) return addr.address;
    }
  }
  return null;
}

/// true para faixas de IP típicas de roteador doméstico/Wi-Fi local — usado
/// para descartar o IP de dados móveis quando não há interface "wlan".
bool _isPrivateLanAddress(String address) {
  final parts = address.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null)) return false;
  final a = parts[0]!, b = parts[1]!;
  if (a == 192 && b == 168) return true;
  if (a == 10) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  return false;
}
