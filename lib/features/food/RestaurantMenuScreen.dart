import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:async';

import 'cart/cart_provider.dart';
import 'cart/cart_bar.dart';
import 'active_order_bottom_bar.dart'; 

// Helper to safely parse price values
double parseDouble(dynamic value, {double defaultValue = 0.0}) {
  if (value is String) return double.tryParse(value) ?? defaultValue;
  if (value is num) return value.toDouble();
  return defaultValue;
}

// Helper to safely parse any number field for sorting
num parseNum(dynamic value, {num defaultValue = 0}) {
  if (value is num) return value;
  if (value is String) return double.tryParse(value) ?? defaultValue;
  return defaultValue;
}

// ✅ NEW: Helper to safely parse Stock (int)
int parseInt(dynamic value, {int defaultValue = 0}) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? defaultValue;
  if (value is double) return value.toInt();
  return defaultValue;
}

// A simple reusable widget for info chips
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color backgroundColor;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
    this.backgroundColor = Colors.black45,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class RestaurantMenuScreen extends StatefulWidget {
  final String restaurantId;
  final String? restaurantName;
  final Position? userPosition;

  const RestaurantMenuScreen({
    super.key,
    required this.restaurantId,
    this.restaurantName,
    this.userPosition,
  });

  @override
  State<RestaurantMenuScreen> createState() => _RestaurantMenuScreenState();
}

class _RestaurantMenuScreenState extends State<RestaurantMenuScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late Stream<DocumentSnapshot> _restaurantStream;
  late TabController _tabController;
  final _scrollController = ScrollController();

  List<QueryDocumentSnapshot> _allMenuItems = [];
  List<QueryDocumentSnapshot> _processedMenuItems = []; 

  bool _isLoadingMenu = true;
  bool _isLoadingMore = false;
  bool _hasMoreItems = true;
  DocumentSnapshot? _lastDocument;
  final int _documentLimit = 50;

  String? _filterType;
  String? _sortBy;
  bool _isRestaurantOpen = true; 

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    _restaurantStream = FirebaseFirestore.instance
        .collection("restaurants")
        .doc(widget.restaurantId)
        .snapshots();
        
    _loadInitialMenuData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients && 
        _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        _hasMoreItems &&
        !_isLoadingMore) {
      _loadMoreMenuData();
    }
  }

  void _applyFiltersAndSort() {
    List<QueryDocumentSnapshot> tempItems = List.from(_allMenuItems);

    if (_filterType == "veg") {
      tempItems = tempItems
          .where((doc) => (doc.data() as Map<String, dynamic>)["isVeg"] == true)
          .toList();
    } else if (_filterType == "non-veg") {
      tempItems = tempItems
          .where((doc) => (doc.data() as Map<String, dynamic>)["isVeg"] == false)
          .toList();
    }

    if (_sortBy != null) {
      switch (_sortBy) {
        case "price_asc":
          tempItems.sort((a, b) => parseDouble((a.data() as Map<String, dynamic>)["price"])
              .compareTo(parseDouble((b.data() as Map<String, dynamic>)["price"])));
          break;
        case "price_desc":
          tempItems.sort((a, b) => parseDouble((b.data() as Map<String, dynamic>)["price"])
              .compareTo(parseDouble((a.data() as Map<String, dynamic>)["price"])));
          break;
        case "popularity":
          tempItems.sort((a, b) =>
              parseNum((b.data() as Map<String, dynamic>)["popularity"])
                  .compareTo(parseNum((a.data() as Map<String, dynamic>)["popularity"])));
          break;
        case "rating":
          tempItems.sort((a, b) =>
              parseNum((b.data() as Map<String, dynamic>)["rating"])
                  .compareTo(parseNum((a.data() as Map<String, dynamic>)["rating"])));
          break;
      }
    }

    if (mounted) {
      setState(() {
        _processedMenuItems = tempItems;
      });
    }
  }

  Future<void> _loadInitialMenuData() async {
    if (!mounted) return;
    setState(() {
      _allMenuItems.clear();
      _processedMenuItems.clear();
      _isLoadingMenu = true;
      _hasMoreItems = true;
      _lastDocument = null;
    });
    await _loadMoreMenuData();
  }

  Future<void> _loadMoreMenuData() async {
    if (!_hasMoreItems || _isLoadingMore) return;
    if (!mounted) return;
    setState(() => _isLoadingMore = true);

    Query query = FirebaseFirestore.instance
        .collection("restaurants")
        .doc(widget.restaurantId)
        .collection("menu")
        .limit(_documentLimit);

    if (_lastDocument != null) {
      query = query.startAfterDocument(_lastDocument!);
    }

    try {
      final querySnapshot = await query.get();
      if (querySnapshot.docs.isEmpty) {
        if (!mounted) return;
        setState(() {
          _hasMoreItems = false;
          _isLoadingMenu = false;
          _isLoadingMore = false;
        });
        return;
      }

      if (!mounted) return;
      _allMenuItems.addAll(querySnapshot.docs);
      _lastDocument = querySnapshot.docs.last;
      if (querySnapshot.docs.length < _documentLimit) _hasMoreItems = false;
      _isLoadingMenu = false;
      _isLoadingMore = false;
      _applyFiltersAndSort();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingMenu = false;
        _isLoadingMore = false;
      });
    }
  }

  String _getDistance(double resLat, double resLon) {
    if (widget.userPosition == null) return "Detecting...";
    double distanceInMeters = Geolocator.distanceBetween(
      widget.userPosition!.latitude,
      widget.userPosition!.longitude,
      resLat,
      resLon,
    );
    return "${(distanceInMeters / 1000).toStringAsFixed(1)} km";
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ActiveOrderBottomBar(),
          CartBar(),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _restaurantStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return _buildShimmerHeader();
          final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          final name = data["name"] ?? widget.restaurantName ?? "Unnamed Restaurant";
          // Updated to handle common field name variations to ensure image displays
          final image = (data["imageUrl"] ?? data["imageURL"] ?? "").toString();
          final rating = data["rating"]?.toString() ?? "0.0";
          final cuisine = data["cuisine"] ?? "";
          final lat = parseDouble(data['latitude']);
          final lon = parseDouble(data['longitude']);
          _isRestaurantOpen = (data['status'] ?? 'open') == 'open';

          return NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                elevation: 0,
                backgroundColor: const Color(0xFF1A1E43),
                flexibleSpace: FlexibleSpaceBar(
                  background: ColorFiltered(
                    colorFilter: _isRestaurantOpen 
                        ? const ColorFilter.mode(Colors.transparent, BlendMode.multiply)
                        : const ColorFilter.mode(Colors.grey, BlendMode.saturation),
                    child: (image.isNotEmpty && image.startsWith('http')) 
                        ? CachedNetworkImage(
                            imageUrl: image, 
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Shimmer.fromColors(
                                baseColor: Colors.grey.shade300,
                                highlightColor: Colors.grey.shade100,
                                child: Container(color: Colors.white),
                            ),
                            errorWidget: (context, url, error) => const Icon(Icons.broken_image, size: 50, color: Colors.white),
                          )
                        : Container(
                            color: Colors.grey[300], 
                            child: const Center(child: Icon(Icons.restaurant, size: 50, color: Colors.white))
                          ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 16, color: Colors.grey),
                          Text(" ${_getDistance(lat, lon)} from you", style: const TextStyle(color: Colors.grey)),
                          const SizedBox(width: 15),
                          const Icon(Icons.star, size: 16, color: Colors.orange),
                          Text(" $rating", style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(cuisine, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                      const Divider(height: 30),
                    ],
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverAppBarDelegate(
                  TabBar(
                    controller: _tabController,
                    labelColor: Colors.black,
                    indicatorColor: const Color(0xFF1A1E43),
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                    tabs: const [
                      Tab(text: "All Items"),
                      Tab(text: "Offers"),
                      Tab(text: "Categories"),
                    ],
                  ),
                ),
              ),
            ],
            body: _isRestaurantOpen 
              ? TabBarView(
                  controller: _tabController,
                  children: [
                    _buildFilteredMenuTab(),
                    _buildOffersList(_allMenuItems, "bigdeal"),
                    _buildCategoryTab(),
                  ],
                )
              : _buildClosedOverlayMessage(),
          );
        },
      ),
    );
  }

  Widget _buildCategoryTab() {
    final List<String> categories = ["Arabian", "Indian", "Biriyani", "Shawarma", "Burger", "Parotta", "Cakes", "Dosa", "Momos", "Shake", "Icecream", "Juice", "Chinese"];
    final Map<String, List<QueryDocumentSnapshot>> grouped = {};
    for (var doc in _allMenuItems) {
      final itemData = doc.data() as Map<String, dynamic>;
      final itemTags = List<String>.from(itemData["tags"] ?? []);
      for (var cat in categories) {
        if (itemTags.contains(cat.toLowerCase())) {
          grouped.putIfAbsent(cat, () => []).add(doc);
        }
      }
    }

    if (grouped.isEmpty) return _buildEmptyState("No categories found.");

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: grouped.keys.length,
      itemBuilder: (context, index) {
        final categoryName = grouped.keys.elementAt(index);
        final categoryItems = grouped[categoryName]!;
        return ExpansionTile(
          initiallyExpanded: index == 0,
          title: Text(categoryName, style: const TextStyle(fontWeight: FontWeight.bold)),
          children: categoryItems.map((doc) {
            return Selector<CartProvider, int>(
              selector: (_, cart) => cart.getQuantity(doc.id),
              builder: (context, qty, _) => _buildMenuItemCard(context, doc.id, doc.data() as Map<String, dynamic>, qty, isCategoryItem: true),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildMenuItemCard(BuildContext context, String itemId, Map<String, dynamic> item, int qty, {bool isCategoryItem = false}) {
    final imageUrl = item["imageUrl"] ?? "";
    final isVeg = item['isVeg'] == true;
    final name = item["name"] ?? "Unnamed Item";
    final price = parseDouble(item["price"]);
    final stock = parseInt(item["stock"], defaultValue: 0); 
    final isOutOfStock = stock <= 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F1F1)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(isVeg ? Icons.eco : Icons.set_meal, color: isVeg ? Colors.green : Colors.red, size: 16),
                const SizedBox(height: 4),
                Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isOutOfStock ? Colors.grey : Colors.black)),
                const SizedBox(height: 4),
                Text("₹${price.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ColorFiltered(
                  colorFilter: isOutOfStock ? const ColorFilter.mode(Colors.grey, BlendMode.saturation) : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl, 
                    height: 90, 
                    width: 90, 
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Shimmer.fromColors(
                        baseColor: Colors.grey.shade300,
                        highlightColor: Colors.grey.shade100,
                        child: Container(color: Colors.white, height: 90, width: 90),
                    ),
                    errorWidget: (context, url, error) => const Icon(Icons.fastfood, size: 40, color: Colors.grey)
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (isOutOfStock)
                const Text("Sold Out", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
              else
                _buildCartButton(itemId, name, price, widget.restaurantId, imageUrl, qty, stock),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildCartButton(String itemId, String name, double price, String restaurantId, String? imageUrl, int qty, int stock) {
    final cart = Provider.of<CartProvider>(context, listen: false);
    if (qty > 0) {
      return Container(
        height: 36, width: 100,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            InkWell(onTap: () => cart.reduceQuantity(itemId), child: const Icon(Icons.remove, size: 18, color: Colors.orange)),
            Text(qty.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
            InkWell(onTap: () {
              if (qty + 1 > stock) return;
              cart.addItem(id: itemId, name: name, price: price, restaurantId: restaurantId, image: imageUrl, qty: 1);
            }, child: const Icon(Icons.add, size: 18, color: Colors.orange)),
          ],
        ),
      );
    } else {
      return ElevatedButton(
        onPressed: () => cart.addItem(id: itemId, name: name, price: price, restaurantId: restaurantId, image: imageUrl, qty: 1),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, minimumSize: const Size(100, 36), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        child: const Text("ADD"),
      );
    }
  }

  Widget _buildClosedOverlayMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.store_mall_directory_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text("Restaurant is Closed", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black)),
          const SizedBox(height: 8),
          const Text("We are not accepting orders right now.", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(child: Text(message, style: const TextStyle(color: Colors.grey)));
  }

  Widget _buildShimmerHeader() {
    return const Center(child: CircularProgressIndicator(color: Colors.orange));
  }

  Widget _buildFilteredMenuTab() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: _processedMenuItems.length,
      itemBuilder: (context, index) {
        final doc = _processedMenuItems[index];
        return Selector<CartProvider, int>(
          selector: (_, cart) => cart.getQuantity(doc.id),
          builder: (context, qty, _) => _buildMenuItemCard(context, doc.id, doc.data() as Map<String, dynamic>, qty),
        );
      },
    );
  }

  Widget _buildOffersList(List<QueryDocumentSnapshot> allItems, String offerTag) {
    final offerItems = allItems.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final tags = List<String>.from(data["tags"] ?? const []);
      return tags.contains(offerTag);
    }).toList();
    if (offerItems.isEmpty) return _buildEmptyState("No offers available.");
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: offerItems.length,
      itemBuilder: (context, index) {
        final doc = offerItems[index];
        return Selector<CartProvider, int>(
          selector: (_, cart) => cart.getQuantity(doc.id),
          builder: (context, qty, _) => _buildMenuItemCard(context, doc.id, doc.data() as Map<String, dynamic>, qty),
        );
      },
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);
  final TabBar _tabBar;
  @override double get minExtent => _tabBar.preferredSize.height;
  @override double get maxExtent => _tabBar.preferredSize.height;
  @override Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: Colors.white, child: _tabBar);
  }
  @override bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}