import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_shapes.dart';

abstract final class FeatureGuideEligibility {
  static bool shouldOpenAutomatically({
    required bool completedOnboardingThisSession,
    required bool wasAlreadyShown,
  }) => completedOnboardingThisSession && !wasAlreadyShown;
}

/// A contextual coach mark shown over HomeWallet's real interface.
///
/// The target rectangle is measured by [HomeShell] after every navigation
/// change. This widget only presents the spotlight and explanatory bubble, so
/// it can also be exercised independently in widget tests.
class AppGuideOverlay extends StatelessWidget {
  const AppGuideOverlay({
    super.key,
    required this.targetRect,
    required this.currentStep,
    required this.totalSteps,
    required this.icon,
    required this.title,
    required this.description,
    required this.onNext,
    required this.onSkip,
    this.onPrevious,
  });

  final Rect targetRect;
  final int currentStep;
  final int totalSteps;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback? onPrevious;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final last = currentStep == totalSteps - 1;
    return BlockSemantics(
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final safeTarget = Rect.fromLTRB(
              targetRect.left.clamp(8, size.width - 8),
              targetRect.top.clamp(8, size.height - 8),
              targetRect.right.clamp(8, size.width - 8),
              targetRect.bottom.clamp(8, size.height - 8),
            );
            final spotlight = safeTarget.inflate(7);
            final placeAbove = spotlight.center.dy > size.height * .54;
            final bubbleWidth = math.min(360.0, size.width - 32);
            final halfBubble = bubbleWidth / 2;
            final horizontalCenter = spotlight.center.dx.clamp(
              halfBubble + 16,
              size.width - halfBubble - 16,
            );
            return Stack(
              children: [
                const ModalBarrier(
                  dismissible: false,
                  color: Colors.transparent,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _SpotlightPainter(
                        target: spotlight,
                        scrim: Colors.black.withValues(alpha: .76),
                        border: colors.primary,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: horizontalCenter - halfBubble,
                  width: bubbleWidth,
                  top: placeAbove ? null : spotlight.bottom + 14,
                  bottom: placeAbove ? size.height - spotlight.top + 14 : null,
                  child: _GuideBubble(
                    currentStep: currentStep,
                    totalSteps: totalSteps,
                    icon: icon,
                    title: title,
                    description: description,
                    onPrevious: onPrevious,
                    onNext: onNext,
                    onSkip: onSkip,
                    last: last,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GuideBubble extends StatelessWidget {
  const _GuideBubble({
    required this.currentStep,
    required this.totalSteps,
    required this.icon,
    required this.title,
    required this.description,
    required this.onPrevious,
    required this.onNext,
    required this.onSkip,
    required this.last,
  });

  final int currentStep;
  final int totalSteps;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Guía, paso ${currentStep + 1} de $totalSteps',
      container: true,
      child: Material(
        color: colors.surface,
        elevation: 14,
        shadowColor: Colors.black54,
        shape: const RoundedRectangleBorder(
          borderRadius: AppShapes.extraLargeRadius,
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: colors.primaryContainer,
                    foregroundColor: colors.primary,
                    child: Icon(icon, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'PASO ${currentStep + 1} DE $totalSteps',
                      key: const Key('guide_step_counter'),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .6,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const Key('guide_skip_button'),
                    onPressed: onSkip,
                    child: const Text('Omitir'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                key: const Key('guide_step_title'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 7),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.4,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: List.generate(
                  totalSteps,
                  (index) => Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 4,
                      margin: EdgeInsets.only(
                        right: index == totalSteps - 1 ? 0 : 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            index <= currentStep
                                ? colors.primary
                                : colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  if (onPrevious != null)
                    IconButton.outlined(
                      key: const Key('guide_previous_button'),
                      tooltip: 'Paso anterior',
                      onPressed: onPrevious,
                      icon: const Icon(Icons.arrow_back),
                    ),
                  if (onPrevious != null) const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('guide_next_button'),
                      onPressed: onNext,
                      icon: Icon(
                        last ? Icons.check : Icons.arrow_forward,
                        size: 20,
                      ),
                      label: Text(last ? 'Finalizar' : 'Siguiente'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({
    required this.target,
    required this.scrim,
    required this.border,
  });

  final Rect target;
  final Color scrim;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final targetRRect = RRect.fromRectAndRadius(
      target,
      const Radius.circular(18),
    );
    final scrimPath =
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & size)
          ..addRRect(targetRRect);
    canvas.drawPath(scrimPath, Paint()..color = scrim);
    canvas.drawRRect(
      targetRRect,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.target != target ||
      oldDelegate.scrim != scrim ||
      oldDelegate.border != border;
}
