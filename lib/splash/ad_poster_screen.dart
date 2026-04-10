import 'dart:async';
import 'package:flutter/material.dart';

class AdPosterScreen extends StatefulWidget {
  final String imageUrl;
  final Widget nextScreen;

  const AdPosterScreen({
    Key? key,
    required this.imageUrl,
    required this.nextScreen,
  }) : super(key: key);

  @override
  State<AdPosterScreen> createState() => _AdPosterScreenState();
}

class _AdPosterScreenState extends State<AdPosterScreen> {
  Timer? _timer;
  int _secondsLeft = 8;
  bool _canSkip = false;

  @override
  void initState() {
    super.initState();

    // ⏱️ Global ad lifetime (8s)
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        _closeAd();
      } else if (mounted) {
        setState(() {
          _secondsLeft--;
          if (_secondsLeft <= 4) {
            _canSkip = true;
          }
        });
      }
    });
  }

  void _closeAd() {
    _timer?.cancel();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => widget.nextScreen,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 🖼️ Image paints instantly because it was precached
          Image.network(
            widget.imageUrl.trim(),
            fit: BoxFit.cover,
            gaplessPlayback: true, // 🔑 prevents flicker
            errorBuilder: (_, error, __) {
              debugPrint('❌ Ad image failed: $error');
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _closeAd());
              return const SizedBox.shrink();
            },
          ),

          // ⏭️ Skip Button
          if (_canSkip)
            Positioned(
              top: 50,
              right: 20,
              child: GestureDetector(
                onTap: _closeAd,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Text(
                    "Skip in $_secondsLeft",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
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
