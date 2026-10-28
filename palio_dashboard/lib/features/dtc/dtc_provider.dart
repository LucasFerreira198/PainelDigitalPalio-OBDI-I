import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dashboard/dashboard_provider.dart';

/// Lista de DTCs ativos. Em modo simulação retorna dados de exemplo;
/// em modo live, lê os códigos reais da ECU via KWP2000 / Modo 03.
final dtcListProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  final mode = ref.watch(dataSourceModeProvider);
  if (mode == DataSourceMode.live) {
    final obdService = ref.watch(currentObd2ServiceProvider);
    if (obdService == null) return const [];
    return obdService.readDtcs();
  }
  return const ['P0300', 'P0171'];
});
