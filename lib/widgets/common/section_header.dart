import 'package:flutter/material.dart';
import '../../lang/translations.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;

  const SectionHeader({super.key, required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
      sliver: SliverToBoxAdapter(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onSeeAll != null)
              TextButton(
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: primary,
                ),
                child: Text(
                  t('see_all') ?? 'See All',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
