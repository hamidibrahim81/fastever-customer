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
import 'package:carousel_slider/carousel_slider.dart'; // ✅ Added for carousel support

// ✅ OPTIMIZATION IMPORTS
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

// Import your feature screens
import '../food/food_home_screen.dart'; 
import '../instahub/InstantOrderHomeScreen.dart'; 
import '../instahub/MorningOrderHomeScreen.dart'; 
import '../auth/login_screen.dart'; 

// --- Global Route Observer for Video Playback Control ---
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

// ----------------------------------------------------------------------
// Helper Functions
// ----------------------------------------------------------------------
double parseDouble(dynamic value, {double defaultValue = 0.0}) {
  if (value is String) return double.tryParse(value) ?? defaultValue;
  if (value is num) return value.toDouble();
  return defaultValue;
}

// ----------------------------------------------------------------------
// Location Service Data Structure
// ----------------------------------------------------------------------
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

// ----------------------------------------------------------------------
// Gate State
// ----------------------------------------------------------------------
enum GateState {
  loading,
  locationOffOrDenied,
  outOfArea,
  allowed,
}

// ----------------------------------------------------------------------
// Reusable Video Player (Unchanged)
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
        _controller.setLooping(widget.looping);
        _controller.setVolume(0);
        if (widget.autoplay) _controller.play();
        setState(() {});
      }).catchError((_) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute? route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
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
    if (widget.autoplay) {
      _controller.play();
    }
    _isVisible = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.isInitialized) return;
    if (_isVisible) {
      if (state == AppLifecycleState.resumed &&
          !_controller.value.isPlaying &&
          widget.autoplay) {
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
          child: const Center(
              child: CircularProgressIndicator(color: Color(0xFFFD3C68))));
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
// Header Ad Carousel Widget (UPDATED)
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
          .get(), // Removed limit(1) to get multiple images
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
           return Shimmer.fromColors(
            baseColor: Colors.grey.shade300,
            highlightColor: Colors.grey.shade100,
            child: Container(color: Colors.white),
          );
        }
        
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(color: Colors.grey.shade200); 
        }

        final adDocs = snapshot.data!.docs;

        return CarouselSlider(
          options: CarouselOptions(
            height: double.infinity,
            viewportFraction: 1.0,
            autoPlay: true,
            autoPlayInterval: const Duration(seconds: 3), // 🔥 3 Seconds switch
            autoPlayAnimationDuration: const Duration(milliseconds: 800),
            autoPlayCurve: Curves.easeInOut,
            enlargeCenterPage: false,
          ),
          items: adDocs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final adUrl = data['url'];

            return CachedNetworkImage(
              imageUrl: adUrl ?? '',
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
// Home Screen Redesigned (With Drawer)
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
  bool _serviceLocationsLoaded = false; // ✅ Optimization Flag

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
    if (state == AppLifecycleState.resumed && _gateState == GateState.locationOffOrDenied) {
      _initGate();
    }
  }

  void _setupTokenListener() {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'fcmToken': newToken});
        debugPrint("🔥 FCM Token Refreshed and Updated");
      }
    });
  }

  void _subscribeToTopics() async {
    try {
      await FirebaseMessaging.instance.subscribeToTopic("offers");
      await FirebaseMessaging.instance.subscribeToTopic("all_users");
      debugPrint("🚀 Subscribed to topics: offers & all_users");
    } catch (e) {
      debugPrint("❌ Topic subscription failed: $e");
    }
  }

  Future<void> _loadServiceLocations() async {
    if (_serviceLocationsLoaded) return; // ✅ Don't reload if already have them
    try {
      final snap =
          await FirebaseFirestore.instance.collection('service_areas').get();
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
      final distanceMeters = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, loc.latitude, loc.longitude);
      final distanceKm = distanceMeters / 1000;
      
      if (distanceKm <= loc.radiusKm + bufferKm) {
        return true;
      }
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
        if (!mounted) return;
        setState(() {
          _gateState = GateState.locationOffOrDenied;
          _isLoadingLocation = false;
        });
        return;
      }

      // ✅ OPTIMIZATION: Try last known location first (INSTANT)
      Position? initialPosition = await Geolocator.getLastKnownPosition();

      // ✅ Request current with High accuracy to trigger high accuracy prompt
      initialPosition ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high, 
        timeLimit: const Duration(seconds: 10),
      );

      _handlePositionUpdate(initialPosition, isManual: false);

      // Start the stream in background
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 100,
        ),
      ).listen((Position position) {
        if (!mounted) {
          _positionStreamSubscription?.cancel();
          return;
        }
        _handlePositionUpdate(position, isManual: false);
      }, onError: (e) {
        debugPrint("Location Stream Error: $e");
      });

    } catch (e) {
      debugPrint("🔥 _initGate Error (likely timeout): $e");
      if (_currentPosition == null && mounted) {
        setState(() => _gateState = GateState.locationOffOrDenied);
      }
    } finally {
      if (!mounted) return;
      setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _handlePositionUpdate(Position position, {required bool isManual}) async {
    if (!isManual && _currentPosition != null) {
      final distanceInMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      if (distanceInMeters < 50) return;
    }
    
    _resolvePlaceName(position);
    
    bool inside = _isInsideAnyServiceLocation(position);

    if (!mounted) return;
    setState(() {
      _currentPosition = position;
      _gateState = inside ? GateState.allowed : GateState.outOfArea; 
    });
  }

  // ✅ UPDATED METHOD FOR SYSTEM POPUP
  Future<bool> _ensureLocationAvailable() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    // 🔥 STEP 1: If location service OFF -> trigger native system popup
    if (!serviceEnabled) {
      try {
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 3),
          ),
        );
      } catch (_) {}
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
    }

    if (!serviceEnabled) return false;

    // 🔥 STEP 2: Handle permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
  }

  Future<void> _resolvePlaceName(Position position) async {
    try {
      final placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);
      final place = placemarks.first;
      if (!mounted) return;
      setState(() {
         _currentLocation = "${place.locality ?? place.subLocality ?? 'Unknown Area'}, ${place.country ?? ''}";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _currentLocation = "Location detected"; });
    }
  }

  void _selectManualLocation(_ServiceLocation location) async {
    _positionStreamSubscription?.cancel();
    
    Position manualPosition = Position(
      latitude: location.latitude,
      longitude: location.longitude,
      timestamp: DateTime.now(),
      accuracy: 0.0,
      altitude: 0.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      altitudeAccuracy: 0.0,
      headingAccuracy: 0.0,
    );

    setState(() {
      _currentPosition = manualPosition;
      _currentLocation = "${location.name} (Manual)";
      _gateState = GateState.allowed;
    });
  }

  // --- START: ACCOUNT ACTIONS ---
  
  Future<void> _launchURL(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open link")),
      );
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    bool isDeleting = false;
    bool isDeletedSuccess = false;
    String statusMsg = "Processing deletion...";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false, 
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Deletion under process... please wait.")),
            );
          }
        },
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isDeletedSuccess ? "Success" : "Delete Account?"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isDeleting) ...[
                    const CircularProgressIndicator(color: Colors.red),
                    const SizedBox(height: 20),
                    Text(statusMsg, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                    const SizedBox(height: 10),
                    const Text("App is locked for 7 seconds to ensure your data is removed safely.", textAlign: TextAlign.center),
                  ] else if (isDeletedSuccess) ...[
                    const Icon(Icons.check_circle, color: Colors.green, size: 60),
                    const SizedBox(height: 15),
                    const Text("You are no longer a user of KEEVO. Your account has been permanently removed.", textAlign: TextAlign.center),
                  ] else
                    const Text("Are you sure? This will lock the app for 7 seconds while your account is deleted."),
                ],
              ),
              actions: [
                if (!isDeleting && !isDeletedSuccess) ...[
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("No")),
                  TextButton(
                    onPressed: () async {
                      setDialogState(() {
                        isDeleting = true;
                        statusMsg = "Deleting your data...";
                      });

                      try {
                        final String uid = user.uid;
                        await FirebaseFirestore.instance.collection('users').doc(uid).delete();
                        await user.delete();
                      } catch (e) {
                        debugPrint("Deletion task error: $e");
                      }

                      await Future.delayed(const Duration(seconds: 7));

                      if (mounted) {
                        setDialogState(() {
                          isDeleting = false;
                          isDeletedSuccess = true;
                        });
                      }
                    },
                    child: const Text("Yes, DELETE", style: TextStyle(color: Colors.red)),
                  ),
                ],
                if (isDeletedSuccess)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      onPressed: () async {
                        final checkUser = FirebaseAuth.instance.currentUser;
                        if (checkUser == null) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                            (route) => false,
                          );
                        } else {
                          setDialogState(() {
                            isDeletedSuccess = false;
                            isDeleting = true;
                            statusMsg = "Finalizing deletion...";
                          });
                          await Future.delayed(const Duration(seconds: 7));
                          setDialogState(() {
                            isDeleting = false;
                            isDeletedSuccess = true;
                          });
                        }
                      },
                      child: const Text("Back to Login", style: TextStyle(color: Colors.white)),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
  // --- END: ACCOUNT ACTIONS ---

  List<Map<String, dynamic>> get services => [
        {
          'title': 'Food Delivery',
          'image': 'assets/instahub/s1.png',
          'screen': const FoodHomeScreen(), 
          'isAvailable': true,
        },
        {
          'title': 'Instant Shopping',
          'image': 'assets/instahub/s2.png',
          'screen': const InstantOrderHomeScreen(),
          'isAvailable': true,
        },
        {
          'title': 'Morning Orders',
          'image': 'assets/instahub/s6.png',
          'screen': const MorningOrderHomeScreen(),
          'isAvailable': true,
        },
        {
          'title': 'Ride Service',
          'image': 'assets/instahub/s3.png',
          'screen': null,
          'isAvailable': false,
        },
        {
          'title': 'Home Services',
          'image': 'assets/instahub/s4.png',
          'screen': null,
          'isAvailable': false,
        },
        {
          'title': 'Book My Time',
          'image': 'assets/instahub/s5.png',
          'screen': null,
          'isAvailable': false,
        },
        {
          'title': 'Sale / Rent',
          'image': 'assets/instahub/s7.png',
          'screen': null,
          'isAvailable': false,
        },
        {
          'title': 'Travel',
          'image': 'assets/instahub/s7.png',
          'screen': null,
          'isAvailable': false,
        },
      ];
      
  Scaffold _buildLocationRequiredScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_off, size: 72, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  "Location Access is Off",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  "We need your location to show available services. Please enable it in settings.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFD3C68),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: () async => Geolocator.openLocationSettings(),
                    child: const Text("Go to Settings", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "App will automatically refresh when you return.",
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Scaffold _buildComingSoonScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_disabled, size: 72, color: Color(0xFFFD3C68)),
                const SizedBox(height: 16),
                const Text(
                  "Service is not yet available in your area.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                if (_serviceLocations.isNotEmpty)
                  Expanded(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        const Text("Select a Service Area:", style: TextStyle(fontWeight: FontWeight.bold)),
                        ..._serviceLocations.map((loc) => ListTile(
                          title: Text(loc.name),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () => _selectManualLocation(loc),
                        )).toList(),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _initGate,
                  icon: const Icon(Icons.refresh),
                  label: const Text("Re-check My Location"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_gateState) {
      case GateState.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFFFD3C68))));
      case GateState.locationOffOrDenied:
        return _buildLocationRequiredScreen();
      case GateState.outOfArea:
        return _buildComingSoonScreen(); 
      case GateState.allowed:
        return _buildMainContent();
    }
  }

  Widget _buildMainContent() {
    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF333333)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.fastfood, color: Colors.white, size: 48),
                  SizedBox(height: 10),
                  Text('KEEVO', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                  Text('v1.0.0', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Home'),
              onTap: () => Navigator.pop(context),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.privacy_tip),
              title: const Text('Privacy Policy'),
              onTap: () => _launchURL('https://sites.google.com/view/fastever-privacy'),
            ),
            ListTile(
              leading: const Icon(Icons.description),
              title: const Text('Terms & Conditions'),
              onTap: () => _launchURL('https://sites.google.com/view/fastever-termsconditions/home'),
            ),
            ListTile(
              leading: const Icon(Icons.local_shipping),
              title: const Text('Shipping & Delivery'),
              onTap: () => _launchURL('https://sites.google.com/view/shipping-and-delivery-policy-k/home'),
            ),
            ListTile(
              leading: const Icon(Icons.assignment_return),
              title: const Text('Refund & Cancellation'),
              onTap: () => _launchURL('https://sites.google.com/view/refundandcancellationpolicykee/home'),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Delete Account', style: TextStyle(color: Colors.red)),
              onTap: _deleteAccount,
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: _logout,
            ),
          ],
        ),
      ),
      
      appBar: AppBar(
        automaticallyImplyLeading: true, 
        iconTheme: const IconThemeData(color: Colors.white), 
        backgroundColor: const Color(0xFF333333),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.location_on, color: Color(0xFFFD3C68), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _currentLocation, 
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.white,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (_isLoadingLocation)
              const Padding(
                padding: EdgeInsets.only(left: 8.0),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2.0, color: Colors.white),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.edit_location_alt, color: Colors.white),
              onPressed: () {
                setState(() => _gateState = GateState.outOfArea);
              },
            )
          ],
        ),
      ),
      backgroundColor: const Color(0xfff5f5f5), 
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 220,
              width: double.infinity,
              child: Material(
                elevation: 8, 
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
                clipBehavior: Clip.antiAlias,
                child: const HeaderAdVideo(tag: 'hads1'), // 🔥 Now displays a Carousel
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 30, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "Our Services 🛍️",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF333333), 
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    "Everything you need, all in one place. Explore our offerings!",
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = services[index];
                  final isAvailable = item['isAvailable'] as bool;
                  return GestureDetector(
                    onTap: () {
                      if (isAvailable) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => item['screen'] ?? const SizedBox.shrink()),
                        );
                      } else {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text("🚀 ${item['title']} Coming Soon!"),
                            content: const Text("We're working hard to make this service available shortly."),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK", style: TextStyle(color: Color(0xFFFD3C68))))
                            ],
                          ),
                        );
                      }
                    },
                    child: ServiceGridItem(
                      title: item['title'],
                      imagePath: item['image'],
                      isAvailable: isAvailable,
                    ),
                  );
                },
                childCount: services.length,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16, 
                crossAxisSpacing: 16,
                childAspectRatio: 0.9, 
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 30),
              child: Container(
                height: 160,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFD3C68), Color(0xFFFF528A)], 
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFD3C68).withOpacity(0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text(
                            "Don't Miss Out!",
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 8),
                          Text(
                            "Exclusive deals and offers are waiting for you in our carousel!",
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 15),
                    const Icon(Icons.flash_on, color: Colors.white, size: 40),
                  ],
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)), 
        ],
      ),
    );
  }
}

class ServiceGridItem extends StatelessWidget {
  final String title;
  final String imagePath;
  final bool isAvailable;

  const ServiceGridItem({
    required this.title,
    required this.imagePath,
    required this.isAvailable,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: Image.asset(imagePath, fit: BoxFit.cover, width: double.infinity),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF333333)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (!isAvailable)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Colors.black.withOpacity(0.7),
              ),
              child: const Center(
                child: Text(
                  "Coming Soon",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }
}