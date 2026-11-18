
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

// Firebase configuration
import 'firebase_options.dart';

// Screens
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';
import 'features/home/ServiceCheckScreen.dart';
import 'features/profile/profile_screen.dart';
import 'splash/splash_screen.dart';

// Providers
import 'features/food/cart/cart_provider.dart';
import 'features/cart/morning_cart_provider.dart';
import 'features/instahub/instahub_cart_provider.dart';

// Global Loader
import 'features/loading/global_loader.dart';

// GLOBAL KEYS
final GlobalKey<NavigatorState> appNavigatorKey =
    GlobalKey<NavigatorState>();

final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// BACKGROUND MESSAGE HANDLER
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    debugPrint(
      'FASTever background message: ${message.messageId}',
    );
  } catch (e, stackTrace) {
    debugPrint(
      'FASTever background Firebase initialization error: $e',
    );
    debugPrint('$stackTrace');
  }
}

// NOTIFICATION CHANNEL SETUP
const AndroidNotificationChannel channel =
    AndroidNotificationChannel(
  'high_importance_channel',
  'High Importance Notifications',
  description: 'This channel is used for order updates.',
  importance: Importance.max,
);

final FlutterLocalNotificationsPlugin
    flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// --------------------------------------------------
// MAIN
// --------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // STEP 1: FIREBASE INITIALIZATION
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(
      const Duration(seconds: 20),
    );

    debugPrint('FASTever: Firebase initialized successfully.');
  } catch (e, stackTrace) {
    debugPrint(
      'FASTever Firebase initialization failed: $e',
    );
    debugPrint('$stackTrace');

    runApp(
      FirebaseStartupErrorApp(
        error: e.toString(),
      ),
    );

    return;
  }

  // STEP 2: REGISTER BACKGROUND MESSAGE HANDLER
  try {
    FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler,
    );

    debugPrint(
      'FASTever: Background message handler registered.',
    );
  } catch (e) {
    debugPrint(
      'FASTever background handler registration error: $e',
    );
  }

  // STEP 3: LOCAL NOTIFICATION INITIALIZATION
  // Notification errors must not prevent the app from opening.

  try {
    const AndroidInitializationSettings
        initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings
        initializationSettingsDarwin =
        DarwinInitializationSettings();

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await flutterLocalNotificationsPlugin
        .initialize(initializationSettings)
        .timeout(
      const Duration(seconds: 10),
    );

    debugPrint(
      'FASTever: Local notifications initialized.',
    );
  } catch (e, stackTrace) {
    debugPrint(
      'FASTever local notification initialization error: $e',
    );
    debugPrint('$stackTrace');
  }

  // STEP 4: ANDROID NOTIFICATION CHANNEL
  try {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel)
        .timeout(
      const Duration(seconds: 10),
    );

    debugPrint(
      'FASTever: Android notification channel ready.',
    );
  } catch (e) {
    debugPrint(
      'FASTever notification channel error: $e',
    );
  }

  // STEP 5: START APPLICATION
  // Notification permission is requested after the first frame.
  runApp(const FASTeverGoApp());
}

// --------------------------------------------------
// APP
// --------------------------------------------------

class FASTeverGoApp extends StatefulWidget {
  const FASTeverGoApp({super.key});

  @override
  State<FASTeverGoApp> createState() => _FASTeverGoAppState();
}

class _FASTeverGoAppState extends State<FASTeverGoApp> {
  bool _permissionRequestStarted = false;

  @override
  void initState() {
    super.initState();

    // Let the first Flutter frame render before requesting
    // notification permission.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _permissionRequestStarted) return;

      _permissionRequestStarted = true;

      unawaited(_requestNotificationPermission());
    });
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging
          .requestPermission(
        alert: true,
        badge: true,
        sound: true,
      )
          .timeout(
        const Duration(seconds: 15),
      );

      debugPrint(
        'FASTever notification permission: '
        '${settings.authorizationStatus}',
      );
    } catch (e, stackTrace) {
      debugPrint(
        'FASTever notification permission error: $e',
      );
      debugPrint('$stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => CartProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => MorningCartProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) {
            final user = FirebaseAuth.instance.currentUser;

            return InstahubCartProvider(
              userId: user?.uid ?? 'is_guest',
            );
          },
        ),
      ],
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        navigatorObservers: [routeObserver],
        scaffoldMessengerKey: appScaffoldMessengerKey,
        title: 'FASTeverGo',
        debugShowCheckedModeBanner: false,

        theme: ThemeData(
          useMaterial3: true,
          primarySwatch: Colors.amber,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFFFB800),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            centerTitle: true,
            elevation: 1,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFB800),
              foregroundColor: Colors.black,
            ),
          ),
        ),

        builder: (context, child) {
          return GlobalLoader.wrapper(
            context,
            MaintenanceGateWrapper(
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },

        // SPLASH SCREEN IS THE FIRST SCREEN
        home: const SplashScreen(),

        routes: {
          '/login': (context) => const LoginScreen(),
          '/home': (context) => const HomeScreen(),
          '/profile': (context) => const ProfileScreen(),
          '/service-check': (context) =>
              const ServiceCheckScreen(),
        },
      ),
    );
  }
}

// --------------------------------------------------
// FIREBASE STARTUP ERROR SCREEN
// --------------------------------------------------

class FirebaseStartupErrorApp extends StatelessWidget {
  final String error;

  const FirebaseStartupErrorApp({
    super.key,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFB800),
        ),
      ),
      home: FirebaseStartupErrorScreen(
        error: error,
      ),
    );
  }
}

class FirebaseStartupErrorScreen extends StatefulWidget {
  final String error;

  const FirebaseStartupErrorScreen({
    super.key,
    required this.error,
  });

  @override
  State<FirebaseStartupErrorScreen> createState() =>
      _FirebaseStartupErrorScreenState();
}

class _FirebaseStartupErrorScreenState
    extends State<FirebaseStartupErrorScreen> {
  bool _retrying = false;

  Future<void> _retryFirebase() async {
    if (_retrying) return;

    setState(() {
      _retrying = true;
    });

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ).timeout(
          const Duration(seconds: 20),
        );
      }

      if (!mounted) return;

      // Firebase initialized successfully.
      // Restart the app widget tree with the normal application.
      runApp(const FASTeverGoApp());
    } catch (e, stackTrace) {
      debugPrint(
        'FASTever Firebase retry failed: $e',
      );
      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _retrying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFC400),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    size: 65,
                    color: Colors.black,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Unable to Start FASTever',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'We are unable to connect to our '
                    'application services. Please check '
                    'your internet connection and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed:
                          _retrying ? null : _retryFirebase,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: const Color(0xFFFFC400),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _retrying
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFFFC400),
                              ),
                            )
                          : const Text(
                              'Retry',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------
// GATE WRAPPER
// --------------------------------------------------

class MaintenanceGateWrapper extends StatefulWidget {
  final Widget child;

  const MaintenanceGateWrapper({
    super.key,
    required this.child,
  });

  @override
  State<MaintenanceGateWrapper> createState() => _MaintenanceGateWrapperState();
}

class _MaintenanceGateWrapperState extends State<MaintenanceGateWrapper> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _maintenanceStream;

  @override
  void initState() {
    super.initState();
    _maintenanceStream = FirebaseFirestore.instance
        .collection('app_settings')
        .doc('maintenance')
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _maintenanceStream,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.exists) {
          final data =
              snapshot.data!.data() as Map<String, dynamic>?;

          if (data == null) return widget.child;

          final status = data['status'] ?? 'normal';

          // 1. MAINTENANCE
          if (status == 'maintenance') {
            return AppStatusGate(
              title: data['title'] ??
                  "We're Making Things Better!",
              message: data['message'] ??
                  "We are currently performing maintenance "
                      "to serve you better. We'll be back very soon!",
              email: data['support_email'] ?? '',
              whatsapp: data['support_wa'] ?? '',
            );
          }

          // 2. LAUNCH
          if (status == 'launch') {
            return LaunchImageGate(
              imageUrl: data['image_url'] ?? '',
            );
          }

          // 3. ADS
          if (status == 'ads') {
            return AdScreenGate(
              imageUrl: data['image_url2'] ?? '',
              child: widget.child,
            );
          }
        }

        // 4. NORMAL
        return widget.child;
      },
    );
  }
}

// --------------------------------------------------
// MAINTENANCE UI WITH FLOATING PARTICLE EFFECT
// --------------------------------------------------

class AppStatusGate extends StatefulWidget {
  final String title;
  final String message;
  final String email;
  final String whatsapp;

  const AppStatusGate({
    super.key,
    required this.title,
    required this.message,
    required this.email,
    required this.whatsapp,
  });

  @override
  State<AppStatusGate> createState() => _AppStatusGateState();
}

class _AppStatusGateState extends State<AppStatusGate>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _launchWA(BuildContext context) async {
    if (widget.whatsapp.isEmpty) return;

    final url = Uri.parse(
      'https://wa.me/91${widget.whatsapp}?text=Hello FASTever Support!',
    );

    try {
      if (!await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      )) {
        throw 'Could not launch WhatsApp';
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('WhatsApp could not be opened.'),
          ),
        );
      }
    }
  }

  Future<void> _launchEmail(BuildContext context) async {
    if (widget.email.isEmpty) return;

    final url = Uri.parse(
      'mailto:${widget.email}?subject=App Support Request',
    );

    try {
      if (!await launchUrl(url)) {
        throw 'No email app found';
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Contact us directly at: ${widget.email}',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const brandGold = Color(0xFFFFB800);
    const darkBg = Color(0xFF101418);

    return Scaffold(
      backgroundColor: darkBg,
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _animController,
            builder: (context, child) {
              return CustomPaint(
                size: Size.infinite,
                painter: MaintenanceParticlePainter(
                  _animController.value,
                ),
              );
            },
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text(
                          'FAST',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            fontStyle: FontStyle.italic,
                            letterSpacing: 1.0,
                          ),
                        ),
                        Text(
                          'EVER',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: brandGold,
                            fontStyle: FontStyle.italic,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'AT DOORSTEP SERVICE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withOpacity(0.6),
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B2228)
                            .withOpacity(0.92),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: brandGold.withOpacity(0.35),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: brandGold.withOpacity(0.08),
                            blurRadius: 30,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: brandGold.withOpacity(0.12),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: brandGold.withOpacity(0.3),
                              ),
                            ),
                            child: const Icon(
                              Icons.engineering_rounded,
                              size: 56,
                              color: brandGold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: brandGold.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.build_rounded,
                                  size: 14,
                                  color: brandGold,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Under Maintenance',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: brandGold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            widget.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.message,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.7),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (widget.whatsapp.isNotEmpty ||
                        widget.email.isNotEmpty) ...[
                      Text(
                        'Need assistance?',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.whatsapp.isNotEmpty)
                            ElevatedButton.icon(
                              onPressed: () => _launchWA(context),
                              icon: const Icon(
                                Icons.chat_bubble_rounded,
                                size: 18,
                              ),
                              label: const Text('WhatsApp'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          if (widget.whatsapp.isNotEmpty &&
                              widget.email.isNotEmpty)
                            const SizedBox(width: 12),
                          if (widget.email.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: () => _launchEmail(context),
                              icon: const Icon(
                                Icons.email_rounded,
                                size: 18,
                              ),
                              label: const Text('Email Us'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withOpacity(0.3),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(12),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 28),
                    Text(
                      'Thank you for your patience! \u2764\uFE0F',
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: Colors.white.withOpacity(0.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------
// BACKGROUND PARTICLES PAINTER
// --------------------------------------------------

class MaintenanceParticlePainter extends CustomPainter {
  final double animationValue;

  MaintenanceParticlePainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFB800).withOpacity(0.14)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 18; i++) {
      final double dx =
          (size.width / 18) * i + (i % 3 * 8);

      final double dy =
          ((animationValue * size.height) + (i * 55)) %
              size.height;

      final double radius = (i % 3) + 2.5;

      canvas.drawCircle(
        Offset(dx, dy),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant MaintenanceParticlePainter oldDelegate,
  ) =>
      true;
}

// --------------------------------------------------
// LAUNCH STATUS
// --------------------------------------------------

class LaunchImageGate extends StatelessWidget {
  final String imageUrl;

  const LaunchImageGate({
    super.key,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;

              return const Center(
                child: CircularProgressIndicator(
                  color: Colors.amber,
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Text(
                  'Unable to load image',
                  style: TextStyle(color: Colors.white54),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------
// ADS STATUS
// --------------------------------------------------

class AdScreenGate extends StatefulWidget {
  final String imageUrl;
  final Widget child;

  const AdScreenGate({
    super.key,
    required this.imageUrl,
    required this.child,
  });

  @override
  State<AdScreenGate> createState() => _AdScreenGateState();
}

class _AdScreenGateState extends State<AdScreenGate> {
  bool _isDismissed = false;

  void _handleAdTap() {
    setState(() {
      _isDismissed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isDismissed) {
      return widget.child;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _handleAdTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              widget.imageUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;

                return const Center(
                  child: CircularProgressIndicator(
                    color: Colors.amber,
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Text(
                    'Unable to load advertisement',
                    style: TextStyle(color: Colors.white54),
                  ),
                );
              },
            ),
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                    child: const Text(
                      'Tap anywhere to continue',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
