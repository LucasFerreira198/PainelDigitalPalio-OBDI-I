import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';

const String _speedUnitKey = 'app_speed_unit';
const String _pressureUnitKey = 'app_pressure_unit';
const String _tempUnitKey = 'app_temp_unit';
const String _clusterThemeKey = 'app_cluster_theme';
const String _shiftLightRpmKey = 'app_shift_light_rpm';
const String _overheatTempKey = 'app_overheat_temp_c';
const String _lowBatteryKey = 'app_low_battery_v';
const String _showRpmChartKey = 'app_show_rpm_chart';
const String _palioProfileKey = 'app_palio_engine_profile';

/// Unidade de velocidade (km/h vs mph)
class SpeedUnitNotifier extends Notifier<SpeedUnit> {
  @override
  SpeedUnit build() {
    _load();
    return SpeedUnit.kmh;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_speedUnitKey);
    if (saved != null) {
      state = SpeedUnit.values.byName(saved);
    }
  }

  Future<void> set(SpeedUnit unit) async {
    state = unit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_speedUnitKey, unit.name);
  }
}

final speedUnitProvider = NotifierProvider<SpeedUnitNotifier, SpeedUnit>(
  SpeedUnitNotifier.new,
);

/// Unidade de pressão (kPa, Bar, PSI)
class PressureUnitNotifier extends Notifier<PressureUnit> {
  @override
  PressureUnit build() {
    _load();
    return PressureUnit.kpa;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_pressureUnitKey);
    if (saved != null) {
      state = PressureUnit.values.byName(saved);
    }
  }

  Future<void> set(PressureUnit unit) async {
    state = unit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pressureUnitKey, unit.name);
  }
}

final pressureUnitProvider =
    NotifierProvider<PressureUnitNotifier, PressureUnit>(
  PressureUnitNotifier.new,
);

/// Unidade de temperatura (°C vs °F)
class TempUnitNotifier extends Notifier<TempUnit> {
  @override
  TempUnit build() {
    _load();
    return TempUnit.celsius;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_tempUnitKey);
    if (saved != null) {
      state = TempUnit.values.byName(saved);
    }
  }

  Future<void> set(TempUnit unit) async {
    state = unit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tempUnitKey, unit.name);
  }
}

final tempUnitProvider = NotifierProvider<TempUnitNotifier, TempUnit>(
  TempUnitNotifier.new,
);

/// Tema visual do Cluster (Cores do painel)
class ClusterThemeNotifier extends Notifier<ClusterTheme> {
  @override
  ClusterTheme build() {
    _load();
    return ClusterTheme.fiatOrange;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_clusterThemeKey);
    if (saved != null) {
      state = ClusterTheme.values.byName(saved);
    }
  }

  Future<void> set(ClusterTheme theme) async {
    state = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clusterThemeKey, theme.name);
  }
}

final clusterThemeProvider =
    NotifierProvider<ClusterThemeNotifier, ClusterTheme>(
  ClusterThemeNotifier.new,
);

/// Ponto de Shift Light (RPM para troca de marcha)
class ShiftLightNotifier extends Notifier<double> {
  @override
  double build() {
    _load();
    return 5500.0;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_shiftLightRpmKey);
    if (saved != null) {
      state = saved;
    }
  }

  Future<void> set(double rpm) async {
    state = rpm;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_shiftLightRpmKey, rpm);
  }
}

final shiftLightRpmProvider =
    NotifierProvider<ShiftLightNotifier, double>(
  ShiftLightNotifier.new,
);

/// Limite de alerta de superaquecimento da água (°C)
class OverheatTempNotifier extends Notifier<double> {
  @override
  double build() {
    _load();
    return 100.0;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_overheatTempKey);
    if (saved != null) {
      state = saved;
    }
  }

  Future<void> set(double temp) async {
    state = temp;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_overheatTempKey, temp);
  }
}

final overheatTempProvider =
    NotifierProvider<OverheatTempNotifier, double>(
  OverheatTempNotifier.new,
);

/// Limite de alerta de bateria fraca (Volts)
class LowBatteryNotifier extends Notifier<double> {
  @override
  double build() {
    _load();
    return 11.8;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_lowBatteryKey);
    if (saved != null) {
      state = saved;
    }
  }

  Future<void> set(double volts) async {
    state = volts;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_lowBatteryKey, volts);
  }
}

final lowBatteryAlertProvider =
    NotifierProvider<LowBatteryNotifier, double>(
  LowBatteryNotifier.new,
);

/// Exibição do gráfico de RPM
class ShowRpmChartNotifier extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return true;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_showRpmChartKey);
    if (saved != null) {
      state = saved;
    }
  }

  Future<void> set(bool show) async {
    state = show;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showRpmChartKey, show);
  }
}

final showRpmChartProvider =
    NotifierProvider<ShowRpmChartNotifier, bool>(
  ShowRpmChartNotifier.new,
);

/// Perfil de motor Fiat Palio selecionado
class PalioEngineProfileNotifier extends Notifier<PalioEngineProfile> {
  @override
  PalioEngineProfile build() {
    _load();
    return PalioEngineProfile.auto;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_palioProfileKey);
    if (saved != null) {
      state = PalioEngineProfile.values.byName(saved);
    }
  }

  Future<void> set(PalioEngineProfile profile) async {
    state = profile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_palioProfileKey, profile.name);
  }
}

final palioEngineProfileProvider =
    NotifierProvider<PalioEngineProfileNotifier, PalioEngineProfile>(
  PalioEngineProfileNotifier.new,
);
