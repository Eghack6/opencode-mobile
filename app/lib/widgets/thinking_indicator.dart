import 'package:flutter/material.dart';

class ThinkingIndicator extends StatefulWidget {
  final bool showThinking;

  const ThinkingIndicator({super.key, this.showThinking = true});

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.secondaryContainer,
            child: Icon(Icons.smart_toy,
                size: 16, color: theme.colorScheme.onSecondaryContainer),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...List.generate(3, (i) {
                        return Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 2),
                          child: Dot(
                            delay: i * 200,
                            controller: _controller,
                          ),
                        );
                      }),
                      const SizedBox(width: 8),
                      Text(
                        '正在思考...',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface
                              .withOpacity(0.5),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Dot extends StatelessWidget {
  final int delay;
  final AnimationController controller;

  const Dot({super.key, required this.delay, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = ((controller.value * 1200 - delay) % 1200) / 1200;
        final opacity = (t < 0.3)
            ? 0.3 + t * 2.33
            : (t < 0.6)
                ? 1.0
                : 1.0 - (t - 0.6) * 2.5;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(
                  opacity.clamp(0.3, 1.0),
                ),
          ),
        );
      },
    );
  }
}
