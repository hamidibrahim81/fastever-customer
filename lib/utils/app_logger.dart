import 'package:flutter/foundation.dart';

/// App-wide logger
/// Logs only in DEBUG mode
/// Automatically disabled in RELEASE & PROFILE builds
void appLog(dynamic message, {String? tag}) {
  if (!kDebugMode) return;

  final output = tag != null
      ? '[${tag.toUpperCase()}] ${message.toString()}'
      : message.toString();

  debugPrint(output);
}
