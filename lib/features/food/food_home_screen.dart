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

import '../profile/profile_screen2.dart';
import 'RestaurantMenuScreen.dart';
import 'CategoryScreen.dart';
import 'offer_screen.dart';
import 'combo_screen.dart';
import 'cart/cart_provider.dart';
import 'cart/cart_bar.dart';
import 'cart_screen.dart';
import 'active_order_bottom_bar.dart'; 

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
  // --- Double-Tap-to-Exit Variables ---
  DateTime? _lastPressed;
  
  String _currentLocation = "Detecting...";
  bool _isLoadingLocation = true;
  Position? _currentPosition;
  GateState _gateState = GateState.loading;
  StreamSubscription<Position>? _positionStreamSubscription;

  final CarouselController _carouselController = CarouselController();
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = "";
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _initGate();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _positionStreamSubscription?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchQuery = _searchController.text.trim();
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

  // --- END: GATE LOGIC ---

  // --- START: Double-Tap-to-Exit / Search Clear Logic ---
  void _handlePop(bool didPop, dynamic result) {
    if (didPop) return;

    // 1. If search is active, clear search first
    if (_searchQuery.isNotEmpty) {
      setState(() {
        _searchController.clear();
        _searchQuery = "";
      });
      return;
    }

    // 2. Double tap logic
    const duration = Duration(milliseconds: 2000);
    final now = DateTime.now();

    if (_lastPressed == null || now.difference(_lastPressed!) > duration) {
      _lastPressed = now;
      _showSnackBar("Press back again to exit");
    } else {
      // 3. Explicitly navigate back to main Home Screen to prevent black screen
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      }
    }
  }
  // --- END: Double-Tap-to-Exit Logic ---

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      autofocus: false,
      decoration: InputDecoration(
        hintText: "Search for food or restaurants...",
        prefixIcon: const Icon(Icons.search, color: Colors.grey),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, color: Colors.grey),
                onPressed: () {
                  setState(() {
                    _searchController.clear();
                    _searchQuery = "";
                  });
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

  Widget _buildSearchResultsList() {
    if (_searchQuery.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collectionGroup("menu")
          .where("name", isGreaterThanOrEqualTo: _searchQuery)
          .where("name", isLessThan: _searchQuery + '\uf8ff')
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
              child: Text("No food items match your search."));
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final itemDoc = snapshot.data!.docs[index];
            final itemData = itemDoc.data() as Map<String, dynamic>;

            // ✅ HIDE IF STOCK IS 0
            if (parseInt(itemData['stock']) <= 0) return const SizedBox.shrink();

            return FutureBuilder<DocumentSnapshot>(
              future: itemDoc.reference.parent.parent!.get(),
              builder: (context, restaurantSnapshot) {
                if (restaurantSnapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox.shrink();
                }
                final restaurantData = restaurantSnapshot.data?.data() as Map<String, dynamic>?;
                
                // ✅ HIDE IF RESTAURANT IS CLOSED
                final status = restaurantData?['status'] ?? 'open';
                if (status != 'open') return const SizedBox.shrink();

                final restaurantName = restaurantData?['name'] ?? 'Unknown';
                final restaurantRating = parseDouble(restaurantData?['rating'], defaultValue: 0.0);
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                  child: _FoodCard(
                    key: ValueKey(itemDoc.id),
                    itemDoc: itemDoc,
                    restaurantName: restaurantName,
                    restaurantRating: restaurantRating,
                    isSearchCard: true,
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
          child: Text("Food Items",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        _buildSearchResultsList(),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text("Restaurants",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
      stream: FirebaseFirestore.instance
          .collection('restaurants')
          .where("name", isGreaterThanOrEqualTo: _searchQuery)
          .where("name", isLessThan: _searchQuery + '\uf8ff')
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
              child: Text('No restaurants match your search.'));
        }

        // ✅ ONLY SHOW OPEN RESTAURANTS
        final filteredDocs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return (data['status'] ?? 'open') == 'open';
        }).toList();

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

    return Scaffold(
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
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
                if (isSearching)
                  SliverToBoxAdapter(
                    child: _buildCombinedSearchResults(),
                  )
                else ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: _buildSectionTitle("Categories"),
                    ),
                  ),
                  SliverToBoxAdapter(child: _buildCategories()),
                  SliverToBoxAdapter(child: _buildTwoImageOffers()),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: _buildSectionTitle("Popular Foods"),
                    ),
                  ),
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
            Color(0xFF242B73),
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
                InkWell(
                  onTap: () {
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
            const SizedBox(height: 16),
            if (_searchQuery.isEmpty)
              Column(
                children: [
                  const SizedBox(height: 8),
                  _buildAdsCarousel(),
                ],
              ),
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
              child: Container(height: 280, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)))
          );
        }
        
        final docs = snapshot.data?.docs;
        if (docs == null || docs.isEmpty) return const SizedBox.shrink();

        final List<String> imageUrls = docs
            .map((doc) => (doc.data() as Map<String, dynamic>?)?['imageUrl']?.toString() ?? '')
            .where((url) => url.isNotEmpty)
            .toList();

        if (imageUrls.isEmpty) return const SizedBox.shrink();

        return CarouselSlider(
          options: CarouselOptions(
            autoPlay: true,
            height: 180,
            viewportFraction: 1.1,
            enlargeCenterPage: true,
            enlargeFactor: 0.3,
            autoPlayInterval: const Duration(seconds: 4),
          ),
          items: imageUrls
              .map((item) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 5.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedNetworkImage(
                        imageUrl: item,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (context, url) => Shimmer.fromColors(
                            baseColor: Colors.grey.shade300,
                            highlightColor: Colors.grey.shade100,
                            child: Container(color: Colors.white),
                        ),
                        errorWidget: (context, url, error) => const Icon(Icons.error),
                      ),
                    ),
                  ))
              .toList(),
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

  Widget _buildSectionTitle(String title) {
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
              color: Color.fromARGB(221, 129, 20, 20),
            ),
          ),
          TextButton(
            onPressed: () {},
            child: const Text("View All"),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, IconData icon, Color color) {
    return Chip(
      label: Text(label),
      avatar: Icon(icon, color: color, size: 18),
      backgroundColor: color.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
    );
  }

  Widget _buildCategories() {
    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildCategoryItem("Arabian", 'assets/images/arabian.jpeg'),
          _buildCategoryItem("Indian", 'assets/images/indian.jpeg'),
          _buildCategoryItem("Biriyani", 'assets/images/biriyani.jpeg'),
          _buildCategoryItem("Shawarma", 'assets/images/shawarma.jpeg'),
          _buildCategoryItem("Burger", 'assets/images/burger.jpeg'),
          _buildCategoryItem("Parotta", 'assets/images/parotta.jpeg'),
          _buildCategoryItem("Cakes", 'assets/images/cakes.jpeg'),
          _buildCategoryItem("Dosa", 'assets/images/dosa.jpeg'),
          _buildCategoryItem("Momos", 'assets/images/momos.jpeg'),
          _buildCategoryItem("Shake", 'assets/images/shake.jpeg'),
          _buildCategoryItem("Icecream", 'assets/images/icecream.jpeg'),
          _buildCategoryItem("Juice", 'assets/images/juice.jpeg'),
          _buildCategoryItem("Chinese", 'assets/images/chinese.jpeg'),
        ],
      ),
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
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Container(
              width: 70,
              height: 70,
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
            const SizedBox(height: 6),
            Text(name, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildPopularFoods() {
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
              .where("stock", isGreaterThan: 0)
              .snapshots(),
          builder: (context, popularFoodsSnapshot) {
            if (popularFoodsSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final allItems = popularFoodsSnapshot.data?.docs ?? [];

            final filteredItems = allItems.where((item) {
              final restaurantId = item.reference.parent.parent?.id;
              return nearbyRestaurants.any((doc) => doc.id == restaurantId);
            }).toList();

            if (filteredItems.isEmpty) {
              return const Center(child: Text('No popular foods found.'));
            }

            final halfLength = (filteredItems.length / 2).ceil();
            final firstRow = filteredItems.take(halfLength).toList();
            final secondRow = filteredItems.skip(halfLength).toList();

            return SizedBox(
              height: 480,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Column(
                      children: [
                        Row(
                          children: firstRow.map((itemDoc) {
                            return _FoodCard(
                              key: ValueKey(itemDoc.id),
                              itemDoc: itemDoc,
                              restaurantName: "",
                              restaurantRating: 0,
                              isSearchCard: false,
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: secondRow.map((itemDoc) {
                            return _FoodCard(
                              key: ValueKey(itemDoc.id),
                              itemDoc: itemDoc,
                              restaurantName: "",
                              restaurantRating: 0,
                              isSearchCard: false,
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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

              // ✅ ONLY SHOW OPEN RESTAURANTS
              final filteredDocs = docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final status = data['status'] ?? 'open';
                final name = data['name']?.toString().toLowerCase() ?? '';
                final query = _searchQuery.toLowerCase();
                return name.contains(query) && status == 'open';
              }).toList();

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
    if (newQuantity < 0) return;

    // ✅ ADDED: CLIENT-SIDE STOCK LIMIT VALIDATION
    final int stockAvailable = parseInt(itemData['stock'], defaultValue: 0);
    if (newQuantity > stockAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Only $stockAvailable left in stock!"),
          duration: const Duration(seconds: 2),
        ),
      );
      return; // Exit without updating quantity
    }

    final cart = Provider.of<CartProvider>(context, listen: false);
    
    // ✅ Capture the unique Firestore Document ID
    final itemId = widget.itemDoc.id; 

    final restaurantId = widget.itemDoc.reference.parent.parent?.id ?? '';
    final price = parseDouble(itemData['price'], defaultValue: 0.0);

    if (newQuantity == 0) {
      cart.removeItem(itemId);
    } else {
      cart.updateItem(
        id: itemId, // 🔥 Passing the ID to the cart
        name: itemData['name'] ?? 'Unknown',
        price: price,
        restaurantId: restaurantId,
        image: imageUrl,
        qty: newQuantity,
        isInstaHub: itemData['isInstaHub'] ?? false,
      );
    }
  }

  Widget _buildQuantitySelector() {
    return quantity > 0
        ? Container(
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
                  child: const Icon(Icons.remove, size: 18, color: Colors.white),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('$quantity',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                InkWell(
                  onTap: () => _changeQuantity(quantity + 1),
                  child: const Icon(Icons.add, size: 18, color: Colors.white),
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
              minimumSize: const Size(double.infinity, 32),
            ),
            child: const Text('ADD', style: TextStyle(fontSize: 12)),
          );
  }

  Widget _buildPopularFoodCard() {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
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
                  height: 90,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Shimmer.fromColors(
                    baseColor: Colors.grey.shade300,
                    highlightColor: Colors.grey.shade100,
                    child: Container(color: Colors.white, height: 90),
                  ),
                  errorWidget: (context, url, error) => Image.network(
                    "https://via.placeholder.com/150",
                    height: 90,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              if (isPopular)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      "Popular",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(4.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(itemData['name']?.toString() ?? 'N/A',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (widget.restaurantName != null) ...[
                  const SizedBox(height: 2),
                  Text(widget.restaurantName!,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
                if (widget.restaurantRating != null) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.orange, size: 12),
                      const SizedBox(width: 2),
                      Text(
                        widget.restaurantRating!.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Text("₹${parseDouble(itemData['price']).toStringAsFixed(0)}",
                    style: const TextStyle(fontSize: 13, color: Colors.green)),
                const SizedBox(height: 8),
                _buildQuantitySelector(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchFoodCard() {
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
                  itemData['name']?.toString() ?? 'N/A',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text("₹${parseDouble(itemData['price']).toStringAsFixed(0)}",
                    style: const TextStyle(fontSize: 14, color: Colors.green)),
                const SizedBox(height: 4),
                Text((itemData['isVeg'] == true) ? "Veg" : "Non-Veg",
                    style: TextStyle(
                        fontSize: 12,
                        color: (itemData['isVeg'] == true)
                            ? Colors.green
                            : Colors.red)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
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
                            fontSize: 12,
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
                const SizedBox(height: 8),
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

  const _RestaurantCard({
    required this.restaurantId,
    required this.name,
    required this.distance,
    required this.deliveryTime,
    required this.rating,
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
      debugPrint('Error fetching images for restaurant ${widget.restaurantId}: $e');
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
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    RestaurantMenuScreen(restaurantId: widget.restaurantId)),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                child: _isLoadingImages
                    ? Shimmer.fromColors(
                        baseColor: Colors.grey.shade300,
                        highlightColor: Colors.grey.shade100,
                        child: Container(height: 180, color: Colors.white),
                      )
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 500),
                        child: _imageUrls.isNotEmpty
                            ? CachedNetworkImage(
                                key: ValueKey<String>(_imageUrls[_currentImageIndex]),
                                imageUrl: _imageUrls[_currentImageIndex],
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Shimmer.fromColors(
                                    baseColor: Colors.grey.shade300,
                                    highlightColor: Colors.grey.shade100,
                                    child: Container(height: 180, color: Colors.white),
                                ),
                                errorWidget: (context, url, error) {
                                  return Container(
                                    height: 180,
                                    color: Colors.grey[300],
                                    child: const Center(child: Icon(Icons.broken_image)),
                                  );
                                },
                              )
                            : Container(
                                key: const ValueKey<String>('placeholder'),
                                height: 180,
                                width: double.infinity,
                                color: Colors.grey[300],
                                child: const Center(
                                    child: Text('No images available')),
                              ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.name,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                              "${widget.distance.toStringAsFixed(1)} km • ${widget.deliveryTime} min",
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.grey)),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.orange, size: 16),
                        const SizedBox(width: 4),
                        Text(widget.rating.toString(),
                            style: const TextStyle(fontSize: 13)),
                      ],
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}