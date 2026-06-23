// ios_lifecycle_mixin.dart
// Add this to your ChatProvider or create a separate mixin
// Handles SSE reconnection when app returns from background on iOS

import 'package:flutter/widgets.dart';

mixin AppLifecycleMixin on ChangeNotifier {
  final List<VoidCallback> _onResumeCallbacks = [];

  void addOnResumeCallback(VoidCallback callback) {
    _onResumeCallbacks.add(callback);
  }

  void removeOnResumeCallback(VoidCallback callback) {
    _onResumeCallbacks.remove(callback);
  }

  void onResumeFromBackground() {
    for (final cb in _onResumeCallbacks) {
      cb();
    }
  }
}

/// Wrap your ChatProvider with this observer to handle iOS background suspension
class AppLifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onResume;

  AppLifecycleObserver({required this.onResume});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume();
    }
  }
}

/// Usage in your app.dart or main.dart:
///
/// ```dart
/// class _MyAppState extends State<MyApp> {
///   late AppLifecycleObserver _lifecycleObserver;
///
///   @override
///   void initState() {
///     super.initState();
///     final chatProvider = context.read<ChatProvider>();
///     _lifecycleObserver = AppLifecycleObserver(
///       onResume: () {
///         // Reconnect SSE if it was dropped while in background
///         chatProvider.reconnectEvents();
///       },
///     );
///     WidgetsBinding.instance.addObserver(_lifecycleObserver);
///   }
///
///   @override
///   void dispose() {
///     WidgetsBinding.instance.removeObserver(_lifecycleObserver);
///     super.dispose();
///   }
/// }
/// ```
