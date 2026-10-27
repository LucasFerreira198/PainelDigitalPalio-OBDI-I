import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

import '../../../shared/settings/app_settings.dart';
import '../../../shared/theme/app_theme.dart';

class LambdaGauge extends StatelessWidget {
  final double lambda;
  final ClusterTheme? theme;

  const LambdaGauge({super.key, required this.lambda, this.theme});

  @override
  Widget build(BuildContext context) {
    final accent = theme?.accent ?? AppTheme.accent;

    return SfRadialGauge(
      axes: [
        RadialAxis(
          minimum: 0,
          maximum: 2,
          interval: 0.5,
          axisLineStyle: const AxisLineStyle(
            thickness: 0.15,
            thicknessUnit: GaugeSizeUnit.factor,
            color: AppTheme.gaugeIdle,
          ),
          majorTickStyle: const MajorTickStyle(color: Colors.white54),
          axisLabelStyle: const GaugeTextStyle(color: Colors.white70),
          pointers: [
            NeedlePointer(
              value: lambda.clamp(0, 2),
              needleColor: accent,
              knobStyle: KnobStyle(color: accent),
              animationType: AnimationType.linear,
              enableAnimation: true,
              animationDuration: 100,
            ),
          ],
          annotations: [
            GaugeAnnotation(
              positionFactor: 0.6,
              angle: 90,
              widget: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    lambda.toStringAsFixed(2),
                    style: AppTheme.digitalDisplay(fontSize: 24, color: accent),
                  ),
                  const Text(
                    'λ',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
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
