import 'package:flutter/material.dart';

import '../../../shared/settings/app_settings.dart';
import '../../../shared/theme/app_theme.dart';

class PidTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData? icon;
  final bool isWarning;
  final Color? accentColor;
  final ClusterTheme? theme;

  const PidTile({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    this.icon,
    bool isWarning = false,
    bool? warning,
    this.accentColor,
    this.theme,
  }) : isWarning = warning ?? isWarning;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = isWarning
        ? AppTheme.danger
        : (accentColor ?? theme?.accent ?? Colors.white);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isWarning
              ? AppTheme.danger.withOpacity(0.8)
              : AppTheme.cardBorder,
          width: isWarning ? 1.5 : 1.0,
        ),
        boxShadow: isWarning
            ? [
                BoxShadow(
                  color: AppTheme.danger.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                )
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 11,
                  color: isWarning ? AppTheme.danger : Colors.white54,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: isWarning ? AppTheme.danger : Colors.white60,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: AppTheme.digitalDisplay(
                    fontSize: 20,
                    color: effectiveColor,
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 3),
                  Text(
                    unit,
                    style: TextStyle(
                      color: isWarning ? AppTheme.danger : Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
