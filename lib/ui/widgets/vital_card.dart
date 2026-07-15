import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// A glassmorphism vital-sign card.
///
/// Shows a large animated number, unit label, icon, and label text.
class VitalCard extends StatelessWidget {
  const VitalCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.accentColor,
    this.subtitle,
    this.isAlert = false,
    this.onTap,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color accentColor;
  final String? subtitle;
  final bool isAlert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget cardContent = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        decoration: BoxDecoration(
          color: isAlert
              ? const Color(0x33E53935)
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isAlert
                ? const Color(0xAAE53935)
                : accentColor.withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.15),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: accentColor, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Value
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      color: isAlert ? const Color(0xFFFF6B6B) : Theme.of(context).colorScheme.onSurface,
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      letterSpacing: -1,
                    ),
                  )
                      .animate(key: ValueKey(value))
                      .fadeIn(duration: 250.ms)
                      .slideY(begin: 0.15, end: 0, duration: 250.ms),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      unit,
                      style: TextStyle(
                        color: accentColor.withValues(alpha: 0.85),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          splashColor: accentColor.withValues(alpha: 0.2),
          highlightColor: accentColor.withValues(alpha: 0.1),
          child: cardContent,
        ),
      ),
    );
  }
}
