import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/bluetooth/bt_device_model.dart';
import '../../core/cloud/cloud_relay_service.dart';
import '../../core/diagnostics/diagnostics_provider.dart';
import '../../core/obd2/obd2_service.dart';
import '../../core/ota/ota_dialog.dart';
import '../../shared/settings/app_settings.dart';
import '../../shared/settings/app_settings_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../dashboard/dashboard_provider.dart';
import '../diagnostics/test_obd_screen.dart';
import 'settings_provider.dart';

Future<void> _connectToDevice(
  BuildContext context,
  WidgetRef ref,
  BtDeviceModel device,
) async {
  ref.read(connectingAddressProvider.notifier).state = device.address;
  try {
    final btManager = ref.read(btManagerProvider);
    await btManager.connect(device.address);

    // Inicializa o adaptador com o protocolo selecionado (ou KWP2000 Fast Init padrão Palio)
    final manualProtocol = ref.read(manualEcuProtocolProvider);
    final targetProtocol = manualProtocol ?? EcuProtocol.kwp2000FastInit;

    final obd2Service = Obd2Service(
      btManager,
      logSink: ref.read(remoteLogServiceProvider).log,
    );
    await obd2Service.setupAdapter(protocol: targetProtocol);
    await obd2Service.dispose();

    ref.read(dataSourceModeProvider.notifier).state = DataSourceMode.live;
    ref.read(obdReconnectTokenProvider.notifier).state++;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'OBD2 conectado a ${device.name}. Use "Conectar à ECU" no '
            'Dashboard.',
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao conectar a ${device.name}: $e')),
      );
    }
  } finally {
    ref.read(connectingAddressProvider.notifier).state = null;
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bondedDevicesAsync = ref.watch(bondedDevicesProvider);
    final localIpAsync = ref.watch(localIpProvider);
    final isServerRunning = ref.watch(wsServerRunningProvider);
    final speedUnit = ref.watch(speedUnitProvider);
    final tempUnit = ref.watch(tempUnitProvider);
    final pressureUnit = ref.watch(pressureUnitProvider);
    final clusterTheme = ref.watch(clusterThemeProvider);
    final shiftLightRpm = ref.watch(shiftLightRpmProvider);
    final overheatTemp = ref.watch(overheatTempProvider);
    final lowBatteryAlert = ref.watch(lowBatteryAlertProvider);
    final showRpmChart = ref.watch(showRpmChartProvider);
    final engineProfile = ref.watch(palioEngineProfileProvider);
    final dataSourceMode = ref.watch(dataSourceModeProvider);
    final connectingAddress = ref.watch(connectingAddressProvider);
    final cloudCode = ref.watch(cloudRelayCodeProvider);
    final manualProtocol = ref.watch(manualEcuProtocolProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Configurações do Painel'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // -----------------------------------------------------------
          // SEÇÃO 1: VEÍCULO & PERFIL PALIO
          // -----------------------------------------------------------
          _buildSectionHeader('Veículo & Injeção Eletrônica'),
          Card(
            color: AppTheme.surface,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<PalioEngineProfile>(
                    isExpanded: true,
                    initialValue: engineProfile,
                    dropdownColor: AppTheme.surface,
                    decoration: const InputDecoration(
                      labelText: 'Modelo do Palio / Motorização',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: UnderlineInputBorder(),
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    items: PalioEngineProfile.values
                        .map(
                          (profile) => DropdownMenuItem(
                            value: profile,
                            child: Text(
                              '${profile.displayName} (${profile.ecuModel})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(palioEngineProfileProvider.notifier)
                            .set(value);
                        // Ajusta shift light automaticamente para a faixa do motor
                        ref
                            .read(shiftLightRpmProvider.notifier)
                            .set((value.redlineRpm - 500).toDouble());
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ECU: ${engineProfile.ecuModel} • Faixa máx: ${engineProfile.maxRpm} RPM • Linha vermelha: ${engineProfile.redlineRpm} RPM',
                    style: TextStyle(
                      color: clusterTheme.accent,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // -----------------------------------------------------------
          // SEÇÃO 2: TEMA VISUAL DO CLUSTER
          // -----------------------------------------------------------
          _buildSectionHeader('Tema Visual dos Instrumentos'),
          Card(
            color: AppTheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: ClusterTheme.values.map((theme) {
                  final isSelected = theme == clusterTheme;
                  return InkWell(
                    onTap: () =>
                        ref.read(clusterThemeProvider.notifier).set(theme),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isSelected
                              ? theme.accent
                              : Colors.white12,
                          width: isSelected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        color: isSelected
                            ? theme.accent.withOpacity(0.15)
                            : Colors.transparent,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: theme.accent,
                              shape: BoxShape.circle,
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: theme.accent.withOpacity(0.6),
                                        blurRadius: 6,
                                      )
                                    ]
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            theme.label,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.white60,
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // -----------------------------------------------------------
          // SEÇÃO 3: ALERTAS DE SEGURANÇA
          // -----------------------------------------------------------
          _buildSectionHeader('Alertas & Avisos de Segurança'),
          Card(
            color: AppTheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Shift Light (Troca de marcha)',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      Text(
                        '${shiftLightRpm.toStringAsFixed(0)} RPM',
                        style: TextStyle(
                          color: clusterTheme.accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: shiftLightRpm,
                    min: 4000,
                    max: 7500,
                    divisions: 35,
                    activeColor: clusterTheme.accent,
                    label: '${shiftLightRpm.toStringAsFixed(0)} RPM',
                    onChanged: (val) => ref
                        .read(shiftLightRpmProvider.notifier)
                        .set(val.roundToDouble()),
                  ),
                  const Divider(color: Colors.white10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Alerta de Superaquecimento',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      Text(
                        '${tempUnit.convert(overheatTemp).toStringAsFixed(0)} ${tempUnit.label}',
                        style: const TextStyle(
                          color: AppTheme.danger,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: overheatTemp,
                    min: 90,
                    max: 120,
                    divisions: 30,
                    activeColor: AppTheme.danger,
                    label: '${overheatTemp.toStringAsFixed(0)} °C',
                    onChanged: (val) => ref
                        .read(overheatTempProvider.notifier)
                        .set(val),
                  ),
                  const Divider(color: Colors.white10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Aviso de Tensão Baixa da Bateria',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      Text(
                        '${lowBatteryAlert.toStringAsFixed(1)} V',
                        style: const TextStyle(
                          color: AppTheme.warning,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: lowBatteryAlert,
                    min: 11.0,
                    max: 12.5,
                    divisions: 15,
                    activeColor: AppTheme.warning,
                    label: '${lowBatteryAlert.toStringAsFixed(1)} V',
                    onChanged: (val) => ref
                        .read(lowBatteryAlertProvider.notifier)
                        .set(val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // -----------------------------------------------------------
          // SEÇÃO 4: UNIDADES DE MEDIDA
          // -----------------------------------------------------------
          _buildSectionHeader('Unidades de Medida'),
          Card(
            color: AppTheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Velocidade',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<SpeedUnit>(
                      segments: const [
                        ButtonSegment(value: SpeedUnit.kmh, label: Text('km/h')),
                        ButtonSegment(value: SpeedUnit.mph, label: Text('mph')),
                      ],
                      selected: {speedUnit},
                      onSelectionChanged: (s) =>
                          ref.read(speedUnitProvider.notifier).set(s.first),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Temperatura',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<TempUnit>(
                      segments: const [
                        ButtonSegment(value: TempUnit.celsius, label: Text('Celsius (°C)')),
                        ButtonSegment(value: TempUnit.fahrenheit, label: Text('Fahrenheit (°F)')),
                      ],
                      selected: {tempUnit},
                      onSelectionChanged: (s) =>
                          ref.read(tempUnitProvider.notifier).set(s.first),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Pressão do Coletor (MAP)',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<PressureUnit>(
                      segments: const [
                        ButtonSegment(value: PressureUnit.kpa, label: Text('kPa')),
                        ButtonSegment(value: PressureUnit.bar, label: Text('Bar')),
                        ButtonSegment(value: PressureUnit.psi, label: Text('PSI')),
                      ],
                      selected: {pressureUnit},
                      onSelectionChanged: (s) =>
                          ref.read(pressureUnitProvider.notifier).set(s.first),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // -----------------------------------------------------------
          // SEÇÃO 5: VISUALIZAÇÃO & GRÁFICOS
          // -----------------------------------------------------------
          _buildSectionHeader('Exibição da Telemetria'),
          Card(
            color: AppTheme.surface,
            child: SwitchListTile(
              title: const Text('Histórico de RPM em Tempo Real'),
              subtitle: const Text(
                'Alterna entre gráfico contínuo ou telemetria resumida',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              value: showRpmChart,
              activeThumbColor: clusterTheme.accent,
              onChanged: (val) =>
                  ref.read(showRpmChartProvider.notifier).set(val),
            ),
          ),
          const SizedBox(height: 20),

          // -----------------------------------------------------------
          // SEÇÃO 6: FONTE DE DADOS
          // -----------------------------------------------------------
          _buildSectionHeader('Fonte de Dados'),
          Card(
            color: AppTheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<DataSourceMode>(
                segments: const [
                  ButtonSegment(
                    value: DataSourceMode.simulation,
                    label: Text('Simulação'),
                  ),
                  ButtonSegment(
                    value: DataSourceMode.live,
                    label: Text('Bluetooth (ELM327)'),
                  ),
                ],
                selected: {dataSourceMode},
                onSelectionChanged: (selection) => ref
                    .read(dataSourceModeProvider.notifier)
                    .state = selection.first,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // -----------------------------------------------------------
          // SEÇÃO 7: PROTOCOLO DA ECU (BLOQUEADO E OTIMIZADO PARA PALIO FIRE)
          // -----------------------------------------------------------
          _buildSectionHeader('Protocolo da ECU (Específico Fiat Palio Fire)'),
          Card(
            color: AppTheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock_outline, color: clusterTheme.accent, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Protocolo Fixo do Palio Fire (AlfaOBD)',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'ECU: Marelli IAW 4AF/4EF/59F/5AF (4AF/4EF/59F/5AF EOBD)',
                    style: TextStyle(
                      color: clusterTheme.accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '• Inicialização: ISO 14230-4 KWP2000 Fast Init (ATSP5, ATIB10, ATSH8110F1)',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '• Handshake de Despertar: 1A 97 (Resposta 5A 97)',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '• Velocidade da Linha K: 10400 bps (Pino 7)',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.troubleshoot, size: 20),
                      label: const Text(
                        'ABRIR CENTRAL DE TESTE & DIAGNÓSTICO',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TestObdScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // -----------------------------------------------------------
          // SEÇÃO 8: BLUETOOTH PAREADO
          // -----------------------------------------------------------
          _buildSectionHeader('Adaptador OBD2 Bluetooth'),
          bondedDevicesAsync.when(
            data: (devices) {
              if (devices.isEmpty) {
                return const Text(
                  'Nenhum dispositivo pareado. Pareie o adaptador ELM327 '
                  'nas configurações Bluetooth do Android primeiro.',
                  style: TextStyle(color: Colors.white54),
                );
              }
              return Column(
                children: devices
                    .map(
                      (d) => Card(
                        color: AppTheme.surface,
                        child: ListTile(
                          leading: Icon(
                            Icons.bluetooth,
                            color: clusterTheme.accent,
                          ),
                          title: Text(d.name),
                          subtitle: Text(
                            d.address,
                            style: const TextStyle(color: Colors.white54),
                          ),
                          trailing: connectingAddress == d.address
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: clusterTheme.accent,
                                  ),
                                )
                              : const Icon(
                                  Icons.chevron_right,
                                  color: Colors.white38,
                                ),
                          onTap: connectingAddress != null
                              ? null
                              : () => _connectToDevice(context, ref, d),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
            loading: () => const CircularProgressIndicator(),
            error: (error, _) => Text(
              'Erro ao listar dispositivos: $error',
              style: const TextStyle(color: AppTheme.danger),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => ref.invalidate(bondedDevicesProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('Atualizar lista de dispositivos'),
          ),
          const SizedBox(height: 20),

          // -----------------------------------------------------------
          // SEÇÃO 9: WEBSOCKET & CLOUD RELAY
          // -----------------------------------------------------------
          _buildSectionHeader('PC Viewer & Espelhamento'),
          Card(
            color: AppTheme.surface,
            child: Column(
              children: [
                ListTile(
                  title: localIpAsync.when(
                    data: (ip) => Text(
                      ip != null ? 'ws://$ip:8765' : 'Sem rede Wi-Fi detectada',
                      style: AppTheme.digitalDisplay(fontSize: 16),
                    ),
                    loading: () => const Text('Detectando IP...'),
                    error: (_, __) => const Text('Erro ao detectar IP'),
                  ),
                  subtitle: const Text(
                    'Servidor local para o PC Viewer na mesma rede Wi-Fi',
                    style: TextStyle(color: Colors.white54),
                  ),
                  trailing: Switch(
                    value: isServerRunning,
                    activeThumbColor: clusterTheme.accent,
                    onChanged: (value) async {
                      final server = ref.read(wsServerProvider);
                      if (value) {
                        await server.start();
                      } else {
                        await server.stop();
                      }
                      ref.read(wsServerRunningProvider.notifier).state = value;
                    },
                  ),
                ),
                const Divider(color: Colors.white10),
                ListTile(
                  title: Text(
                    cloudCode ?? 'Desativado',
                    style: AppTheme.digitalDisplay(fontSize: 16),
                  ),
                  subtitle: const Text(
                    'Relé em nuvem (PC e celular em redes separadas)',
                    style: TextStyle(color: Colors.white54),
                  ),
                  trailing: Switch(
                    value: cloudCode != null,
                    activeThumbColor: clusterTheme.accent,
                    onChanged: (value) async {
                      final relay = ref.read(cloudRelayServiceProvider);
                      if (value) {
                        final code = CloudRelayService.generateCode();
                        await relay.startPublishing(code);
                        ref.read(cloudRelayCodeProvider.notifier).state = code;
                      } else {
                        relay.stopPublishing();
                        ref.read(cloudRelayCodeProvider.notifier).state = null;
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // -----------------------------------------------------------
          // SEÇÃO 10: ATUALIZAÇÕES
          // -----------------------------------------------------------
          _buildSectionHeader('Atualizações do Aplicativo'),
          OutlinedButton.icon(
            onPressed: () => checkAndPromptUpdate(context, ref),
            icon: const Icon(Icons.system_update),
            label: const Text('Verificar atualizações (OTA)'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
