// lib/food/food_home_screen.dart

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math';

// ✅ OPTIMIZATION PACKAGES
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

// ✅ IMPORT AUTH GUARDS
import 'package:fastevergo_v1/utils/auth_guards.dart'; 

import '../profile/profile_screen2.dart';
import 'RestaurantMenuScreen.dart';
import 'CategoryScreen.dart';
import 'offer_screen.dart';
import 'combo_screen.dart';
import 'cart/cart_provider.dart';
import 'cart/cart_bar.dart';
import 'cart_screen.dart';
import 'active_order_bottom_bar.dart'; 

// ✅ IMPORT NOTIFICATION SCREEN & BELL BUTTON COMPONENT
import 'package:fastevergo_v1/features/notification/NotificationScreen.dart';

// Helper function for safe parsing of Firestore data
double parseDouble(dynamic value, {double defaultValue = 0.0}) {
  if (value is String) return double.tryParse(value) ?? defaultValue;
  if (value is num) return value.toDouble();
  return defaultValue;
}

int parseInt(dynamic value, {int defaultValue = 0}) {
  if (value is String) return int.tryParse(value) ?? defaultValue;
  if (value is num) return value.toInt();
  return defaultValue;
}

/// 🔀 Mixes items evenly across restaurants using a round-robin rotation
List<Map<String, dynamic>> interleaveByRestaurant(List<Map<String, dynamic>> items) {
  if (items.isEmpty) return items;

  final Map<String, List<Map<String, dynamic>>> grouped = {};
  for (var item in items) {
    final resId = item['resId']?.toString() ?? 'unknown';
    grouped.putIfAbsent(resId, () => []).add(item);
  }

  final List<Map<String, dynamic>> interleaved = [];
  final List<List<Map<String, dynamic>>> buckets = grouped.values.toList();

  int maxCount = 0;
  for (var bucket in buckets) {
    if (bucket.length > maxCount) maxCount = bucket.length;
  }

  for (int i = 0; i < maxCount; i++) {
    for (var bucket in buckets) {
      if (i < bucket.length) {
        interleaved.add(bucket[i]);
      }
    }
  }

  return interleaved;
}

class FoodHomeScreen extends StatefulWidget {
  const FoodHomeScreen({super.key});

  @override
  State<FoodHomeScreen> createState() => _FoodHomeScreenState();
}

enum GateState {
  loading,
  locationOffOrDenied,
  allowed,
}

class _FoodHomeScreenState extends State<FoodHomeScreen> {
  DateTime? _lastPressed;
  
  String _currentLocation = "Detecting...";
  bool _isLoadingLocation = true;
  Position? _currentPosition;
  GateState _gateState = GateState.loading;
  StreamSubscription<Position>? _positionStreamSubscription;

  final CarouselController _carouselController = CarouselController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  String _searchQuery = "";
  Timer? _debounce;
  bool _isSearchFocused = false;

  // --- SEPARATE FILTER & CATEGORY STATES ---
  String _selectedPopularFilter = "All"; 
  String? _selectedCategoryFilter;      

  final List<String> _popularFilters = [
    "All",
    "Veg",
    "Non-Veg",
    "Under ₹150",
    "Top Rated",
    "Fast Delivery"
  ];

  final List<String> _categoryFilters = [
    "Arabian", "Indian", "Fried Chicken", "Biriyani", "Shawarma", 
    "Burger", "Parotta", "Cakes", "Dosa", "Snacks", "Momos", 
    "Shake", "Icecream", "Juice", "Chinese", "Tea & Coffee", "Grills", "Desserts"
  ];

  @override
  void initState() {
    super.initState();
    _initGate();
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.removeListener(_onFocusChanged);
    _searchFocusNode.dispose();
    _positionStreamSubscription?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  void _onFocusChanged() {
    setState(() {
      _isSearchFocused = _searchFocusNode.hasFocus;
    });
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  // --- START: GATE LOGIC ---
  Future<void> _initGate() async {
    try {
      if (!mounted) return;
      setState(() {
        _gateState = GateState.loading;
        _isLoadingLocation = true;
      });

      bool canLocate = await _ensureLocationAvailable();
      if (!canLocate) {
        if (!mounted) return;
        setState(() {
          _gateState = GateState.locationOffOrDenied;
          _isLoadingLocation = false;
        });
        return;
      }
      
      if (!mounted) return;
      setState(() {
        _gateState = GateState.allowed;
      });

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
        _handlePositionUpdate(position); 
      }, onError: (e) {
        if (!mounted) return;
        setState(() {
          _gateState = GateState.locationOffOrDenied;
          _isLoadingLocation = false;
        });
      });

      final initialPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _handlePositionUpdate(initialPosition);
      
    } catch (e) {
      debugPrint("🔥 _initGate Error: $e");
      if (!mounted) return;
      setState(() => _gateState = GateState.locationOffOrDenied);
    } finally {
      if (!mounted) return;
      setState(() => _isLoadingLocation = false);
    }
  }

  Future<void> _handlePositionUpdate(Position position) async {
    if (_currentPosition != null) {
      final distanceInMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      if (distanceInMeters < 50) {
        return;
      }
    }
    await _resolvePlaceName(position);
    if (!mounted) return;
    setState(() {
      _currentPosition = position;
      _gateState = GateState.allowed; 
    });
  }

  Future<bool> _ensureLocationAvailable() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
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
      _currentLocation = "${place.locality ?? 'Unknown'}, ${place.country ?? ''}";
    } catch (_) {
      if (!mounted) return;
      _currentLocation = "Location detected";
    }
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000;
  }

  int _calculateDeliveryTime(double distance, int prepTime) {
    return (distance * 4).round() + prepTime;
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _handlePop(bool didPop, dynamic result) {
    if (didPop) return;

    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
      return;
    }

    if (_searchQuery.isNotEmpty) {
      setState(() {
        _searchController.clear();
        _searchQuery = "";
      });
      return;
    }

    const duration = Duration(milliseconds: 2000);
    final now = DateTime.now();

    if (_lastPressed == null || now.difference(_lastPressed!) > duration) {
      _lastPressed = now;
      _showSnackBar("Press back again to exit");
    } else {
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      }
    }
  }

  bool _matchesQuery(String targetText, String query) {
    if (query.isEmpty) return true;
    final cleanTarget = targetText.toLowerCase();
    final queryWords = query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (queryWords.isEmpty) return true;

    for (var qWord in queryWords) {
      final targetWords = cleanTarget.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      bool wordMatched = targetWords.any((tWord) => tWord.startsWith(qWord));
      if (!wordMatched) return false;
    }
    return true;
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      autofocus: false,
      decoration: InputDecoration(
        hintText: "Search for food, 'under 150', 'near me'...",
        prefixIcon: const Icon(Icons.search, color: Colors.grey),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, color: Colors.grey),
                onPressed: () {
                  setState(() {
                    _searchController.clear();
                    _searchQuery = "";
                  });
                  _searchFocusNode.unfocus();
                },
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _buildPopularSearchesOverlay() {
    if (!_isSearchFocused || _searchQuery.isNotEmpty) return const SizedBox.shrink();

    final popularTerms = [
      "Biriyani", "Shawarma", "Burger", "Fried Chicken", "Arabian", 
      "Pizza", "Under 150", "Near me", "4+ rating", "Fast delivery"
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "🔥 Popular searches",
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: popularTerms.map((term) {
              return ActionChip(
                label: Text(term, style: const TextStyle(fontSize: 12)),
                backgroundColor: Colors.grey.shade100,
                onPressed: () {
                  _searchController.text = term.toLowerCase();
                  _searchFocusNode.unfocus();
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsList() {
    if (_searchQuery.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collectionGroup("menu").snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("No food items match your search."));
        }

        final rawQuery = _searchQuery;

        bool isVegOnly = rawQuery.contains('veg') && !rawQuery.contains('non veg');
        bool isNonVegOnly = rawQuery.contains('non veg') || rawQuery.contains('non-veg');
        bool isCheap = rawQuery.contains('cheap') || rawQuery.contains('budget');
        bool isBestRated = rawQuery.contains('4 star') || rawQuery.contains('4+ rating') || rawQuery.contains('best rated') || rawQuery.contains('top rated');

        double? maxPrice;
        double? minPrice;
        final underReg = RegExp(r'(?:under|below)\s*(\d+)');
        final matchUnder = underReg.firstMatch(rawQuery);
        if (matchUnder != null) {
          maxPrice = double.tryParse(matchUnder.group(1) ?? '');
        }

        final rangeReg = RegExp(r'(\d+)\s*-\s*(\d+)');
        final matchRange = rangeReg.firstMatch(rawQuery);
        if (matchRange != null) {
          minPrice = double.tryParse(matchRange.group(1) ?? '');
          maxPrice = double.tryParse(matchRange.group(2) ?? '');
        }

        String queryText = rawQuery
            .replaceAll(RegExp(r'(?:under|below)\s*\d+'), '')
            .replaceAll(RegExp(r'\d+\s*-\s*\d+'), '')
            .replaceAll('veg', '')
            .replaceAll('non-veg', '')
            .replaceAll('non veg', '')
            .replaceAll('cheap', '')
            .replaceAll('4 star', '')
            .replaceAll('4+ rating', '')
            .replaceAll('best rated', '')
            .replaceAll('top rated', '')
            .trim();

        final matchingDocs = snapshot.data!.docs.where((itemDoc) {
          final itemData = itemDoc.data() as Map<String, dynamic>;
          final stock = parseInt(itemData['stock']);
          if (stock <= 0) return false;

          final name = itemData['name']?.toString() ?? '';
          final category = itemData['category']?.toString() ?? '';
          final tags = (itemData['tags'] as List?)?.join(' ') ?? '';
          final keywords = (itemData['keywords'] as List?)?.join(' ') ?? '';
          final combinedText = "$name $category $tags $keywords";

          bool matchesText = queryText.isEmpty || _matchesQuery(combinedText, queryText);

          final bool itemIsVeg = itemData['isVeg'] == true;
          if (isVegOnly && !itemIsVeg) return false;
          if (isNonVegOnly && itemIsVeg) return false;

          final double price = parseDouble(itemData['price']);
          if (maxPrice != null && price > maxPrice) return false;
          if (minPrice != null && price < minPrice) return false;
          if (isCheap && price > 150) return false;

          return matchesText;
        }).toList();

        matchingDocs.sort((a, b) {
          final dataA = a.data() as Map<String, dynamic>;
          final dataB = b.data() as Map<String, dynamic>;
          final nameA = (dataA['name']?.toString() ?? '').toLowerCase();
          final nameB = (dataB['name']?.toString() ?? '').toLowerCase();

          final bool startsWithA = queryText.isNotEmpty && nameA.startsWith(queryText);
          final bool startsWithB = queryText.isNotEmpty && nameB.startsWith(queryText);

          if (startsWithA && !startsWithB) return -1;
          if (!startsWithA && startsWithB) return 1;
          return nameA.compareTo(nameB);
        });

        if (matchingDocs.isEmpty) {
          return const Center(child: Text("No food items match your search."));
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: matchingDocs.length,
          itemBuilder: (context, index) {
            final itemDoc = matchingDocs[index];

            return FutureBuilder<DocumentSnapshot>(
              future: itemDoc.reference.parent.parent!.get(),
              builder: (context, restaurantSnapshot) {
                if (restaurantSnapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox.shrink();
                }
                final restaurantData = restaurantSnapshot.data?.data() as Map<String, dynamic>?;
                
                final status = restaurantData?['status'] ?? 'open';
                if (status != 'open') return const SizedBox.shrink();

                final restaurantName = restaurantData?['name'] ?? 'Unknown';
                final restaurantRating = parseDouble(restaurantData?['rating'], defaultValue: 0.0);

                if (isBestRated && restaurantRating < 4.0) return const SizedBox.shrink();
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                  child: InkWell(
                    onTap: () {
                      _searchFocusNode.unfocus();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RestaurantMenuScreen(
                            restaurantId: itemDoc.reference.parent.parent!.id,
                            userPosition: _currentPosition,
                          ),
                        ),
                      );
                    },
                    child: _FoodCard(
                      key: ValueKey(itemDoc.id),
                      itemDoc: itemDoc,
                      restaurantName: restaurantName,
                      restaurantRating: restaurantRating,
                      isSearchCard: true,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildCombinedSearchResults() {
    if (_searchQuery.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text("Food Items", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        _buildSearchResultsList(),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text("Restaurants", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        _buildNearbyRestaurantsList(),
      ],
    );
  }

  Widget _buildNearbyRestaurantsList() {
    if (_currentPosition == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('restaurants').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No restaurants match your search.'));
        }

        final rawQuery = _searchQuery;
        bool isNearMe = rawQuery.contains('near me') || rawQuery.contains('nearby');
        bool isFastDelivery = rawQuery.contains('fast') || rawQuery.contains('quick') || rawQuery.contains('min');
        bool isBestRated = rawQuery.contains('4 star') || rawQuery.contains('4+ rating') || rawQuery.contains('best rated');

        String queryText = rawQuery
            .replaceAll('near me', '')
            .replaceAll('nearby', '')
            .replaceAll('fast', '')
            .replaceAll('quick', '')
            .replaceAll('min', '')
            .replaceAll('4 star', '')
            .replaceAll('4+ rating', '')
            .replaceAll('best rated', '')
            .trim();

        final filteredDocs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status'] ?? 'open';
          if (status != 'open') return false;

          final name = data['name']?.toString() ?? '';
          bool matchesText = queryText.isEmpty || _matchesQuery(name, queryText);
          if (!matchesText) return false;

          final double lat = parseDouble(data['latitude']);
          final double lon = parseDouble(data['longitude']);
          final double distance = _calculateDistance(
            _currentPosition!.latitude, _currentPosition!.longitude, lat, lon,
          );

          if (isNearMe && distance > 5.0) return false;

          final int prepTime = parseInt(data['prepTime']);
          final int deliveryTime = _calculateDeliveryTime(distance, prepTime);
          if (isFastDelivery && deliveryTime > 30) return false;

          final double rating = parseDouble(data['rating'], defaultValue: 4.0);
          if (isBestRated && rating < 4.0) return false;

          return true;
        }).toList();

        filteredDocs.sort((a, b) {
          final dataA = a.data() as Map<String, dynamic>;
          final dataB = b.data() as Map<String, dynamic>;
          final double latA = parseDouble(dataA['latitude']);
          final double lonA = parseDouble(dataA['longitude']);
          final double latB = parseDouble(dataB['latitude']);
          final double lonB = parseDouble(dataB['longitude']);

          final distA = _calculateDistance(_currentPosition!.latitude, _currentPosition!.longitude, latA, lonA);
          final distB = _calculateDistance(_currentPosition!.latitude, _currentPosition!.longitude, latB, lonB);
          return distA.compareTo(distB);
        });

        if (filteredDocs.isEmpty) {
          return const Center(child: Text('No restaurants match your search.'));
        }

        return Column(
          children: filteredDocs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final double lat = parseDouble(data['latitude']);
            final double lon = parseDouble(data['longitude']);
            final int prepTime = parseInt(data['prepTime']);
            final double rating = parseDouble(data['rating'], defaultValue: 4.0);

            final double distance = _calculateDistance(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              lat,
              lon,
            );
            final int deliveryTime = _calculateDeliveryTime(distance, prepTime);

            return _RestaurantCard(
              key: ValueKey(doc.id),
              restaurantId: doc.id,
              name: data['name']?.toString() ?? "Unknown",
              rating: rating,
              distance: distance,
              deliveryTime: deliveryTime,
              userPosition: _currentPosition,
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_gateState) {
      case GateState.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case GateState.locationOffOrDenied:
        return _buildLocationRequiredScreen();
      case GateState.allowed:
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: _handlePop,
          child: _buildMainScreen(),
        );
    }
  }

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
                  "Please turn on location to continue",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  "We use your location to check service availability in your area.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () async => Geolocator.openLocationSettings(),
                  child: const Text("Open Location Settings"),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _initGate,
                  child: const Text("I’ve turned it on • Retry"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainScreen() {
    final bool isSearching = _searchQuery.isNotEmpty;

    return GestureDetector(
      onTap: () => _searchFocusNode.unfocus(),
      child: Scaffold(
        backgroundColor: Colors.white,
        bottomNavigationBar: const ActiveOrderBottomBar(),
        body: SafeArea(
          child: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildTopSection(),
                  ),
                  if (_isSearchFocused && _searchQuery.isEmpty)
                    SliverToBoxAdapter(
                      child: _buildPopularSearchesOverlay(),
                    ),
                  if (isSearching)
                    SliverToBoxAdapter(
                      child: _buildCombinedSearchResults(),
                    )
                  else ...[
                    SliverToBoxAdapter(child: _buildCategories()),
                    SliverToBoxAdapter(child: _buildAdsCarousel()),
                    SliverToBoxAdapter(child: _buildTwoImageOffers()),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: _buildSectionTitle("Popular Foods", onViewAll: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AllPopularFoodsScreen(userPosition: _currentPosition),
                            ),
                          );
                        }),
                      ),
                    ),
                    SliverToBoxAdapter(child: _buildPopularFilterChips()),
                    SliverToBoxAdapter(child: _buildPopularCategoryChips()),
                    _buildPopularFoods(),
                    SliverToBoxAdapter(
                        child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: _buildSectionTitle("Nearby Restaurants"),
                    )),
                    _buildNearbyRestaurants(),
                    const SliverToBoxAdapter(child: SizedBox(height: 80)),
                  ],
                ],
              ),
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: CartBar(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopSection() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A1E43),
            Color(0xFF1A1E43),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () {
                      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.location_on,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Flexible(
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
                            child: CircularProgressIndicator(
                              strokeWidth: 2.0,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.notifications_rounded, color: Colors.white),
                  onPressed: () => Navigator.push(
                    context, 
                    MaterialPageRoute(builder: (_) => const NotificationScreen()),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () {
                    if (!requireLoginGlobal("Please login to access profile")) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen2()),
                    );
                  },
                  child: const CircleAvatar(
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person, color: Color(0xFF1A1E43)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSearchBar(),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildAdsCarousel() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ads')
          .where('tag', isEqualTo: 'home_adsbanner')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Shimmer.fromColors(
              baseColor: Colors.grey.shade300,
              highlightColor: Colors.grey.shade100,
              child: Container(height: 180, margin: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)))
          );
        }
        
        final docs = snapshot.data?.docs;
        if (docs == null || docs.isEmpty) return const SizedBox.shrink();

        final List<String> imageUrls = docs
            .map((doc) => (doc.data() as Map<String, dynamic>?)?['imageUrl']?.toString() ?? '')
            .where((url) => url.isNotEmpty)
            .toList();

        if (imageUrls.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: CarouselSlider(
            options: CarouselOptions(
              autoPlay: true,
              height: 180,
              viewportFraction: 0.92,
              enlargeCenterPage: true,
              enlargeFactor: 0.2,
              autoPlayInterval: const Duration(seconds: 4),
            ),
            items: imageUrls
                .map((item) => Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, spreadRadius: 1)
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedNetworkImage(
                        imageUrl: item,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: Colors.grey.shade200),
                        errorWidget: (context, url, error) => const Icon(Icons.error),
                      ),
                    ),
                  ))
                .toList(),
          ),
        );
      },
    );
  }
  
  Widget _buildTwoImageOffers() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle("Special Offers"),
          Row(
            children: [
              Expanded(
                child: _buildStaticOfferImageButton(
                  tag: "bigdeal", 
                  imageAssets: const ['assets/images/bigd1.jpeg', 'assets/images/bigd2.jpeg'],
                  offerTitle: "Big Deals",
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStaticOfferImageButton(
                  tag: "combo", 
                  imageAssets: const ['assets/images/combod1.jpeg', 'assets/images/combod2.jpeg'],
                  offerTitle: "Combo Deals",
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStaticOfferImageButton(
      {required String tag,
      required List<String> imageAssets,
      required String offerTitle}) {
    final screenWidth = MediaQuery.of(context).size.width;
    final buttonHeight = (screenWidth / 2) / 1.777;

    if (imageAssets.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[200],
      ),
      child: CarouselSlider(
        options: CarouselOptions(
          autoPlay: true,
          height: buttonHeight,
          viewportFraction: 1.0,
          autoPlayInterval: const Duration(seconds: 3),
          autoPlayAnimationDuration: const Duration(milliseconds: 800),
          autoPlayCurve: Curves.fastOutSlowIn,
        ),
        items: imageAssets.map((assetPath) {
          return Builder(
            builder: (BuildContext context) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () {
                    if (tag == 'bigdeal') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              OfferScreen(title: offerTitle, offerTag: 'bigdeal'),
                        ),
                      );
                    } else if (tag == 'combo') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ComboScreen(),
                        ),
                      );
                    }
                  },
                  child: Image.asset(
                    assetPath,
                    height: buttonHeight,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: buttonHeight,
                        color: Colors.red.shade100,
                        child: const Center(
                            child:
                                Text('Asset Error', style: TextStyle(fontSize: 10))),
                      );
                    },
                  ),
                ),
              );
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSectionTitle(String title, {VoidCallback? onViewAll}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8), 
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1E43),
            ),
          ),
          TextButton(
            onPressed: onViewAll ?? () {},
            child: const Text("View All"),
          ),
        ],
      ),
    );
  }

  // --- 💎 PREMIUM PROFESSIONAL CHIP BUILDERS ---

  Widget _buildPopularFilterChips() {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: _popularFilters.length,
        itemBuilder: (context, index) {
          final filter = _popularFilters[index];
          final isSelected = _selectedPopularFilter == filter;

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(filter),
              selected: isSelected,
              selectedColor: const Color(0xFF1A1E43),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF1A1E43),
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
              backgroundColor: Colors.white,
              elevation: isSelected ? 3 : 0,
              pressElevation: 1,
              shadowColor: Colors.black.withOpacity(0.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: isSelected ? const Color(0xFF1A1E43) : Colors.grey.shade300,
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              onSelected: (selected) {
                setState(() {
                  _selectedPopularFilter = filter;
                });
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildPopularCategoryChips() {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: _categoryFilters.length,
        itemBuilder: (context, index) {
          final category = _categoryFilters[index];
          final isSelected = _selectedCategoryFilter == category;

          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              label: Text(category),
              selected: isSelected,
              selectedColor: const Color(0xFF2E7D32),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
              backgroundColor: Colors.grey.shade50,
              elevation: isSelected ? 3 : 0,
              pressElevation: 1,
              shadowColor: Colors.black.withOpacity(0.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade300,
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              onSelected: (selected) {
                setState(() {
                  _selectedCategoryFilter = selected ? category : null;
                });
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategories() {
    return Stack(
      children: [
        Column(
          children: [
            Container(height: 50, color: const Color(0xFF1A1E43)),
            Container(height: 70, color: Colors.white),         ],
        ),
        SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildCategoryItem("Arabian", 'assets/images/arabian.jpeg'),
              _buildCategoryItem("Indian", 'assets/images/indian.jpeg'),
              _buildCategoryItem("Fried Chicken", 'assets/images/fried.png'),
              _buildCategoryItem("Biriyani", 'assets/images/biriyani.jpeg'),
              _buildCategoryItem("Shawarma", 'assets/images/shawarma.jpeg'),
              _buildCategoryItem("Burger", 'assets/images/burger.jpeg'),
              _buildCategoryItem("Parotta", 'assets/images/parotta.jpeg'),
              _buildCategoryItem("Cakes", 'assets/images/cakes.jpeg'),
              _buildCategoryItem("Dosa", 'assets/images/dosa.jpeg'),
              _buildCategoryItem("Snacks", 'assets/images/snacks.png'),
              _buildCategoryItem("Momos", 'assets/images/momos.jpeg'),
              _buildCategoryItem("Shake", 'assets/images/shake.jpeg'),
              _buildCategoryItem("Icecream", 'assets/images/icecream.jpeg'),
              _buildCategoryItem("Juice", 'assets/images/juice.jpeg'),
              _buildCategoryItem("Chinese", 'assets/images/chinese.jpeg'),
              _buildCategoryItem("Tea & Coffee", 'assets/images/tea.png'),
              _buildCategoryItem("Grills", 'assets/images/grills.png'),
              _buildCategoryItem("Desserts", 'assets/images/desserts.png'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryItem(String name, String imagePath) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CategoryScreen(category: name.toLowerCase()),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(right: 15, top: 12),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 6,
                    spreadRadius: 1,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(color: Colors.white, width: 2.5), 
              ),
              child: ClipOval(
                child: Image.asset(
                  imagePath,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Image.asset(
                      'assets/images/placeholder.png',
                      fit: BoxFit.cover,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              name, 
              style: const TextStyle(
                fontSize: 12, 
                fontWeight: FontWeight.bold, 
                color: Colors.black87
              )
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPopularFoods() {
    if (_currentPosition == null) {
      return const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return SliverToBoxAdapter(
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('restaurants').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No popular foods available.'));
          }

          final nearbyRestaurants = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final String status = data['status'] ?? 'open';
            final double lat = parseDouble(data['latitude']);
            final double lon = parseDouble(data['longitude']);
            final double distance = _calculateDistance(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              lat,
              lon,
            );
            return distance <= 10.0 && status == 'open';
          }).toList();

          if (nearbyRestaurants.isEmpty) {
            return const Center(child: Text('No popular foods in your area.'));
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collectionGroup('menu')
                .where('tags', arrayContains: 'pops')
                .snapshots(),
            builder: (context, popularFoodsSnapshot) {
              if (popularFoodsSnapshot.connectionState ==
                  ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allItems = popularFoodsSnapshot.data?.docs ?? [];

              return FutureBuilder<List<Map<String, dynamic>>>(
                future: Future.wait(allItems.map((itemDoc) async {
                  final resDoc = await itemDoc.reference.parent.parent!.get();
                  final resData = resDoc.data() as Map<String, dynamic>? ?? {};
                  final itemData = itemDoc.data() as Map<String, dynamic>;
                  final categoryStr = (itemData['category'] ?? '').toString().toLowerCase();
                  final nameStr = (itemData['name'] ?? '').toString().toLowerCase();
                  final tagsList = (itemData['tags'] as List?)?.map((e) => e.toString().toLowerCase()).toList() ?? [];
                  
                  return {
                    'itemDoc': itemDoc,
                    'itemData': itemData,
                    'resId': itemDoc.reference.parent.parent!.id,
                    'resName': resData['name'] ?? 'Unknown',
                    'resRating': parseDouble(resData['rating'], defaultValue: 4.0),
                    'resLat': parseDouble(resData['latitude']),
                    'resLon': parseDouble(resData['longitude']),
                    'prepTime': parseInt(resData['prepTime']),
                    'category': categoryStr,
                    'name': nameStr,
                    'tags': tagsList,
                  };
                })),
                builder: (context, enrichedSnapshot) {
                  if (!enrichedSnapshot.hasData) {
                    return const SizedBox(
                      height: 750,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final enrichedItems = enrichedSnapshot.data!.where((map) {
                    final resId = map['resId'];
                    return nearbyRestaurants.any((doc) => doc.id == resId);
                  }).toList();

                  final rawFilteredItems = enrichedItems.where((map) {
                    final itemData = map['itemData'] as Map<String, dynamic>;
                    final price = parseDouble(itemData['price']);
                    final isVeg = itemData['isVeg'] == true;
                    final category = map['category'] as String;
                    final name = map['name'] as String;
                    final tags = map['tags'] as List<String>;

                    bool matchesGeneral = true;
                    if (_selectedPopularFilter == "Veg") {
                      matchesGeneral = isVeg;
                    } else if (_selectedPopularFilter == "Non-Veg") {
                      matchesGeneral = !isVeg;
                    } else if (_selectedPopularFilter == "Under ₹150") {
                      matchesGeneral = price <= 150;
                    } else if (_selectedPopularFilter == "Top Rated") {
                      matchesGeneral = (map['resRating'] as double) >= 4.0;
                    } else if (_selectedPopularFilter == "Fast Delivery") {
                      final dist = _calculateDistance(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                        map['resLat'],
                        map['resLon'],
                      );
                      final deliveryTime = _calculateDeliveryTime(dist, map['prepTime']);
                      matchesGeneral = deliveryTime <= 30;
                    }

                    bool matchesCategory = true;
                    if (_selectedCategoryFilter != null) {
                      final targetCat = _selectedCategoryFilter!.toLowerCase();
                      matchesCategory = category.contains(targetCat) ||
                          name.contains(targetCat) ||
                          tags.any((t) => t.contains(targetCat));
                    }

                    return matchesGeneral && matchesCategory;
                  }).toList();

                  // 🔀 Mix items evenly across all nearby restaurants
                  final filteredItems = interleaveByRestaurant(rawFilteredItems);

                  if (filteredItems.isEmpty) {
                    return const SizedBox(
                      height: 200,
                      child: Center(child: Text('No popular foods match this filter.')),
                    );
                  }

                  return SizedBox(
                    height: 690,
                    child: GridView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.34,
                      ),
                      itemCount: filteredItems.length,
                      itemBuilder: (context, index) {
                        final dataMap = filteredItems[index];
                        final itemDoc = dataMap['itemDoc'] as DocumentSnapshot;

                        return InkWell(
                          onTap: () {
                            _searchFocusNode.unfocus();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RestaurantMenuScreen(
                                  restaurantId: dataMap['resId'],
                                  userPosition: _currentPosition,
                                ),
                              ),
                            );
                          },
                          child: _FoodCard(
                            key: ValueKey(itemDoc.id),
                            itemDoc: itemDoc,
                            restaurantName: dataMap['resName'],
                            restaurantRating: dataMap['resRating'],
                            isSearchCard: false,
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildNearbyRestaurants() {
    if (_currentPosition == null) {
      return SliverList(
        delegate: SliverChildListDelegate(
          [
            const Center(child: CircularProgressIndicator()),
          ],
        ),
      );
    }
    return SliverList(
      delegate: SliverChildListDelegate(
        [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('restaurants').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data?.docs;
              if (docs == null || docs.isEmpty) {
                return const Center(child: Text('No nearby restaurants found.'));
              }

              final filteredDocs = docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final status = data['status'] ?? 'open';
                final name = (data['name']?.toString() ?? '').toLowerCase();
                return _matchesQuery(name, _searchQuery) && status == 'open';
              }).toList();

              filteredDocs.sort((a, b) {
                final dataA = a.data() as Map<String, dynamic>;
                final dataB = b.data() as Map<String, dynamic>;
                final nameA = (dataA['name']?.toString() ?? '').toLowerCase();
                final nameB = (dataB['name']?.toString() ?? '').toLowerCase();

                final bool startsWithA = _searchQuery.isNotEmpty && nameA.startsWith(_searchQuery);
                final bool startsWithB = _searchQuery.isNotEmpty && nameB.startsWith(_searchQuery);

                if (startsWithA && !startsWithB) return -1;
                if (!startsWithA && startsWithB) return 1;
                return nameA.compareTo(nameB);
              });

              if (filteredDocs.isEmpty) {
                return const Center(child: Text('No results for your search.'));
              }

              return Column(
                children: filteredDocs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final double lat = parseDouble(data['latitude']);
                  final double lon = parseDouble(data['longitude']);
                  final int prepTime = parseInt(data['prepTime']);
                  final double rating = parseDouble(data['rating'], defaultValue: 4.0);

                  final double distance = _calculateDistance(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                    lat,
                    lon,
                  );
                  final int deliveryTime = _calculateDeliveryTime(distance, prepTime);

                  return _RestaurantCard(
                    key: ValueKey(doc.id),
                    restaurantId: doc.id,
                    name: data['name']?.toString() ?? "Unknown",
                    rating: rating,
                    distance: distance,
                    deliveryTime: deliveryTime,
                    userPosition: _currentPosition,
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 🚀 ALL POPULAR FOODS SCREEN (VIEW ALL PAGE)
// ==========================================
class AllPopularFoodsScreen extends StatefulWidget {
  final Position? userPosition;

  const AllPopularFoodsScreen({super.key, this.userPosition});

  @override
  State<AllPopularFoodsScreen> createState() => _AllPopularFoodsScreenState();
}

class _AllPopularFoodsScreenState extends State<AllPopularFoodsScreen> {
  String _selectedPopularFilter = "All";
  String? _selectedCategoryFilter;

  final List<String> _popularFilters = [
    "All", "Veg", "Non-Veg", "Under ₹150", "Top Rated", "Fast Delivery"
  ];

  final List<String> _categoryFilters = [
    "Arabian", "Indian", "Fried Chicken", "Biriyani", "Shawarma", 
    "Burger", "Parotta", "Cakes", "Dosa", "Snacks", "Momos", 
    "Shake", "Icecream", "Juice", "Chinese", "Tea & Coffee", "Grills", "Desserts"
  ];

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000;
  }

  int _calculateDeliveryTime(double distance, int prepTime) {
    return (distance * 4).round() + prepTime;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1E43),
        title: const Text("All Popular Foods", style: TextStyle(color: Colors.white, fontSize: 18)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: widget.userPosition == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                SizedBox(
                  height: 48,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    itemCount: _popularFilters.length,
                    itemBuilder: (context, index) {
                      final filter = _popularFilters[index];
                      final isSelected = _selectedPopularFilter == filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(filter),
                          selected: isSelected,
                          selectedColor: const Color(0xFF1A1E43),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : const Color(0xFF1A1E43),
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                            side: BorderSide(
                              color: isSelected ? const Color(0xFF1A1E43) : Colors.grey.shade300,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          onSelected: (selected) {
                            setState(() {
                              _selectedPopularFilter = filter;
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    itemCount: _categoryFilters.length,
                    itemBuilder: (context, index) {
                      final category = _categoryFilters[index];
                      final isSelected = _selectedCategoryFilter == category;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(category),
                          selected: isSelected,
                          selectedColor: const Color(0xFF2E7D32),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                          backgroundColor: Colors.grey.shade50,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                            side: BorderSide(
                              color: isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade300,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          onSelected: (selected) {
                            setState(() {
                              _selectedCategoryFilter = selected ? category : null;
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('restaurants').snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                      final nearbyRestaurants = snapshot.data!.docs.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final String status = data['status'] ?? 'open';
                        final double lat = parseDouble(data['latitude']);
                        final double lon = parseDouble(data['longitude']);
                        final double distance = _calculateDistance(
                          widget.userPosition!.latitude, widget.userPosition!.longitude, lat, lon,
                        );
                        return distance <= 10.0 && status == 'open';
                      }).toList();

                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collectionGroup('menu')
                            .where('tags', arrayContains: 'pops')
                            .snapshots(),
                        builder: (context, popularSnap) {
                          if (!popularSnap.hasData) return const Center(child: CircularProgressIndicator());

                          final allItems = popularSnap.data?.docs ?? [];

                          return FutureBuilder<List<Map<String, dynamic>>>(
                            future: Future.wait(allItems.map((itemDoc) async {
                              final resDoc = await itemDoc.reference.parent.parent!.get();
                              final resData = resDoc.data() as Map<String, dynamic>? ?? {};
                              final itemData = itemDoc.data() as Map<String, dynamic>;
                              final categoryStr = (itemData['category'] ?? '').toString().toLowerCase();
                              final nameStr = (itemData['name'] ?? '').toString().toLowerCase();
                              final tagsList = (itemData['tags'] as List?)?.map((e) => e.toString().toLowerCase()).toList() ?? [];

                              return {
                                'itemDoc': itemDoc,
                                'itemData': itemData,
                                'resId': itemDoc.reference.parent.parent!.id,
                                'resName': resData['name'] ?? 'Unknown',
                                'resRating': parseDouble(resData['rating'], defaultValue: 4.0),
                                'resLat': parseDouble(resData['latitude']),
                                'resLon': parseDouble(resData['longitude']),
                                'prepTime': parseInt(resData['prepTime']),
                                'category': categoryStr,
                                'name': nameStr,
                                'tags': tagsList,
                              };
                            })),
                            builder: (context, enrichedSnapshot) {
                              if (!enrichedSnapshot.hasData) {
                                return const Center(child: CircularProgressIndicator());
                              }

                              final enrichedItems = enrichedSnapshot.data!.where((map) {
                                final resId = map['resId'];
                                return nearbyRestaurants.any((doc) => doc.id == resId);
                              }).toList();

                              final rawFilteredItems = enrichedItems.where((map) {
                                final itemData = map['itemData'] as Map<String, dynamic>;
                                final price = parseDouble(itemData['price']);
                                final isVeg = itemData['isVeg'] == true;
                                final category = map['category'] as String;
                                final name = map['name'] as String;
                                final tags = map['tags'] as List<String>;

                                bool matchesGeneral = true;
                                if (_selectedPopularFilter == "Veg") {
                                  matchesGeneral = isVeg;
                                } else if (_selectedPopularFilter == "Non-Veg") {
                                  matchesGeneral = !isVeg;
                                } else if (_selectedPopularFilter == "Under ₹150") {
                                  matchesGeneral = price <= 150;
                                } else if (_selectedPopularFilter == "Top Rated") {
                                  matchesGeneral = (map['resRating'] as double) >= 4.0;
                                } else if (_selectedPopularFilter == "Fast Delivery") {
                                  final dist = _calculateDistance(
                                    widget.userPosition!.latitude,
                                    widget.userPosition!.longitude,
                                    map['resLat'],
                                    map['resLon'],
                                  );
                                  final deliveryTime = _calculateDeliveryTime(dist, map['prepTime']);
                                  matchesGeneral = deliveryTime <= 30;
                                }

                                bool matchesCategory = true;
                                if (_selectedCategoryFilter != null) {
                                  final targetCat = _selectedCategoryFilter!.toLowerCase();
                                  matchesCategory = category.contains(targetCat) ||
                                      name.contains(targetCat) ||
                                      tags.any((t) => t.contains(targetCat));
                                }

                                return matchesGeneral && matchesCategory;
                              }).toList();

                              // 🔀 Mix items evenly across all nearby restaurants
                              final filteredItems = interleaveByRestaurant(rawFilteredItems);

                              if (filteredItems.isEmpty) {
                                return const Center(child: Text("No items found matching filter."));
                              }

                              return GridView.builder(
                                padding: const EdgeInsets.all(16),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 0.62,
                                ),
                                itemCount: filteredItems.length,
                                itemBuilder: (context, index) {
                                  final dataMap = filteredItems[index];
                                  final itemDoc = dataMap['itemDoc'] as DocumentSnapshot;

                                  return InkWell(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => RestaurantMenuScreen(
                                            restaurantId: dataMap['resId'],
                                            userPosition: widget.userPosition,
                                          ),
                                        ),
                                      );
                                    },
                                    child: _FoodCard(
                                      key: ValueKey(itemDoc.id),
                                      itemDoc: itemDoc,
                                      restaurantName: dataMap['resName'],
                                      restaurantRating: dataMap['resRating'],
                                      isSearchCard: false,
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

// ==========================================
// 🍕 EXPANDABLE RED DESCRIPTION COMPONENT
// ==========================================
class _ExpandableItemDescription extends StatefulWidget {
  final String text;
  final String? itemName;
  final int maxLines;
  final bool openDialogOnMore;

  const _ExpandableItemDescription({
    required this.text,
    this.itemName,
    this.maxLines = 2,
    this.openDialogOnMore = false,
    Key? key,
  }) : super(key: key);

  @override
  State<_ExpandableItemDescription> createState() =>
      _ExpandableItemDescriptionState();
}

class _ExpandableItemDescriptionState
    extends State<_ExpandableItemDescription> {
  bool _isExpanded = false;

  void _showFullDescriptionModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      widget.itemName ?? "Description",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1E43),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(height: 20),
              Text(
                widget.text,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.red.shade700,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.trim().isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final textSpan = TextSpan(
          text: widget.text,
          style: TextStyle(
            fontSize: 10.5,
            color: Colors.red.shade700,
            height: 1.2,
            fontWeight: FontWeight.w500,
          ),
        );

        final textPainter = TextPainter(
          text: textSpan,
          maxLines: widget.maxLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);

        final bool isOverflowing = textPainter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.text,
              style: TextStyle(
                fontSize: 10.5,
                color: Colors.red.shade700,
                height: 1.2,
                fontWeight: FontWeight.w500,
              ),
              maxLines: _isExpanded ? null : widget.maxLines,
              overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            if (isOverflowing) ...[
              const SizedBox(height: 2),
              InkWell(
                onTap: () {
                  if (widget.openDialogOnMore) {
                    _showFullDescriptionModal(context);
                  } else {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  }
                },
                child: Text(
                  _isExpanded ? "View Less" : "View More",
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ==========================================
// 🍕 FOOD CARD COMPONENT
// ==========================================
class _FoodCard extends StatefulWidget {
  final DocumentSnapshot itemDoc;
  final String? restaurantName;
  final double? restaurantRating;
  final bool isSearchCard;

  const _FoodCard({
    required this.itemDoc,
    this.restaurantName,
    this.restaurantRating,
    required this.isSearchCard,
    Key? key,
  }) : super(key: key);

  @override
  State<_FoodCard> createState() => _FoodCardState();
}

class _FoodCardState extends State<_FoodCard> {
  late Map<String, dynamic> itemData;
  late String imageUrl;
  late bool isPopular;
  int quantity = 0;

  @override
  void initState() {
    super.initState();
    itemData = widget.itemDoc.data() as Map<String, dynamic>;
    imageUrl = itemData['imageUrl'] ?? 'https://via.placeholder.com/150';
    final tags = itemData['tags'] as List?;
    isPopular = tags?.contains('pops') ?? false;

    final cart = Provider.of<CartProvider>(context, listen: false);
    cart.addListener(_updateQuantityFromCart);
    quantity = cart.getQuantity(widget.itemDoc.id);
  }

  @override
  void dispose() {
    Provider.of<CartProvider>(context, listen: false)
        .removeListener(_updateQuantityFromCart);
    super.dispose();
  }

  void _updateQuantityFromCart() {
    final cart = Provider.of<CartProvider>(context, listen: false);
    final newQuantity = cart.getQuantity(widget.itemDoc.id);
    if (newQuantity != quantity) {
      setState(() {
        quantity = newQuantity;
      });
    }
  }

  void _changeQuantity(int newQuantity) {
    if (!requireLoginGlobal("Please login to add items to cart")) return;

    final int stockAvailable = parseInt(itemData['stock'], defaultValue: 0);
    if (stockAvailable <= 0) return; 

    if (newQuantity < 0) return;

    if (newQuantity > stockAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Only $stockAvailable left in stock!"),
          duration: const Duration(seconds: 2),
        ),
      );
      return; 
    }

    final cart = Provider.of<CartProvider>(context, listen: false);
    final itemId = widget.itemDoc.id; 
    final restaurantId = widget.itemDoc.reference.parent.parent?.id ?? '';
    final price = parseDouble(itemData['price'], defaultValue: 0.0);

    if (newQuantity == 0) {
      cart.removeItem(itemId);
    } else {
      cart.updateItem(
        id: itemId, 
        name: itemData['name'] ?? 'Unknown',
        price: price,
        restaurantId: restaurantId,
        image: imageUrl,
        qty: newQuantity,
        isInstaHub: (itemData['isInstaHub'] == true),
      );
    }
  }

  Widget _buildQuantitySelector() {
    return quantity > 0
        ? Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 21, 101, 192),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => _changeQuantity(quantity - 1),
                  child: const Icon(Icons.remove, size: 16, color: Colors.white),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '$quantity',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => _changeQuantity(quantity + 1),
                  child: const Icon(Icons.add, size: 16, color: Colors.white),
                ),
              ],
            ),
          )
        : ElevatedButton(
            onPressed: () => _changeQuantity(1),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 82, 11, 225),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: EdgeInsets.zero,
              minimumSize: const Size(double.infinity, 30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('ADD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          );
  }

  Widget _buildPopularFoodCard() {
    final int stock = parseInt(itemData['stock'], defaultValue: 0);
    final bool isSoldOut = stock <= 0;
    final String? description = itemData['description']?.toString();
    final String itemName = itemData['name']?.toString() ?? 'N/A';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.18),
            blurRadius: 4,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: AbsorbPointer(
        absorbing: isSoldOut, 
        child: Opacity(
          opacity: isSoldOut ? 0.7 : 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(12)),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      height: 82,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Shimmer.fromColors(
                        baseColor: Colors.grey.shade300,
                        highlightColor: Colors.grey.shade100,
                        child: Container(color: Colors.white, height: 82),
                      ),
                      errorWidget: (context, url, error) => Image.network(
                        "https://via.placeholder.com/150",
                        height: 82,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  if (isSoldOut)
                    Positioned.fill(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                        ),
                        child: const Center(
                          child: Text(
                            "SOLD OUT",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  if (isPopular && !isSoldOut)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          "Popular",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            itemName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.restaurantName != null) ...[
                            Text(
                              widget.restaurantName!,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "₹${parseDouble(itemData['price']).toStringAsFixed(0)}",
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (widget.restaurantRating != null) 
                                Row(
                                  children: [
                                    const Icon(Icons.star, color: Colors.orange, size: 11),
                                    const SizedBox(width: 2),
                                    Text(
                                      widget.restaurantRating!.toStringAsFixed(1),
                                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          // 🔴 RED DESCRIPTION WITH SAFE VIEW MORE
                          if (description != null && description.trim().isNotEmpty) ...[
                            const SizedBox(height: 2),
                            _ExpandableItemDescription(
                              text: description.trim(),
                              itemName: itemName,
                              maxLines: 2,
                              openDialogOnMore: true,
                            ),
                          ],
                        ],
                      ),
                      _buildQuantitySelector(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchFoodCard() {
    final String? description = itemData['description']?.toString();
    final String itemName = itemData['name']?.toString() ?? 'N/A';

    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 4,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              placeholder: (context, url) => Shimmer.fromColors(
                baseColor: Colors.grey.shade300,
                highlightColor: Colors.grey.shade100,
                child: Container(color: Colors.white, width: 80, height: 80),
              ),
              errorWidget: (context, url, error) => const Icon(Icons.fastfood, size: 60),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  itemName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  "₹${parseDouble(itemData['price']).toStringAsFixed(0)}",
                  style: const TextStyle(fontSize: 13, color: Colors.green, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  (itemData['isVeg'] == true) ? "Veg" : "Non-Veg",
                  style: TextStyle(
                    fontSize: 11,
                    color: (itemData['isVeg'] == true) ? Colors.green : Colors.red,
                  ),
                ),
                // 🔴 OPTIONAL RED DESCRIPTION
                if (description != null && description.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _ExpandableItemDescription(
                    text: description.trim(),
                    itemName: itemName,
                    maxLines: 2,
                    openDialogOnMore: false,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (widget.restaurantName != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        widget.restaurantName!,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, color: Colors.orange, size: 12),
                          const SizedBox(width: 2),
                          Text(
                            widget.restaurantRating?.toStringAsFixed(1) ?? 'N/A',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
                _buildQuantitySelector(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isSearchCard) {
      return _buildSearchFoodCard();
    } else {
      return _buildPopularFoodCard();
    }
  }
}

class _RestaurantCard extends StatefulWidget {
  final String restaurantId;
  final String name;
  final double distance;
  final int deliveryTime;
  final double rating;
  final Position? userPosition;

  const _RestaurantCard({
    required this.restaurantId,
    required this.name,
    required this.distance,
    required this.deliveryTime,
    required this.rating,
    this.userPosition,
    Key? key,
  }) : super(key: key);

  @override
  State<_RestaurantCard> createState() => _RestaurantCardState();
}

class _RestaurantCardState extends State<_RestaurantCard>
    with AutomaticKeepAliveClientMixin {
  List<String> _imageUrls = [];
  int _currentImageIndex = 0;
  Timer? _timer;
  bool _isLoadingImages = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchMenuImages();
  }

  Future<void> _fetchMenuImages() async {
    try {
      final menuSnapshot = await FirebaseFirestore.instance
          .collection('restaurants')
          .doc(widget.restaurantId)
          .collection('menu')
          .limit(10)
          .get();

      final urls = menuSnapshot.docs
          .map((doc) =>
              (doc.data() as Map<String, dynamic>?)?['imageUrl']?.toString())
          .where((url) => url != null && url.isNotEmpty)
          .cast<String>()
          .toList();

      if (!mounted) return;
      if (urls.isNotEmpty) {
        setState(() {
          _imageUrls = urls;
          _isLoadingImages = false;
        });
        _startImageRotation();
      } else {
        setState(() {
          _isLoadingImages = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingImages = false;
      });
    }
  }

  void _startImageRotation() {
    if (_imageUrls.length <= 1) {
      return;
    }
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _currentImageIndex = (_currentImageIndex + 1) % _imageUrls.length;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        RestaurantMenuScreen(
                          restaurantId: widget.restaurantId,
                          userPosition: widget.userPosition,
                        ),
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      _isLoadingImages
                          ? Shimmer.fromColors(
                              baseColor: Colors.grey.shade200,
                              highlightColor: Colors.grey.shade50,
                              child: Container(height: 190, color: Colors.white),
                            )
                          : AnimatedSwitcher(
                              duration: const Duration(milliseconds: 500),
                              child: _imageUrls.isNotEmpty
                                  ? CachedNetworkImage(
                                      key: ValueKey<String>(_imageUrls[_currentImageIndex]),
                                      imageUrl: _imageUrls[_currentImageIndex],
                                      height: 190,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Shimmer.fromColors(
                                        baseColor: Colors.grey.shade200,
                                        highlightColor: Colors.grey.shade50,
                                        child: Container(height: 190, color: Colors.white),
                                      ),
                                      errorWidget: (context, url, error) {
                                        return Container(
                                          height: 190,
                                          color: Colors.grey[100],
                                          child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                                        );
                                      },
                                    )
                                  : Container(
                                      key: const ValueKey<String>('placeholder'),
                                      height: 190,
                                      width: double.infinity,
                                      color: Colors.grey[100],
                                      child: const Center(
                                          child: Text('No images available', style: TextStyle(color: Colors.grey, fontSize: 12))),
                                    ),
                            ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.02),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.name,
                                  style: const TextStyle(
                                      fontSize: 16, 
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF1A1E43),
                                      letterSpacing: -0.2)),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  const Icon(Icons.access_time_rounded, size: 13, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text(
                                    "${widget.deliveryTime} mins",
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 6),
                                    child: Text("•", style: TextStyle(color: Colors.grey, fontSize: 12)),
                                  ),
                                  Text(
                                    "${widget.distance.toStringAsFixed(1)} km",
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, color: Color(0xFF2E7D32), size: 15),
                              const SizedBox(width: 3),
                              Text(
                                widget.rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF2E7D32),
                                ),
                              ),
                            ],
                          ),
                        )
                      ],
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