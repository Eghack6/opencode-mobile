// Add this method to your ChatProvider class in chat_provider.dart
// It handles SSE reconnection when returning from iOS background

/// Reconnect SSE event stream (call when app resumes from background on iOS)
void reconnectEvents() {
  if (!_isConnected) return;
  _log('Reconnecting SSE after app resume...');
  _connectEvents();
}
