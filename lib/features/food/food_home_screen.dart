// lib/features/food/food_home_screen.dart

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

import 'package:fastevergo_v1/utils/auth_guards.dart';

import 'package:fastevergo_v1/features/loading/global_loader.dart';

import '../profile/profile_screen2.dart';
import 'RestaurantMenuScreen.dart';
import 'CategoryScreen.dart';
import 'offer_screen.dart';
import 'combo_screen.dart';
import 'cart/cart_provider.dart';
import 'cart/cart_bar.dart';
import 'cart_screen.dart';
import 'active_order_bottom_bar.dart';

typedef ItemMap = Map<String, dynamic>;
typedef ItemList = List<ItemMap>;

// Safe parsing helpers
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

ItemList interleaveByRestaurant(ItemList items) {
  if (items.isEmpty) return items;

  final Map<String, ItemList> grouped = {};
  for (var item in items) {
    final resId = item['resId']?.toString() ?? 'unknown';
    grouped.putIfAbsent(resId, () => []).add(item);
  }

  final ItemList interleaved = [];
  final List<ItemList> buckets = grouped.values.toList();

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

// Display ordering based on time-of-day
int _mealPriority(ItemMap item, int hour) {
  final info = '${item['name'] ?? ''} ${item['category'] ?? ''} '
          '${(item['tags'] as List?)?.join(' ') ?? ''}'
      .toLowerCase();
  bool has(List<String> words) => words.any(info.contains);

  if (hour < 11) {
    if (has([
      'dosa', 'idli', 'puttu', 'appam', 'breakfast', 'porotta',
      'parotta', 'tea', 'coffee', 'veg', 'upma', 'poori'
    ])) return 0;
    if (has(['indian', 'meals', 'rice'])) return 1;
  } else if (hour < 15) {
    if (has(['meals', 'biriyani', 'biryani', 'rice', 'indian', 'thali'])) return 0;
    if (has(['veg', 'curry', 'parotta'])) return 1;
  } else {
    if (has([
      'mandi', 'arabian', 'alfaham', 'al faham', 'al-faham',
      'shawaya', 'shawarma', 'grill', 'kebab'
    ])) return 0;
    if (has(['fried chicken', 'burger', 'chicken'])) return 1;
  }
  return 2;
}

// In-Stock items first, Sold-Out items strictly at the end
ItemList _sortPopularFoods(ItemList items) {
  final hour = DateTime.now().hour;
  final ItemList inStockItems = [];
  final ItemList outOfStockItems = [];

  for (final map in items) {
    final data = map['itemData'] as ItemMap;
    final stock = parseInt(data['stock']);
    if (stock > 0) {
      inStockItems.add(map);
    } else {
      outOfStockItems.add(map);
    }
  }

  ItemList mixRestaurants(ItemList list) {
    // Prioritize suitable meals within each restaurant, not across the
    // entire list; otherwise one restaurant can occupy a whole tier.
    final Map<String, ItemList> grouped = {};
    for (final map in list) {
      final restaurantId = map['resId']?.toString() ?? 'unknown';
      grouped.putIfAbsent(restaurantId, () => []).add(map);
    }
    for (final bucket in grouped.values) {
      bucket.sort((a, b) {
        final aData = a['itemData'] as ItemMap;
        final bData = b['itemData'] as ItemMap;
        return _mealPriority(aData, hour).compareTo(_mealPriority(bData, hour));
      });
    }
    return interleaveByRestaurant([
      for (final bucket in grouped.values) ...bucket,
    ]);
  }

  return [
    ...mixRestaurants(inStockItems),
    ...mixRestaurants(outOfStockItems),
  ];
}

int _restaurantOrders(ItemMap data) {
  for (final key in ['totalOrders', 'orderCount', 'completedOrdersCount']) {
    if (data.containsKey(key)) return parseInt(data[key]);
  }
  return 0;
}


/// Admin-controlled restaurant order. Missing ranks follow ranked restaurants.
int _restaurantDisplayOrder(ItemMap data) {
  final value = data['displayOrder'];
  if (value is num) return value.toInt() >= 1 ? value.toInt() : 2147483647;
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null && parsed >= 1) return parsed;
  }
  return 2147483647;
}

int _compareRestaurantDisplayOrder(
  QueryDocumentSnapshot<dynamic> a,
  QueryDocumentSnapshot<dynamic> b,
) {
  final dataA = a.data() as ItemMap;
  final dataB = b.data() as ItemMap;
  final rank = _restaurantDisplayOrder(dataA)
      .compareTo(_restaurantDisplayOrder(dataB));
  if (rank != 0) return rank;
  final nameA = (dataA['name']?.toString() ?? '').toLowerCase();
  final nameB = (dataB['name']?.toString() ?? '').toLowerCase();
  final name = nameA.compareTo(nameB);
  return name != 0 ? name : a.id.compareTo(b.id);
}

class FoodHomeScreen extends StatefulWidget {
  // Location is provided by the main Home Screen. Never start a second GPS
  // request here: a manually selected service area must remain selected.
  final Position? selectedPosition;
  final String? selectedLocationName;

  const FoodHomeScreen({
    super.key,
    this.selectedPosition,
    this.selectedLocationName,
  });

  @override
  State<FoodHomeScreen> createState() => _FoodHomeScreenState();
}

enum GateState { locationUnavailable, allowed }

class _FoodHomeScreenState extends State<FoodHomeScreen> {
  DateTime? _lastPressed;

  late String _currentLocation;
  Position? _currentPosition;
  late GateState _gateState;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  String _searchQuery = "";
  Timer? _debounce;
  bool _isSearchFocused = false;

  int _searchMenuLimit = 25;
  int _restaurantsLimit = 10;
  final ScrollController _mainScrollController = ScrollController();
  StreamSubscription<QuerySnapshot>? _restaurantSubscription;
  List<QueryDocumentSnapshot<dynamic>>? _cachedRestaurants;
  Object? _restaurantError;
  Timer? _restaurantTimeout;
  bool _restaurantTimedOut = false;

  late final Stream<QuerySnapshot> _searchMenuStream;

  @override
  void initState() {
    super.initState();
    _useSelectedLocation();
    _listenToRestaurants();
    _searchMenuStream =
        FirebaseFirestore.instance.collectionGroup('menu').snapshots();
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onFocusChanged);
  }

  // One subscription owned by the screen: search and normal lists share it.
  // Switching between search and home never discards restaurant results.
  void _listenToRestaurants() {
    _restaurantSubscription?.cancel();
    _restaurantTimeout?.cancel();
    _restaurantError = null;
    _restaurantTimedOut = false;
    _restaurantTimeout = Timer(const Duration(seconds: 12), () {
      if (mounted && _cachedRestaurants == null) {
        setState(() => _restaurantTimedOut = true);
      }
    });
    _restaurantSubscription = FirebaseFirestore.instance
        .collection('restaurants')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      _restaurantTimeout?.cancel();
      setState(() {
        _cachedRestaurants = snapshot.docs;
        _restaurantError = null;
        _restaurantTimedOut = false;
      });
    }, onError: (Object error) {
      if (!mounted) return;
      _restaurantTimeout?.cancel();
      setState(() {
        _restaurantError = error;
        _restaurantTimedOut = false;
      });
    });
  }

  Widget _restaurantLoadingOrError() {
    if (_restaurantError != null || _restaurantTimedOut) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Restaurants could not be loaded. Check your connection.'),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => setState(_listenToRestaurants),
            child: const Text('Retry'),
          ),
        ]),
      );
    }
    return const Center(child: Padding(
      padding: EdgeInsets.all(24), child: CircularProgressIndicator(),
    ));
  }

  @override
  void didUpdateWidget(covariant FoodHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPosition != widget.selectedPosition ||
        oldWidget.selectedLocationName != widget.selectedLocationName) {
      _useSelectedLocation();
    }
  }

  void _useSelectedLocation() {
    _currentPosition = widget.selectedPosition;
    _currentLocation = widget.selectedLocationName?.trim().isNotEmpty == true
        ? widget.selectedLocationName!.trim()
        : (_currentPosition == null ? 'Select a service area' : 'Selected service area');
    _gateState = _currentPosition == null
        ? GateState.locationUnavailable
        : GateState.allowed;
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.removeListener(_onFocusChanged);
    _searchFocusNode.dispose();
    _restaurantSubscription?.cancel();
    _restaurantTimeout?.cancel();
    _mainScrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() => _isSearchFocused = _searchFocusNode.hasFocus);
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final nextQuery = _searchController.text.trim().toLowerCase();
      if (nextQuery == _searchQuery) return;
      setState(() {
        _searchQuery = nextQuery;
        _searchMenuLimit = 25;
      });
    });
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2) / 1000;
  }

  int _calculateDeliveryTime(double distance, int prepTime) {
    return (distance * 4).round() + prepTime;
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
    final queryWords =
        query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (queryWords.isEmpty) return true;

    for (var qWord in queryWords) {
      final targetWords =
          cleanTarget.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
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
    if (!_isSearchFocused || _searchQuery.isNotEmpty) {
      return const SizedBox.shrink();
    }

    final popularTerms = [
      "Biriyani",
      "Shawarma",
      "Burger",
      "Fried Chicken",
      "Arabian",
      "Pizza",
      "Under 150",
      "Near me",
      "4+ rating",
      "Fast delivery",
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Popular searches",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
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
      stream: _searchMenuStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('Unable to load data. Please try again.'));
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("No food items match your search."));
        }

        final rawQuery = _searchQuery;

        bool isVegOnly = RegExp(r'\bveg\b').hasMatch(rawQuery) && !RegExp(r'non[ -]?veg').hasMatch(rawQuery);
        bool isNonVegOnly = RegExp(r'non[ -]?veg').hasMatch(rawQuery);
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
            .replaceAll(RegExp(r'non[ -]?veg'), '')
            .replaceAll(RegExp(r'\bveg\b'), '')
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

        return Column(
          children: [
            ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: matchingDocs.length < _searchMenuLimit
              ? matchingDocs.length : _searchMenuLimit,
          itemBuilder: (context, index) {
            final itemDoc = matchingDocs[index];

            final parent = itemDoc.reference.parent.parent;
            if (parent == null) return const SizedBox.shrink();
            final matches = _cachedRestaurants?.where(
              (doc) => doc.id == parent.id,
            ).toList() ?? [];
            if (matches.isEmpty) return const SizedBox.shrink();
            final restaurantData = matches.first.data() as ItemMap;
                
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
                      GlobalLoader.run(
                        duration: const Duration(milliseconds: 1800),
                        task: () async {
                          if (context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RestaurantMenuScreen(
                                  restaurantId: itemDoc.reference.parent.parent!.id,
                                  userPosition: _currentPosition,
                                ),
                              ),
                            );
                          }
                        },
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
        ),
            if (_searchMenuLimit < matchingDocs.length)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: OutlinedButton(
                  onPressed: () => setState(() => _searchMenuLimit += 25),
                  child: const Text('Load More Food Items'),
                ),
              ),
          ],
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
          child: Text(
            "Food Items",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        _buildSearchResultsList(),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            "Restaurants",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        _buildNearbyRestaurantsList(),
      ],
    );
  }

  Widget _buildNearbyRestaurantsList() {
    if (_currentPosition == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final docs = _cachedRestaurants;
    if (docs == null) return _restaurantLoadingOrError();
    {
        if (docs.isEmpty) {
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

        final filteredDocs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status'] ?? 'open';
          if (status != 'open') return false;

          final name = data['name']?.toString() ?? '';
          bool matchesText = queryText.isEmpty || _matchesQuery(name, queryText);
          if (!matchesText) return false;

          final double lat = parseDouble(data['latitude']);
          final double lon = parseDouble(data['longitude']);
          if (lat < -90 || lat > 90 || lon < -180 || lon > 180 || (lat == 0 && lon == 0)) return false;
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

        // Admin priority is authoritative; distance is still used for
        // eligibility and delivery-time calculations, not list ordering.
        filteredDocs.sort(_compareRestaurantDisplayOrder);

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
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_gateState == GateState.locationUnavailable) {
      return _buildLocationRequiredScreen();
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handlePop,
      child: _buildMainScreen(),
    );
  }

  Scaffold _buildLocationRequiredScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.location_on_outlined, size: 72, color: Colors.grey),
                const SizedBox(height: 16),
                const Text('Choose a delivery area to continue',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'Select your delivery area on the main home screen. '
                  'You can select an area even when ordering from abroad.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context)
                      .pushNamedAndRemoveUntil('/home', (route) => false),
                  child: const Text('Choose Area on Home'),
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
                controller: _mainScrollController,
                slivers: [
                  SliverToBoxAdapter(child: _buildTopSection()),
                  if (_isSearchFocused && _searchQuery.isEmpty)
                    SliverToBoxAdapter(child: _buildPopularSearchesOverlay()),
                  if (isSearching)
                    SliverToBoxAdapter(child: _buildCombinedSearchResults())
                  else ...[
                    SliverToBoxAdapter(child: _buildCategories()),
                    SliverToBoxAdapter(child: _buildTwoImageOffers()),
                    const SliverToBoxAdapter(child: _AnimatedPopularFoodsBanner()),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: _buildSectionTitle("Nearby Restaurants"),
                      ),
                    ),
                    _buildNearbyRestaurants(),
                    const SliverToBoxAdapter(child: SizedBox(height: 80)),
                  ],
                ],
              ),
              const Positioned(bottom: 0, left: 0, right: 0, child: CartBar()),
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
          colors: [Color(0xFF1A1E43), Color(0xFF1A1E43)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                    Navigator.of(context)
                        .pushNamedAndRemoveUntil('/home', (route) => false);
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Colors.white,
                        size: 20,
                      ),
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
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () {
                    if (!requireLoginGlobal("Please login to access profile")) {
                      return;
                    }
                    GlobalLoader.run(
                      duration: const Duration(milliseconds: 1800),
                      task: () async {
                        if (context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ProfileScreen2(),
                            ),
                          );
                        }
                      },
                    );
                  },
                  child: const CircleAvatar(
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person, color: Color(0xFF1A1E43)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            _buildSearchBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTwoImageOffers() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Special Offers'),
          const Row(children: [
            Expanded(
              child: _ShakingOfferCard(
                tag: 'bigdeal',
                imageAsset: 'assets/images/bigd1.jpeg',
                offerTitle: 'Big Deals',
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _ShakingOfferCard(
                tag: 'combo',
                imageAsset: 'assets/images/combod1.jpeg',
                offerTitle: 'Combo Deals',
              ),
            ),
          ]),
        ],
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
          if (onViewAll != null)
            TextButton(onPressed: onViewAll, child: const Text("View All")),
        ],
      ),
    );
  }

  Widget _buildCategories() {
    return Stack(
      children: [
        Column(children: [
          Container(height: 33, color: const Color(0xFF1A1E43)),
          Container(height: 74, color: Colors.white),
        ]),
        SizedBox(
          height: 107,
          child: _LoopingFoodCategories(
            onCategoryTap: (name) {
              GlobalLoader.run(
                duration: const Duration(milliseconds: 1800),
                task: () async {
                  if (!mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CategoryScreen(
                        category: name == 'Al Faham'
                            ? 'alfaham'
                            : name.toLowerCase(),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNearbyRestaurants() {
    if (_currentPosition == null) {
      return SliverList(
        delegate: SliverChildListDelegate([
          const Center(child: CircularProgressIndicator()),
        ]),
      );
    }
    return SliverList(
      delegate: SliverChildListDelegate([
        Builder(
          builder: (context) {
            final docs = _cachedRestaurants;
            if (docs == null) return _restaurantLoadingOrError();
            if (docs == null || docs.isEmpty) {
              return const Center(child: Text('No nearby restaurants found.'));
            }

            final filteredDocs = docs.where((doc) {
              final data = doc.data() as ItemMap;
              final status = data['status'] ?? 'open';
              final name = (data['name']?.toString() ?? '').toLowerCase();
              final lat = parseDouble(data['latitude']);
              final lon = parseDouble(data['longitude']);
              final hasCoordinates = lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180 && !(lat == 0 && lon == 0);
              return _matchesQuery(name, _searchQuery) && status == 'open' && hasCoordinates;
            }).toList();

            // Keep restaurant order exactly as saved in the admin panel.
            // Search relevance and order count must not override displayOrder.
            filteredDocs.sort(_compareRestaurantDisplayOrder);

            if (filteredDocs.isEmpty) {
              return const Center(child: Text('No results for your search.'));
            }

            final visibleDocs = filteredDocs.take(_restaurantsLimit).toList();
            return Column(
              children: [
                ...visibleDocs.map((doc) {
                  final data = doc.data() as ItemMap;
                  final double lat = parseDouble(data['latitude']);
                  final double lon = parseDouble(data['longitude']);
                  final int prepTime = parseInt(data['prepTime']);
                  final double rating = parseDouble(
                    data['rating'],
                    defaultValue: 4.0,
                  );

                  final double distance = _calculateDistance(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                    lat,
                    lon,
                  );
                  final int deliveryTime = _calculateDeliveryTime(
                    distance,
                    prepTime,
                  );

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
                if (filteredDocs.length > _restaurantsLimit)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _restaurantsLimit += 10;
                        });
                      },
                      child: const Text("Load More Restaurants"),
                    ),
                  ),
              ],
            );
          },
        ),
      ]),
    );
  }
}

// ==========================================
// ==========================================
class _AnimatedPopularFoodsBanner extends StatefulWidget {
  const _AnimatedPopularFoodsBanner();

  @override
  State<_AnimatedPopularFoodsBanner> createState() =>
      _AnimatedPopularFoodsBannerState();
}

class _AnimatedPopularFoodsBannerState extends State<_AnimatedPopularFoodsBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _arrowOffsetAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.018).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    _arrowOffsetAnimation = Tween<double>(begin: 0.0, end: 5.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFFB71C1C),
                Color(0xFFE53935),
                Color(0xFFD32F2F),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD32F2F).withOpacity(0.38),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                final pos = context
                    .findAncestorStateOfType<_FoodHomeScreenState>()
                    ?._currentPosition;
                GlobalLoader.run(
                  duration: const Duration(seconds: 2),
                  task: () async {
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AllPopularFoodsScreen(
                          userPosition: pos,
                        ),
                      ),
                    );
                  },
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Text(
                        "",
                        style: TextStyle(fontSize: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Popular Foods',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(Icons.stars_rounded, color: Color(0xFFFFD54F), size: 18),
                            ],
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Explore best-selling dishes near you',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _arrowOffsetAnimation,
                      builder: (context, _) {
                        return Transform.translate(
                          offset: Offset(_arrowOffsetAnimation.value, 0),
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Color(0xFFB71C1C),
                              size: 14,
                            ),
                          ),
                        );
                      },
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

// ==========================================
// ==========================================
class AllPopularFoodsScreen extends StatefulWidget {
  final Position? userPosition;

  const AllPopularFoodsScreen({super.key, this.userPosition});

  @override
  State<AllPopularFoodsScreen> createState() => _AllPopularFoodsScreenState();
}

class _AllPopularFoodsScreenState extends State<AllPopularFoodsScreen> {
  static const int _popularPageSize = 25;
  int _popularItemsLimit = 25;
  final ScrollController _popularFoodsScrollController = ScrollController();

  // Keep the same Firestore subscriptions while more cards are appended.
  // Recreating streams in build() temporarily removes the list and resets scroll.
  late final Stream<QuerySnapshot> _popularRestaurantsStream;
  late final Stream<QuerySnapshot> _popularMenuStream;

  @override
  void initState() {
    super.initState();
    _popularRestaurantsStream =
        FirebaseFirestore.instance.collection('restaurants').snapshots();
    _popularMenuStream = FirebaseFirestore.instance
        .collectionGroup('menu')
        .where('tags', arrayContains: 'pops')
        .snapshots();
  }


  @override
  void dispose() {
    _popularFoodsScrollController.dispose();
    super.dispose();
  }

  String _selectedPopularFilter = "All";
  String? _selectedCategoryFilter;

  final List<String> _popularFilters = [
    "All",
    "Veg",
    "Non-Veg",
    "Under Rs.150",
    "Top Rated",
    "Fast Delivery",
  ];

  final List<String> _categoryFilters = [
    "Mandi",
    "Arabian",
    "Al Faham",
    "Shawaya",
    "Indian",
    "Breakfast",
    "Veg Specials",
    "Seafoods",
    "Fried Chicken",
    "Biriyani",
    "Shawarma",
    "Burger",
    "Meals",
    "Parotta",
    "Cakes",
    "Dosa",
    "Snacks",
    "Momos",
    "Shake",
    "Icecream",
    "Juice",
    "Chinese",
    "Tea & Coffee",
    "Grills",
    "Desserts",
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
      // Use the same cart bar as the Food Home Screen.
      // It listens to CartProvider and shows View Cart when items are added.
      bottomNavigationBar: const CartBar(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1E43),
        title: const Text(
          "All Popular Foods",
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: widget.userPosition == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Location is not ready. Please enable location to view nearby popular foods.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                SizedBox(
                  height: 48,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
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
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF1A1E43),
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                            side: BorderSide(
                              color: isSelected
                                  ? const Color(0xFF1A1E43)
                                  : Colors.grey.shade300,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
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
                              color: isSelected
                                  ? const Color(0xFF2E7D32)
                                  : Colors.grey.shade300,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          onSelected: (selected) {
                            setState(() {
                              _selectedCategoryFilter =
                                  selected ? category : null;
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
                    stream: _popularRestaurantsStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(child: Text('No restaurants available.'));
                      }

                      final nearbyRestaurants = snapshot.data!.docs.where((doc) {
                        final data = doc.data() as ItemMap;
                        final String status = data['status'] ?? 'open';
                        final double lat = parseDouble(data['latitude']);
                        final double lon = parseDouble(data['longitude']);
                        final double distance = _calculateDistance(
                          widget.userPosition!.latitude,
                          widget.userPosition!.longitude,
                          lat,
                          lon,
                        );
                        return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180 && !(lat == 0 && lon == 0) && distance <= 10.0 && status == 'open';
                      }).toList();

                      if (nearbyRestaurants.isEmpty) {
                        return const Center(
                          child: Text('No open restaurants within 10 km.'),
                        );
                      }

                      return StreamBuilder<QuerySnapshot>(
                        stream: _popularMenuStream,
                        builder: (context, popularSnap) {
                          if (popularSnap.hasError) return const Center(child: Text('Unable to load popular foods. Please try again.'));
                          if (popularSnap.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          final allItems = popularSnap.data?.docs ?? <DocumentSnapshot>[];

                          final restaurantById = <String, ItemMap>{
                            for (final doc in nearbyRestaurants)
                              doc.id: doc.data() as ItemMap,
                          };

                          final enrichedItems = allItems
                              .where((itemDoc) => restaurantById.containsKey(
                                  itemDoc.reference.parent.parent?.id))
                              .map((itemDoc) {
                            final resId = itemDoc.reference.parent.parent!.id;
                            final resData = restaurantById[resId]!;
                            final itemData = itemDoc.data() as ItemMap;
                            return <String, dynamic>{
                              'itemDoc': itemDoc,
                              'itemData': itemData,
                              'resId': resId,
                              'resName': resData['name'] ?? 'Unknown',
                              'resRating': parseDouble(
                                resData['rating'],
                                defaultValue: 4.0,
                              ),
                              'resLat': parseDouble(resData['latitude']),
                              'resLon': parseDouble(resData['longitude']),
                              'prepTime': parseInt(resData['prepTime']),
                              'category': (itemData['category'] ?? '')
                                  .toString()
                                  .toLowerCase(),
                              'name': (itemData['name'] ?? '')
                                  .toString()
                                  .toLowerCase(),
                              'tags': (itemData['tags'] as List?)
                                      ?.map((tag) => tag.toString().toLowerCase())
                                      .toList() ??
                                  <String>[],
                            };
                          }).toList();

                          final rawFilteredItems = enrichedItems.where((map) {
                            final itemData = map['itemData'] as ItemMap;
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
                            } else if (_selectedPopularFilter == "Under Rs.150") {
                              matchesGeneral = price <= 150;
                            } else if (_selectedPopularFilter == "Top Rated") {
                              matchesGeneral =
                                  (map['resRating'] as double) >= 4.0;
                            } else if (_selectedPopularFilter == "Fast Delivery") {
                              final dist = _calculateDistance(
                                widget.userPosition!.latitude,
                                widget.userPosition!.longitude,
                                map['resLat'],
                                map['resLon'],
                              );
                              final deliveryTime = _calculateDeliveryTime(
                                dist,
                                map['prepTime'],
                              );
                              matchesGeneral = deliveryTime <= 30;
                            }

                            bool matchesCategory = true;
                            if (_selectedCategoryFilter != null) {
                              final targetCat = _selectedCategoryFilter!.toLowerCase();
                              matchesCategory = category.contains(targetCat) ||
                                  name.contains(targetCat) ||
                                  tags.any((t) => t.contains(targetCat)) ||
                                  (targetCat == 'al faham' &&
                                      ('$category $name ${tags.join(' ')}')
                                          .contains('alfaham'));
                            }

                            return matchesGeneral && matchesCategory;
                          }).toList();

                          final filteredItems = _sortPopularFoods(rawFilteredItems);

                          if (filteredItems.isEmpty) {
                            return const Center(
                              child: Text("No items found matching filter."),
                            );
                          }

                          return ListView(
                            controller: _popularFoodsScrollController,
                            padding: const EdgeInsets.all(16),
                            children: [
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: 0.83,
                                ),
                                itemCount: filteredItems.length < _popularItemsLimit
                                    ? filteredItems.length
                                    : _popularItemsLimit,
                                itemBuilder: (context, index) {
                                  final dataMap = filteredItems[index];
                                  final itemDoc = dataMap['itemDoc'] as DocumentSnapshot;

                                  return InkWell(
                                    onTap: () {
                                      GlobalLoader.run(
                                        duration: const Duration(milliseconds: 1800),
                                        task: () async {
                                          if (context.mounted) {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => RestaurantMenuScreen(
                                                  restaurantId: dataMap['resId'],
                                                  userPosition: widget.userPosition,
                                                ),
                                              ),
                                            );
                                          }
                                        },
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
                              if (_popularItemsLimit < filteredItems.length)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 20),
                                  child: Center(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        setState(() {
                                          _popularItemsLimit += _popularPageSize;
                                        });
                                      },
                                      child: const Text("Load More Popular Items"),
                                    ),
                                  ),
                                ),
                            ],
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
// HORIZONTAL LOOPING CATEGORIES WITH 4S RESUME TIMEOUT
// ==========================================
class _LoopingFoodCategories extends StatefulWidget {
  final ValueChanged<String> onCategoryTap;
  const _LoopingFoodCategories({required this.onCategoryTap});

  @override
  State<_LoopingFoodCategories> createState() => _LoopingFoodCategoriesState();
}

class _LoopingFoodCategoriesState extends State<_LoopingFoodCategories>
    with WidgetsBindingObserver {
  static const double _itemWidth = 100;
  static const List<(String, String)> _categories = [
    ('Mandi', 'assets/images/mnd.jpeg'),
    ('Arabian', 'assets/images/arabian.jpeg'),
    ('Al Faham', 'assets/images/alfaham.jpeg'),
    ('Shawaya', 'assets/images/shawaya.jpeg'),
    ('Indian', 'assets/images/indian.jpeg'),
    ('Breakfast', 'assets/images/breakfast.jpeg'),
    ('Veg Specials', 'assets/images/vegspecials.jpeg'),
    ('Seafoods', 'assets/images/seafoods.jpeg'),
    ('Fried Chicken', 'assets/images/fried.png'),
    ('Biriyani', 'assets/images/biriyani.jpeg'),
    ('Shawarma', 'assets/images/shawarma.jpeg'),
    ('Burger', 'assets/images/burger.jpeg'),
    ('Meals', 'assets/images/meals.jpeg'),
    ('Parotta', 'assets/images/parotta.jpeg'),
    ('Cakes', 'assets/images/cakes.jpeg'),
    ('Dosa', 'assets/images/dosa.jpeg'),
    ('Snacks', 'assets/images/snacks.png'),
    ('Momos', 'assets/images/momos.jpeg'),
    ('Shake', 'assets/images/shake.jpeg'),
    ('Icecream', 'assets/images/icecream.jpeg'),
    ('Juice', 'assets/images/juice.jpeg'),
    ('Chinese', 'assets/images/chinese.jpeg'),
    ('Tea & Coffee', 'assets/images/tea.png'),
    ('Grills', 'assets/images/grills.png'),
    ('Desserts', 'assets/images/desserts.png'),
  ];

  late final ScrollController _scrollController;
  Timer? _autoScrollTimer;
  Timer? _resumeTimer;
  bool _pausedByTouch = false;
  bool _appActive = true;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController = ScrollController(
      initialScrollOffset: _categories.length * _itemWidth,
    );
    _autoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 2300),
      (_) => _moveLeft(),
    );
  }

  void _handleTouchStart() {
    setState(() {
      _pausedByTouch = true;
    });
    _resumeTimer?.cancel();
  }

  void _handleTouchEnd() {
    _resumeTimer?.cancel();
    // Resume auto scroll after 4 seconds of no touch interaction
    _resumeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _pausedByTouch = false;
        });
      }
    });
  }

  Future<void> _moveLeft() async {
    if (!mounted ||
        !_appActive ||
        _pausedByTouch ||
        _isAnimating ||
        !_scrollController.hasClients ||
        !TickerMode.of(context)) return;
    const cycle = _itemWidth * 25;
    var offset = _scrollController.offset;
    if (offset >= 2 * cycle) {
      offset -= cycle;
      _scrollController.jumpTo(offset);
    }
    _isAnimating = true;
    try {
      await _scrollController.animateTo(
        offset + _itemWidth,
        duration: const Duration(milliseconds: 1900),
        curve: Curves.linear,
      );
    } finally {
      _isAnimating = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoScrollTimer?.cancel();
    _resumeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _handleTouchStart(),
      onPointerUp: (_) => _handleTouchEnd(),
      onPointerCancel: (_) => _handleTouchEnd(),
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _categories.length * 4,
        itemExtent: _itemWidth,
        itemBuilder: (context, index) {
          final (name, imagePath) = _categories[index % _categories.length];
          return InkWell(
            onTap: () => widget.onCategoryTap(name),
            child: Padding(
              padding: const EdgeInsets.only(top: 5, right: 7),
              child: Column(children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(color: Colors.white, width: 2.5),
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      imagePath,
                      fit: BoxFit.cover,
                      cacheWidth: 128,
                      cacheHeight: 128,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.restaurant_menu_rounded,
                        color: Color(0xFF1A1E43),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// ==========================================
class _ShakingOfferCard extends StatefulWidget {
  final String tag;
  final String imageAsset;
  final String offerTitle;
  const _ShakingOfferCard({
    required this.tag,
    required this.imageAsset,
    required this.offerTitle,
  });
  @override
  State<_ShakingOfferCard> createState() => _ShakingOfferCardState();
}

class _ShakingOfferCardState extends State<_ShakingOfferCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _pulse = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.045)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 14,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.045, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 18,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 68),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => Transform.scale(
          scale: reduceMotion ? 1.0 : _pulse.value,
          child: child,
        ),
        child: AspectRatio(
          aspectRatio: 1.777,
          child: Material(
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                if (widget.tag == 'bigdeal') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OfferScreen(
                        title: widget.offerTitle,
                        offerTag: 'bigdeal',
                      ),
                    ),
                  );
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ComboScreen()),
                  );
                }
              },
              child: Image.asset(
                widget.imageAsset,
                fit: BoxFit.cover,
                cacheWidth: 400,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.local_offer_outlined),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// EXPANDABLE RED DESCRIPTION COMPONENT
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

class _ExpandableItemDescriptionState extends State<_ExpandableItemDescription> {
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
// FOOD CARD COMPONENT
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
  late ItemMap itemData;
  late String imageUrl;
  late bool isPopular;
  int quantity = 0;

  @override
  void initState() {
    super.initState();
    itemData = widget.itemDoc.data() as ItemMap;
    imageUrl = itemData['imageUrl'] ?? 'https://via.placeholder.com/150';
    final tags = itemData['tags'] as List?;
    isPopular = tags?.contains('pops') ?? false;

    final cart = Provider.of<CartProvider>(context, listen: false);
    cart.addListener(_updateQuantityFromCart);
    quantity = cart.getQuantity(widget.itemDoc.id);
  }

  @override
  void dispose() {
    Provider.of<CartProvider>(
      context,
      listen: false,
    ).removeListener(_updateQuantityFromCart);
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
    if (parseInt(itemData['stock']) <= 0) {
      return const SizedBox(
        height: 30,
        child: Center(
          child: Text(
            'SOLD OUT',
            style: TextStyle(
              color: Colors.red,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }
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
                  child: const Icon(
                    Icons.remove,
                    size: 16,
                    color: Colors.white,
                  ),
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
            child: const Text(
              'ADD',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
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
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      memCacheWidth: 300,
                      memCacheHeight: 200,
                      height: 82,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Shimmer.fromColors(
                        baseColor: Colors.grey.shade300,
                        highlightColor: Colors.grey.shade100,
                        child: Container(color: Colors.white, height: 82),
                      ),
                      errorWidget: (context, url, error) => const SizedBox(
                        height: 82,
                        child: Center(child: Icon(Icons.fastfood)),
                      ),
                    ),
                  ),
                  if (isSoldOut)
                    Positioned.fill(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            "SOLD OUT",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (isPopular && !isSoldOut)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
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
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
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
                                "Rs.${parseDouble(itemData['price']).toStringAsFixed(0)}",
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (widget.restaurantRating != null)
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.star,
                                      color: Colors.orange,
                                      size: 11,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      widget.restaurantRating!.toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          if (description != null &&
                              description.trim().isNotEmpty) ...[
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
              memCacheWidth: 200,
              memCacheHeight: 200,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              placeholder: (context, url) => Shimmer.fromColors(
                baseColor: Colors.grey.shade300,
                highlightColor: Colors.grey.shade100,
                child: Container(color: Colors.white, width: 80, height: 80),
              ),
              errorWidget: (context, url, error) =>
                  const Icon(Icons.fastfood, size: 60),
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
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  "Rs.${parseDouble(itemData['price']).toStringAsFixed(0)}",
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  (itemData['isVeg'] == true) ? "Veg" : "Non-Veg",
                  style: TextStyle(
                    fontSize: 11,
                    color: (itemData['isVeg'] == true)
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
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
                          color: Colors.green.shade800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star,
                            color: Colors.orange,
                            size: 12,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            widget.restaurantRating?.toStringAsFixed(1) ??
                                'N/A',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
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

// ==========================================
// RESTAURANT CARD WITH AUTO-ROTATING MENU IMAGES
// ==========================================
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
  Timer? _rotationTimer;
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
          .limit(5)
          .get();

      final urls = menuSnapshot.docs
          .map(
            (doc) =>
                (doc.data() as Map<String, dynamic>?)?['imageUrl']?.toString(),
          )
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
    if (_imageUrls.length <= 1) return;
    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(const Duration(milliseconds: 3500), (timer) {
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
    _rotationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                GlobalLoader.run(
                  duration: const Duration(milliseconds: 1800),
                  task: () async {
                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RestaurantMenuScreen(
                            restaurantId: widget.restaurantId,
                            userPosition: widget.userPosition,
                          ),
                        ),
                      );
                    }
                  },
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
                              child: Container(
                                height: 135,
                                color: Colors.white,
                              ),
                            )
                          : AnimatedSwitcher(
                              duration: const Duration(milliseconds: 650),
                              switchInCurve: Curves.easeIn,
                              switchOutCurve: Curves.easeOut,
                              transitionBuilder: (child, animation) {
                                return FadeTransition(opacity: animation, child: child);
                              },
                              child: _imageUrls.isNotEmpty
                                  ? CachedNetworkImage(
                                      key: ValueKey<String>(
                                        _imageUrls[_currentImageIndex],
                                      ),
                                      imageUrl: _imageUrls[_currentImageIndex],
                                      memCacheWidth: 600,
                                      memCacheHeight: 300,
                                      height: 135,
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) =>
                                          Shimmer.fromColors(
                                        baseColor: Colors.grey.shade200,
                                        highlightColor: Colors.grey.shade50,
                                        child: Container(
                                          height: 135,
                                          color: Colors.white,
                                        ),
                                      ),
                                      errorWidget: (context, url, error) {
                                        return Container(
                                          height: 135,
                                          color: Colors.grey[100],
                                          child: const Center(
                                            child: Icon(
                                              Icons.broken_image,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        );
                                      },
                                    )
                                  : Container(
                                      key: const ValueKey<String>('placeholder'),
                                      height: 135,
                                      width: double.infinity,
                                      color: Colors.grey[100],
                                      child: const Center(
                                        child: Text(
                                          'No images available',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
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
                                Colors.black.withOpacity(0.04),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_imageUrls.length > 1)
                        Positioned(
                          bottom: 8,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.45),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(
                                _imageUrls.length > 5 ? 5 : _imageUrls.length,
                                (idx) => Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                  width: _currentImageIndex % (_imageUrls.length > 5 ? 5 : _imageUrls.length) == idx ? 6 : 4,
                                  height: _currentImageIndex % (_imageUrls.length > 5 ? 5 : _imageUrls.length) == idx ? 6 : 4,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _currentImageIndex % (_imageUrls.length > 5 ? 5 : _imageUrls.length) == idx
                                        ? Colors.white
                                        : Colors.white54,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A1E43),
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.access_time_rounded,
                                    size: 13,
                                    color: Colors.grey,
                                  ),
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
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: Text(
                                      "-",
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                      ),
                                    ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: Color(0xFF2E7D32),
                                size: 15,
                              ),
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
    );
  }
}