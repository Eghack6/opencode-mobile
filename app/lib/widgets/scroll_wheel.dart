import 'package:flutter/material.dart';

class ScrollWheel extends StatefulWidget {
  final int itemCount;
  final int activeIndex;
  final ValueChanged<int> onIndexChanged;
  final Color themeColor;

  const ScrollWheel({
    super.key,
    required this.itemCount,
    required this.activeIndex,
    required this.onIndexChanged,
    required this.themeColor,
  });

  @override
  State<ScrollWheel> createState() => _ScrollWheelState();
}

class _ScrollWheelState extends State<ScrollWheel> {
  static const double _lineHeight = 2;
  static const double _lineSpacing = 10;
  static const double _wheelWidth = 28;
  static const double _activeWidth = 16;
  static const double _inactiveWidth = 8;
  static const double _snapDistance = 28;

  double _accumulatedDelta = 0;
  int _displayIndex = 0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _displayIndex = widget.activeIndex;
  }

  @override
  void didUpdateWidget(ScrollWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging) {
      _displayIndex = widget.activeIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.itemCount;
    if (total <= 1) return const SizedBox(width: _wheelWidth);

    final totalHeight = total * _lineHeight + (total - 1) * _lineSpacing;

    return GestureDetector(
      onVerticalDragStart: (_) {
        _isDragging = true;
        _accumulatedDelta = 0;
      },
      onVerticalDragUpdate: (details) {
        _accumulatedDelta += details.delta.dy;
        if (_accumulatedDelta.abs() >= _snapDistance) {
          final direction = _accumulatedDelta > 0 ? 1 : -1;
          final newIndex = (_displayIndex + direction).clamp(0, total - 1);
          if (newIndex != _displayIndex) {
            setState(() => _displayIndex = newIndex);
            widget.onIndexChanged(newIndex);
          }
          _accumulatedDelta = 0;
        }
      },
      onVerticalDragEnd: (_) {
        _isDragging = false;
        _accumulatedDelta = 0;
      },
      onVerticalDragCancel: () {
        _isDragging = false;
        _accumulatedDelta = 0;
        _displayIndex = widget.activeIndex;
      },
      child: Container(
        width: _wheelWidth,
        color: Colors.transparent,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(total, (i) {
            final isActive = i == _displayIndex;
            return Padding(
              padding: EdgeInsets.symmetric(vertical: _lineSpacing / 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: isActive ? _activeWidth : _inactiveWidth,
                height: _lineHeight,
                decoration: BoxDecoration(
                  color: isActive
                      ? widget.themeColor
                      : widget.themeColor.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
