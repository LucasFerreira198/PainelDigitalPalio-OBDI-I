import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

import '../../../shared/settings/app_settings.dart';
import '../../../shared/theme/app_theme.dart';

class SpeedGauge extends StatelessWidget {
  final double speedKmh;
  final SpeedUnit unit;
  final ClusterTheme theme;

  const SpeedGauge({
    super.key,
    required this.speedKmh,
    this.unit = SpeedUnit.kmh,
    this.theme = ClusterTheme.fiatOrange,
  });

  @override
  Widget build(BuildContext context) {
    final maxSpeed = unit == SpeedUnit.kmh ? 220.0 : 140.0;
    final displaySpeed = unit.convert(speedKmh);

    return SfRadialGauge(
      axes: [
        RadialAxis(
          minimum: 0,
          maximum: maxSpeed,
          interval: unit == SpeedUnit.kmh ? 20 : 20,
          startAngle: 140,
          endAngle: 40,
          axisLineStyle: AxisLineStyle(
            thickness: 0.12,
            thicknessUnit: GaugeSizeUnit.factor,
            color: theme.gaugeRing,
          ),
          majorTickStyle: const MajorTickStyle(
            color: Colors.white60,
            length: 8,
            thickness: 1.5,
          ),
          minorTickStyle: const MinorTickStyle(
            color: Colors.white24,
            length: 4,
            thickness: 1,
          ),
          axisLabelStyle: const GaugeTextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          pointers: [
            NeedlePointer(
              value: displaySpeed.clamp(0, maxSpeed),
              needleColor: theme.needleColor,
              knobStyle: KnobStyle(
                color: theme.needleColor,
                knobRadius: 0.08,
                borderColor: Colors.black,
                borderWidth: 2,
              ),
              needleLength: 0.8,
              needleStartWidth: 1,
              needleEndWidth: 4,
              animationType: AnimationType.ease,
              enableAnimation: true,
              animationDuration: 120,
            ),
          ],
          annotations: [
            GaugeAnnotation(
              positionFactor: 0.45,
              angle: 90,
              widget: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displaySpeed.toStringAsFixed(0),
                    style: AppTheme.digitalDisplay(
                      fontSize: 38,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    unit.label,
                    style: TextStyle(
                      color: theme.accent.withOpacity(0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
