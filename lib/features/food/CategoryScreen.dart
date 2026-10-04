import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:math';

// ✅ IMPORT AUTH GUARD
import 'package:fastevergo_v1/utils/auth_guards.dart';

// Local imports
import 'RestaurantMenuScreen.dart';
import 'cart/cart_provider.dart';
import 'cart/cart_bar.dart';
import 'active_order_bottom_bar.dart';

/// ------------------------------
/// Helper Parsers
/// ------------------------------
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

/// ------------------------------
/// Food Item Model
/// ------------------------------
class FoodItemModel {
  final String id;
  final String name;
  final double price;
  final double mrp;
  final String imageUrl;
  final String restaurantId;
  final String? restaurantName;
  final double? restaurantRating;
  final double distance;
  final bool isVeg;
  final bool isInstaHub;
  final String? description;

  FoodItemModel({
    required this.id,
    required this.name,
    required this.price,
    required this.mrp,
    required this.imageUrl,
    required this.restaurantId,
    this.restaurantName,
    this.restaurantRating,
    required this.distance,
    this.isVeg = false,
    this.isInstaHub = false,
    this.description,
  });

  factory FoodItemModel.fromMap(Map<String, dynamic> data) {
    final rawMrp = data['mrp'] ?? data['originalPrice'] ?? data['price'] ?? 0;
    final rawPrice = data['offerPrice'] ?? data['offerSalePrice'] ?? data['price'] ?? 0;

    return FoodItemModel(
      id: data['id'] ?? '',
      name: data['name'] ?? data['productName'] ?? 'Unnamed Dish',
      price: parseDouble(rawPrice),
      mrp: parseDouble(rawMrp),
      imageUrl: data['imageUrl'] ?? data['image'] ?? 'https://via.placeholder.com/200',
      restaurantId: data['restaurantId'] ?? '',
      restaurantName: data['restaurantName'],
      restaurantRating: parseDouble(data['restaurantRating']),
      distance: parseDouble(data['distance']),
      isVeg: data['isVeg'] == true,
      isInstaHub: data['isInstaHub'] == true,
      description: data['description']?.toString(),
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
  List<Map<String, dynamic>> _documents = [];
  bool _isLoading = true;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  final int _documentLimit = 80; // Larger batch so multiple restaurants can be pulled and interleaved
  bool _isFetchingMore = false;
  bool _fetchError = false;
  Position? _userPosition;

  late String _selectedFilterTag;

  final List<Map<String, String>> _filterOptions = const [
    {"label": "🍽️ All", "tag": "all"},
    {"label": "⚡ Top Selling", "tag": "top_sell"},
    {"label": "💸 Best Offers", "tag": "best_offer"},
    {"label": "🌱 Pure Veg", "tag": "veg"},
  ];

  @override
  void initState() {
    super.initState();
    final initialCat = widget.category.toLowerCase().trim();
    _selectedFilterTag = initialCat.isEmpty ? 'all' : initialCat;
    _initData();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _initData() async {
    try {
      _userPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
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
            _scrollController.position.maxScrollExtent * 0.85 &&
        !_isFetchingMore &&
        _hasMore) {
      _loadMoreData();
    }
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _documents = [];
        _lastDocument = null;
        _hasMore = true;
        _fetchError = false;
      });
    }
    await _loadMoreData();
  }

  /// 🔀 Interleaves items across different restaurants in round-robin fashion
  List<Map<String, dynamic>> _interleaveByRestaurant(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return [];

    // Group items by restaurant
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var item in items) {
      final restId = item['restaurantId']?.toString() ?? 'unknown';
      grouped.putIfAbsent(restId, () => []).add(item);
    }

    // Shuffle inside each restaurant queue so items within that restaurant vary
    for (var list in grouped.values) {
      list.shuffle(Random());
    }

    // Round-robin selection: Pick 1 item from Restaurant A, 1 from B, 1 from C, then repeat
    final List<Map<String, dynamic>> result = [];
    final List<String> restaurantKeys = grouped.keys.toList()..shuffle(Random());

    bool itemsRemaining = true;
    while (itemsRemaining) {
      itemsRemaining = false;
      for (var key in restaurantKeys) {
        final list = grouped[key]!;
        if (list.isNotEmpty) {
          result.add(list.removeAt(0));
          if (list.isNotEmpty) {
            itemsRemaining = true;
          }
        }
      }
    }
    return result;
  }

  Future<void> _loadMoreData() async {
    if (!_hasMore || _isFetchingMore) return;

    if (mounted) {
      setState(() {
        _isFetchingMore = true;
      });
    }

    try {
      Query query = FirebaseFirestore.instance.collectionGroup("menu");

      if (_selectedFilterTag == 'veg') {
        query = query.where("isVeg", isEqualTo: true);
      } else if (_selectedFilterTag == 'top_sell') {
        query = query.where("tags", arrayContains: "top_sell");
      } else if (_selectedFilterTag == 'best_offer') {
        query = query.where("tags", arrayContains: "best_offer");
      } else if (_selectedFilterTag != 'all') {
        query = query.where("tags", arrayContains: _selectedFilterTag);
      }

      query = query.limit(_documentLimit);

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

      final restaurantIds = newDocs
          .map(
            (d) =>
                (d.data() as Map<String, dynamic>)['restaurantId'] ??
                d.reference.parent.parent?.id,
          )
          .whereType<String>()
          .toSet();

      final restaurantSnapshots = await Future.wait(
        restaurantIds.map(
          (id) => FirebaseFirestore.instance
              .collection('restaurants')
              .doc(id)
              .get(),
        ),
      );

      final restaurantMap = <String, Map<String, dynamic>>{};
      for (var doc in restaurantSnapshots) {
        if (doc.exists && doc.data() != null) {
          restaurantMap[doc.id] = doc.data()!;
        }
      }

      final List<Map<String, dynamic>> rawBatch = [];
      for (var doc in newDocs) {
        final data = Map<String, dynamic>.from(doc.data() as Map);
        final restaurantId =
            data['restaurantId'] ?? doc.reference.parent.parent?.id ?? '';

        data['id'] = doc.id;
        data['restaurantId'] = restaurantId;

        double dist = 0.0;
        if (restaurantId.isNotEmpty && restaurantMap.containsKey(restaurantId)) {
          final restData = restaurantMap[restaurantId]!;
          final String status = restData['status'] ?? 'open';
          if (status != 'open') continue;

          data['restaurantName'] = restData['name'] ?? 'Restaurant Unknown';
          data['restaurantRating'] = parseDouble(restData['rating']);

          if (_userPosition != null) {
            dist = Geolocator.distanceBetween(
                  _userPosition!.latitude,
                  _userPosition!.longitude,
                  parseDouble(restData['latitude']),
                  parseDouble(restData['longitude']),
                ) /
                1000;
          }
        } else {
          continue;
        }

        data['distance'] = dist;
        rawBatch.add(data);
      }

      // Mix completely across multiple restaurants
      final interleavedBatch = _interleaveByRestaurant(rawBatch);

      _documents.addAll(interleavedBatch);

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

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFFF8F8F8);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          widget.category.isEmpty ? "EXPLORE DISHES" : widget.category.toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Color(0xFF1A1E43),
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A1E43)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Column(
            children: [
              _buildFilterChips(),
              Container(color: const Color(0xFFEEEEEE), height: 1),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const ActiveOrderBottomBar(),
      body: Stack(
        children: [
          RefreshIndicator(
            color: const Color(0xFF1A1E43),
            onRefresh: _loadData,
            child: _isLoading
                ? _buildShimmerLoading()
                : _fetchError
                    ? _buildErrorWidget(const Color(0xFF1A1E43))
                    : _documents.isEmpty
                        ? _buildNoItemsFound()
                        : ListView.builder(
                            controller: _scrollController,
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 110, top: 8),
                            itemCount: _documents.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _documents.length) {
                                return _buildBottomLoader(const Color(0xFF1A1E43));
                              }

                              final foodData = _documents[index];
                              final foodItem = FoodItemModel.fromMap(foodData);

                              return Selector<CartProvider, int>(
                                selector: (_, cart) => cart.getQuantity(foodItem.id),
                                builder: (context, quantityInCart, child) {
                                  return _buildFoodItemCard(
                                    context,
                                    foodData,
                                    foodItem.restaurantId,
                                    foodItem.id,
                                    quantityInCart,
                                    foodItem.restaurantName,
                                    foodItem.restaurantRating,
                                    foodItem.distance,
                                    foodItem.price,
                                    foodItem.mrp,
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

  Widget _buildFilterChips() {
    return Container(
      height: 48,
      color: Colors.white,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemCount: _filterOptions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final opt = _filterOptions[index];
          final isSelected = _selectedFilterTag == opt["tag"];

          return ChoiceChip(
            label: Text(opt["label"]!),
            selected: isSelected,
            selectedColor: const Color(0xFF1A1E43),
            backgroundColor: const Color(0xFFF1F3F6),
            side: BorderSide(
              color: isSelected ? const Color(0xFF1A1E43) : Colors.transparent,
            ),
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFF1A1E43),
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 12,
            ),
            onSelected: (selected) {
              if (selected && _selectedFilterTag != opt["tag"]!) {
                setState(() {
                  _selectedFilterTag = opt["tag"]!;
                });
                _loadData();
              }
            },
          );
        },
      ),
    );
  }

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
            Icon(Icons.search_off_rounded, size: 60, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              "No dishes found from open restaurants.",
              style: TextStyle(
                color: Colors.grey,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );

  Widget _buildErrorWidget(Color primaryColor) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              "Failed to load items. Check your connection.",
              style: TextStyle(
                color: Colors.red,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                "Retry",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );

  Widget _buildShimmerLoading() => ListView.builder(
        itemCount: 5,
        padding: const EdgeInsets.only(bottom: 80, top: 8),
        itemBuilder: (context, index) => _buildShimmerItemCard(),
      );

  Widget _buildShimmerItemCard() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(color: const Color(0xFFF0F0F0)),
        ),
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade200,
          highlightColor: Colors.grey.shade50,
          child: Row(
            children: [
              const SizedBox(
                width: 90,
                height: 90,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 8),
                    Container(width: 100, height: 14, color: Colors.white),
                    const SizedBox(height: 8),
                    Container(width: 80, height: 14, color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildFoodItemCard(
    BuildContext context,
    Map<String, dynamic> food,
    String restaurantId,
    String itemId,
    int quantityInCart,
    String? restaurantName,
    double? restaurantRating,
    double distance,
    double foodPrice,
    double mrp,
  ) {
    final cart = Provider.of<CartProvider>(context, listen: false);

    final imageUrl = food['imageUrl'] ?? food['image'] ?? "https://via.placeholder.com/200";
    final foodName = food['name'] ?? food['productName'] ?? "Unnamed Dish";
    final int stockAvailable = parseInt(food['stock'] ?? food['stockLevels'], defaultValue: 0);
    final isOutOfStock = stockAvailable <= 0;
    final String? description = food['description']?.toString();

    final bool hasDiscount = mrp > foodPrice && foodPrice > 0;
    final int discountPercent = hasDiscount ? (((mrp - foodPrice) / mrp) * 100).round() : 0;

    void updateCart(int newQuantity) {
      if (!requireLoginGlobal("Please login to add items to cart")) return;

      if (newQuantity <= 0) {
        cart.removeItem(itemId);
      } else {
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

    Widget quantityButton() {
      if (isOutOfStock) {
        return const SizedBox.shrink();
      }

      if (quantityInCart > 0) {
        return Container(
          height: 36,
          width: 100,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1E43),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              InkWell(
                onTap: () => updateCart(quantityInCart - 1),
                child: const Icon(Icons.remove, color: Colors.white, size: 16),
              ),
              Text(
                '$quantityInCart',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              InkWell(
                onTap: () => updateCart(quantityInCart + 1),
                child: const Icon(Icons.add, color: Colors.white, size: 16),
              ),
            ],
          ),
        );
      }
      return SizedBox(
        height: 36,
        width: 100,
        child: ElevatedButton(
          onPressed: () => updateCart(1),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A1E43),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: EdgeInsets.zero,
          ),
          child: const Text(
            "ADD",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        if (!isOutOfStock && restaurantId.isNotEmpty && context.mounted) {
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
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(color: const Color(0xFFF0F0F0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    foodName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isOutOfStock ? Colors.grey : const Color(0xFF1A1E43),
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  if (restaurantName != null &&
                      restaurantName.isNotEmpty &&
                      restaurantName != 'Unknown Restaurant')
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            restaurantName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                        if (restaurantRating != null && restaurantRating > 0)
                          Row(
                            children: [
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.star_rounded,
                                size: 14,
                                color: Color(0xFF2E7D32),
                              ),
                              Text(
                                restaurantRating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF2E7D32),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 13,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "${distance.toStringAsFixed(1)} km",
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        "₹${foodPrice.toStringAsFixed(0)}",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                      if (hasDiscount) ...[
                        const SizedBox(width: 8),
                        Text(
                          "₹${mrp.toStringAsFixed(0)}",
                          style: TextStyle(
                            decoration: TextDecoration.lineThrough,
                            fontSize: 12,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            "$discountPercent% OFF",
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (description != null && description.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _ExpandableItemDescription(
                      text: description.trim(),
                      itemName: foodName,
                      maxLines: 2,
                      openDialogOnMore: false,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 90,
                        height: 90,
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          width: 90,
                          height: 90,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Shimmer.fromColors(
                            baseColor: Colors.grey.shade200,
                            highlightColor: Colors.grey.shade50,
                            child: Container(
                              width: 90,
                              height: 90,
                              color: Colors.white,
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            width: 90,
                            height: 90,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.fastfood, color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                    if (isOutOfStock)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Text(
                              "SOLD OUT",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                quantityButton(),
              ],
            ),
          ],
        ),
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
    super.key,
    required this.text,
    this.itemName,
    this.maxLines = 2,
    this.openDialogOnMore = false,
  });

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
                    icon: const Icon(
                      Icons.close,
                      size: 20,
                      color: Colors.grey,
                    ),
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