import 'dart:math' as math;

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
                    _CompassCardinalLabels(
                      headingDeg: compassAvailable ? heading ?? 0 : 0,
                    ),
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

/// Adds live cardinal labels and a large boundary pointer to the status circle.
class CompassStatusOverlay extends StatelessWidget {
  const CompassStatusOverlay({
    super.key,
    required this.targetBearingDeg,
    required this.deviceHeadingDeg,
    required this.compassAvailable,
  });

  final double? targetBearingDeg;
  final double? deviceHeadingDeg;
  final bool compassAvailable;

  @override
  Widget build(BuildContext context) {
    final heading = deviceHeadingDeg;
    final target = targetBearingDeg;
    final hasHeading = compassAvailable && heading != null;
    final hasDirection = hasHeading && target != null;
    final relative = hasDirection
        ? relativeBearingDegrees(
            targetBearingDeg: target, deviceHeadingDeg: heading)
        : 180.0;
    final aligned = hasDirection && (relative <= 30 || relative >= 330);
    final pointerColor =
        aligned ? Colors.green.shade800 : Theme.of(context).colorScheme.primary;
    final dialAngle = hasHeading ? -heading * math.pi / 180 : 0.0;
    final angle = hasDirection ? target * math.pi / 180 : 0.0;
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, constraints) {
        final size = constraints.maxWidth;
        final pointerSize = size * 0.23;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                key: const Key('compassForwardRange'),
                painter: _ForwardRangePainter(aligned: aligned),
              ),
            ),
            Positioned.fill(
              child: Transform.rotate(
                key: const Key('compassStatusDial'),
                angle: dialAngle,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (hasHeading)
                      for (final cardinal in const {
                        '北': 0,
                        '東': 90,
                        '南': 180,
                        '西': 270
                      }.entries)
                        Positioned(
                          left: size / 2 +
                              math.sin(cardinal.value * math.pi / 180) *
                                  size *
                                  0.60 -
                              18,
                          top: size / 2 -
                              math.cos(cardinal.value * math.pi / 180) *
                                  size *
                                  0.60 -
                              16,
                          child: Transform.rotate(
                            angle: -dialAngle,
                            child: SizedBox(
                              width: 36,
                              height: 32,
                              child: Center(
                                  child: Text(cardinal.key,
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black))),
                            ),
                          ),
                        ),
                    if (hasDirection)
                      Positioned(
                        left: size / 2 +
                            math.sin(angle) * size * 0.40 -
                            pointerSize / 2,
                        top: size / 2 -
                            math.cos(angle) * size * 0.40 -
                            pointerSize / 2,
                        child: Transform.rotate(
                          key: const Key('compassStatusPointer'),
                          angle: angle,
                          child: SizedBox(
                            width: pointerSize,
                            height: pointerSize,
                            child: CustomPaint(
                              painter: _DirectionArrowPainter(
                                color: pointerColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _CompassCardinalLabels extends StatelessWidget {
  const _CompassCardinalLabels({required this.headingDeg});

  final double headingDeg;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.bold,
        );
    return Stack(
      children: [
        for (final cardinal
            in const {'北': 0, '東': 90, '南': 180, '西': 270}.entries)
          Align(
            // Move the labels around the dial, keeping the text upright.
            alignment: Alignment(
              math.sin((cardinal.value - headingDeg) * math.pi / 180),
              -math.cos((cardinal.value - headingDeg) * math.pi / 180),
            ),
            child: Text(cardinal.key, style: style),
          ),
      ],
    );
  }
}

/// Fixed screen-forward acceptance range; the compass rotates beneath it.
class _ForwardRangePainter extends CustomPainter {
  const _ForwardRangePainter({required this.aligned});

  final bool aligned;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    const start = -math.pi / 2 - math.pi / 6;
    const sweep = math.pi / 3;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.91),
      start,
      sweep,
      false,
      Paint()
        ..color = Colors.green.withValues(alpha: aligned ? 0.65 : 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.16,
    );
    final outline = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = aligned ? 7 : 4;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius - 2), start,
        sweep, false, outline);
    for (final angle in [start, start + sweep]) {
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(center + direction * radius * 0.8,
          center + direction * (radius - 2), outline);
    }
  }

  @override
  bool shouldRepaint(_ForwardRangePainter oldDelegate) =>
      aligned != oldDelegate.aligned;
}
