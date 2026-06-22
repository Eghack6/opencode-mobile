import 'package:flutter/material.dart';

class ReasonBlock extends StatefulWidget {
  final String content;
  final bool defaultExpanded;

  const ReasonBlock({
    super.key,
    required this.content,
    this.defaultExpanded = false,
  });

  @override
  State<ReasonBlock> createState() => _ReasonBlockState();
}

class _ReasonBlockState extends State<ReasonBlock>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late Animation<double> _opacity;
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.defaultExpanded;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: _expanded ? 1.0 : 0.0,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);
    _opacity = Tween<double>(begin: 0, end: 1).animate(_animation);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_expanded) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.amber.withOpacity(0.08)
            : Colors.amber.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.amber.withOpacity(0.2) : Colors.amber.withOpacity(0.15),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.psychology, size: 16, color: theme.colorScheme.tertiary),
                  const SizedBox(width: 6),
                  Text(
                    '思考过程',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      size: 18,
                      color: theme.colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ClipRect(
            child: AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                return Align(
                  alignment: Alignment.topCenter,
                  heightFactor: _animation.value.clamp(0.0, 1.0),
                  child: Opacity(
                    opacity: _opacity.value,
                    child: child,
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: SelectableText(
                  widget.content,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: theme.colorScheme.onSurface.withOpacity(0.65),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
