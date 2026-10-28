import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

import '../../../shared/settings/app_settings.dart';
import '../../../shared/theme/app_theme.dart';

class RpmGauge extends StatelessWidget {
  final double rpm;
  final ClusterTheme theme;
  final double shiftLightRpm;
  final double maxRpm;
  final double redlineRpm;

  const RpmGauge({
    super.key,
    required this.rpm,
    this.theme = ClusterTheme.fiatOrange,
    this.shiftLightRpm = 5500.0,
    this.maxRpm = 8000.0,
    this.redlineRpm = 6500.0,
  });

  bool get _isShiftLight => rpm >= shiftLightRpm && shiftLightRpm > 0;

  @override
  Widget build(BuildContext context) {
    final activeColor = _isShiftLight ? AppTheme.danger : theme.accent;
    final effectiveMax = maxRpm > 0 ? maxRpm : 8000.0;
    final effectiveRedline = redlineRpm > 0 ? redlineRpm : 6500.0;

    return SfRadialGauge(
      axes: [
        RadialAxis(
          minimum: 0,
          maximum: effectiveMax,
          interval: 1000,
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
          ranges: [
            GaugeRange(
              startValue: 0,
              endValue: 1000,
              color: AppTheme.gaugeIdle.withOpacity(0.5),
              startWidth: 0.12,
              endWidth: 0.12,
              sizeUnit: GaugeSizeUnit.factor,
            ),
            GaugeRange(
              startValue: 1000,
              endValue: 4000,
              color: theme.accent.withOpacity(0.4),
              startWidth: 0.12,
              endWidth: 0.12,
              sizeUnit: GaugeSizeUnit.factor,
            ),
            GaugeRange(
              startValue: 4000,
              endValue: shiftLightRpm.clamp(4000, effectiveMax),
              color: AppTheme.warning.withOpacity(0.8),
              startWidth: 0.12,
              endWidth: 0.12,
              sizeUnit: GaugeSizeUnit.factor,
            ),
            GaugeRange(
              startValue: effectiveRedline.clamp(4000, effectiveMax),
              endValue: effectiveMax,
              color: AppTheme.danger,
              startWidth: 0.12,
              endWidth: 0.12,
              sizeUnit: GaugeSizeUnit.factor,
            ),
          ],
          pointers: [
            NeedlePointer(
              value: rpm.clamp(0, effectiveMax),
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
              animationType: AnimationType.linear,
              enableAnimation: true,
              animationDuration: 50,
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
                      fontSize: 32,
                      color: _isShiftLight ? AppTheme.danger : Colors.white,
                    ),
                    child: Text(rpm.toStringAsFixed(0)),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isShiftLight ? 'SHIFT' : 'RPM',
                        style: TextStyle(
                          color: _isShiftLight
                              ? AppTheme.danger
                              : Colors.white54,
                          fontSize: 12,
                          fontWeight: _isShiftLight
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
