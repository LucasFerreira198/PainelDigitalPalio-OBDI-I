import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/obd2/dtc_decoder.dart';
import '../../shared/theme/app_theme.dart';
import 'dtc_provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/obd2/dtc_decoder.dart';
import '../../shared/theme/app_theme.dart';
import '../dashboard/dashboard_provider.dart';
import 'dtc_provider.dart';

class DtcScreen extends ConsumerStatefulWidget {
  const DtcScreen({super.key});

  @override
  ConsumerState<DtcScreen> createState() => _DtcScreenState();
}

class _DtcScreenState extends ConsumerState<DtcScreen> {
  bool _isClearing = false;

  Future<void> _clearFaultCodes() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Limpar códigos de falha?'),
        content: const Text(
          'Esta ação enviará o comando de reset de diagnósticos (KWP2000 14 FF 00 / Modo 04) para a ECU. A luz da injeção se apagará se as falhas não forem permanentes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apagar Falhas'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isClearing = true);
    final obdService = ref.read(currentObd2ServiceProvider);
    bool ok = false;
    if (obdService != null) {
      ok = await obdService.clearDtcs();
      ref.invalidate(dtcListProvider);
    }

    if (mounted) {
      setState(() => _isClearing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Códigos de falha limpos com sucesso na ECU!'
                : 'Falha ao limpar códigos (verifique se a chave de ignição está ligada).',
          ),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dtcsAsync = ref.watch(dtcListProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Diagnóstico de Falhas (DTC)'),
        actions: [
          if (_isClearing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
                ),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
              tooltip: 'Apagar falhas da ECU',
              onPressed: _clearFaultCodes,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Atualizar lista',
              onPressed: () => ref.invalidate(dtcListProvider),
            ),
          ],
        ],
      ),
      body: dtcsAsync.when(
        data: (codes) {
          if (codes.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: AppTheme.gaugeNormal,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Nenhuma falha ativa registrada na ECU',
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Sistema de injeção eletrônica sem anomalias detectadas',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: codes.length,
            separatorBuilder: (_, __) => const Divider(color: Colors.white12),
            itemBuilder: (context, index) {
              final code = codes[index];
              return ListTile(
                leading: const Icon(Icons.warning_amber, color: AppTheme.danger),
                title: Text(
                  code,
                  style: AppTheme.digitalDisplay(fontSize: 18),
                ),
                subtitle: Text(
                  describeDtc(code),
                  style: const TextStyle(color: Colors.white70),
                ),
              );
            },
          );
        },
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppTheme.accent),
              SizedBox(height: 12),
              Text(
                'Consultando memória de falhas da ECU...',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        error: (error, stack) => Center(
          child: Text(
            'Erro ao ler DTCs: $error',
            style: const TextStyle(color: AppTheme.danger),
          ),
        ),
      ),
    );
  }
}
