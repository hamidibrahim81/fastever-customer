import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:geolocator/geolocator.dart'; // ✅ Added for distance calculation
import 'dart:async';

// Local imports
import 'RestaurantMenuScreen.dart';
import 'cart/cart_provider.dart';
import 'cart/cart_bar.dart';
import 'active_order_bottom_bar.dart'; 

/// ------------------------------
/// Helper Parsers
/// ------------------------------
double parseDouble(dynamic value, {double defaultValue = 0.0}) {
  if (value is String) return double.tryParse(value.toString()) ?? defaultValue;
  if (value is num) return value.toDouble();
  return defaultValue;
}

int parseInt(dynamic value, {int defaultValue = 0}) {
  if (value is String) return int.tryParse(value.toString()) ?? defaultValue;
  if (value is num) return value.toInt();
  return defaultValue;
}

/// ------------------------------
/// Food Item Model
/// ------------------------------
class FoodItemModel {
  final String id;
  final String name;
  final double price;
  final String imageUrl;
  final String restaurantId;
  final String? restaurantName;
  final double? restaurantRating;
  final double distance; // ✅ Added to show distance
  final bool isVeg;
  final bool isInstaHub;

  FoodItemModel({
    required this.id,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.restaurantId,
    this.restaurantName,
    this.restaurantRating,
    required this.distance, // ✅
    this.isVeg = false,
    this.isInstaHub = false,
  });

  //  factory to create from the merged Map
  factory FoodItemModel.fromMap(Map<String, dynamic> data) {
    return FoodItemModel(
      id: data['id'] ?? '', // ID extracted from DocumentSnapshot.id
      name: data['name'] ?? 'Unnamed Dish',
      price: parseDouble(data['price']),
      imageUrl: data['imageUrl'] ?? 'https://via.placeholder.com/200',
      restaurantId: data['restaurantId'] ?? '', // Corrected ID from merge
      restaurantName: data['restaurantName'], // Merged field
      restaurantRating: parseDouble(data['restaurantRating']), // Merged field
      distance: parseDouble(data['distance']), // ✅ Merged distance field
      isVeg: data['isVeg'] == true,
      isInstaHub: data['isInstaHub'] == true,
    );
  }
}

/// ------------------------------
/// Category Screen
/// ------------------------------
class CategoryScreen extends StatefulWidget {
  final String category;
  const CategoryScreen({super.key, required this.category});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  final ScrollController _scrollController = ScrollController();
  // State now holds Maps with merged restaurant data
  List<Map<String, dynamic>> _documents = []; 
  bool _isLoading = true;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  final int _documentLimit = 30;
  bool _isFetchingMore = false;
  bool _fetchError = false;
  Position? _userPosition; // ✅ To calculate sorting

  @override
  void initState() {
    super.initState();
    _initData(); // ✅ Get location then load
    _scrollController.addListener(_onScroll);
  }

  // ✅ Step 1: Get User Location
  Future<void> _initData() async {
    try {
      _userPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (e) {
      debugPrint("Location error: $e");
    }
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent * 0.9 &&
        !_isFetchingMore &&
        _hasMore) {
      _loadMoreData();
    }
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _documents = []; // Resetting list of maps
        _lastDocument = null;
        _hasMore = true;
        _fetchError = false;
      });
    }
    await _loadMoreData();
  }

  /// ------------------------------
  /// Load More Data (with Restaurant Join & Sorting)
  /// ------------------------------
  Future<void> _loadMoreData() async {
    if (!_hasMore || _isFetchingMore) return;

    if (mounted) {
      setState(() {
        _isFetchingMore = true;
      });
    }

    try {
      // 1. Fetch menu items
      Query query = FirebaseFirestore.instance
          .collectionGroup("menu")
          .where("tags", arrayContains: widget.category.toLowerCase())
          .orderBy(FieldPath.documentId)
          .limit(_documentLimit);

      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final querySnapshot = await query.get();
      final newDocs = querySnapshot.docs;

      if (newDocs.isEmpty) {
        if (mounted) {
          setState(() {
            _hasMore = false;
            _isFetchingMore = false;
            _isLoading = false;
          });
        }
        return;
      }

      // 2. Collect all unique restaurant IDs
      final restaurantIds = newDocs
          .map((d) => (d.data() as Map<String, dynamic>)['restaurantId'] ?? d.reference.parent.parent?.id)
          .whereType<String>()
          .toSet();

      // 3. Fetch restaurant details once per batch
      final restaurantSnapshots = await Future.wait(
        restaurantIds.map((id) => FirebaseFirestore.instance
            .collection('restaurants')
            .doc(id)
            .get()),
      );

      // 4. Build restaurant data map
      final restaurantMap = {
        for (var doc in restaurantSnapshots)
          if (doc.exists) doc.id: doc.data()
      };

      // 5. Merge restaurant data into a new list of maps
      final List<Map<String, dynamic>> mergedDataList = [];
      for (var doc in newDocs) {
        final data = Map<String, dynamic>.from(doc.data() as Map); 
        final restaurantId = data['restaurantId'] ?? doc.reference.parent.parent?.id ?? '';
        
        data['id'] = doc.id; 
        data['restaurantId'] = restaurantId;

        double dist = 0.0;
        if (restaurantId.isNotEmpty && restaurantMap.containsKey(restaurantId)) {
          final restData = restaurantMap[restaurantId]!;
          
          // ✅ CHECK STATUS: Skip this item if restaurant is not "open"
          final String status = restData['status'] ?? 'open';
          if (status != 'open') continue;

          data['restaurantName'] = restData['name'] ?? 'Restaurant Unknown';
          data['restaurantRating'] = parseDouble(restData['rating']); 

          // ✅ Calculate Distance if location is available
          if (_userPosition != null) {
            dist = Geolocator.distanceBetween(
              _userPosition!.latitude, _userPosition!.longitude,
              parseDouble(restData['latitude']), parseDouble(restData['longitude'])
            ) / 1000;
          }
        } else {
           // If restaurant data doesn't exist, we skip the item
           continue;
        }
        
        data['distance'] = dist; // ✅ Add distance to map
        mergedDataList.add(data);
      }

      // ✅ Step 2: Sort the combined list by distance (closest first)
      _documents.addAll(mergedDataList);
      _documents.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

      if (mounted) {
        setState(() {
          _lastDocument = newDocs.last;
          if (newDocs.length < _documentLimit) _hasMore = false;
          _isLoading = false;
          _isFetchingMore = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading data: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isFetchingMore = false;
          _fetchError = true;
        });
      }
    }
  }

  /// ------------------------------
  /// Build UI
  /// ------------------------------
  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    const backgroundColor = Color(0xFFF8F8F8);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          widget.category.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      bottomNavigationBar: const ActiveOrderBottomBar(),
      body: Stack(
        children: [
          RefreshIndicator(
            color: primaryColor,
            onRefresh: _loadData,
            child: _isLoading
                ? _buildShimmerLoading()
                : _fetchError
                    ? _buildErrorWidget(primaryColor)
                    : _documents.isEmpty
                        ? _buildNoItemsFound()
                        : ListView.builder(
                            controller: _scrollController,
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 100, top: 8),
                            itemCount: _documents.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _documents.length) {
                                return _buildBottomLoader(primaryColor);
                              }

                              final foodData = _documents[index]; 
                              final foodItem = FoodItemModel.fromMap(foodData); 

                              return Selector<CartProvider, int>(
                                selector: (_, cart) =>
                                    cart.getQuantity(foodItem.id),
                                builder: (context, quantityInCart, child) {
                                  return _buildFoodItemCard(
                                    context,
                                    foodData, 
                                    foodItem.restaurantId,
                                    foodItem.id,
                                    quantityInCart,
                                    foodItem.restaurantName, 
                                    foodItem.restaurantRating, 
                                    foodItem.distance, // ✅ Added distance
                                  );
                                },
                              );
                            },
                          ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CartBar(),
          ),
        ],
      ),
    );
  }

  /// ------------------------------
  /// UI Helper Widgets
  /// ------------------------------
  Widget _buildBottomLoader(Color color) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
        ),
      );

  Widget _buildNoItemsFound() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              "No dishes found from open restaurants.",
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );

  Widget _buildErrorWidget(Color primaryColor) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              "Failed to load items. Check your connection.",
              style: TextStyle(color: Colors.red, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              child: const Text("Retry", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

  Widget _buildShimmerLoading() => ListView.builder(
        itemCount: 5,
        padding: const EdgeInsets.only(bottom: 80, top: 8),
        itemBuilder: (context, index) => _buildShimmerItemCard(),
      );

  Widget _buildShimmerItemCard() => Card(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Container(
            height: 130,
            padding: const EdgeInsets.all(10.0),
            child: Row(
              children: [
                const SizedBox(
                  width: 110,
                  height: 110,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(width: double.infinity, height: 16, color: Colors.white),
                      const SizedBox(height: 8),
                      Container(width: 100, height: 14, color: Colors.white),
                      const SizedBox(height: 8),
                      Container(width: 80, height: 14, color: Colors.white),
                      const SizedBox(height: 8),
                      Container(width: 90, height: 38, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  /// ------------------------------
  /// Food Card Builder
  /// ------------------------------
  Widget _buildFoodItemCard(
    BuildContext context,
    Map<String, dynamic> food,
    String restaurantId,
    String itemId,
    int quantityInCart,
    String? restaurantName, 
    double? restaurantRating, 
    double distance,
  ) {
    final cart = Provider.of<CartProvider>(context, listen: false);
    final primaryColor = Theme.of(context).primaryColor;

    final imageUrl = food['imageUrl'] ?? "https://via.placeholder.com/200";
    final foodName = food['name'] ?? "Unnamed Dish";
    final foodPrice = parseDouble(food['price']);
    final int stockAvailable = parseInt(food['stock'], defaultValue: 0); // ✅ STOCK VARIABLE

    void _updateCart(int newQuantity) {
      if (newQuantity <= 0) {
        cart.removeItem(itemId);
      } else {
        // ✅ STOCK LIMIT VALIDATION
        if (newQuantity > stockAvailable) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Only $stockAvailable left in stock!"),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }

        cart.updateItem(
          id: itemId,
          name: foodName,
          price: foodPrice,
          restaurantId: restaurantId,
          image: imageUrl,
          qty: newQuantity,
          isInstaHub: food['isInstaHub'] == true,
        );
      }
    }

    Widget _quantityButton() {
      if (quantityInCart > 0) {
        return Container(
          // ✅ INCREASED CONTAINER SIZE & PADDING
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                // ✅ INCREASED ICON SIZE (24)
                icon: const Icon(Icons.remove, color: Colors.red, size: 24),
                onPressed: () => _updateCart(quantityInCart - 1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text('$quantityInCart',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)), // ✅ INCREASED FONT
              ),
              IconButton(
                // ✅ INCREASED ICON SIZE (24)
                icon: Icon(Icons.add, color: primaryColor, size: 24),
                onPressed: () => _updateCart(quantityInCart + 1),
              ),
            ],
          ),
        );
      }
      return ElevatedButton(
        onPressed: () => _updateCart(1),
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          // ✅ INCREASED BUTTON SIZE
          minimumSize: const Size(120, 46),
          elevation: 0,
        ),
        child: const Text("ADD",
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold, color: Colors.white)),
      );
    }

    return GestureDetector(
      onTap: () {
        if (restaurantId.isNotEmpty && context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RestaurantMenuScreen(
                restaurantId: restaurantId,
                restaurantName: restaurantName,
              ),
            ),
          );
        }
      },
      child: Card(
        elevation: 4,
        shadowColor: Colors.black12,
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(12.0), // ✅ INCREASED PADDING
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  width: 110,
                  height: 110,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Shimmer.fromColors(
                    baseColor: Colors.grey.shade300,
                    highlightColor: Colors.grey.shade100,
                    child: Container(
                      width: 110,
                      height: 110,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(foodName,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            overflow: TextOverflow.ellipsis)),
                    const SizedBox(height: 4),
                    if (restaurantName != null && restaurantName.isNotEmpty && restaurantName != 'Unknown Restaurant')
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              restaurantName,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade800),
                            ),
                          ),
                          if (restaurantRating != null && restaurantRating > 0)
                            Row(
                              children: [
                                const SizedBox(width: 6),
                                const Icon(Icons.star,
                                    size: 14, color: Colors.amber),
                                Text(
                                  restaurantRating.toStringAsFixed(1),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                        ],
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 14, color: Colors.green),
                        const SizedBox(width: 2),
                        Text(
                          "${distance.toStringAsFixed(1)} km away",
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8), // ✅ EXTRA SPACING
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("₹${foodPrice.toStringAsFixed(0)}",
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: primaryColor)),
                        _quantityButton(),
                      ],
                    ),
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