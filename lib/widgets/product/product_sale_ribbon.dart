import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Corner ribbon banner for products on sale (use inside a [Stack]).
/// Looks like a diagonal red banner across the top-left corner.
class ProductSaleRibbon extends StatelessWidget {
  final String? label;
  final double size;

  const ProductSaleRibbon({super.key, this.label, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = label ?? 'SALE';
    final bannerWidth = size * 1.42;
    final bannerHeight = size * 0.22;
    final fontSize = size <= 40 ? 7.0 : 9.5;

    return Positioned(
      top: 0,
      left: 0,
      child: SizedBox(
        width: size,
        height: size,
        child: ClipRect(
          child: Stack(
            children: [
              Positioned(
                top: size * 0.18,
                left: -size * 0.22,
                child: Transform.rotate(
                  angle: -math.pi / 4,
                  child: Container(
                    width: bannerWidth,
                    height: bannerHeight,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      text,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
