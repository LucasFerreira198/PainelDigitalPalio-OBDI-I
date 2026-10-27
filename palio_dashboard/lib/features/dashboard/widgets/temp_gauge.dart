import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

import '../../../shared/settings/app_settings.dart';
import '../../../shared/theme/app_theme.dart';

class TempGauge extends StatelessWidget {
  final double tempC;
  final TempUnit unit;
  final ClusterTheme theme;
  final double overheatThreshold;

  const TempGauge({
    super.key,
    required this.tempC,
    this.unit = TempUnit.celsius,
    this.theme = ClusterTheme.fiatOrange,
    this.overheatThreshold = 100.0,
  });

  bool get _isOverheating => tempC >= overheatThreshold;

  @override
  Widget build(BuildContext context) {
    final activeColor = _isOverheating ? AppTheme.danger : theme.needleColor;
    final minVal = unit == TempUnit.celsius ? 40.0 : 100.0;
    final maxVal = unit == TempUnit.celsius ? 130.0 : 260.0;
    final displayTemp = unit.convert(tempC);

    return SfRadialGauge(
      axes: [
        RadialAxis(
          minimum: minVal,
          maximum: maxVal,
          interval: unit == TempUnit.celsius ? 20 : 40,
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
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
          ranges: [
            GaugeRange(
              startValue: unit.convert(82.0),
              endValue: unit.convert(95.0),
              color: AppTheme.success.withOpacity(0.4),
              startWidth: 0.12,
              endWidth: 0.12,
              sizeUnit: GaugeSizeUnit.factor,
            ),
            GaugeRange(
              startValue: unit.convert(overheatThreshold),
              endValue: maxVal,
              color: AppTheme.danger,
              startWidth: 0.12,
              endWidth: 0.12,
              sizeUnit: GaugeSizeUnit.factor,
            ),
          ],
          pointers: [
            NeedlePointer(
              value: displayTemp.clamp(minVal, maxVal),
              needleColor: activeColor,
              knobStyle: KnobStyle(
                color: activeColor,
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
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 150),
                    style: AppTheme.digitalDisplay(
                      fontSize: 30,
                      color: _isOverheating ? AppTheme.danger : Colors.white,
                    ),
                    child: Text(displayTemp.toStringAsFixed(0)),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isOverheating) ...[
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: AppTheme.danger,
                          size: 12,
                        ),
                        const SizedBox(width: 2),
                      ],
                      Text(
                        'ÁGUA ${unit.label}',
                        style: TextStyle(
                          color: _isOverheating
                              ? AppTheme.danger
                              : Colors.white54,
                          fontSize: 10,
                          fontWeight: _isOverheating
                              ? FontWeight.bold
                              : FontWeight.normal,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
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
