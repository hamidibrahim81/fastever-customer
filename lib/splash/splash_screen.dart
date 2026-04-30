import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Added for persistence

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

  void _navigateNext() async {
    if (_navigated) return; 
    _navigated = true;

    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    Widget nextScreen;

    if (user == null) {
      nextScreen = const LoginScreen();
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
            if (doc.data()?['name'] != null && doc.data()?['name'].toString().trim().isNotEmpty) {
              // Update local cache so we don't have to fetch next time
              await prefs.setBool('profile_${user.uid}', true);
              nextScreen = const HomeScreen();
            } else {
              nextScreen = const ProfileScreen();
            }
          } else {
            // User exists in Auth but not in Firestore: Send to Profile, NOT Login
            nextScreen = const ProfileScreen();
          }
        } catch (e) {
          debugPrint('Splash Timeout/Error: $e');
          // If we have a user but network fails, default to Home to avoid locking them out
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
      backgroundColor: const Color(0xFF000000), 
      body: Center(
        child: Lottie.asset(
          'assets/logo.json',
          width: 260,
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