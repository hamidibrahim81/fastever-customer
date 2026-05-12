import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Persistence fix


import '../features/home/home_screen.dart';
import '../features/profile/profile_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _navigationTimer;
  bool _navigated = false; // Guard to prevent double navigation

  @override
  void initState() {
    super.initState();
    // Start a fallback timer (4s) in case Lottie fails to trigger onLoaded
    _startNavigationTimer(const Duration(seconds: 4));
  }

  void _startNavigationTimer(Duration duration) {
    _navigationTimer?.cancel(); // Cancel any previous timer
    _navigationTimer = Timer(duration, () => _navigateNext());
  }

  // 🛡️ ADVANCED SAFETY NAVIGATION LOGIC
  void _navigateNext() async {
    if (_navigated) return; // Prevent multiple executions
    _navigated = true;

    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    Widget nextScreen;

    if (user == null) {
      nextScreen = const HomeScreen();
    } else {
      // 1. Check local cache first for instant loading
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
            // FIX: Handle nullability safely to avoid 'bool?' build error
            final data = doc.data();
            final String? name = data?['name']?.toString().trim();

            if (name != null && name.isNotEmpty) {
              // Update local cache so we don't have to fetch Firestore next time
              await prefs.setBool('profile_${user.uid}', true);
              nextScreen = const HomeScreen();
            } else {
              nextScreen = const ProfileScreen();
            }
          } else {
            // User exists in Auth but not in Firestore: Send to Profile
            nextScreen = const ProfileScreen();
          }
        } catch (e) {
          debugPrint('Splash Timeout/Error: $e');
          // If logged in but network fails, go to Home to avoid locking user out
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
      backgroundColor: const Color(0xFF000000), // 🔥 Black background
      body: Center(
        child: Lottie.asset(
          'assets/logo.json',
          width: 260,
          repeat: false,
          onLoaded: (composition) {
            // Lottie loaded successfully, use its duration
            _startNavigationTimer(composition.duration);
          },
          errorBuilder: (context, error, stackTrace) {
            // If Lottie fails, the initState timer will handle navigation
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}