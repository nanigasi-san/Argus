import 'package:flutter/material.dart';

/// Returns the clockwise turn from the device top to the target direction.
double relativeBearingDegrees({
  required double targetBearingDeg,
  required double deviceHeadingDeg,
}) {
  return (targetBearingDeg - deviceHeadingDeg + 360) % 360;
}

/// Shows the direction to the nearest boundary relative to the device heading.
class CompassNavigationCard extends StatelessWidget {
  const CompassNavigationCard({
    super.key,
    required this.targetBearingDeg,
    required this.deviceHeadingDeg,
    required this.distanceToBoundaryM,
    required this.compassAvailable,
  });

  final double? targetBearingDeg;
  final double? deviceHeadingDeg;
  final double? distanceToBoundaryM;
  final bool compassAvailable;

  @override
  Widget build(BuildContext context) {
    final target = targetBearingDeg;
    final heading = deviceHeadingDeg;
    final hasDirection = target != null && heading != null && compassAvailable;
    final relativeBearing = hasDirection
        ? relativeBearingDegrees(
            targetBearingDeg: target,
            deviceHeadingDeg: heading,
          )
        : 0.0;
    final signedDeviation =
        relativeBearing > 180 ? relativeBearing - 360 : relativeBearing;
    final isAligned = hasDirection && signedDeviation.abs() <= 30;
    final colors = Theme.of(context).colorScheme;
    final alignedColor = Colors.green;
    final guidanceColor = !hasDirection
        ? colors.onSurfaceVariant
        : isAligned
            ? alignedColor
            : colors.primary;
    final guidanceBackground = !hasDirection
        ? colors.surfaceContainerHighest
        : isAligned
            ? alignedColor.withValues(alpha: 0.1)
            : colors.primaryContainer;

    return Semantics(
      container: true,
      label: hasDirection
          ? isAligned
              ? 'コンパス案内。進行方向は範囲内です。画面上方向へ進んでください。'
              : 'コンパス案内。矢印が画面上部を向くまで端末を回してください。'
          : 'コンパス案内。端末コンパスを取得中です。',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            children: [
              Text(
                '境界へのナビゲーション',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                _formatDistance(distanceToBoundaryM),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                '最寄りの境界まで',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 18),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '↑ 画面上に矢印を合わせる',
                  style: TextStyle(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: 184,
                height: 184,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.surface,
                        border: Border.all(
                          color: guidanceColor.withValues(alpha: 0.65),
                          width: 3,
                        ),
                      ),
                    ),
                    const _CompassCardinalLabels(),
                    AnimatedRotation(
                      key: const Key('compassTargetArrow'),
                      turns: relativeBearing / 360,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      child: SizedBox(
                        width: 96,
                        height: 96,
                        child: CustomPaint(
                          painter: _DirectionArrowPainter(
                            color: guidanceColor,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.surface,
                        border: Border.all(color: guidanceColor, width: 2),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _GuidanceBanner(
                color: guidanceColor,
                backgroundColor: guidanceBackground,
                title: !hasDirection
                    ? target == null
                        ? '位置情報を取得中です'
                        : '端末コンパスを取得中です'
                    : isAligned
                        ? 'そのまま画面上方向へ進んでください'
                        : '端末を${signedDeviation > 0 ? '右' : '左'}へあと ${signedDeviation.abs().toStringAsFixed(0)}° 回してください',
                detail: !hasDirection
                    ? '方向を取得すると進行案内を開始します'
                    : isAligned
                        ? '進行方向の範囲内（±30°）です'
                        : '矢印が画面上を向いたら進んでください',
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDistance(double? distanceM) {
    if (distanceM == null) {
      return '-';
    }
    if (distanceM >= 1000) {
      return '${(distanceM / 1000).toStringAsFixed(2)} km';
    }
    return '${distanceM.toStringAsFixed(0)} m';
  }
}

class _GuidanceBanner extends StatelessWidget {
  const _GuidanceBanner({
    required this.color,
    required this.backgroundColor,
    required this.title,
    required this.detail,
  });

  final Color color;
  final Color backgroundColor;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _DirectionArrowPainter extends CustomPainter {
  const _DirectionArrowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 4)
      ..lineTo(size.width - 8, size.height * 0.55)
      ..lineTo(size.width * 0.64, size.height * 0.55)
      ..lineTo(size.width * 0.64, size.height - 4)
      ..lineTo(size.width * 0.36, size.height - 4)
      ..lineTo(size.width * 0.36, size.height * 0.55)
      ..lineTo(8, size.height * 0.55)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DirectionArrowPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _CompassCardinalLabels extends StatelessWidget {
  const _CompassCardinalLabels();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.bold,
        );
    return Stack(
      children: [
        Align(alignment: Alignment.topCenter, child: Text('N', style: style)),
        Align(
          alignment: Alignment.centerRight,
          child: Text('E', style: style),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Text('S', style: style),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('W', style: style),
        ),
      ],
    );
  }
}
