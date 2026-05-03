import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // ✅ Added for FCM
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // ✅ Added for Local Notifications
import 'package:cloud_firestore/cloud_firestore.dart'; // ✅ Switched to Firestore for Maintenance Mode
import 'package:url_launcher/url_launcher.dart'; // ✅ Added for Contact Support
import 'dart:async'; // ✅ Added for Countdown Timer

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

// ✅ STEP 1: BACKGROUND MESSAGE HANDLER
// This must be a top-level function (outside any class)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );  
  debugPrint("Handling a background message: ${message.messageId}");
}

// ✅ STEP 2: NOTIFICATION CHANNEL SETUP
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel', // id
  'High Importance Notifications', // title
  description: 'This channel is used for order updates.', // description
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

  // ✅ INITIALIZE LOCAL NOTIFICATIONS (REQUIRED TO PREVENT CRASHES)
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const DarwinInitializationSettings initializationSettingsDarwin =
      DarwinInitializationSettings();

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // ✅ SET UP BACKGROUND HANDLER
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // ✅ INITIALIZE LOCAL NOTIFICATIONS & CHANNEL
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  // ✅ REQUEST NOTIFICATION PERMISSIONS
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
            return InstahubCartProvider(userId: user?.uid ?? "guest_user");
          },
        ),
      ],
      child: MaterialApp(
        title: 'FASTeverGo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          primarySwatch: Colors.green,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            centerTitle: true,
            elevation: 1,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        // ✅ DYNAMIC STATUS GATE: Controls Maintenance vs Inauguration Mode
        builder: (context, child) {
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('app_settings')
                .doc('maintenance')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return child!;
              }

              if (snapshot.hasError) {
                return child!;
              }

              if (snapshot.hasData && snapshot.data!.exists) {
                final data = snapshot.data!.data() as Map<String, dynamic>?;
                if (data != null && data['is_enabled'] == true) {
                  return AppStatusGate(
                    status: data['status'] ?? "maintenance",
                    title: data['title'] ?? "Maintenance in Progress",
                    message: data['message'] ?? "We're fine-tuning FASTever to serve you better.",
                    targetDate: data['date_time'] ?? "2026-02-15 10:00:00", // Format for timer
                    email: data['support_email'] ?? "bloohostgroup.official@gmail.com",
                    whatsapp: data['support_wa'] ?? "7356103498",
                  ); 
                }
              }
              return child!;
            },
          );
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

// ✅ DYNAMIC GATE COMPONENT WITH TIMER & SUPPORT
class AppStatusGate extends StatefulWidget {
  final String status;   // "inauguration" or "maintenance"
  final String title;
  final String message;
  final String targetDate;
  final String email;
  final String whatsapp;

  const AppStatusGate({
    super.key, 
    required this.status, 
    required this.title, 
    required this.message, 
    required this.targetDate,
    required this.email,
    required this.whatsapp,
  });

  @override
  State<AppStatusGate> createState() => _AppStatusGateState();
}

class _AppStatusGateState extends State<AppStatusGate> {
  Timer? _timer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    // Requires format: YYYY-MM-DD HH:MM:SS
    final DateTime target = DateTime.tryParse(widget.targetDate) ?? DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      if (mounted) {
        setState(() {
          _timeLeft = target.isAfter(now) ? target.difference(now) : Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _launchWA() async {
    final url = Uri.parse("https://wa.me/91${widget.whatsapp}?text=Hello KEEVO Support Team!");
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw 'Could not launch WhatsApp';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("WhatsApp not installed or could not be opened.")),
        );
      }
    }
  }

  Future<void> _launchEmail() async {
    final url = Uri.parse("mailto:${widget.email}?subject=App Support Request");
    try {
      if (!await launchUrl(url)) {
        throw 'No email app found';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Please contact us directly at: ${widget.email}")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isInauguration = widget.status == "inauguration";
    Color themeColor = isInauguration ? Colors.orange : Colors.green;
    IconData mainIcon = isInauguration ? Icons.celebration_rounded : Icons.handyman_rounded;

    String timerText = "${_timeLeft.inDays}d : ${_timeLeft.inHours % 24}h : ${_timeLeft.inMinutes % 60}m : ${_timeLeft.inSeconds % 60}s";

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: themeColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(mainIcon, size: 80, color: themeColor),
              ),
              const SizedBox(height: 30),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 15),
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey[600], height: 1.5),
              ),
              const SizedBox(height: 35),
              // Countdown Label
              Text(isInauguration ? "Launching In" : "Back Online In", 
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                decoration: BoxDecoration(
                  color: themeColor,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  timerText,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5),
                ),
              ),
              const SizedBox(height: 50),
              // Support Section
              const Text("Support Team:", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _supportBtn(Icons.chat_bubble_rounded, "WhatsApp", const Color(0xFF25D366), _launchWA),
                  const SizedBox(width: 15),
                  _supportBtn(Icons.email_rounded, "Email", Colors.blueAccent, _launchEmail),
                ],
              ),
              const SizedBox(height: 40),
              const Text(
                "Thank you for your patience!",
                style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _supportBtn(IconData icon, String label, Color color, VoidCallback action) {
    return ElevatedButton.icon(
      onPressed: action,
      icon: Icon(icon, size: 18, color: Colors.white),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}