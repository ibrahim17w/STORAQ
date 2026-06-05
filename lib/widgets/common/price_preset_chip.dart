// lib/widgets/common/price_preset_chip.dart
import 'package:flutter/material.dart';

class PricePresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  const PricePresetChip({
    super.key,
    required this.label,
    required this.onTap,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          color: isActive
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurface,
        ),
      ),
      backgroundColor: isActive
          ? Theme.of(context).colorScheme.primary
          : Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      side: BorderSide(
        color: isActive
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline.withOpacity(0.2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      onPressed: onTap,
    );
  }
}
