import 'package:flutter/material.dart';

/// Unidade de velocidade
enum SpeedUnit { kmh, mph }

extension SpeedUnitConversion on SpeedUnit {
  String get label => this == SpeedUnit.kmh ? 'km/h' : 'mph';

  double convert(double speedKmh) =>
      this == SpeedUnit.kmh ? speedKmh : speedKmh * 0.621371;
}

/// Unidade de pressão (para MAP / coletor)
enum PressureUnit { kpa, bar, psi }

extension PressureUnitConversion on PressureUnit {
  String get label => switch (this) {
        PressureUnit.kpa => 'kPa',
        PressureUnit.bar => 'bar',
        PressureUnit.psi => 'psi',
      };

  double convert(double mapKpa) => switch (this) {
        PressureUnit.kpa => mapKpa,
        PressureUnit.bar => mapKpa / 100.0,
        PressureUnit.psi => mapKpa * 0.145038,
      };

  String format(double mapKpa) => switch (this) {
        PressureUnit.kpa => mapKpa.toStringAsFixed(0),
        PressureUnit.bar => convert(mapKpa).toStringAsFixed(2),
        PressureUnit.psi => convert(mapKpa).toStringAsFixed(1),
      };
}

/// Unidade de temperatura
enum TempUnit { celsius, fahrenheit }

extension TempUnitConversion on TempUnit {
  String get label => this == TempUnit.celsius ? '°C' : '°F';

  double convert(double tempC) =>
      this == TempUnit.celsius ? tempC : (tempC * 9 / 5) + 32;

  String format(double tempC) => convert(tempC).toStringAsFixed(0);
}

/// Esquemas de cores e temas visuais do cluster
enum ClusterTheme {
  fiatOrange,
  abarthRed,
  cyberBlue,
  toxicGreen,
  stealthOled,
}

extension ClusterThemeProperties on ClusterTheme {
  String get label => switch (this) {
        ClusterTheme.fiatOrange => 'Fiat Sport (Âmbar/Laranja)',
        ClusterTheme.abarthRed => 'Abarth Racing (Vermelho)',
        ClusterTheme.cyberBlue => 'Tech Cyan (Azul)',
        ClusterTheme.toxicGreen => 'Toxic Green (Verde)',
        ClusterTheme.stealthOled => 'Stealth OLED (Monocromático)',
      };

  Color get accent => switch (this) {
        ClusterTheme.fiatOrange => const Color(0xFFFF6A00),
        ClusterTheme.abarthRed => const Color(0xFFE53935),
        ClusterTheme.cyberBlue => const Color(0xFF00D2FF),
        ClusterTheme.toxicGreen => const Color(0xFF00E676),
        ClusterTheme.stealthOled => const Color(0xFFE0E0E0),
      };

  Color get needleColor => accent;

  Color get gaugeRing => switch (this) {
        ClusterTheme.fiatOrange => const Color(0x33FF6A00),
        ClusterTheme.abarthRed => const Color(0x33E53935),
        ClusterTheme.cyberBlue => const Color(0x3300D2FF),
        ClusterTheme.toxicGreen => const Color(0x3300E676),
        ClusterTheme.stealthOled => const Color(0x33FFFFFF),
      };

  Color get glow => accent.withOpacity(0.35);
}

/// Perfis de Motor do Fiat Palio extraídos do AlfaOBD
enum PalioEngineProfile {
  auto,
  fire10_13_8v,
  fireFlex10_14,
  fireEvo,
  etorq16v,
  standardObd,
}

extension PalioEngineProfileDetails on PalioEngineProfile {
  String get label => switch (this) {
        PalioEngineProfile.auto => 'Auto-Detectar ECU',
        PalioEngineProfile.fire10_13_8v => 'Palio Fire 1.0 / 1.3 8V (IAW 4AF/59F)',
        PalioEngineProfile.fireFlex10_14 => 'Palio Fire Flex 1.0 / 1.4 (IAW 4SF/4GF)',
        PalioEngineProfile.fireEvo => 'Palio Fire EVO 1.0 / 1.4 (IAW 7GF)',
        PalioEngineProfile.etorq16v => 'Palio 1.6 16V E.torQ (IAW 7GF / Delphi)',
        PalioEngineProfile.standardObd => 'OBD-II Padrão Universal (EOBD)',
      };

  String get ecuDescription => switch (this) {
        PalioEngineProfile.auto => 'Identificação automática na Linha K',
        PalioEngineProfile.fire10_13_8v => 'Marelli IAW 4AF / 59F • KWP2000 Fast Init',
        PalioEngineProfile.fireFlex10_14 => 'Marelli IAW 4SF / 4GF • KWP2000 Fast Init',
        PalioEngineProfile.fireEvo => 'Marelli IAW 7GF • KWP2000 / CAN 500k',
        PalioEngineProfile.etorq16v => 'Marelli IAW 7GF • KWP2000 / CAN',
        PalioEngineProfile.standardObd => 'SAE J1979 / ISO 15765-4',
      };
}
