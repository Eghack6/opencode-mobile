import 'package:flutter/material.dart';

void showToast(BuildContext context, String message, {Color? bgColor}) {
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => Positioned(
      top: MediaQuery.of(ctx).padding.top + kToolbarHeight + 32,
      left: 0,
      right: 0,
      child: _ToastWidget(
        message: message,
        backgroundColor: bgColor,
        onDone: () => entry.remove(),
      ),
    ),
  );
  Overlay.of(context).insert(entry);
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final Color? backgroundColor;
  final VoidCallback onDone;
  const _ToastWidget({required this.message, this.backgroundColor, required this.onDone});

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDone());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: widget.backgroundColor ?? Colors.green,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(widget.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, decoration: TextDecoration.none)),
        ),
      ),
    );
  }
}
