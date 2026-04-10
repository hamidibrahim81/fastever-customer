import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lottie/lottie.dart';

import '../features/auth/login_screen.dart';
import '../features/home/home_screen.dart';
import '../features/profile/profile_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {

  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();
  }

  void _startNavigationTimer(Duration duration) {
    _navigationTimer = Timer(duration, () => _navigateNext());
  }

  // 🛡️ ADVANCED SAFETY NAVIGATION LOGIC (UNCHANGED)
  void _navigateNext() async {
    final user = FirebaseAuth.instance.currentUser;
    Widget nextScreen;

    if (user == null) {
      nextScreen = const LoginScreen();
    } else {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 5));

        if (doc.exists) {
          if (doc.data()?['name'] != null) {
            nextScreen = const HomeScreen();
          } else {
            nextScreen = const ProfileScreen();
          }
        } else {
          await FirebaseAuth.instance.signOut();
          nextScreen = const LoginScreen();
        }
      } catch (e) {
        debugPrint('Splash Timeout/Error: $e');
        nextScreen = const HomeScreen();
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
            _startNavigationTimer(composition.duration);
          },
        ),
      ),
    );
  }
}
