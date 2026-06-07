import 'package:flutter/material.dart';
import '../../lang/translations.dart';

/// Home screen search field + filter control in a single row.
class HomeSearchBar extends StatelessWidget {
  final VoidCallback onSearchTap;
  final VoidCallback onFilterTap;
  final bool hasActiveFilters;

  const HomeSearchBar({
    super.key,
    required this.onSearchTap,
    required this.onFilterTap,
    this.hasActiveFilters = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Row(
      children: [
        Expanded(
          child: Material(
            color: theme.brightness == Brightness.dark
                ? theme.colorScheme.surfaceContainerLow
                : Colors.white,
            elevation: 0,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onSearchTap,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: theme.brightness == Brightness.dark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 14,
                            offset: const Offset(0, 3),
                          ),
                        ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      size: 22,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t('search') ?? 'Search',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: hasActiveFilters
                  ? theme.colorScheme.secondary
                  : primary,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: onFilterTap,
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(
                    Icons.tune_rounded,
                    color: theme.colorScheme.onPrimary,
                    size: 22,
                  ),
                ),
              ),
            ),
            if (hasActiveFilters)
              PositionedDirectional(
                top: -2,
                end: -2,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.scaffoldBackgroundColor,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
