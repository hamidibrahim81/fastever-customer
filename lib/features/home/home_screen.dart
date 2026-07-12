import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_player/video_player.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

import '../food/food_home_screen.dart';
import '../instahub/InstantOrderHomeScreen.dart';
import '../instahub/MorningOrderHomeScreen.dart';
import '../auth/login_screen.dart';
import '../home_services/home_services_screen.dart';
import '../Laundry/LaundryServiceForm.dart';

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

// ----------------------------------------------------------------------
// Premium Color Palette Tokens
// ----------------------------------------------------------------------
class AppColors {
  static const Color primary = Color(0xFF111827);       // Deep Premium Slate/Black
  static const Color accent = Color(0xFFFF4D6D);        // Vibrant Modern Pink/Red
  static const Color background = Color(0xFFF7F8FA);    // Clean Crisp Background
  static const Color cardBg = Colors.white;             // Card Surfaces
  static const Color success = Color(0xFF16A34A);       // Trust Green
  static const Color offer = Color(0xFFF97316);         // High-conversion Orange
  static const Color textDark = Color(0xFF1F2937);      // Deep Text Accent
  static const Color textLight = Color(0xFF6B7280);     // Secondary Subtitles
}

// ----------------------------------------------------------------------
// Helper Functions
// ----------------------------------------------------------------------
double parseDouble(dynamic value, {double defaultValue = 0.0}) {
  if (value is String) return double.tryParse(value) ?? defaultValue;
  if (value is num) return value.toDouble();
  return defaultValue;
}

class _ServiceLocation {
  final String name;
  final double latitude;
  final double longitude;
  final double radiusKm;

  _ServiceLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
  });
}

enum GateState { loading, locationOffOrDenied, outOfArea, allowed }

// ----------------------------------------------------------------------
// Reusable Video Player Configuration
// ----------------------------------------------------------------------
class NetworkVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final bool autoplay;
  final bool looping;
  final bool isCoverFit;
  const NetworkVideoPlayer({
    required this.videoUrl,
    this.autoplay = true,
    this.looping = true,
    this.isCoverFit = true,
    super.key,
  });
  @override
  State<NetworkVideoPlayer> createState() => _NetworkVideoPlayerState();
}

class _NetworkVideoPlayerState extends State<NetworkVideoPlayer>
    with WidgetsBindingObserver, RouteAware {
  late VideoPlayerController _controller;
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (!mounted) return;
        _controller.setLooping(widget.looping);
        _controller.setVolume(0);
        if (widget.autoplay) _controller.play();
        setState(() {});
      }).catchError((e) => debugPrint("Video Error: $e"));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute? route = ModalRoute.of(context);
    if (route is PageRoute) routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didPushNext() {
    _controller.pause();
    _isVisible = false;
  }

  @override
  void didPopNext() {
    if (widget.autoplay) _controller.play();
    _isVisible = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.isInitialized) return;
    if (_isVisible) {
      if (state == AppLifecycleState.resumed && widget.autoplay) {
        _controller.play();
      } else if (state == AppLifecycleState.paused) {
        _controller.pause();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return Container(
          color: Colors.black,
          child: const Center(child: CircularProgressIndicator(color: AppColors.accent)));
    }
    return FittedBox(
      fit: widget.isCoverFit ? BoxFit.cover : BoxFit.contain,
      child: SizedBox(
        width: _controller.value.size.width,
        height: _controller.value.size.height,
        child: VideoPlayer(_controller),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Premium Banner Slider Component
// ----------------------------------------------------------------------
class HeaderAdVideo extends StatefulWidget {
  final String tag;
  const HeaderAdVideo({required this.tag, super.key});

  @override
  State<HeaderAdVideo> createState() => _HeaderAdVideoState();
}

class _HeaderAdVideoState extends State<HeaderAdVideo> {
  int _currentBannerIndex = 0;
  List<QueryDocumentSnapshot> _cachedAds = [];
  bool _isLoading = true;
  StreamSubscription<QuerySnapshot>? _adsSubscription;

  @override
  void initState() {
    super.initState();
    _adsSubscription = FirebaseFirestore.instance
        .collection('ads')
        .where('tag', isEqualTo: widget.tag)
        .where('active', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _cachedAds = snapshot.docs;
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _adsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Shimmer.fromColors(
        baseColor: Colors.grey.shade200,
        highlightColor: Colors.grey.shade50,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          height: 180,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      );
    }

    if (_cachedAds.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 180,
          child: CarouselSlider(
            options: CarouselOptions(
              height: 180,
              viewportFraction: 0.9,
              enlargeCenterPage: true,
              autoPlay: true,
              autoPlayInterval: const Duration(seconds: 4),
              autoPlayAnimationDuration: const Duration(milliseconds: 800),
              autoPlayCurve: Curves.fastOutSlowIn,
              onPageChanged: (index, reason) {
                setState(() {
                  _currentBannerIndex = index;
                });
              },
            ),
            items: _cachedAds.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: CachedNetworkImage(
                  imageUrl: data['url'] ?? '',
                  fit: BoxFit.cover,
                  width: double.infinity,
                  placeholder: (context, url) => Shimmer.fromColors(
                    baseColor: Colors.grey.shade200,
                    highlightColor: Colors.grey.shade50,
                    child: Container(color: Colors.white),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey.shade100,
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _cachedAds.asMap().entries.map((entry) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: _currentBannerIndex == entry.key ? 16.0 : 6.0,
              height: 6.0,
              margin: const EdgeInsets.symmetric(horizontal: 3.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: _currentBannerIndex == entry.key 
                    ? AppColors.accent 
                    : Colors.grey.shade300,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------
// Home Screen Module
// ----------------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  GateState _gateState = GateState.loading;
  String _currentLocation = "Detecting Location Node...";
  bool _isLoadingLocation = true;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  List<_ServiceLocation> _serviceLocations = []; 
  bool _serviceLocationsLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initGate();
    _setupTokenListener(); 
    _subscribeToTopics(); 
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _positionStreamSubscription?.resume();
      if (_gateState == GateState.locationOffOrDenied) _initGate();
    } else if (state == AppLifecycleState.paused) {
      _positionStreamSubscription?.pause(); 
    }
  }

  void _setupTokenListener() {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'fcmToken': newToken}).catchError((e) => debugPrint("Token infrastructure break: $e"));
      }
    });
  }

  void _subscribeToTopics() async {
    try {
      NotificationSettings settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        await FirebaseMessaging.instance.subscribeToTopic("offers");
        await FirebaseMessaging.instance.subscribeToTopic("all_users");
      }
    } catch (e) {
      debugPrint("Topic initialization failure: $e");
    }
  }

  Future<void> _loadServiceLocations() async {
    if (_serviceLocationsLoaded) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('service_areas').get().timeout(const Duration(seconds: 10));
      _serviceLocations = snap.docs.map((d) {
        final data = d.data();
        return _ServiceLocation(
          name: data['name']?.toString() ?? '',
          latitude: parseDouble(data['latitude']),
          longitude: parseDouble(data['longitude']),
          radiusKm: parseDouble(data['radiusKm']),
        );
      }).toList();
      _serviceLocationsLoaded = true;
    } catch (e) {
      debugPrint('Error compiling perimeter maps: $e');
    }
  }

  bool _isInsideAnyServiceLocation(Position pos) {
    const bufferKm = 0.05;
    for (final loc in _serviceLocations) {
      final distanceKm = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, loc.latitude, loc.longitude) / 1000;
      if (distanceKm <= loc.radiusKm + bufferKm) return true;
    }
    return false;
  }

  Future<void> _initGate() async {
    try {
      if (!mounted) return;
      setState(() {
        _gateState = GateState.loading;
        _isLoadingLocation = true;
      });

      await _loadServiceLocations().timeout(const Duration(seconds: 10));

      bool canLocate = await _ensureLocationAvailable();
      if (!canLocate) {
        if (mounted) setState(() => _gateState = GateState.locationOffOrDenied);
        return;
      }

      Position? initialPosition = await Geolocator.getLastKnownPosition();
      initialPosition ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high, 
        timeLimit: const Duration(seconds: 8),
      );

      _handlePositionUpdate(initialPosition, isManual: false);

      _positionStreamSubscription?.cancel();
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 100),
      ).listen((Position position) {
        if (mounted) _handlePositionUpdate(position, isManual: false);
      });

    } catch (e) {
      if (_currentPosition == null && mounted) setState(() => _gateState = GateState.locationOffOrDenied);
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _handlePositionUpdate(Position position, {required bool isManual}) async {
    if (!isManual && _currentPosition != null) {
      final dist = Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, position.latitude, position.longitude);
      if (dist < 50) return;
    }
    _resolvePlaceName(position);
    bool inside = _isInsideAnyServiceLocation(position);
    if (mounted) setState(() { _currentPosition = position; _gateState = inside ? GateState.allowed : GateState.outOfArea; });
  }

  Future<bool> _ensureLocationAvailable() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      try { await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 2))); } catch (_) {}
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
    }
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    return permission != LocationPermission.denied && permission != LocationPermission.deniedForever;
  }

  Future<void> _resolvePlaceName(Position position) async {
    try {
      final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (mounted && placemarks.isNotEmpty) {
        final place = placemarks.first;
        setState(() => _currentLocation = "${place.locality ?? place.subLocality ?? 'Unknown Segment'}, ${place.administrativeArea ?? ''}");
      }
    } catch (_) {
      if (mounted) setState(() => _currentLocation = "Active Deployment Zone");
    }
  }

  void _selectManualLocation(_ServiceLocation location) {
    _positionStreamSubscription?.cancel();
    Position manualPosition = Position(
      latitude: location.latitude, longitude: location.longitude,
      timestamp: DateTime.now(), accuracy: 0, altitude: 0, heading: 0, speed: 0,
      speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0,
    );
    setState(() { _currentPosition = manualPosition; _currentLocation = "${location.name} (Override)"; _gateState = GateState.allowed; });
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) { await launchUrl(uri); }
    else { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Link integration failure"))); }
  }

  bool get _isLoggedIn => FirebaseAuth.instance.currentUser != null;

  void _goToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (r) => false,
    );
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          bool isDeleting = false;
          bool isDeletedSuccess = false;

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text(isDeletedSuccess ? "Data Purged" : "System Decommission Check", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDeleting) ...[
                  const CircularProgressIndicator(color: AppColors.accent),
                  const SizedBox(height: 20),
                  const Text("Removing profile secure frames...", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent)),
                ] else if (isDeletedSuccess) ...[
                  const Icon(Icons.check_circle, color: AppColors.success, size: 60),
                  const SizedBox(height: 12),
                  const Text(" E-Commerce identity scrub completed safely.", textAlign: TextAlign.center),
                ] else
                  const Text("Warning: Terminating your account breaks cross-app storage sync arrays and configurations permanently."),
              ],
            ),
            actions: [
              if (!isDeleting && !isDeletedSuccess) ...[
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Abort", style: TextStyle(color: AppColors.textLight))),
                TextButton(
                  onPressed: () async {
                    setDialogState(() => isDeleting = true);
                    try {
                      final uid = user.uid;
                      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
                      await user.reload();
                      await FirebaseAuth.instance.currentUser?.delete();
                      if (mounted) setDialogState(() { isDeleting = false; isDeletedSuccess = true; });
                    } catch (e) {
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Authentication stale. Re-login required to commit deletion."), backgroundColor: AppColors.accent));
                      }
                    }
                  },
                  child: const Text("SCRUB ALL DATA", style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
                ),
              ],
              if (isDeletedSuccess)
                TextButton(
                  onPressed: _logout,
                  child: const Text("Return to Terminal Root"),
                ),
            ],
          );
        },
      ),
    );
  }

  List<Map<String, dynamic>> get services => [
    {
      'title': 'Food Delivery', 
      'subtitle': 'Hot meals from restaurants',
      'tag': '20 min',
      'gradient': [const Color(0xFFFF416C), const Color(0xFFFF4B2B)],
      'image': 'assets/instahub/s1.png', 
      'screen': const FoodHomeScreen(), 
      'isAvailable': true
    },
    {
      'title': 'Instahub', 
      'subtitle': 'Groceries delivered instantly',
      'tag': '10 min',
      'gradient': [const Color(0xFF11998e), const Color(0xFF38ef7d)],
      'image': 'assets/instahub/s2.png', 
      'screen': const InstantOrderHomeScreen(), 
      'isAvailable': true
    },
    {
      'title': 'Morning Orders', 
      'subtitle': 'Daily fresh essentials',
      'tag': 'Before 7 AM',
      'gradient': [const Color(0xFF00c6ff), const Color(0xFF0072ff)],
      'image': 'assets/instahub/s6.png', 
      'screen': const MorningOrderHomeScreen(), 
      'isAvailable': true
    },
    {
      'title': 'Other Services', 
      'subtitle': 'Home care & premium hubs',
      'tag': 'Explore',
      'gradient': [const Color(0xFF7F00FF), const Color(0xFFE100FF)],
      'image': 'assets/instahub/s9.png', 
      'screen': const OtherServicesScreen(), 
      'isAvailable': true
    },
  ];

  List<Map<String, dynamic>> get exploreServices => [
    {'title': 'Home Service', 'image': 'assets/instahub/home.png', 'screen': const HomeServicesScreen()},
    {'title': 'Laundry', 'image': 'assets/instahub/laundry.png', 'screen': const OtherServicesScreen()}, 
    {'title': 'Pharmacy', 'image': 'assets/instahub/pharmacy.png', 'screen': const OtherServicesScreen()},
    {'title': 'Beauty & Wellness', 'image': 'assets/instahub/beauty.png', 'screen': const OtherServicesScreen()},
    {'title': 'Healthcare', 'image': 'assets/instahub/healthcare.png', 'screen': const OtherServicesScreen()},
    {'title': 'Events', 'image': 'assets/instahub/events.png', 'screen': const OtherServicesScreen()},
  ];

  @override
  Widget build(BuildContext context) {
    switch (_gateState) {
      case GateState.loading: 
        return const Scaffold(
          backgroundColor: AppColors.primary,
          body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
        );
      case GateState.locationOffOrDenied: return _buildLocationRequiredScreen();
      case GateState.outOfArea: return _buildComingSoonScreen(); 
      case GateState.allowed: return _buildMainContent();
    }
  }

  Scaffold _buildLocationRequiredScreen() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20)]),
                child: const Icon(Icons.location_off_rounded, size: 80, color: AppColors.accent),
              ),
              const SizedBox(height: 32),
              const Text("Location Matrix Required", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary, letterSpacing: -0.5)),
              const SizedBox(height: 12),
              const Text("FASTever requires geolocation arrays coordinates to calculate nearby dark stores and dispatch routes correctly.", textAlign: TextAlign.center, style: TextStyle(color: AppColors.textLight, fontSize: 14)),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity, 
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary, 
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 18)
                  ),
                  onPressed: () => Geolocator.openLocationSettings(), 
                  child: const Text("Authorize Geolocation Settings", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Scaffold _buildComingSoonScreen() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text("Perimeter Bounds\nComing Soon", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.primary, height: 1.1)),
              const SizedBox(height: 12),
              const Text("Your explicit GPS address is outside our live fulfillment sectors right now.", style: TextStyle(color: AppColors.textLight, fontSize: 15)),
              const SizedBox(height: 32),
              if (_serviceLocations.isNotEmpty) ...[
                const Text("Select active system node explicitly:", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.primary, letterSpacing: 0.5)),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: _serviceLocations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, idx) {
                      final loc = _serviceLocations[idx];
                      return Container(
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.black.withOpacity(0.04))),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                          title: Text(loc.name, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
                          subtitle: Text("${loc.radiusKm} KM Protected Perimeter Bound", style: const TextStyle(fontSize: 12)),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.primary),
                          onTap: () => _selectManualLocation(loc),
                        ),
                      );
                    },
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AppColors.accent),
                    onPressed: _initGate, 
                    icon: const Icon(Icons.refresh_rounded, size: 18), 
                    label: const Text("Re-verify Geolocation Arrays", style: TextStyle(fontWeight: FontWeight.bold))
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: Drawer(
        backgroundColor: Colors.white,
        child: ListView(
          padding: EdgeInsets.zero, 
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: AppColors.primary), 
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, 
                mainAxisAlignment: MainAxisAlignment.end, 
                children: const [
                  Icon(Icons.layers_sharp, color: AppColors.accent, size: 40), 
                  SizedBox(height: 12),
                  Text('FASTever Core', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                  Text('System Console Engine v1.0.0', style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace')),
                ],
              ),
            ),
            ListTile(leading: const Icon(Icons.home_filled, color: AppColors.primary), title: const Text('Dashboard Module'), onTap: () => Navigator.pop(context)),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: const Text('Privacy Frame policy'), onTap: () => _launchURL('https://sites.google.com/view/fastever-privacy')),
            ListTile(leading: const Icon(Icons.description_outlined), title: const Text('Terms of Operations'), onTap: () => _launchURL('https://sites.google.com/view/fastever-termsconditions/home')),
            const Divider(height: 1),
            if (_isLoggedIn) ...[
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent),
                title: const Text('Scrub User Core', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                onTap: _deleteAccount,
              ),
              ListTile(
                leading: const Icon(Icons.power_settings_new_rounded),
                title: const Text('Disconnect Profile'),
                onTap: _logout,
              ),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.login_rounded, color: AppColors.success),
                title: const Text('Initialize Authorization Log'),
                onTap: _goToLogin,
              ),
            ],
          ],
        ),
      ),
      appBar: AppBar(
        iconTheme: const IconThemeData(color: AppColors.primary), 
        backgroundColor: AppColors.background, 
        elevation: 0,
        centerTitle: false,
        title: GestureDetector(
          onTap: () => setState(() => _gateState = GateState.outOfArea),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.navigation_rounded, color: AppColors.accent, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _currentLocation, 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary, overflow: TextOverflow.ellipsis)
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.primary)
            ],
          ),
        ),
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [

          // EXPLORE MORE SERVICES LABEL
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              child: Text(
                "Explore More Services 🌟", 
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textDark, letterSpacing: 0.3)
              ),
            ),
          ),

          // HORIZONTAL SLIDER ROW FRAME (BOXFIT.COVER IMAGES + BOTTOM TEXT)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 85,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: exploreServices.length,
                itemBuilder: (context, idx) {
                  final service = exploreServices[idx];
                  return GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => service['screen'])),
                    child: Container(
                      width: 135,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 2))
                        ],
                        border: Border.all(color: Colors.black.withOpacity(0.025))
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: SizedBox(
                                width: double.infinity,
                                height: double.infinity,
                                child: Image.asset(
                                  service['image'], 
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: AppColors.primary.withOpacity(0.05),
                                      child: const Icon(Icons.category_outlined, size: 18, color: AppColors.textLight),
                                    );
                                  },
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      service['title'], 
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: AppColors.textDark),
                                      maxLines: 1, 
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          
          // SECTION LABEL: MAIN RAPID MATRIX
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text("Quick Services ⚡", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary, letterSpacing: -0.5)),
                  Text("Premium contextual on-demand hubs optimized instantly", style: TextStyle(color: AppColors.textLight, fontSize: 12)),
                ],
              ),
            ),
          ),

          // RE-ENGINEERED 2-COLUMN FLOATING SERVICE MODULE CARDS (BALANCED RATIO & TIGHT CORES)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate((context, index) {
                final item = services[index];
                return GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => item['screen'])),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 12, offset: const Offset(0, 4))
                      ],
                      border: Border.all(color: Colors.black.withOpacity(0.03))
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 8,
                                child: SizedBox(
                                  width: double.infinity,
                                  height: double.infinity,
                                  child: Image.asset(
                                    item['image'], 
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        item['title'], 
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        item['subtitle'], 
                                        style: const TextStyle(fontSize: 10, color: AppColors.textLight, fontWeight: FontWeight.w500), 
                                        maxLines: 1, 
                                        overflow: TextOverflow.ellipsis
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            ],
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(30)),
                              child: Text(
                                item['tag'], 
                                style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold),
                                maxLines: 1,
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                );
              }, childCount: services.length),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, 
                mainAxisSpacing: 16, 
                crossAxisSpacing: 16, 
                childAspectRatio: 0.88 
              )
            ),
          ),

          // PREMIUM COMPONENT BANNER AREA
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 8),
              child: const HeaderAdVideo(tag: 'hads1'),
            ),
          ),

          // SECTION LABEL: TRENDING CAROUSEL MODULES
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text("Popular Today 🔥", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.primary, letterSpacing: -0.5)),
                  Text("View All", style: TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),

          // HORIZONTAL SNAP SLIDER: POPULAR ITEMS
          SliverToBoxAdapter(
            child: SizedBox(
              height: 150,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildPopularHorizonCard("🚨 Classic Pizza Deal", "50% OFF INSTANTLY", "Order Now →", const Color(0xFFFF9900)),
                  _buildPopularHorizonCard("🍔 Smash Burgers", "Free Delivery Runs", "Secure Pack →", const Color(0xFF00C6FF)),
                  _buildPopularHorizonCard("🥛 Fresh Dairy Bundles", "Morning Lock-In", "Reserve Slot →", const Color(0xFF7F00FF)),
                ],
              ),
            ),
          ),

          // DYNAMIC HELP & CUSTOMER SERVICE DESK FOOTER
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 48),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 10))]
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text("Need Operational Help?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          SizedBox(height: 4),
                          Text("Our logistics network dispatcher is live 24/7.", style: TextStyle(color: Colors.white60, fontSize: 12)),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                      ),
                      onPressed: () => _launchURL("https://sites.google.com/view/fastever-privacy"), 
                      child: const Text("Support", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))
                    )
                  ],
                ),
              ),
            ),
          ),

        ],
      ),
    );
  }

  Widget _buildPopularHorizonCard(String title, String highlight, String action, Color variant) {
    return Container(
      width: 260,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [variant, variant.withOpacity(0.8)]),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: variant.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: -0.5)),
          const SizedBox(height: 4),
          Text(highlight, style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5)),
          const Spacer(),
          Text(action, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Unified Other Services View (Injected locally to guarantee error-free compiling)
// ---------------------------------------------------------------------
class OtherServicesScreen extends StatelessWidget {
  const OtherServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> allServices = [
      {'title': 'Home Service', 'image': 'assets/instahub/homee.png', 'screen': const HomeServicesScreen()},
      {'title': 'Laundry', 'image': 'assets/instahub/laundryy.png', 'screen': const LaundryServiceForm()},
      {'title': 'Car Wash', 'image': 'assets/instahub/carwashh.png', 'screen': null},
      {'title': 'Book Your Time', 'image': 'assets/instahub/bookyy.png', 'screen': null},
      {'title': 'Take Ride', 'image': 'assets/instahub/ridey.png', 'screen': null},
      {'title': 'Pharmacy', 'image': 'assets/instahub/pharmacyy.png', 'screen': null},
      {'title': 'Events', 'image': 'assets/instahub/eventyy.png', 'screen': null},
      
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "All Services 🌟",
          style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: GridView.builder(
            physics: const BouncingScrollPhysics(),
            itemCount: allServices.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.88,
            ),
            itemBuilder: (context, index) {
              final item = allServices[index];
              return GestureDetector(
                onTap: () {
                  if (item['screen'] != null) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => item['screen']));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("${item['title']} subsystem coming online soon!")),
                    );
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 12, offset: const Offset(0, 4))
                    ],
                    border: Border.all(color: Colors.black.withOpacity(0.03)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 7,
                          child: SizedBox(
                            width: double.infinity,
                            height: double.infinity,
                            child: Image.asset(
                              item['image'],
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  item['title'],
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.primary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  "Tap to book",
                                  style: TextStyle(fontSize: 10, color: AppColors.textLight, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}