import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

// IMPORT GLOBAL AUTH GUARD
import 'package:fastevergo_v1/utils/auth_guards.dart';

// IMPORT GLOBAL LOADER
import 'package:fastevergo_v1/features/loading/global_loader.dart';

import '../food/food_home_screen.dart';
import '../food/track_order_screen.dart'; // Adjust only if your tracking file has a different name.
import '../food/combo_screen.dart';
import '../food/offer_screen.dart';
import '../instahub/InstantOrderHomeScreen.dart';
import '../instahub/MorningOrderHomeScreen.dart';
import '../auth/login_screen.dart';
import '../home_services/home_services_screen.dart';
import '../laundry/LaundryServiceForm.dart';
import '../car_wash/CarWashingCentresScreen.dart';
import '../book_time/book_time_screens.dart';
import '../takearide/takeridescreen.dart';
import '../pharmacy/pharmacy_order_screen.dart';
import '../lab_test/labs_list_screen.dart';
import '../profile/profile_screen2.dart';
import '../cake/cake_screen.dart';

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

// Shared Coming Soon UI for unavailable services.
// Firestore service_status values remain unchanged: false means unavailable.
Future<void> showServiceComingSoonDialog(
  BuildContext context,
  String serviceTitle,
) {
  final title = serviceTitle.trim().isEmpty ? 'This service' : serviceTitle.trim();
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 390),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 25, 20, 23),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFD65A), Color(0xFFFFB800)],
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.rocket_launch_rounded,
                        color: Color(0xFF171717),
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'COMING SOON',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF171717),
                        fontWeight: FontWeight.w900,
                        fontSize: 23,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 23, 24, 25),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 11),
                    Text(
                      'Something exciting is on the way! '
                      '$title will be available on FASTever soon. '
                      'Stay tuned for a faster, easier experience.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 14,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 23),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF111827),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Got it!',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ----------------------------------------------------------------------
// Premium Color Palette Tokens
// ----------------------------------------------------------------------
class AppColors {
  static const Color primary = Color(0xFF111827); // Deep Premium Slate/Black
  static const Color accent = Color(0xFFFF4D6D); // Vibrant Modern Pink/Red
  static const Color background = Color(0xFFF7F8FA); // Clean Crisp Background
  static const Color cardBg = Colors.white; // Card Surfaces
  static const Color success = Color(0xFF16A34A); // Trust Green
  static const Color offer = Color(0xFFF97316); // High-conversion Orange
  static const Color textDark = Color(0xFF1F2937); // Deep Text Accent
  static const Color textLight = Color(0xFF6B7280); // Secondary Subtitles
}

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
// Premium Banner Slider Component
// ----------------------------------------------------------------------
class HeaderAdBanner extends StatefulWidget {
  final String tag;
  const HeaderAdBanner({required this.tag, super.key});

  @override
  State<HeaderAdBanner> createState() => _HeaderAdBannerState();
}

class _HeaderAdBannerState extends State<HeaderAdBanner> {
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
              if (_currentBannerIndex >= _cachedAds.length) {
                _currentBannerIndex = 0;
              }
              _isLoading = false;
            });
          }
        }, onError: (Object error, StackTrace stackTrace) {
          debugPrint('Banner stream failed: $error');
          if (mounted) setState(() => _isLoading = false);
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
                  imageUrl: (data['url'] ?? '').toString(),
                  memCacheWidth: 960,
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
// Quick Services: a distinct, subtle lift-and-pulse on each card every 2s.
// Stagger the three cards inside one 2s cycle, rather than shaking them.
// Animation only repaints each card's transform and respects reduced motion.
// ----------------------------------------------------------------------
class _QuickServicePulseCard extends StatefulWidget {
  final int index;
  final Widget child;

  const _QuickServicePulseCard({
    required this.index,
    required this.child,
    super.key,
  });

  @override
  State<_QuickServicePulseCard> createState() => _QuickServicePulseCardState();
}

class _QuickServicePulseCardState extends State<_QuickServicePulseCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) return widget.child;

    return AnimatedBuilder(
      animation: _pulseController,
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        // Each card animates for ~0.67s in sequence within the 2s cycle.
        final phase = ((_pulseController.value - widget.index / 3 + 1) % 1) * 3;
        final pulse = phase < 1 ? math.sin(phase * math.pi) : 0.0;
        return Transform.translate(
          offset: Offset(0, -6.0 * pulse),
          child: Transform.scale(
            scale: 1.0 + 0.045 * pulse,
            child: child,
          ),
        );
      },
    );
  }
}

// ----------------------------------------------------------------------
// Lightweight discovery card: one entrance and a brief shake every 2 seconds.
// Animation rebuilds only the card transform, not the HomeScreen/Firestore UI.
// ----------------------------------------------------------------------
class _ExploreMoreAnimatedCard extends StatefulWidget {
  final String image;
  final VoidCallback onTap;

  const _ExploreMoreAnimatedCard({required this.image, required this.onTap});

  @override
  State<_ExploreMoreAnimatedCard> createState() =>
      _ExploreMoreAnimatedCardState();
}

class _ExploreMoreAnimatedCardState extends State<_ExploreMoreAnimatedCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: reduceMotion ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 1450),
      curve: Curves.easeOutCubic,
      builder: (context, progress, child) => Opacity(
        opacity: progress,
        child: Transform.translate(
          offset: Offset(0, (1 - progress) * 36),
          child: child,
        ),
      ),
      child: AnimatedBuilder(
        animation: _shakeController,
        builder: (context, child) {
          // Small movement for the first 0.3 seconds of each 2-second cycle.
          final phase = _shakeController.value;
          final shake = reduceMotion || phase >= 0.15
              ? 0.0
              : math.sin(phase / 0.15 * math.pi) *
                  math.sin(phase / 0.15 * 6 * math.pi) * 3.0;
          return Transform.translate(offset: Offset(shake, 0), child: child);
        },
        child: RepaintBoundary(
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              child: SizedBox(
                height: 122,
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      height: double.infinity,
                      child: Image.asset(
                        widget.image,
                        fit: BoxFit.cover,
                        cacheWidth: 420,
                        errorBuilder: (context, error, stackTrace) =>
                            const ColoredBox(
                          color: Color(0xFFF3F4F6),
                          child: Icon(Icons.grid_view_rounded),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Other Services',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'Explore more services available on FASTever',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.3,
                                color: AppColors.textLight,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 7),
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Tap to explore',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(Icons.arrow_forward_rounded, size: 15,
                                    color: AppColors.primary),
                              ],
                            ),
                          ],
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

// ----------------------------------------------------------------------
// Seamlessly looping, lightweight Explore More Services strip.
// The static cards are built once; only their composited position animates.
// No Firestore requests, timers or setState calls are made per frame.
// ----------------------------------------------------------------------
class _LoopingExploreServicesStrip extends StatefulWidget {
  final List<Map<String, dynamic>> services;
  final void Function(Map<String, dynamic> service) onServiceTap;

  const _LoopingExploreServicesStrip({
    required this.services,
    required this.onServiceTap,
  });

  @override
  State<_LoopingExploreServicesStrip> createState() =>
      _LoopingExploreServicesStripState();
}

class _LoopingExploreServicesStripState
    extends State<_LoopingExploreServicesStrip>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double _cardWidth = 135;
  static const double _cardMargin = 6;
  static const double _itemWidth = _cardWidth + _cardMargin * 2;
  static const double _pixelsPerSecond = 28;
  static const Duration _resumeDelay = Duration(seconds: 3);

  late final AnimationController _animation;
  late final ScrollController _scrollController;
  Timer? _resumeTimer;
  bool _fingerDown = false;
  bool _appResumed = true;
  bool _reduceMotion = false;
  bool _userScrolling = false;

  double get _cycleWidth => widget.services.length * _itemWidth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animation = AnimationController(vsync: this)..addListener(_tick);
    _scrollController = ScrollController(initialScrollOffset: _cycleWidth);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resumeAnimation();
    });
  }

  double _wrap(double offset) {
    if (_cycleWidth <= 0) return 0;
    return ((offset % _cycleWidth) + _cycleWidth) % _cycleWidth;
  }

  void _tick() {
    if (!_scrollController.hasClients || _fingerDown || _userScrolling ||
        !_appResumed || _reduceMotion || _cycleWidth <= 0) return;
    // The three identical copies make the loop visually seamless.
    final offset = _cycleWidth * (1 + _animation.value);
    _scrollController.jumpTo(offset);
  }

  void _pause() {
    _resumeTimer?.cancel();
    _resumeTimer = null;
    _animation.stop();
  }

  void _scheduleResume() {
    _pause();
    _resumeTimer = Timer(_resumeDelay, () {
      _resumeTimer = null;
      if (!mounted || _fingerDown || _userScrolling) return;
      _resumeAnimation();
    });
  }

  void _resumeAnimation() {
    if (!mounted || !_appResumed || _reduceMotion || _fingerDown ||
        _userScrolling || widget.services.length < 2 ||
        !_scrollController.hasClients) return;
    final position = _wrap(_scrollController.offset);
    // Recenter on the middle copy, preserving the exact visible card.
    _scrollController.jumpTo(_cycleWidth + position);
    _animation.duration = Duration(
      milliseconds: (_cycleWidth / _pixelsPerSecond * 1000).round(),
    );
    _animation.value = position / _cycleWidth;
    _animation.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _pause();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _resumeTimer == null) _resumeAnimation();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _LoopingExploreServicesStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.services.length != widget.services.length) {
      _pause();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _animation.value = 0;
        _scrollController.jumpTo(_cycleWidth);
        _resumeAnimation();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    if (!_appResumed) {
      _pause();
    } else if (!_fingerDown && !_userScrolling) {
      _resumeAnimation();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeTimer?.cancel();
    _animation.removeListener(_tick);
    _animation.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _card(Map<String, dynamic> service, int index) {
    return Padding(
      key: ValueKey('explore-$index-${service['key']}'),
      padding: const EdgeInsets.symmetric(horizontal: _cardMargin),
      child: SizedBox(
        width: _cardWidth,
        child: RepaintBoundary(
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => widget.onServiceTap(service),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: SizedBox(
                      width: double.infinity,
                      child: Image.asset(
                        service['image'] as String,
                        fit: BoxFit.cover,
                        cacheWidth: 350,
                        errorBuilder: (context, error, stackTrace) =>
                            const ColoredBox(
                          color: Color(0xFFF3F4F6),
                          child: Center(
                            child: Icon(Icons.category_outlined,
                                size: 18, color: AppColors.textLight),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          service['title'] as String,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                            color: AppColors.textDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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

  @override
  Widget build(BuildContext context) {
    if (widget.services.isEmpty) return const SizedBox.shrink();
    final count = widget.services.length;
    return SizedBox(
      height: 85,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          _fingerDown = true;
          _pause();
        },
        onPointerUp: (_) {
          _fingerDown = false;
          if (!_userScrolling) _scheduleResume();
        },
        onPointerCancel: (_) {
          _fingerDown = false;
          if (!_userScrolling) _scheduleResume();
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollStartNotification &&
                notification.dragDetails != null) {
              _userScrolling = true;
              _pause();
            } else if (notification is ScrollEndNotification &&
                _userScrolling) {
              _userScrolling = false;
              if (!_fingerDown) _scheduleResume();
            }
            return false;
          },
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: count * 3,
            itemExtent: _itemWidth,
            itemBuilder: (context, index) =>
                _card(widget.services[index % count], index),
          ),
        ),
      ),
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
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSubscription;
  StreamSubscription<String>? _tokenSubscription;

  GateState _gateState = GateState.loading;
  String _currentLocation = "Detecting Location Node...";
  bool _isLoadingLocation = true;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  List<_ServiceLocation> _serviceLocations = [];
  bool _serviceLocationsLoaded = false;
  bool _gateInitializing = false;
  // A manually chosen service area is intentional (including remote orders).
  // GPS updates must never silently override it.
  bool _manualAreaSelected = false;
  int _locationGeneration = 0;
  bool _serviceAreaLoadFailed = false;
  int _geocodeRequestId = 0;
  Map<String, dynamic> _serviceStatuses = {};

  DateTime? _lastBackPressedAt;
  bool _exitDialogOpen = false;

  Future<void> _handleHomeBackPress() async {
    if (!mounted || _exitDialogOpen) return;
    final now = DateTime.now();
    final previous = _lastBackPressedAt;
    if (previous == null || now.difference(previous) > const Duration(seconds: 2)) {
      _lastBackPressedAt = now;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
        ));
      return;
    }

    _lastBackPressedAt = null;
    _exitDialogOpen = true;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    try {
      final shouldExit = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Exit FASTever?'),
          content: const Text('Are you sure you want to quit the app?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Yes'),
            ),
          ],
        ),
      );
      if (shouldExit == true && mounted) {
        await SystemNavigator.pop();
      }
    } finally {
      _exitDialogOpen = false;
    }
  }


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initGate();
    _setupTokenListener();
    _subscribeToTopics();
    _listenToServiceStatuses();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStreamSubscription?.cancel();
    _statusSubscription?.cancel();
    _tokenSubscription?.cancel();
    _geocodeRequestId++;
    _locationGeneration++;
    super.dispose();
  }

  void _listenToServiceStatuses() {
    _statusSubscription = FirebaseFirestore.instance
        .collection('app_settings')
        .doc('service_status')
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            if (mounted) {
              setState(() {
                _serviceStatuses = snapshot.data()!;
              });
            }
          }
        }, onError: (Object error, StackTrace stackTrace) {
          debugPrint('Service status listener failed: $error');
        });
  }

  void _handleServiceTap(
    String serviceKey,
    String serviceTitle,
    Widget? screen, {
    bool requiresAuth = true,
  }) {
    if (requiresAuth &&
        !requireLoginGlobal("Please login to access $serviceTitle")) {
      return;
    }

    final isAvailable = _serviceStatuses[serviceKey] != false;

    if (!isAvailable) {
      _showMaintenanceDialog(serviceTitle);
      return;
    }

    if (screen != null) {
      GlobalLoader.run(
        duration: const Duration(milliseconds: 1800),
        task: () async {
          if (mounted) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
          }
        },
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("$serviceTitle coming soon!")));
    }
  }

  void _showMaintenanceDialog(String serviceTitle) {
    showServiceComingSoonDialog(context, serviceTitle);
  }

  void _showSupportBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return FutureBuilder<QuerySnapshot>(
          future: FirebaseFirestore.instance
              .collection('customer_supprt')
              .limit(1)
              .get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 250,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                ),
              );
            }

            String supportCall = "";
            String supportMail = "";

            if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
              final data =
                  snapshot.data!.docs.first.data() as Map<String, dynamic>;
              supportCall = (data['support_call'] ?? '').toString();
              supportMail = (data['support_mail'] ?? '').toString();
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: const [
                        Icon(
                          Icons.headset_mic_rounded,
                          color: AppColors.accent,
                          size: 28,
                        ),
                        SizedBox(width: 10),
                        Text(
                          "FASTever Support",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Our customer support team is always active and ready to assist you. Choose how you'd like to reach us:",
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textLight,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (supportCall.isNotEmpty) ...[
                      InkWell(
                        onTap: () async {
                          final uri = Uri.parse("tel:$supportCall");
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          } else {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Could not make call"),
                                ),
                              );
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: const BoxDecoration(
                                  color: AppColors.success,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.phone_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "Call Us Directly",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      supportCall,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.success,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: AppColors.success,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (supportMail.isNotEmpty) ...[
                      InkWell(
                        onTap: () async {
                          final uri = Uri.parse(
                            "mailto:$supportMail?subject=FASTever Support Request",
                          );
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          } else {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Could not open mail app"),
                                ),
                              );
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFFECDD3)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: const BoxDecoration(
                                  color: AppColors.accent,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.email_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "Send an Email",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      supportMail,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.accent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: AppColors.accent,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_manualAreaSelected) {
        _positionStreamSubscription?.resume();
        if (_gateState == GateState.locationOffOrDenied ||
            _serviceAreaLoadFailed) {
          _initGate();
        }
      }
    } else if (state == AppLifecycleState.paused) {
      _positionStreamSubscription?.pause();
    }
  }

  void _setupTokenListener() {
    _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'fcmToken': newToken})
            .catchError((e) => debugPrint("Token infrastructure break: $e"));
      }
    });
  }

  void _subscribeToTopics() async {
    try {
      NotificationSettings settings = await FirebaseMessaging.instance
          .requestPermission();
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
      final snap = await FirebaseFirestore.instance
          .collection('service_areas')
          .get()
          .timeout(const Duration(seconds: 10));
      _serviceLocations = snap.docs.map((d) {
        final data = d.data();
        return _ServiceLocation(
          name: data['name']?.toString() ?? '',
          latitude: parseDouble(data['latitude']),
          longitude: parseDouble(data['longitude']),
          radiusKm: parseDouble(data['radiusKm']),
        );
      }).where((area) =>
          area.latitude.isFinite && area.longitude.isFinite &&
          area.latitude >= -90 && area.latitude <= 90 &&
          area.longitude >= -180 && area.longitude <= 180 &&
          area.radiusKm.isFinite && area.radiusKm > 0).toList();
      _serviceLocationsLoaded = true;
      _serviceAreaLoadFailed = false;
    } catch (e) {
      _serviceAreaLoadFailed = true;
      debugPrint('Error compiling perimeter maps: $e');
    }
  }

  bool _isInsideAnyServiceLocation(Position pos) {
    const bufferKm = 0.05;
    for (final loc in _serviceLocations) {
      final distanceKm =
          Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            loc.latitude,
            loc.longitude,
          ) /
          1000;
      if (distanceKm <= loc.radiusKm + bufferKm) return true;
    }
    return false;
  }

  Future<void> _initGate() async {
    if (_gateInitializing || !mounted) return;
    _gateInitializing = true;
    final generation = ++_locationGeneration;
    // An explicit re-check switches back to the customer's actual GPS.
    _manualAreaSelected = false;
    try {
      setState(() {
        _gateState = GateState.loading;
        _isLoadingLocation = true;
      });

      await _loadServiceLocations();
      if (!mounted || generation != _locationGeneration) return;
      if (!_serviceLocationsLoaded) {
        setState(() => _gateState = GateState.locationOffOrDenied);
        return;
      }

      final canLocate = await _ensureLocationAvailable();
      if (!mounted || generation != _locationGeneration) return;
      if (!canLocate) {
        setState(() => _gateState = GateState.locationOffOrDenied);
        return;
      }

      // Always request a FRESH position first. Never decide serviceability
      // from a potentially days-old getLastKnownPosition() result.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted || generation != _locationGeneration ||
          _manualAreaSelected) return;
      _handlePositionUpdate(position, isManual: false);

      await _positionStreamSubscription?.cancel();
      if (!mounted || generation != _locationGeneration ||
          _manualAreaSelected) return;
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 100,
        ),
      ).listen((Position updated) {
        if (mounted && !_manualAreaSelected &&
            generation == _locationGeneration) {
          _handlePositionUpdate(updated, isManual: false);
        }
      }, onError: (Object error, StackTrace stackTrace) {
        debugPrint('Position stream failed: $error');
      });
    } catch (e) {
      debugPrint('Fresh location detection failed: $e');
      if (mounted && generation == _locationGeneration &&
          !_manualAreaSelected) {
        setState(() => _gateState = GateState.locationOffOrDenied);
      }
    } finally {
      _gateInitializing = false;
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _handlePositionUpdate(
    Position position, {
    required bool isManual,
  }) async {
    if (!mounted || (_manualAreaSelected && !isManual)) return;
    if (!isManual && _currentPosition != null) {
      final dist = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      // Re-evaluate even with little movement if the previous fix was poor.
      if (dist < 50 &&
          position.accuracy >= _currentPosition!.accuracy &&
          _gateState != GateState.loading) return;
    }
    _resolvePlaceName(position);
    final inside = _isInsideAnyServiceLocation(position);
    setState(() {
      _currentPosition = position;
      _gateState = inside ? GateState.allowed : GateState.outOfArea;
    });
  }

  Future<bool> _ensureLocationAvailable() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      try {
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 2),
          ),
        );
      } catch (_) {}
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
    }
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
  }

  Future<void> _resolvePlaceName(Position position) async {
    final requestId = ++_geocodeRequestId;
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (mounted && requestId == _geocodeRequestId && placemarks.isNotEmpty) {
        final place = placemarks.first;
        setState(
          () => _currentLocation =
              "${place.locality ?? place.subLocality ?? 'Unknown Segment'}, ${place.administrativeArea ?? ''}",
        );
      }
    } catch (_) {
      if (mounted && requestId == _geocodeRequestId) {
        setState(() => _currentLocation = "Active Deployment Zone");
      }
    }
  }

  void _selectManualLocation(_ServiceLocation location) {
    // Preserve remote/abroad customer ordering through a chosen service area.
    _manualAreaSelected = true;
    _locationGeneration++;
    _geocodeRequestId++;
    _positionStreamSubscription?.cancel();
    Position manualPosition = Position(
      latitude: location.latitude,
      longitude: location.longitude,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      altitudeAccuracy: 0,
      headingAccuracy: 0,
    );
    setState(() {
      _currentPosition = manualPosition;
      _currentLocation = "${location.name} (Override)";
      _gateState = GateState.allowed;
    });
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !['https', 'http'].contains(uri.scheme)) return;
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Unable to launch URL');
      }
    } catch (error) {
      debugPrint('Link launch failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link')),
        );
      }
    }
  }

  bool get _isLoggedIn => FirebaseAuth.instance.currentUser != null;

  void _goToLogin() {
    GlobalLoader.run(
      duration: const Duration(milliseconds: 1800),
      task: () async {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        }
      },
    );
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    GlobalLoader.run(
      duration: const Duration(milliseconds: 1800),
      task: () async {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (r) => false,
          );
        }
      },
    );
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;
    bool deleting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text('Delete Account',
              style: TextStyle(fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (deleting) ...[
                const CircularProgressIndicator(color: AppColors.accent),
                const SizedBox(height: 16),
                const Text('Deleting your account...'),
              ] else
                const Text('Are you sure you want to delete your account? '
                    'This action is permanent and cannot be undone.'),
            ],
          ),
          actions: deleting ? null : [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (deleting) return;
                setDialogState(() => deleting = true);
                try {
                  final uid = user.uid;
                  // Delete Auth FIRST: if Firebase requires recent login,
                  // the Firestore profile remains intact for a retry.
                  await user.delete();

                  // After Auth deletion, Firestore rules may deny this write.
                  // A trusted backend cleanup (Auth onDelete / callable) is
                  // needed for guaranteed removal of all related user data.
                  bool profileCleaned = false;
                  try {
                    await FirebaseFirestore.instance
                        .collection('users').doc(uid).delete();
                    profileCleaned = true;
                  } catch (cleanupError) {
                    debugPrint('Account deleted; profile cleanup pending: '
                        '$cleanupError');
                  }

                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(profileCleaned
                        ? 'Account deleted successfully.'
                        : 'Login account deleted. Profile data cleanup '
                          'requires support; please contact FASTever.'),
                  ));
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                    (route) => false,
                  );
                } on FirebaseAuthException catch (e) {
                  if (!dialogContext.mounted) return;
                  setDialogState(() => deleting = false);
                  ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(
                    content: Text(e.code == 'requires-recent-login'
                        ? 'For security, please log in again before '
                          'deleting your account.'
                        : 'Could not delete account: ${e.message ?? e.code}'),
                  ));
                } catch (e) {
                  debugPrint('Account deletion failed: $e');
                  if (!dialogContext.mounted) return;
                  setDialogState(() => deleting = false);
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text(
                        'Unable to delete account. Please try again.')),
                  );
                }
              },
              child: const Text('DELETE ACCOUNT',
                  style: TextStyle(color: AppColors.accent,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get services => [
    {
      'key': 'food_delivery',
      'title': 'Food Delivery',
      'subtitle': 'Hot meals from restaurants',
      'tag': '20 min',
      'image': 'assets/instahub/s1.jpeg',
      'screen': FoodHomeScreen(
        selectedPosition: _currentPosition,
        selectedLocationName: _currentLocation,
      ),
      'requiresAuth': false,
    },
    {
      'key': 'instahub',
      'title': 'Instahub',
      'subtitle': 'Groceries delivered instantly',
      'tag': '10 min',
      'image': 'assets/instahub/s2.jpeg',
      'screen': const InstantOrderHomeScreen(),
      'requiresAuth': false,
    },
    {
      'key': 'morning_orders',
      'title': 'Morning Orders',
      'subtitle': 'Daily fresh essentials',
      'tag': 'Before 7 AM',
      'image': 'assets/instahub/s6.jpeg',
      'screen': const MorningOrderHomeScreen(),
      'requiresAuth': false,
    },
    {
      'key': 'other_services',
      'title': 'Other Services',
      'subtitle': 'Home care & premium hubs',
      'tag': 'Explore',
      'image': 'assets/instahub/s9.jpeg',
      'screen': const OtherServicesScreen(),
      'requiresAuth': false,
    },
  ];

  List<Map<String, dynamic>> get exploreServices => [
    {
      'key': 'book_time',
      'title': 'Turf Booking',
      'image': 'assets/instahub/turff.jpeg',
      'screen': const TurfDirectoryScreen(),
      'requiresAuth': true,
    },
    {
      'key': 'car_wash',
      'title': 'Car Wash',
      'image': 'assets/instahub/carwash.jpeg',
      'screen': const CarWashingCentresScreen(),
      'requiresAuth': true,
    },
    {
      'key': 'lab_test',
      'title': 'Lab Test',
      'image': 'assets/instahub/lab.jpeg',
      'screen': LabsListScreen(),
      'requiresAuth': true,
    },
    {
      'key': 'laundry',
      'title': 'Laundry',
      'image': 'assets/instahub/laundry.jpeg',
      'screen': const LaundryServiceForm(),
      'requiresAuth': true,
    },
    {
      'key': 'cakes_bakery',
      'title': 'Cakes & Gifts',
      'image': 'assets/instahub/cakesss.jpeg',
      'screen': const CakeScreen(),
      'requiresAuth': true,
    },
    {
      'key': 'home_service',
      'title': 'Home Service',
      'image': 'assets/instahub/home.jpeg',
      'screen': const HomeServicesScreen(),
      'requiresAuth': true,
    },
    {
      'key': 'pharmacy',
      'title': 'Pharmacy',
      'image': 'assets/instahub/pharmacy.jpeg',
      'screen': const PharmacyOrderScreen(),
      'requiresAuth': true,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleHomeBackPress();
      },
      child: _buildHomeForGateState(),
    );
  }

  Widget _buildHomeForGateState() {
    switch (_gateState) {
      case GateState.loading:
        return const Scaffold(
          backgroundColor: AppColors.primary,
          body: Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          ),
        );
      case GateState.locationOffOrDenied:
        return _buildLocationRequiredScreen();
      case GateState.outOfArea:
        return _buildComingSoonScreen();
      case GateState.allowed:
        return _buildMainContent();
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
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.location_off_rounded,
                  size: 80,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                "Location Access Required",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "FASTever needs your location to find nearby stores, services, and delivery options.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textLight, fontSize: 14),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  onPressed: () async {
                    final permission = await Geolocator.checkPermission();
                    if (permission == LocationPermission.deniedForever) {
                      await Geolocator.openAppSettings();
                    } else {
                      await Geolocator.openLocationSettings();
                    }
                    if (mounted && !_manualAreaSelected) _initGate();
                  },
                  child: const Text(
                    "Enable Location",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
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
              const Text(
                "Coming Soon\nTo Your Area",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Your current location is outside our service area right now.",
                style: TextStyle(color: AppColors.textLight, fontSize: 15),
              ),
              const SizedBox(height: 32),
              if (_serviceLocations.isNotEmpty) ...[
                const Text(
                  "Select an available area:",
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: AppColors.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: _serviceLocations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, idx) {
                      final loc = _serviceLocations[idx];
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.black.withOpacity(0.04),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 4,
                          ),
                          title: Text(
                            loc.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          subtitle: Text(
                            "Service within ${loc.radiusKm} KM",
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: AppColors.primary,
                          ),
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
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.accent,
                    ),
                    onPressed: _initGate,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text(
                      "Re-check My Location",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
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
      bottomNavigationBar: const _ActiveOrderTrackingBar(),
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
                  Text(
                    'FASTever',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    'Everyday Services @ Doorstep',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home_rounded, color: AppColors.primary),
              title: const Text(
                'Home',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () => Navigator.pop(context),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy Policy'),
              onTap: () =>
                  _launchURL('https://sites.google.com/view/fastever-privacy'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Terms & Conditions'),
              onTap: () => _launchURL(
                'https://sites.google.com/view/fastever-termsconditions/home',
              ),
            ),
            const Divider(height: 1),
            if (_isLoggedIn) ...[
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Delete Account',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: _deleteAccount,
              ),
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('Logout'),
                onTap: _logout,
              ),
            ] else ...[
              ListTile(
                leading: const Icon(
                  Icons.login_rounded,
                  color: AppColors.success,
                ),
                title: const Text(
                  'Login / Register',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _goToLogin();
                },
              ),
            ],
          ],
        ),
      ),
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: AppColors.primary,
        elevation: 6,
        shadowColor: Colors.black.withOpacity(0.3),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        centerTitle: false,
        title: const Text(
          "FASTever",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.account_circle_outlined,
              color: Colors.white,
              size: 26,
            ),
            onPressed: () {
              if (!requireLoginGlobal("Please login to access profile")) return;
              GlobalLoader.run(
                duration: const Duration(milliseconds: 1800),
                task: () async {
                  if (mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfileScreen2(),
                      ),
                    );
                  }
                },
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // EXPLORE MORE SERVICES LABEL
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              child: const Text(
                "Explore More Services",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),

          // Seamless auto-scrolling service cards, looping from last to first.
          // Pause while touched so customers can tap without chasing a card.
          SliverToBoxAdapter(
            child: _LoopingExploreServicesStrip(
              services: exploreServices,
              onServiceTap: (service) => _handleServiceTap(
                service['key'] as String,
                service['title'] as String,
                service['screen'] as Widget?,
                requiresAuth: service['requiresAuth'] as bool? ?? true,
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
                  Text(
                    "Quick Services",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    "Fast on-demand delivery at your doorstep",
                    style: TextStyle(color: AppColors.textLight, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          // QUICK SERVICES: three compact cards in the first row.
          // Each card lifts/pulses in turn during every 2-second cycle.
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 10,
                childAspectRatio: 0.70,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = services[index];
                  return _QuickServicePulseCard(
                    key: ValueKey('quick-service-${item['key']}'),
                    index: index,
                    child: RepaintBoundary(
                      child: GestureDetector(
                        onTap: () => _handleServiceTap(
                          item['key'],
                          item['title'],
                          item['screen'],
                          requiresAuth: item['requiresAuth'] ?? false,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.035),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Stack(
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 6,
                                      child: SizedBox.expand(
                                        child: Image.asset(
                                          item['image'],
                                          fit: BoxFit.cover,
                                          cacheWidth: 360,
                                          errorBuilder: (context, error, stackTrace) =>
                                              const ColoredBox(
                                            color: Color(0xFFF3F4F6),
                                            child: Center(
                                              child: Icon(
                                                Icons.category_outlined,
                                                color: AppColors.textLight,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 4,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              item['title'],
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                                height: 1.12,
                                                color: AppColors.primary,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              item['subtitle'],
                                              style: const TextStyle(
                                                fontSize: 9,
                                                height: 1.1,
                                                color: AppColors.textLight,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Container(
                                    constraints: const BoxConstraints(maxWidth: 85),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.93),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      item['tag'],
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
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
                },
                childCount: math.min(3, services.length),
              ),
            ),
          ),

          // Fourth service is a full-width discovery card below the first row.
          // Only this card shakes gently every two seconds.
          if (services.length > 3)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _ExploreMoreAnimatedCard(
                  image: services[3]['image'],
                  onTap: () => _handleServiceTap(
                    services[3]['key'],
                    services[3]['title'],
                    services[3]['screen'],
                    requiresAuth: services[3]['requiresAuth'] ?? false,
                  ),
                ),
              ),
            ),

          // PREMIUM COMPONENT BANNER AREA
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 8),
              child: const HeaderAdBanner(tag: 'hads1'),
            ),
          ),

          // CAKE BANNER (NOW CHECKING service_status['cakes_bakery'])
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: InkWell(
                onTap: () {
                  _handleServiceTap(
                    'cakes_bakery',
                    'Cakes & Gifts',
                    const CakeScreen(),
                    requiresAuth: true,
                  );
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: double.infinity,
                  height: 130,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Image.asset(
                            'assets/instahub/todaycakegift1.jpeg',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(color: const Color(0xFF111827)),
                          ),
                        ),
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.black.withOpacity(0.75),
                                  Colors.black.withOpacity(0.3),
                                ],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Text(
                                      "Custom Cakes & Gifts",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      "Order fresh birthday & celebration cakes instantly",
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: const BoxDecoration(
                                  color: AppColors.accent,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // SECTION LABEL: TRENDING CAROUSEL MODULES
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Popular Today",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _handleServiceTap(
                      'food_delivery',
                      'Food Delivery',
                      FoodHomeScreen(
                        selectedPosition: _currentPosition,
                        selectedLocationName: _currentLocation,
                      ),
                      requiresAuth: false,
                    ),
                    child: const Text(
                      "View All",
                      style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ==================================================================
          // 1. POPULAR TODAY: BIG DEALS CROSS-FADE SHOWCASE CARD
          // ==================================================================
          SliverToBoxAdapter(
            child: const PopularOffersBannerCard(offerTag: 'bigdeal'),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ==================================================================
          // 2. POPULAR TODAY: MEGA COMBO DEALS CROSS-FADE SHOWCASE CARD
          // ==================================================================
          SliverToBoxAdapter(child: const PopularComboDealsBannerCard()),

          // DYNAMIC HELP & CUSTOMER SERVICE DESK FOOTER
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 48),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            "Need Help?",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "Our support team is active 24/7.",
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onPressed: _showSupportBottomSheet,
                      child: const Text(
                        "Support",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
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

// Active order tracking shortcut on the main FASTever home screen.
// Reads only the signed-in customer's master order_status documents.
class _ActiveOrderTrackingBar extends StatefulWidget {
  const _ActiveOrderTrackingBar();

  @override
  State<_ActiveOrderTrackingBar> createState() => _ActiveOrderTrackingBarState();
}

class _ActiveOrderTrackingBarState extends State<_ActiveOrderTrackingBar> {
  OverlayEntry? _miniEntry;
  Timer? _miniTimer;
  String? _miniOrderId;
  bool _miniVisible = false;
  Map<String, dynamic>? _miniData;

  @override
  void dispose() {
    _miniTimer?.cancel();
    _miniEntry?.remove();
    _miniEntry?.dispose();
    super.dispose();
  }

  void _dismissMini() {
    if (WidgetsBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _dismissMini();
      });
      return;
    }
    _miniTimer?.cancel();
    _miniTimer = null;
    _miniEntry?.remove();
    _miniEntry?.dispose();
    _miniEntry = null;
    if (mounted && _miniVisible) setState(() => _miniVisible = false);
  }

  void _showMiniIfNew(String id, Map<String, dynamic> data) {
    // Only announce a newly placed order; old active orders retain the bar.
    final created = _created(data);
    if (DateTime.now().difference(created).inSeconds > 90 ||
        DateTime.now().isBefore(created)) return;
    if (_miniOrderId == id) {
      _miniData = data;
      // A Firestore StreamBuilder can run during the build phase.
      // Defer overlay updates until the frame is complete.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _miniOrderId == id && _miniEntry != null) {
          _miniEntry!.markNeedsBuild();
        }
      });
      return;
    }
    _miniOrderId = id;
    _miniData = data;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _miniOrderId != id) return;
      _miniTimer?.cancel();
      _miniEntry?.remove();
      _miniEntry?.dispose();
      _miniVisible = true;
      _miniEntry = OverlayEntry(builder: (overlayContext) {
        final latest = _miniData ?? data;
        final status = _status(latest);
        final name = _partnerField(latest, false);
        final phone = _partnerField(latest, true);
        final assigned = _isPartnerAssigned(latest, name);
        return Positioned.fill(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Material(
                elevation: 18,
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(22),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        tooltip: 'Minimize to bottom tracking bar',
                        onPressed: _dismissMini,
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                      ),
                    ),
                    const Icon(Icons.delivery_dining_rounded,
                        color: Color(0xFFFFB800), size: 48),
                    const SizedBox(height: 8),
                    const Text('Your active order',
                        style: TextStyle(color: Colors.white, fontSize: 19,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text(_label(status), textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFFFB800),
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Text(assigned && name.isNotEmpty
                        ? 'Delivery partner: $name'
                        : 'Waiting for delivery partner assignment',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _dismissMini();
                          _openTracking(id);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFB800),
                          foregroundColor: const Color(0xFF111827),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        icon: const Icon(Icons.location_on_rounded),
                        label: const Text('Track Order',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                    if (assigned && phone.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _callPartner(phone),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF16A34A)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.call_rounded,
                              color: Color(0xFF4ADE80)),
                          label: const Text('Call Delivery Partner'),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        );
      });
      Overlay.of(context).insert(_miniEntry!);
      if (mounted) setState(() {});
      _miniTimer = Timer(const Duration(seconds: 5), _dismissMini);
    });
  }


  static const _finished = <String>{
    'delivered', 'cancelled', 'canceled', 'rejected', 'failed',
    'refunded', 'completed',
  };

  static String _status(Map<String, dynamic> data) =>
      (data['status'] ?? 'pending').toString().trim().toLowerCase();

  static DateTime _created(Map<String, dynamic> data) {
    final value = data['timestamp'];
    if (value is Timestamp) return value.toDate();
    final fallback = data['createdAt'];
    if (fallback is Timestamp) return fallback.toDate();
    return DateTime.tryParse(fallback?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  static String _label(String status) {
    switch (status) {
      case 'pending': return 'Order placed';
      case 'accepted': case 'confirmed': return 'Order confirmed';
      case 'preparing': case 'preparation': return 'Preparing your order';
      case 'ready': return 'Ready for pickup';
      case 'partner_accepted': case 'assigned': return 'Delivery partner assigned';
      case 'arrived_at_pickup': return 'Partner at restaurant';
      case 'picked': case 'picked_up': case 'out_for_delivery':
      case 'on_the_way': return 'On the way to you';
      default: return status.replaceAll('_', ' ');
    }
  }

  static String _value(dynamic value) => value == null ? '' : value.toString().trim();

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static String _partnerField(Map<String, dynamic> data, bool phone) {
    final partner = _map(data['deliveryPartner']);
    final delivery = _map(data['deliveryOrder']);
    final nested = _map(delivery['deliveryPartner']);
    final keys = phone
        ? <String>['driverPhone', 'deliveryPartnerPhone', 'partnerPhone', 'phone', 'phoneNumber', 'mobile']
        : <String>['driverName', 'deliveryPartnerName', 'partnerName', 'name', 'fullName'];
    for (final source in [data, partner, delivery, nested]) {
      for (final key in keys) {
        final value = _value(source[key]);
        if (value.isNotEmpty && value.toLowerCase() != 'null' &&
            value.toLowerCase() != 'unassigned') return value;
      }
    }
    return '';
  }

  static bool _isPartnerAssigned(Map<String, dynamic> data, String name) {
    final partnerId = _value(data['deliveryPartnerId']);
    final driverId = _value(data['driverId']);
    return (partnerId.isNotEmpty && partnerId.toLowerCase() != 'null') ||
        (driverId.isNotEmpty && driverId.toLowerCase() != 'null') ||
        (name.isNotEmpty && name.toLowerCase() != 'delivery partner');
  }

  void _openTracking(String id) {
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TrackOrderScreen(orderId: id),
    ));
  }

  Future<void> _callPartner(String phone) async {
    final number = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (number.isEmpty) return;
    try {
      await launchUrl(Uri(scheme: 'tel', path: number));
    } catch (e) {
      debugPrint('Unable to open phone dialer: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('order_status')
          .where('userId', isEqualTo: user.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.hasError) {
          return const SizedBox.shrink();
        }
        final active = snapshot.data!.docs.where((doc) {
          final status = _status(doc.data());
          return !_finished.contains(status);
        }).toList()
          ..sort((a, b) => _created(b.data()).compareTo(_created(a.data())));
        if (active.isEmpty) return const SizedBox.shrink();
        final order = active.first;
        final status = _status(order.data());
        final orderId = order.id;
        final partnerName = _partnerField(order.data(), false);
        final partnerPhone = _partnerField(order.data(), true);
        _showMiniIfNew(orderId, order.data());
        if (_miniVisible) return const SizedBox.shrink();
        final assigned = _isPartnerAssigned(order.data(), partnerName);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 5, 12, 10),
            child: Material(
              color: const Color(0xFF111827),
              elevation: 8,
              borderRadius: BorderRadius.circular(17),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _openTracking(orderId),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  child: Row(
                    children: [
                      const Icon(Icons.delivery_dining_rounded,
                          color: Color(0xFFFFB800), size: 29),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_label(status),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white,
                                    fontSize: 14, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 3),
                            Text(assigned && partnerName.isNotEmpty
                                ? 'Partner: $partnerName'
                                : active.length > 1
                                    ? '${active.length} active orders Â· Tap to track latest'
                                    : 'Tap to track your delivery',
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70,
                                    fontSize: 11)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (assigned && partnerPhone.isNotEmpty) ...[
                        IconButton(
                          tooltip: 'Call delivery partner',
                          onPressed: () => _callPartner(partnerPhone),
                          icon: const Icon(Icons.call_rounded, color: Colors.white),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      TextButton(
                        onPressed: () => _openTracking(orderId),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFFFB800),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text('Track Order',
                            style: TextStyle(fontWeight: FontWeight.w800,
                                fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ----------------------------------------------------------------------
          // 1. Popular Offers Banner (STRICTLY "bigdeal" with In-Place Cross-Fade)
// ----------------------------------------------------------------------
class PopularOffersBannerCard extends StatefulWidget {
  final String offerTag;
  const PopularOffersBannerCard({super.key, this.offerTag = 'bigdeal'});

  @override
  State<PopularOffersBannerCard> createState() =>
      _PopularOffersBannerCardState();
}

class _PopularOffersBannerCardState extends State<PopularOffersBannerCard> {
  int _currentIndex = 0;
  Timer? _timer;
  int _rotatingCount = 0;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _menuStream;

  @override
  void initState() {
    super.initState();
    _menuStream = FirebaseFirestore.instance
        .collectionGroup('menu')
        .where('tags', arrayContains: widget.offerTag)
        .snapshots();
  }

  void _startTimer(int itemCount) {
    if (itemCount == _rotatingCount) return;
    _rotatingCount = itemCount;
    _timer?.cancel();
    if (itemCount <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted && TickerMode.of(context)) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % itemCount;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _menuStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Shimmer.fromColors(
              baseColor: Colors.grey.shade200,
              highlightColor: Colors.grey.shade50,
              child: Container(
                height: 165,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          );
        }

        final docs = (snapshot.data?.docs ?? []).where((d) {
          final data = d.data() as Map<String, dynamic>;
          final tags = data['tags'];
          if (tags is List) {
            return tags.contains(widget.offerTag);
          }
          return false;
        }).toList();

        if (docs.isEmpty) {
          _startTimer(0);
          return const SizedBox.shrink();
        }

        if (_currentIndex >= docs.length) {
          _currentIndex = 0;
        }

        _startTimer(docs.length);

        final currentDoc = docs[_currentIndex];
        final data = currentDoc.data() as Map<String, dynamic>;
        final String name = data['name'] ?? 'Big Deal';
        final double price = parseDouble(data['price']);
        final double originalPrice = parseDouble(
          data['mrp'] ?? data['originalPrice'],
        );
        final String imageUrl = (data['imageUrl'] ?? data['image'] ?? '')
            .toString();

        String discountBadge = "BIG DEAL";
        if (originalPrice > price && originalPrice > 0) {
          final int percent = (((originalPrice - price) / originalPrice) * 100)
              .round();
          if (percent > 0) discountBadge = "$percent% OFF";
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GestureDetector(
            onTap: () {
              if (!requireLoginGlobal("Please login to view offers")) return;
              GlobalLoader.run(
                duration: const Duration(milliseconds: 1800),
                task: () async {
                  if (mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OfferScreen(
                          title: "Today's Big Deals",
                          offerTag: 'bigdeal',
                        ),
                      ),
                    );
                  }
                },
              );
            },
            child: Container(
              height: 165,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1E43),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 600),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                        child: imageUrl.isNotEmpty
                            ? CachedNetworkImage(
                                key: ValueKey<String>(imageUrl),
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                placeholder: (_, __) =>
                                    Container(color: const Color(0xFF1A1E43)),
                                errorWidget: (_, __, ___) =>
                                    Container(color: const Color(0xFF1A1E43)),
                              )
                            : Container(
                                key: const ValueKey<String>('empty_image'),
                                color: const Color(0xFF1A1E43),
                              ),
                      ),
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.85),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              discountBadge,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            child: Text(
                              name,
                              key: ValueKey<String>(name),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                letterSpacing: -0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                "Rs. ${price.toInt()}",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              if (originalPrice > price) ...[
                                const SizedBox(width: 8),
                                Text(
                                  "Rs. ${originalPrice.toInt()}",
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 12,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              ],
                              const Spacer(),
                              const Text(
                                "View Deals >",
                                style: TextStyle(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ----------------------------------------------------------------------
          // 2. Popular Combo Deals Banner (STRICTLY "combo_deals" with In-Place Cross-Fade)
// ----------------------------------------------------------------------
class PopularComboDealsBannerCard extends StatefulWidget {
  const PopularComboDealsBannerCard({super.key});

  @override
  State<PopularComboDealsBannerCard> createState() =>
      _PopularComboDealsBannerCardState();
}

class _PopularComboDealsBannerCardState
    extends State<PopularComboDealsBannerCard> {
  int _currentIndex = 0;
  Timer? _timer;
  int _rotatingCount = 0;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _menuStream;

  @override
  void initState() {
    super.initState();
    _menuStream = FirebaseFirestore.instance
        .collectionGroup('menu')
        .where('tags', arrayContains: 'combo_deals')
        .snapshots();
  }

  void _startTimer(int itemCount) {
    if (itemCount == _rotatingCount) return;
    _rotatingCount = itemCount;
    _timer?.cancel();
    if (itemCount <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (mounted && TickerMode.of(context)) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % itemCount;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _menuStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Shimmer.fromColors(
              baseColor: Colors.grey.shade200,
              highlightColor: Colors.grey.shade50,
              child: Container(
                height: 165,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          );
        }

        final docs = (snapshot.data?.docs ?? []).where((d) {
          final data = d.data() as Map<String, dynamic>;
          final tags = data['tags'];
          if (tags is List) {
            return tags.contains('combo_deals');
          }
          return false;
        }).toList();

        if (docs.isEmpty) {
          _startTimer(0);
          return const SizedBox.shrink();
        }

        if (_currentIndex >= docs.length) {
          _currentIndex = 0;
        }

        _startTimer(docs.length);

        final currentDoc = docs[_currentIndex];
        final item = currentDoc.data() as Map<String, dynamic>;
        final String name = item['name'] ?? item['title'] ?? 'Combo Deal';
        final double price = parseDouble(item['price']);
        final double mrp = parseDouble(
          item['mrp'] ?? item['promoOfferPrice'] ?? price,
        );
        final String imageUrl = (item['imageUrl'] ?? item['image'] ?? '')
            .toString();

        String discountBadge = "MEGA COMBO";
        if (mrp > price && mrp > 0) {
          final int percent = (((mrp - price) / mrp) * 100).round();
          if (percent > 0) discountBadge = "$percent% OFF";
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GestureDetector(
            onTap: () {
              if (!requireLoginGlobal("Please login to view combo deals")) {
                return;
              }
              GlobalLoader.run(
                duration: const Duration(milliseconds: 1800),
                task: () async {
                  if (mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ComboScreen()),
                    );
                  }
                },
              );
            },
            child: Container(
              height: 165,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 600),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                        child: imageUrl.isNotEmpty
                            ? CachedNetworkImage(
                                key: ValueKey<String>(imageUrl),
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                placeholder: (_, __) =>
                                    Container(color: AppColors.primary),
                                errorWidget: (_, __, ___) =>
                                    Container(color: AppColors.primary),
                              )
                            : Container(
                                key: const ValueKey<String>('empty_combo_img'),
                                color: AppColors.primary,
                              ),
                      ),
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.85),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.offer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              discountBadge,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            child: Text(
                              name,
                              key: ValueKey<String>(name),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                letterSpacing: -0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                "Rs. ${price.toInt()}",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              if (mrp > price) ...[
                                const SizedBox(width: 8),
                                Text(
                                  "Rs. ${mrp.toInt()}",
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 12,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              ],
                              const Spacer(),
                              const Text(
                                "Order Combo >",
                                style: TextStyle(
                                  color: AppColors.offer,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------
// Unified Other Services View (STRICTLY REQUIRES LOGIN)
// ---------------------------------------------------------------------
class OtherServicesScreen extends StatefulWidget {
  const OtherServicesScreen({super.key});

  @override
  State<OtherServicesScreen> createState() => _OtherServicesScreenState();
}

class _OtherServicesScreenState extends State<OtherServicesScreen> {
  Map<String, dynamic> _serviceStatuses = {};
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSubscription;

  @override
  void dispose() {
    _statusSubscription?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _listenToServiceStatuses();
  }

  void _listenToServiceStatuses() {
    _statusSubscription = FirebaseFirestore.instance
        .collection('app_settings')
        .doc('service_status')
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists && snapshot.data() != null) {
            if (mounted) {
              setState(() {
                _serviceStatuses = snapshot.data()!;
              });
            }
          }
        });
  }

  void _handleServiceTap(
    String serviceKey,
    String serviceTitle,
    Widget? screen,
  ) {
    if (!requireLoginGlobal("Please login to access $serviceTitle")) {
      return;
    }

    final isAvailable = _serviceStatuses[serviceKey] != false;

    if (!isAvailable) {
      _showMaintenanceDialog(serviceTitle);
      return;
    }

    if (screen != null) {
      GlobalLoader.run(
        duration: const Duration(milliseconds: 1800),
        task: () async {
          if (mounted) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
          }
        },
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("$serviceTitle coming soon!")));
    }
  }

  void _showMaintenanceDialog(String serviceTitle) {
    showServiceComingSoonDialog(context, serviceTitle);
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> allServices = [
      {
        'key': 'home_service',
        'title': 'Home Service',
        'image': 'assets/instahub/homee.jpeg',
        'screen': const HomeServicesScreen(),
      },
      {
        'key': 'laundry',
        'title': 'Laundry',
        'image': 'assets/instahub/laundryy.jpeg',
        'screen': const LaundryServiceForm(),
      },
      {
        'key': 'car_wash',
        'title': 'Car Wash',
        'image': 'assets/instahub/carwashh.jpeg',
        'screen': const CarWashingCentresScreen(),
      },
      {
        'key': 'book_time',
        'title': 'Book Your Time',
        'image': 'assets/instahub/bookyy.jpeg',
        'screen': const BookTimeHubScreen(),
      },
      {
        'key': 'take_ride',
        'title': 'Take Ride',
        'image': 'assets/instahub/ridey.jpeg',
        'screen': const TakeRideScreen(),
      },
      {
        'key': 'pharmacy',
        'title': 'Pharmacy',
        'image': 'assets/instahub/pharmacyy.jpeg',
        'screen': const PharmacyOrderScreen(),
      },
      {
        'key': 'lab_test',
        'title': 'Lab Test',
        'image': 'assets/instahub/labyy.jpeg',
        'screen': LabsListScreen(),
      },
      {
        'key': 'cakes_bakery',
        'title': 'Cakes & Gifts',
        'image': 'assets/instahub/cakess.jpeg',
        'screen': const CakeScreen(),
      },
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 6,
        shadowColor: Colors.black.withOpacity(0.3),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "All Services",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
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
                onTap: () => _handleServiceTap(
                  item['key'],
                  item['title'],
                  item['screen'],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
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
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    color: AppColors.primary.withOpacity(0.05),
                                    child: const Icon(
                                      Icons.cake_outlined,
                                      size: 36,
                                      color: AppColors.accent,
                                    ),
                                  ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  item['title'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: AppColors.primary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  "Tap to order",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textLight,
                                    fontWeight: FontWeight.w500,
                                  ),
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
    );
  }
}
