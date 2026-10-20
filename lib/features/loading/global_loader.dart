import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class GlobalLoader {
  static final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(false);

  /// Shows the Lottie animation for at least [duration] (default 1.8s).
  static Future<T?> run<T>({
    Duration duration = const Duration(milliseconds: 1800),
    Future<T> Function()? task,
  }) async {
    _isLoading.value = true;
    try {
      if (task != null) {
        final results = await Future.wait([
          Future.delayed(duration),
          task(),
        ]);
        return results[1] as T?;
      } else {
        await Future.delayed(duration);
        return null;
      }
    } finally {
      _isLoading.value = false;
    }
  }

  static void show() => _isLoading.value = true;
  static void hide() => _isLoading.value = false;

  /// Global overlay wrapper
  static Widget wrapper(BuildContext context, Widget? child) {
    return Stack(
      children: [
        if (child != null) child,
        ValueListenableBuilder<bool>(
          valueListenable: _isLoading,
          builder: (context, loading, _) {
            if (!loading) return const SizedBox.shrink();

            // Fully solid background to block all underlying screen changes
            return Material(
              type: MaterialType.canvas,
              color: Colors.white,
              child: SizedBox.expand(
                child: Center(
                  child: SizedBox(
                    width: 230,
                    height: 230,
                    child: Lottie.asset(
                      'assets/loading.json',
                      fit: BoxFit.contain,
                      repeat: true,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}