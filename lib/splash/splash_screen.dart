
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

  // MANDATORY FORCE UPDATE CHECK
  Future<Widget?> _checkForceUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final int currentBuild =
        int.tryParse(info.buildNumber) ?? 0;

    debugPrint('FASTever installed build: $currentBuild');

    debugPrint(
      'FASTever Firebase project: '
      '${FirebaseFirestore.instance.app.options.projectId}',
    );

    debugPrint(
      'FASTever Firestore database: '
      '${FirebaseFirestore.instance.databaseId}',
    );

    // FIRESTORE DOCUMENT DIAGNOSTIC CHECK
    final firestore = FirebaseFirestore.instance;

    // IMPORTANT:
    // The Firestore document ID has one leading space.
    // Actual document ID: " customer_app"
    final doc = await firestore
        .collection('app_config')
        .doc(' customer_app')
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));

    debugPrint('FASTever document exists: ${doc.exists}');
    debugPrint(
      'FASTever document path: ${doc.reference.path}',
    );
    debugPrint('FASTever document data: ${doc.data()}');

    // Inspect collection only if direct document is missing.
    if (!doc.exists) {
      try {
        final query = await firestore
            .collection('app_config')
            .limit(10)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 12));

        debugPrint(
          'FASTever app_config document count: '
          '${query.docs.length}',
        );

        for (final item in query.docs) {
          debugPrint(
            'FASTever document ID: ${item.id}',
          );
        }
      } catch (e) {
        debugPrint(
          'FASTever collection diagnostic error: $e',
        );
      }
    }

    if (!doc.exists || doc.data() == null) {
      throw Exception(
        'Force update configuration not found: '
        'app_config/ customer_app',
      );
    }

    final data = doc.data()!;

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

    debugPrint('FASTever forceUpdate: $forceUpdate');
    debugPrint(
      'FASTever minimum required build: '
      '$minimumBuildNumber',
    );

    if (forceUpdate &&
        currentBuild < minimumBuildNumber) {
      debugPrint(
        'FASTever: MANDATORY UPDATE REQUIRED',
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

  void _navigateNext() async {
    if (_navigated) return;
    _navigated = true;

    // Check mandatory update before home/profile navigation.
    Widget? updateScreen;

    try {
      updateScreen = await _checkForceUpdate();
    } catch (e, stackTrace) {
      debugPrint("========== FASTEVER UPDATE ERROR ==========");
      debugPrint("Error: $e");
      debugPrint("Stack trace: $stackTrace");
      debugPrint("===========================================");

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              const ForceUpdateCheckErrorScreen(),
        ),
      );
      return;
    }

    if (updateScreen != null) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => updateScreen!),
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

    if (url.isEmpty) {
      debugPrint('Force update: Store URL is empty.');
      return;
    }

    final uri = Uri.tryParse(url);

    if (uri == null ||
        (uri.scheme != 'https' &&
            uri.scheme != 'market')) {
      debugPrint('Force update: Invalid store URL.');
      return;
    }

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        debugPrint('Force update: Could not open store.');
      }
    } catch (e) {
      debugPrint('Force update store error: $e');
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

// Only shown when Firebase cannot verify the app version.
class ForceUpdateCheckErrorScreen extends StatelessWidget {
  const ForceUpdateCheckErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
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
