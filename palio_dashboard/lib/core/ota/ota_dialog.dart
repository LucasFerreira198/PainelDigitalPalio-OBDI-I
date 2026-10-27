import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_theme.dart';
import 'ota_provider.dart';
import 'ota_service.dart';

/// Consulta a release mais recente e, se houver atualização, pergunta ao
/// usuário antes de baixar/instalar. Nunca atualiza sem confirmação.
Future<void> checkAndPromptUpdate(
  BuildContext context,
  WidgetRef ref, {
  bool silent = false,
}) async {
  final otaService = ref.read(otaServiceProvider);

  OtaUpdateInfo? update;
  try {
    update = await otaService.checkForUpdate();
  } catch (e) {
    if (!silent && context.mounted) {
      final msg = e.toString().contains('404')
          ? 'Nenhuma atualização encontrada ou repositório não acessível (404).'
          : 'Falha ao verificar atualização: $e';
      _showError(context, msg);
    }
    return;
  }
  if (!context.mounted) return;
  if (update == null) {
    if (!silent) {
      _showError(context, 'Você já está na versão mais recente.');
    }
    return;
  }

  final shouldUpdate = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Nova versão disponível'),
      content: Text(
        'Versão atual: ${update!.currentVersion}\n'
        'Nova versão: ${update.latestVersion}\n\n'
        'Deseja baixar e instalar agora?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Agora não'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Atualizar'),
        ),
      ],
    ),
  );

  if (shouldUpdate != true || !context.mounted) return;

  await _downloadAndInstall(context, ref, update);
}

Future<void> _downloadAndInstall(
  BuildContext context,
  WidgetRef ref,
  OtaUpdateInfo update,
) async {
  final otaService = ref.read(otaServiceProvider);
  final otaInstaller = ref.read(otaInstallerProvider);
  final progress = ValueNotifier<double>(0);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Baixando atualização...'),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: value, color: AppTheme.accent),
            const SizedBox(height: 8),
            Text('${(value * 100).toStringAsFixed(0)}%'),
          ],
        ),
      ),
    ),
  );

  String apkPath;
  try {
    apkPath = await otaService.downloadApk(
      update.downloadUrl,
      onProgress: (value) => progress.value = value,
    );
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context).pop();
      _showError(context, 'Falha ao baixar atualização: $e');
    }
    return;
  }

  if (context.mounted) Navigator.of(context).pop();

  final installed = await otaInstaller.install(apkPath);
  if (!installed && context.mounted) {
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Permissão necessária'),
        content: const Text(
          'Para instalar a atualização, habilite "Instalar de fontes '
          'desconhecidas" para o PalioDash nas configurações do Android.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Abrir configurações'),
          ),
        ],
      ),
    );
    if (openSettings == true) {
      await otaInstaller.openInstallSettings();
    }
  }
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
