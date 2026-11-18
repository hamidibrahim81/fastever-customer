
import 'dart:async';
import 'dart:convert';
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

  static const String _configCacheKey =
      'fastever_force_update_config';

  static const Duration _splashDuration =
      Duration(seconds: 4);

  static const Duration _firestoreTimeout =
      Duration(seconds: 10);

  @override
  void initState() {
    super.initState();

    _startNavigationTimer();
  }

  void _startNavigationTimer() {
    _navigationTimer?.cancel();

    _navigationTimer = Timer(
      _splashDuration,
      _navigateNext,
    );
  }

  // --------------------------------------------------
  // FORCE UPDATE CONFIGURATION
  // --------------------------------------------------

  Future<Map<String, dynamic>?> _getUpdateConfiguration() async {
    final prefs = await SharedPreferences.getInstance();

    // First try to get the latest configuration from Firebase.
    try {
      final firestore = FirebaseFirestore.instance;

      debugPrint(
        'FASTever Firebase project: '
        '${firestore.app.options.projectId}',
      );

      debugPrint(
        'FASTever Firestore database: '
        '${firestore.databaseId}',
      );

      // IMPORTANT:
      // Preserve the existing document ID.
      // It contains one leading space.
      final doc = await firestore
          .collection('app_config')
          .doc(' customer_app')
          .get(
            const GetOptions(source: Source.server),
          )
          .timeout(_firestoreTimeout);

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;

        // Cache the last successful server configuration.
        try {
          await prefs.setString(
            _configCacheKey,
            jsonEncode(data),
          );

          debugPrint(
            'FASTever: Update configuration cached.',
          );
        } catch (e) {
          debugPrint(
            'FASTever cache save error: $e',
          );
        }

        debugPrint(
          'FASTever: Latest server configuration loaded.',
        );

        return data;
      }

      debugPrint(
        'FASTever: Update configuration document not found.',
      );
    } catch (e) {
      debugPrint(
        'FASTever: Server update check failed: $e',
      );
    }

    // ------------------------------------------------
    // FALLBACK TO LAST SUCCESSFUL CONFIGURATION
    // ------------------------------------------------

    try {
      final cachedData = prefs.getString(
        _configCacheKey,
      );

      if (cachedData != null && cachedData.isNotEmpty) {
        final decoded = jsonDecode(cachedData);

        if (decoded is Map) {
          debugPrint(
            'FASTever: Using cached update configuration.',
          );

          return Map<String, dynamic>.from(decoded);
        }
      }
    } catch (e) {
      debugPrint(
        'FASTever: Cached configuration error: $e',
      );
    }

    // No cached configuration means we cannot confirm
    // that an update is mandatory.
    // Allow the customer to continue into the application.

    debugPrint(
      'FASTever: No update configuration available. '
      'Allowing application startup.',
    );

    return null;
  }

  // --------------------------------------------------
  // FORCE UPDATE CHECK
  // --------------------------------------------------

  Future<Widget?> _checkForceUpdate() async {
    int currentBuild = 0;

    try {
      final info = await PackageInfo.fromPlatform()
          .timeout(const Duration(seconds: 8));

      currentBuild = int.tryParse(info.buildNumber) ?? 0;

      debugPrint(
        'FASTever installed build: $currentBuild',
      );
    } catch (e) {
      debugPrint(
        'FASTever package information error: $e',
      );

      // Do not incorrectly block customers when
      // package information cannot be retrieved.
      return null;
    }

    final data = await _getUpdateConfiguration();

    if (data == null) {
      return null;
    }

    final bool forceUpdate =
        data['forceUpdate'] == true;

    final dynamic minimumBuildValue = Platform.isIOS
        ? data['iosMinimumBuildNumber']
        : data['androidMinimumBuildNumber'];

    final int minimumBuildNumber =
        minimumBuildValue is num
            ? minimumBuildValue.toInt()
            : int.tryParse(
                  minimumBuildValue?.toString() ?? '',
                ) ??
                0;

    debugPrint(
      'FASTever forceUpdate: $forceUpdate',
    );

    debugPrint(
      'FASTever minimum required build: '
      '$minimumBuildNumber',
    );

    if (forceUpdate &&
        minimumBuildNumber > 0 &&
        currentBuild < minimumBuildNumber) {
      debugPrint(
        'FASTever: MANDATORY UPDATE REQUIRED.',
      );

      return ForceUpdateScreen(
        title: data['updateTitle']?.toString() ??
            'Update Required',
        message: data['updateMessage']?.toString() ??
            'Please update FASTever to continue.',
        playStoreUrl:
            data['playStoreUrl']?.toString() ?? '',
        appStoreUrl:
            data['appStoreUrl']?.toString() ?? '',
      );
    }

    debugPrint(
      'FASTever: App version accepted.',
    );

    return null;
  }

  // --------------------------------------------------
  // NAVIGATION
  // --------------------------------------------------

  Future<void> _navigateNext() async {
    if (_navigated || !mounted) return;

    _navigated = true;

    _navigationTimer?.cancel();

    Widget? updateScreen;

    try {
      updateScreen = await _checkForceUpdate();
    } catch (e, stackTrace) {
      debugPrint(
        'FASTever update check unexpected error: $e',
      );

      debugPrint('$stackTrace');

      // Do not permanently block app startup
      // because of a temporary update-check error.
      updateScreen = null;
    }

    if (!mounted) return;

    // Mandatory update screen.
    if (updateScreen != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => updateScreen!,
        ),
      );

      return;
    }

    Widget nextScreen;

    try {
      final user = FirebaseAuth.instance.currentUser;

      final prefs = await SharedPreferences.getInstance();

      if (!mounted) return;

      // Customer is not logged in.
      if (user == null) {
        nextScreen = const HomeScreen();
      } else {
        final bool isProfileComplete =
            prefs.getBool('profile_${user.uid}') ?? false;

        if (isProfileComplete) {
          nextScreen = const HomeScreen();
        } else {
          try {
            final doc = await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get()
                .timeout(
                  const Duration(seconds: 7),
                );

            if (!mounted) return;

            if (doc.exists) {
              final data = doc.data();

              final String? name =
                  data?['name']?.toString().trim();

              if (name != null && name.isNotEmpty) {
                try {
                  await prefs.setBool(
                    'profile_${user.uid}',
                    true,
                  );
                } catch (e) {
                  debugPrint(
                    'FASTever profile cache error: $e',
                  );
                }

                nextScreen = const HomeScreen();
              } else {
                nextScreen = const ProfileScreen();
              }
            } else {
              nextScreen = const ProfileScreen();
            }
          } catch (e) {
            debugPrint(
              'FASTever profile check error: $e',
            );

            // Preserve the previous fallback behavior.
            nextScreen = const HomeScreen();
          }
        }
      }
    } catch (e, stackTrace) {
      debugPrint(
        'FASTever navigation error: $e',
      );

      debugPrint('$stackTrace');

      if (!mounted) return;

      // Final fallback to avoid leaving customers
      // stuck on the splash screen.
      nextScreen = const HomeScreen();
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => nextScreen,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration:
            const Duration(milliseconds: 800),
      ),
    );
  }

  // --------------------------------------------------
  // DISPOSE
  // --------------------------------------------------

  @override
  void dispose() {
    _navigationTimer?.cancel();
    super.dispose();
  }

  // --------------------------------------------------
  // SPLASH UI
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFC400),
      body: Center(
        child: Lottie.asset(
          'assets/logo.json',
          width: 400,
          repeat: false,
          errorBuilder: (context, error, stackTrace) {
            debugPrint(
              'FASTever splash animation error: $error',
            );

            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

// ======================================================
// FORCE UPDATE SCREEN
// ======================================================

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
    final url = Platform.isIOS
        ? appStoreUrl
        : playStoreUrl;

    if (url.isEmpty) {
      debugPrint(
        'FASTever force update: Store URL is empty.',
      );

      return;
    }

    final uri = Uri.tryParse(url);

    if (uri == null ||
        (uri.scheme != 'https' &&
            uri.scheme != 'market')) {
      debugPrint(
        'FASTever force update: Invalid store URL.',
      );

      return;
    }

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        debugPrint(
          'FASTever: Could not open application store.',
        );
      }
    } catch (e) {
      debugPrint(
        'FASTever store opening error: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
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
                    const Icon(
                      Icons.system_update_alt,
                      size: 70,
                      color: Colors.black,
                    ),

                    const SizedBox(height: 20),

                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.black54,
                      ),
                    ),

                    const SizedBox(height: 24),

                    ElevatedButton(
                      onPressed: _openStore,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor:
                            const Color(0xFFFFC400),
                        minimumSize: const Size(
                          double.infinity,
                          52,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Update Now',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
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

// ======================================================
// FORCE UPDATE CHECK FALLBACK SCREEN
// ======================================================

class ForceUpdateCheckErrorScreen extends StatelessWidget {
  const ForceUpdateCheckErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFFFC400),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.wifi_off_rounded,
                  size: 70,
                  color: Colors.black,
                ),

                const SizedBox(height: 20),

                const Text(
                  'Unable to Check App Version',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                const Text(
                  'Please check your internet connection '
                  'and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15),
                ),

                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => const SplashScreen(),
                      ),
                    );
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
