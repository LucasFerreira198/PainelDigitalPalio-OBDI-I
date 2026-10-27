import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/obd2/obd2_service.dart';
import '../../shared/models/obd_data_model.dart';
import '../../shared/settings/app_settings.dart';
import '../../shared/settings/app_settings_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../dtc/dtc_screen.dart';
import '../settings/settings_screen.dart';
import 'dashboard_provider.dart';
import 'rpm_history_provider.dart';
import 'widgets/lambda_gauge.dart';
import 'widgets/pid_tile.dart';
import 'widgets/rpm_chart.dart';
import 'widgets/rpm_gauge.dart';
import 'widgets/speed_gauge.dart';
import 'widgets/temp_gauge.dart';

Future<void> _connectEcu(BuildContext context, WidgetRef ref) async {
  final service = ref.read(currentObd2ServiceProvider);
  if (service == null || service.isLoopRunning) return;

  ref.read(connectingEcuProvider.notifier).state = true;
  try {
    final manualProtocol = ref.read(manualEcuProtocolProvider);
    EcuProtocol? protocol;
    if (manualProtocol != null) {
      final ok = await service.connectEcuViaProtocol(manualProtocol);
      protocol = ok ? manualProtocol : null;
    } else {
      protocol = await service.connectEcuAutoDetect();
    }
    if (protocol != null) {
      unawaited(service.startLoop());
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            protocol != null
                ? 'ECU conectada via ${protocol.displayLabel}'
                : manualProtocol != null
                    ? '${manualProtocol.displayLabel} não respondeu '
                        '(verifique a ignição)'
                    : 'ECU não respondeu em nenhum protocolo (verifique a '
                        'ignição)',
          ),
        ),
      );
    }
  } finally {
    ref.read(connectingEcuProvider.notifier).state = false;
  }
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final obdAsync = ref.watch(obdDataProvider);
    final data = obdAsync.value ?? OBDDataModel.empty();
    final rpmHistory = ref.watch(rpmHistoryProvider);
    final speedUnit = ref.watch(speedUnitProvider);
    final tempUnit = ref.watch(tempUnitProvider);
    final pressureUnit = ref.watch(pressureUnitProvider);
    final clusterTheme = ref.watch(clusterThemeProvider);
    final shiftLightRpm = ref.watch(shiftLightRpmProvider);
    final overheatTemp = ref.watch(overheatTempProvider);
    final lowBatteryAlert = ref.watch(lowBatteryAlertProvider);
    final showRpmChart = ref.watch(showRpmChartProvider);
    final engineProfile = ref.watch(palioEngineProfileProvider);
    final connectingEcu = ref.watch(connectingEcuProvider);

    final canConnectEcu =
        data.btStatus == ConnectionStatus.connected && !data.ecuResponding;

    final isShiftLight = data.rpm >= shiftLightRpm && data.rpm > 1000;
    final isOverheating =
        data.coolantTempC >= overheatTemp && data.coolantTempC > 0;
    final isLowBattery =
        data.batteryV > 0 && data.batteryV < lowBatteryAlert;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              if (isShiftLight || isOverheating || isLowBattery)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: isOverheating
                        ? AppTheme.danger
                        : (isShiftLight
                            ? clusterTheme.accent
                            : AppTheme.warning),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isOverheating
                            ? Icons.local_fire_department
                            : (isShiftLight
                                ? Icons.flash_on
                                : Icons.battery_alert),
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isOverheating
                            ? 'ALERTA: SUPERAQUECIMENTO (${tempUnit.convert(data.coolantTempC).toStringAsFixed(0)}${tempUnit.label})'
                            : (isShiftLight
                                ? '⚡ TROCA DE MARCHA (SHIFT LIGHT) ⚡'
                                : 'ALERTA: TENSÃO DE BATERIA BAIXA (${data.batteryV.toStringAsFixed(1)}V)'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    Expanded(
                      child: RpmGauge(
                        rpm: data.rpm,
                        shiftLightRpm: shiftLightRpm,
                        maxRpm: engineProfile.maxRpm.toDouble(),
                        redlineRpm: engineProfile.redlineRpm.toDouble(),
                        theme: clusterTheme,
                      ),
                    ),
                    Expanded(
                      child: SpeedGauge(
                        speedKmh: data.speedKmh,
                        unit: speedUnit,
                        theme: clusterTheme,
                      ),
                    ),
                    Expanded(
                      child: TempGauge(
                        tempC: data.coolantTempC,
                        unit: tempUnit,
                        theme: clusterTheme,
                        overheatThreshold: overheatTemp,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Expanded(
                      child: PidTile(
                        label: 'TPS',
                        value: data.tpsPercent.toStringAsFixed(0),
                        unit: '%',
                        theme: clusterTheme,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: PidTile(
                        label: 'MAP',
                        value: pressureUnit
                            .convert(data.mapKpa)
                            .toStringAsFixed(
                              pressureUnit == PressureUnit.kpa ? 0 : 2,
                            ),
                        unit: pressureUnit.label,
                        theme: clusterTheme,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: LambdaGauge(
                        lambda: data.lambda,
                        theme: clusterTheme,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: PidTile(
                        label: 'Injeção',
                        value: data.injectionMs.toStringAsFixed(1),
                        unit: 'ms',
                        theme: clusterTheme,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: PidTile(
                        label: 'Avanço',
                        value: data.ignitionDeg.toStringAsFixed(0),
                        unit: '°',
                        theme: clusterTheme,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: PidTile(
                        label: 'Bateria',
                        value: data.batteryV > 0
                            ? data.batteryV.toStringAsFixed(1)
                            : '--',
                        unit: 'V',
                        warning: isLowBattery,
                        theme: clusterTheme,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: showRpmChart
                          ? RpmChart(
                              spots: rpmHistory,
                              theme: clusterTheme,
                            )
                          : Container(
                              decoration: AppTheme.cockpitCardDecoration(
                                borderColor: clusterTheme.accent.withOpacity(0.3),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        engineProfile.displayName,
                                        style: TextStyle(
                                          color: clusterTheme.accent,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        'ECU: ${engineProfile.ecuModel}',
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      const Text(
                                        'AR ADM (IAT)',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 10,
                                        ),
                                      ),
                                      Text(
                                        '${tempUnit.convert(data.intakeAirTempC).toStringAsFixed(0)} ${tempUnit.label}',
                                        style: AppTheme.digitalDisplay(
                                          fontSize: 18,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      const Text(
                                        'REDLINE',
                                        style: TextStyle(
                                          color: Colors.white54,
                                          fontSize: 10,
                                        ),
                                      ),
                                      Text(
                                        '${engineProfile.redlineRpm} RPM',
                                        style: AppTheme.digitalDisplay(
                                          fontSize: 18,
                                          color: AppTheme.gaugeDanger,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, sideConstraints) {
                          final compact = sideConstraints.maxHeight < 110;
                          final iconSize = compact ? 18.0 : 24.0;

                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 2,
                                children: [
                                  _StatusBadge(
                                    label: 'OBD2',
                                    status: data.btStatus,
                                  ),
                                  _EcuStatusBadge(
                                    responding: data.ecuResponding,
                                  ),
                                  if (data.ecuProtocolLabel != null)
                                    Text(
                                      data.ecuProtocolLabel!,
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 10,
                                      ),
                                    ),
                                ],
                              ),
                              SizedBox(height: compact ? 2 : 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (canConnectEcu)
                                    Expanded(
                                      child: connectingEcu
                                          ? const Center(
                                              child: SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: AppTheme.accent,
                                                ),
                                              ),
                                            )
                                          : TextButton(
                                              style: TextButton.styleFrom(
                                                padding: EdgeInsets.zero,
                                                minimumSize: Size.zero,
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                              onPressed: () =>
                                                  _connectEcu(context, ref),
                                              child: Text(
                                                'Conectar à ECU',
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize:
                                                      compact ? 9 : 11,
                                                ),
                                              ),
                                            ),
                                    ),
                                  IconButton(
                                    iconSize: iconSize,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(
                                      Icons.warning_amber,
                                      size: iconSize,
                                      color: Colors.white54,
                                    ),
                                    tooltip: 'Códigos de falha',
                                    onPressed: () =>
                                        Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const DtcScreen(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    iconSize: iconSize,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(
                                      Icons.settings,
                                      size: iconSize,
                                      color: Colors.white54,
                                    ),
                                    tooltip: 'Configurações',
                                    onPressed: () =>
                                        Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const SettingsScreen(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EcuStatusBadge extends StatelessWidget {
  final bool responding;

  const _EcuStatusBadge({required this.responding});

  @override
  Widget build(BuildContext context) {
    final color = responding ? AppTheme.gaugeNormal : AppTheme.gaugeDanger;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 12, color: color),
          const SizedBox(width: 6),
          const Text('ECU', style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final ConnectionStatus status;

  const _StatusBadge({required this.label, required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case ConnectionStatus.connected:
        color = AppTheme.gaugeNormal;
      case ConnectionStatus.connecting:
        color = AppTheme.gaugeWarning;
      case ConnectionStatus.disconnected:
        color = AppTheme.gaugeDanger;
    }

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 12, color: color),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}
