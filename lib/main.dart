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

// GLOBAL KEYS
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// BACKGROUND MESSAGE HANDLER
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );  
  debugPrint("Handling a background message: ${message.messageId}");
}

// NOTIFICATION CHANNEL SETUP
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel', 
  'High Importance Notifications', 
  description: 'This channel is used for order updates.', 
  importance: Importance.max,
);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // INITIALIZE LOCAL NOTIFICATIONS
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const DarwinInitializationSettings initializationSettingsDarwin =
      DarwinInitializationSettings();

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // SET UP BACKGROUND HANDLER
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // INITIALIZE LOCAL NOTIFICATIONS & CHANNEL
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // REQUEST NOTIFICATION PERMISSIONS
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  runApp(const FASTeverGoApp());
}

class FASTeverGoApp extends StatelessWidget {
  const FASTeverGoApp({super.key});

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
            return InstahubCartProvider(userId: user?.uid ?? "is_guest");
          },
        ),
      ],
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        scaffoldMessengerKey: appScaffoldMessengerKey,
        title: 'FASTeverGo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          primarySwatch: Colors.amber,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFFB800)),
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
          return MaintenanceGateWrapper(child: child!);
        },
        home: const SplashScreen(),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/home': (context) => const HomeScreen(),
          '/profile': (context) => const ProfileScreen(),
          '/service-check': (context) => const ServiceCheckScreen(),
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// GATE WRAPPER
// -----------------------------------------------------------------------------
class MaintenanceGateWrapper extends StatelessWidget {
  final Widget child;
  const MaintenanceGateWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('app_settings')
          .doc('maintenance')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data == null) return child;

          final status = data['status'] ?? "normal";

          // 1. MAINTENANCE
          if (status == "maintenance") {
            return AppStatusGate(
              title: data['title'] ?? "We're Making Things Better!",
              message: data['message'] ??
                  "We are currently performing maintenance to serve you better. We'll be back very soon!",
              email: data['support_email'] ?? "",
              whatsapp: data['support_wa'] ?? "",
            );
          }

          // 2. LAUNCH (Complete barrier, no interaction)
          if (status == "launch") {
            return LaunchImageGate(
              imageUrl: data['image_url'] ?? "",
            );
          }

          // 3. ADS (Clickable ad banner with local dismissal & seamless routing)
          if (status == "ads") {
            return AdScreenGate(
              imageUrl: data['image_url2'] ?? "",
              child: child,
            );
          }
        }
        // 4. NORMAL
        return child;
      },
    );
  }
}

// -----------------------------------------------------------------------------
// MAINTENANCE UI WITH FLOATING PARTICLE EFFECT
// -----------------------------------------------------------------------------
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
    final url = Uri.parse("https://wa.me/91${widget.whatsapp}?text=Hello FASTever Support!");
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw 'Could not launch WhatsApp';
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("WhatsApp could not be opened.")),
        );
      }
    }
  }

  Future<void> _launchEmail(BuildContext context) async {
    if (widget.email.isEmpty) return;
    final url = Uri.parse("mailto:${widget.email}?subject=App Support Request");
    try {
      if (!await launchUrl(url)) throw 'No email app found';
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Contact us directly at: ${widget.email}")),
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
                painter: MaintenanceParticlePainter(_animController.value),
              );
            },
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text(
                          "FAST",
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            fontStyle: FontStyle.italic,
                            letterSpacing: 1.0,
                          ),
                        ),
                        Text(
                          "EVER",
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
                      "AT DOORSTEP SERVICE",
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
                        color: const Color(0xFF1B2228).withOpacity(0.92),
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
                                  "Under Maintenance",
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
                    if (widget.whatsapp.isNotEmpty || widget.email.isNotEmpty) ...[
                      Text(
                        "Need assistance?",
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
                              icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                              label: const Text("WhatsApp"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          if (widget.whatsapp.isNotEmpty && widget.email.isNotEmpty)
                            const SizedBox(width: 12),
                          if (widget.email.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: () => _launchEmail(context),
                              icon: const Icon(Icons.email_rounded, size: 18),
                              label: const Text("Email Us"),
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
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 28),
                    Text(
                      "Thank you for your patience! ❤️",
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

// -----------------------------------------------------------------------------
// BACKGROUND PARTICLES PAINTER
// -----------------------------------------------------------------------------
class MaintenanceParticlePainter extends CustomPainter {
  final double animationValue;

  MaintenanceParticlePainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFB800).withOpacity(0.14)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 18; i++) {
      double dx = (size.width / 18) * i + (i % 3 * 8);
      double dy = ((animationValue * size.height) + (i * 55)) % size.height;
      double radius = (i % 3) + 2.5;

      canvas.drawCircle(Offset(dx, dy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant MaintenanceParticlePainter oldDelegate) => true;
}

// -----------------------------------------------------------------------------
// LAUNCH STATUS (COMPLETE BARRIER - NO CLICK, NO CLOSE, NO BACK)
// -----------------------------------------------------------------------------
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
                child: CircularProgressIndicator(color: Colors.amber),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Text(
                  "Unable to load image",
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

// -----------------------------------------------------------------------------
// ADS STATUS (CLICKABLE IMAGE2 WITH LOCAL DISMISSAL & EMBEDDED OVERLAY)
// -----------------------------------------------------------------------------
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
    // If dismissed, simply return the app's main child tree smoothly
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
                  child: CircularProgressIndicator(color: Colors.amber),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Text(
                    "Unable to load advertisement",
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
                      "Tap anywhere to continue",
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