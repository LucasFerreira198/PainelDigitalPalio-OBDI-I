import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/obd2/obd2_service.dart';
import '../../shared/models/obd_data_model.dart';
import '../../shared/settings/app_settings.dart';
import '../../shared/settings/app_settings_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../diagnostics/test_obd_screen.dart';
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
  if (service == null) return;
  if (ref.read(connectingEcuProvider)) return;

  ref.read(connectingEcuProvider.notifier).state = true;

  try {
    final ok = await service.connectEcu();
    if (!service.isLoopRunning) {
      unawaited(service.startLoop());
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'ECU Marelli IAW 4AF conectada com sucesso!'
                : 'ECU não respondeu. Ligue a chave de ignição e tente novamente.',
          ),
          backgroundColor:
              ok ? Colors.green.shade800 : Colors.red.shade800,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao conectar à ECU: $e'),
          backgroundColor: Colors.red.shade800,
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
    final isLowFuel =
        data.fuelLevelPercent > 0 && data.fuelLevelPercent <= 15;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              if (isShiftLight || isOverheating || isLowBattery || isLowFuel)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: isOverheating
                        ? AppTheme.danger
                        : (isShiftLight
                            ? clusterTheme.accent
                            : isLowBattery
                                ? AppTheme.warning
                                : const Color(0xFFE65100)),
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
                                : isLowBattery
                                    ? Icons.battery_alert
                                    : Icons.local_gas_station),
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isOverheating
                            ? 'ALERTA: SUPERAQUECIMENTO (${tempUnit.convert(data.coolantTempC).toStringAsFixed(0)}${tempUnit.label})'
                            : (isShiftLight
                                ? '⚡ TROCA DE MARCHA (SHIFT LIGHT) ⚡'
                                : isLowBattery
                                    ? 'ALERTA: TENSÃO DE BATERIA BAIXA (${data.batteryV.toStringAsFixed(1)}V)'
                                    : 'ALERTA: NÍVEL DE COMBUSTÍVEL NA RESERVA (${data.fuelLevelPercent.toStringAsFixed(0)}%)'),
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
                      child: PidTile(
                        label: 'Lambda',
                        value: data.lambda > 0 ? data.lambda.toStringAsFixed(2) : '--',
                        unit: 'λ',
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
                          ? Consumer(
                              builder: (context, ref, _) {
                                final spots = ref.watch(rpmHistoryProvider);
                                return RpmChart(
                                  spots: spots,
                                  theme: clusterTheme,
                                );
                              },
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
                                        '${tempUnit.convert(data.intakeTempC).toStringAsFixed(0)} ${tempUnit.label}',
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
                                  Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.local_gas_station,
                                            size: 11,
                                            color: data.fuelLevelPercent > 0 &&
                                                    data.fuelLevelPercent <= 15
                                                ? AppTheme.warning
                                                : clusterTheme.accent,
                                          ),
                                          const SizedBox(width: 4),
                                          const Text(
                                            'COMBUSTÍVEL',
                                            style: TextStyle(
                                              color: Colors.white54,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        data.fuelLevelPercent > 0
                                            ? '${data.fuelLevelPercent.toStringAsFixed(0)}% (~${(data.fuelLevelPercent * 48.0 / 100.0).toStringAsFixed(0)}L)'
                                            : '--',
                                        style: AppTheme.digitalDisplay(
                                          fontSize: 18,
                                          color: data.fuelLevelPercent > 0 &&
                                                  data.fuelLevelPercent <= 15
                                              ? AppTheme.warning
                                              : Colors.white,
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
                                          ? Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                SizedBox(
                                                  width: compact ? 10 : 12,
                                                  height: compact ? 10 : 12,
                                                  child:
                                                      const CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: AppTheme.accent,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Conectando...',
                                                  style: TextStyle(
                                                    fontSize:
                                                        compact ? 8 : 10,
                                                    color: AppTheme.accent,
                                                  ),
                                                ),
                                              ],
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
                                    iconSize: compact ? 20.0 : 24.0,
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(
                                      Icons.terminal_rounded,
                                      color: AppTheme.accent,
                                    ),
                                    tooltip: 'Diagnóstico & Teste IAW 4AF',
                                    onPressed: () =>
                                        Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const TestObdScreen(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    iconSize: compact ? 20.0 : 24.0,
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(
                                      Icons.warning_amber,
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
                                    iconSize: compact ? 20.0 : 24.0,
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(
                                      Icons.settings,
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
