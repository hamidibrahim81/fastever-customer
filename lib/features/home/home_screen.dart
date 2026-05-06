import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:video_player/video_player.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart'; 
import 'dart:math';
import 'package:firebase_messaging/firebase_messaging.dart'; 
import 'package:carousel_slider/carousel_slider.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

import '../food/food_home_screen.dart'; 
import '../instahub/InstantOrderHomeScreen.dart'; 
import '../instahub/MorningOrderHomeScreen.dart'; 
import '../auth/login_screen.dart'; 
import '../home_services/home_services_screen.dart';

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

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
// Reusable Video Player
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
          child: const Center(child: CircularProgressIndicator(color: Color(0xFFFD3C68))));
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
// Header Ad Carousel
// ----------------------------------------------------------------------
class HeaderAdVideo extends StatelessWidget {
  final String tag;
  const HeaderAdVideo({required this.tag, super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('ads')
          .where('tag', isEqualTo: tag)
          .where('active', isEqualTo: true)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
           return Shimmer.fromColors(
            baseColor: Colors.grey.shade300,
            highlightColor: Colors.grey.shade100,
            child: Container(color: Colors.white),
          );
        }
        
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            color: const Color(0xFF333333),
            child: const Center(child: Icon(Icons.shopping_bag_outlined, color: Colors.white24, size: 48)),
          ); 
        }

        final adDocs = snapshot.data!.docs;

        return CarouselSlider(
          options: CarouselOptions(
            height: double.infinity,
            viewportFraction: 1.0,
            autoPlay: true,
            autoPlayInterval: const Duration(seconds: 4),
            autoPlayAnimationDuration: const Duration(milliseconds: 800),
            autoPlayCurve: Curves.easeInOut,
          ),
          items: adDocs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return CachedNetworkImage(
              imageUrl: data['url'] ?? '',
              fit: BoxFit.cover,
              width: double.infinity,
              placeholder: (context, url) => Shimmer.fromColors(
                baseColor: Colors.grey.shade300,
                highlightColor: Colors.grey.shade100,
                child: Container(color: Colors.white),
              ),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey.shade200,
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

// ----------------------------------------------------------------------
// Home Screen Main
// ----------------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  GateState _gateState = GateState.loading;
  String _currentLocation = "Detecting...";
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
            .update({'fcmToken': newToken}).catchError((e) => debugPrint("Token sync error: $e"));
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
      debugPrint("❌ Topic subscription failed: $e");
    }
  }

  Future<void> _loadServiceLocations() async {
    if (_serviceLocationsLoaded) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('service_areas').get();
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
      debugPrint('Error loading service locations: $e');
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

      await _loadServiceLocations(); 

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
        setState(() => _currentLocation = "${place.locality ?? place.subLocality ?? 'Unknown Area'}, ${place.country ?? ''}");
      }
    } catch (_) {
      if (mounted) setState(() => _currentLocation = "Location detected");
    }
  }

  void _selectManualLocation(_ServiceLocation location) {
    _positionStreamSubscription?.cancel();
    Position manualPosition = Position(
      latitude: location.latitude, longitude: location.longitude,
      timestamp: DateTime.now(), accuracy: 0, altitude: 0, heading: 0, speed: 0,
      speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0,
    );
    setState(() { _currentPosition = manualPosition; _currentLocation = "${location.name} (Manual)"; _gateState = GateState.allowed; });
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) { await launchUrl(uri); }
    else { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not open link"))); }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
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
            title: Text(isDeletedSuccess ? "Success" : "Confirm Deletion"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDeleting) ...[
                  const CircularProgressIndicator(color: Colors.red),
                  const SizedBox(height: 20),
                  const Text("Removing your profile securely...", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                ] else if (isDeletedSuccess) ...[
                  const Icon(Icons.check_circle, color: Colors.green, size: 60),
                  const Text("Account removed permanently.", textAlign: TextAlign.center),
                ] else
                  const Text("This action will permanently delete all your data. This cannot be undone."),
              ],
            ),
            actions: [
              if (!isDeleting && !isDeletedSuccess) ...[
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                TextButton(
                  onPressed: () async {
                    setDialogState(() => isDeleting = true);
                    try {
                      final uid = user.uid;
                      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
                      await user.delete();
                      if (mounted) setDialogState(() { isDeleting = false; isDeletedSuccess = true; });
                    } catch (e) {
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("For security, please logout and login again to delete your account."), backgroundColor: Colors.red));
                      }
                    }
                  },
                  child: const Text("DELETE PERMANENTLY", style: TextStyle(color: Colors.red)),
                ),
              ],
              if (isDeletedSuccess)
                TextButton(onPressed: _logout, child: const Text("Back to Login")),
            ],
          );
        },
      ),
    );
  }

  List<Map<String, dynamic>> get services => [
    {'title': 'Food Delivery', 'image': 'assets/instahub/s1.png', 'screen': const FoodHomeScreen(), 'isAvailable': true},
    {'title': 'Instant Shopping', 'image': 'assets/instahub/s2.png', 'screen': const InstantOrderHomeScreen(), 'isAvailable': true},
    {'title': 'Morning Orders', 'image': 'assets/instahub/s6.png', 'screen': const MorningOrderHomeScreen(), 'isAvailable': true},
    {'title': 'Home Services', 'image': 'assets/instahub/s4.png', 'screen': const HomeServicesScreen(), 'isAvailable': true},
  ];

  @override
  Widget build(BuildContext context) {
    switch (_gateState) {
      case GateState.loading: return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFFFD3C68))));
      case GateState.locationOffOrDenied: return _buildLocationRequiredScreen();
      case GateState.outOfArea: return _buildComingSoonScreen(); 
      case GateState.allowed: return _buildMainContent();
    }
  }

  Scaffold _buildLocationRequiredScreen() {
    return Scaffold(
      body: Center(child: Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.location_off, size: 72, color: Colors.grey),
          const SizedBox(height: 16),
          const Text("Location Access Required", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          SizedBox(width: double.infinity, child: FilledButton(style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFD3C68), padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: () => Geolocator.openLocationSettings(), child: const Text("Open Settings"))),
        ],),),),
    );
  }

  Scaffold _buildComingSoonScreen() {
    return Scaffold(
      body: SafeArea(child: Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.location_disabled, size: 72, color: Color(0xFFFD3C68)),
          const SizedBox(height: 16),
          const Text("Not in Service Area Yet", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          if (_serviceLocations.isNotEmpty) Expanded(child: ListView(children: [
            const Text("Select a Service Area manually:", style: TextStyle(fontWeight: FontWeight.bold)),
            ..._serviceLocations.map((loc) => ListTile(title: Text(loc.name), onTap: () => _selectManualLocation(loc))),
          ])),
          TextButton.icon(onPressed: _initGate, icon: const Icon(Icons.refresh), label: const Text("Re-check My Location")),
        ],),),),
    );
  }

  Widget _buildMainContent() {
    return Scaffold(
      drawer: Drawer(
        child: ListView(padding: EdgeInsets.zero, children: [
          const DrawerHeader(decoration: BoxDecoration(color: Color(0xFF333333)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
            Icon(Icons.fastfood, color: Colors.white, size: 48), SizedBox(height: 10),
            Text('FASTever', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            Text('v1.0.0', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],),),
          ListTile(leading: const Icon(Icons.home), title: const Text('Home'), onTap: () => Navigator.pop(context)),
          const Divider(),
          ListTile(leading: const Icon(Icons.privacy_tip), title: const Text('Privacy Policy'), onTap: () => _launchURL('https://sites.google.com/view/fastever-privacy')),
          ListTile(leading: const Icon(Icons.description), title: const Text('Terms & Conditions'), onTap: () => _launchURL('https://sites.google.com/view/fastever-termsconditions/home')),
          const Divider(),
          ListTile(leading: const Icon(Icons.delete_forever, color: Colors.red), title: const Text('Delete Account', style: TextStyle(color: Colors.red)), onTap: _deleteAccount),
          ListTile(leading: const Icon(Icons.logout), title: const Text('Logout'), onTap: _logout),
        ],),
      ),
      appBar: AppBar(iconTheme: const IconThemeData(color: Colors.white), backgroundColor: const Color(0xFF333333), elevation: 0,
        title: Row(children: [
          const Icon(Icons.location_on, color: Color(0xFFFD3C68), size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(_currentLocation, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white, overflow: TextOverflow.ellipsis))),
          IconButton(icon: const Icon(Icons.edit_location_alt, color: Colors.white), onPressed: () => setState(() => _gateState = GateState.outOfArea))
        ],),
      ),
      backgroundColor: const Color(0xfff5f5f5), 
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: 220, child: Material(elevation: 8, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)), clipBehavior: Clip.antiAlias, child: const HeaderAdVideo(tag: 'hads1')))),
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 30, 20, 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text("Our Services 🛍️", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF333333))),
            SizedBox(height: 6),
            Text("Everything you need, all in one place.", style: TextStyle(color: Colors.grey, fontSize: 14)),
          ],),),),
          SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 16), sliver: SliverGrid(delegate: SliverChildBuilderDelegate((context, index) {
            final item = services[index];
            final isAvailable = item['isAvailable'] as bool;
            return GestureDetector(onTap: () {
              if (isAvailable) { Navigator.push(context, MaterialPageRoute(builder: (_) => item['screen'] ?? const SizedBox.shrink())); }
              else { showDialog(context: context, builder: (context) => AlertDialog(title: Text("${item['title']} Coming Soon"), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))])); }
            }, child: ServiceGridItem(title: item['title'], imagePath: item['image'], isAvailable: isAvailable));
          }, childCount: services.length), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.9))),
          const SliverToBoxAdapter(child: SizedBox(height: 40)), 
        ],
      ),
    );
  }
}

class ServiceGridItem extends StatelessWidget {
  final String title; final String imagePath; final bool isAvailable;
  const ServiceGridItem({required this.title, required this.imagePath, required this.isAvailable, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black12.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 5))]),
      child: Stack(fit: StackFit.expand, children: [
        Column(children: [
          Expanded(child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), child: Image.asset(imagePath, fit: BoxFit.cover, width: double.infinity))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12), child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF333333)), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        if (!isAvailable) Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: Colors.black.withOpacity(0.7)), child: const Center(child: Text("Coming Soon", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
      ],),
    );
  }
}