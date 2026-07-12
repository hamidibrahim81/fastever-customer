import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/home/home_screen.dart';
import '../features/profile/profile_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _navigationTimer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _startNavigationTimer(const Duration(seconds: 4));
  }

  void _startNavigationTimer(Duration duration) {
    _navigationTimer?.cancel();
    _navigationTimer = Timer(duration, () => _navigateNext());
  }

  Future<Widget?> _checkForceUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final int currentBuild = int.tryParse(info.buildNumber) ?? 0;

      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('customer_app')
          .get()
          .timeout(const Duration(seconds: 5));

      if (!doc.exists) return null;

      final data = doc.data()!;

      final bool forceUpdate = data['forceUpdate'] ?? false;

      final int minimumBuildNumber = Platform.isIOS
          ? data['iosMinimumBuildNumber'] ?? 0
          : data['androidMinimumBuildNumber'] ?? 0;

      if (forceUpdate && currentBuild < minimumBuildNumber) {
        return ForceUpdateScreen(
          title: data['updateTitle'] ?? 'Update Required',
          message: data['updateMessage'] ?? 'Please update FASTever to continue.',
          playStoreUrl: data['playStoreUrl'] ?? '',
          appStoreUrl: data['appStoreUrl'] ?? '',
        );
      }

      return null;
    } catch (e) {
      debugPrint("Force update check error: $e");
      return null;
    }
  }

  void _navigateNext() async {
    if (_navigated) return;
    _navigated = true;

    final updateScreen = await _checkForceUpdate();

    if (updateScreen != null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => updateScreen),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    Widget nextScreen;

    if (user == null) {
      nextScreen = const HomeScreen();
    } else {
      bool isProfileComplete = prefs.getBool('profile_${user.uid}') ?? false;

      if (isProfileComplete) {
        nextScreen = const HomeScreen();
      } else {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get()
              .timeout(const Duration(seconds: 5));

          if (doc.exists) {
            final data = doc.data();
            final String? name = data?['name']?.toString().trim();

            if (name != null && name.isNotEmpty) {
              await prefs.setBool('profile_${user.uid}', true);
              nextScreen = const HomeScreen();
            } else {
              nextScreen = const ProfileScreen();
            }
          } else {
            nextScreen = const ProfileScreen();
          }
        } catch (e) {
          debugPrint('Splash Timeout/Error: $e');
          nextScreen = const HomeScreen();
        }
      }
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) => nextScreen,
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 800),
    ));
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFC400),
      body: Center(
        child: Lottie.asset(
          'assets/logo.json',
          width: 400,
          repeat: false,
          onLoaded: (composition) {
            _startNavigationTimer(composition.duration);
          },
          errorBuilder: (context, error, stackTrace) {
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

class ForceUpdateScreen extends StatelessWidget {
  final String title;
  final String message;
  final String playStoreUrl;
  final String appStoreUrl;

  const ForceUpdateScreen({
    super.key,
    required this.title,
    required this.message,
    required this.playStoreUrl,
    required this.appStoreUrl,
  });

  Future<void> _openStore() async {
    final url = Platform.isIOS ? appStoreUrl : playStoreUrl;
    final uri = Uri.parse(url);

    if (url.isNotEmpty) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: const Color(0xFFFFC400),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.system_update_alt, size: 70, color: Colors.black),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, color: Colors.black54),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _openStore,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: const Color(0xFFFFC400),
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        "Update Now",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}