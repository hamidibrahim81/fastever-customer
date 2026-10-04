import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:async';

// ✅ IMPORT AUTH GUARD
import 'package:fastevergo_v1/utils/auth_guards.dart';

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
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        _hasMoreItems &&
        !_isLoadingMore) {
      _loadMoreMenuData();
    }
  }

  void _applyFiltersAndSort() {
    List<QueryDocumentSnapshot> tempItems = List.from(_allMenuItems);

    if (_filterType == "veg") {
      tempItems = tempItems
          .where(
            (doc) => (doc.data() as Map<String, dynamic>)["isVeg"] == true,
          )
          .toList();
    } else if (_filterType == "non-veg") {
      tempItems = tempItems
          .where(
            (doc) => (doc.data() as Map<String, dynamic>)["isVeg"] == false,
          )
          .toList();
    }

    if (_sortBy != null) {
      switch (_sortBy) {
        case "price_asc":
          tempItems.sort(
            (a, b) => parseDouble(
              (a.data() as Map<String, dynamic>)["price"],
            ).compareTo(
              parseDouble((b.data() as Map<String, dynamic>)["price"]),
            ),
          );
          break;
        case "price_desc":
          tempItems.sort(
            (a, b) => parseDouble(
              (b.data() as Map<String, dynamic>)["price"],
            ).compareTo(
              parseDouble((a.data() as Map<String, dynamic>)["price"]),
            ),
          );
          break;
        case "popularity":
          tempItems.sort(
            (a, b) => parseNum(
              (b.data() as Map<String, dynamic>)["popularity"],
            ).compareTo(
              parseNum((a.data() as Map<String, dynamic>)["popularity"]),
            ),
          );
          break;
        case "rating":
          tempItems.sort(
            (a, b) => parseNum(
              (b.data() as Map<String, dynamic>)["rating"],
            ).compareTo(parseNum((a.data() as Map<String, dynamic>)["rating"])),
          );
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
          final name =
              data["name"] ?? widget.restaurantName ?? "Unnamed Restaurant";
          final image =
              (data["imageUrl"] ?? data["imageURL"] ?? "").toString();
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
                        ? const ColorFilter.mode(
                            Colors.transparent,
                            BlendMode.multiply,
                          )
                        : const ColorFilter.mode(
                            Colors.grey,
                            BlendMode.saturation,
                          ),
                    child: (image.isNotEmpty && image.startsWith('http'))
                        ? CachedNetworkImage(
                            imageUrl: image,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Shimmer.fromColors(
                              baseColor: Colors.grey.shade300,
                              highlightColor: Colors.grey.shade100,
                              child: Container(color: Colors.white),
                            ),
                            errorWidget: (context, url, error) => const Icon(
                              Icons.broken_image,
                              size: 50,
                              color: Colors.white,
                            ),
                          )
                        : Container(
                            color: Colors.grey[300],
                            child: const Center(
                              child: Icon(
                                Icons.restaurant,
                                size: 50,
                                color: Colors.white,
                              ),
                            ),
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
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1E43),
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 16,
                            color: Colors.grey,
                          ),
                          Text(
                            " ${_getDistance(lat, lon)} from you",
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text("•", style: TextStyle(color: Colors.grey)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5E9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  size: 14,
                                  color: Color(0xFF2E7D32),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  " $rating",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2E7D32),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        cuisine,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Divider(height: 30, color: Color(0xFFEEEEEE)),
                    ],
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverAppBarDelegate(
                  TabBar(
                    controller: _tabController,
                    labelColor: const Color(0xFF1A1E43),
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: const Color(0xFF1A1E43),
                    indicatorWeight: 3,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
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
    final List<String> categories = [
      "Arabian",
      "Indian",
      "Biriyani",
      "Shawarma",
      "Snacks",
      "Burger",
      "Parotta",
      "Fried Chicken",
      "Tea & Coffee",
      "Grills",
      "Desserts",
      "Cakes",
      "Dosa",
      "Momos",
      "Shake",
      "Icecream",
      "Juice",
      "Chinese",
    ];
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
        return Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: index == 0,
            title: Text(
              categoryName,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: Color(0xFF1A1E43),
              ),
            ),
            children: categoryItems.map((doc) {
              return Selector<CartProvider, int>(
                selector: (_, cart) => cart.getQuantity(doc.id),
                builder: (context, qty, _) => _buildMenuItemCard(
                  context,
                  doc.id,
                  doc.data() as Map<String, dynamic>,
                  qty,
                  isCategoryItem: true,
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildMenuItemCard(
    BuildContext context,
    String itemId,
    Map<String, dynamic> item,
    int qty, {
    bool isCategoryItem = false,
  }) {
    final imageUrl = item["imageUrl"] ?? "";
    final isVeg = item['isVeg'] == true;
    final name = item["name"] ?? "Unnamed Item";
    final price = parseDouble(item["price"]);
    final stock = parseInt(item["stock"], defaultValue: 0);
    final isOutOfStock = stock <= 0;
    final String? description = item['description']?.toString();

    return Container(
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
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isVeg ? Colors.green : Colors.red,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    isVeg ? Icons.circle : Icons.circle,
                    color: isVeg ? Colors.green : Colors.red,
                    size: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isOutOfStock ? Colors.grey : const Color(0xFF1A1E43),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "₹${price.toStringAsFixed(0)}",
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Color(0xFF2E7D32),
                  ),
                ),

                // 🔴 OPTIONAL RED DESCRIPTION
                if (description != null && description.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _ExpandableItemDescription(
                    text: description.trim(),
                    itemName: name,
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
                    child: ColorFiltered(
                      colorFilter: isOutOfStock
                          ? const ColorFilter.mode(
                              Colors.grey,
                              BlendMode.saturation,
                            )
                          : const ColorFilter.mode(
                              Colors.transparent,
                              BlendMode.multiply,
                            ),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        height: 90,
                        width: 90,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Shimmer.fromColors(
                          baseColor: Colors.grey.shade200,
                          highlightColor: Colors.grey.shade50,
                          child: Container(
                            color: Colors.white,
                            height: 90,
                            width: 90,
                          ),
                        ),
                        errorWidget: (context, url, error) => const Icon(
                          Icons.fastfood,
                          size: 40,
                          color: Colors.grey,
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
              if (!isOutOfStock)
                _buildCartButton(
                  itemId,
                  name,
                  price,
                  widget.restaurantId,
                  imageUrl,
                  qty,
                  stock,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCartButton(
    String itemId,
    String name,
    double price,
    String restaurantId,
    String? imageUrl,
    int qty,
    int stock,
  ) {
    final cart = Provider.of<CartProvider>(context, listen: false);
    if (qty > 0) {
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
              onTap: () {
                if (!requireLoginGlobal("Please login to update cart")) return;
                cart.reduceQuantity(itemId);
              },
              child: const Icon(Icons.remove, size: 16, color: Colors.white),
            ),
            Text(
              qty.toString(),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontSize: 14,
              ),
            ),
            InkWell(
              onTap: () {
                if (!requireLoginGlobal("Please login to update cart")) return;
                if (qty + 1 > stock) return;
                cart.addItem(
                  id: itemId,
                  name: name,
                  price: price,
                  restaurantId: restaurantId,
                  image: imageUrl,
                  qty: 1,
                );
              },
              child: const Icon(Icons.add, size: 16, color: Colors.white),
            ),
          ],
        ),
      );
    } else {
      return SizedBox(
        height: 36,
        width: 100,
        child: ElevatedButton(
          onPressed: () {
            if (!requireLoginGlobal("Please login to add items to cart")) return;
            cart.addItem(
              id: itemId,
              name: name,
              price: price,
              restaurantId: restaurantId,
              image: imageUrl,
              qty: 1,
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1A1E43),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: EdgeInsets.zero,
          ),
          child: const Text(
            "ADD",
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.5,
            ),
          ),
        ),
      );
    }
  }

  Widget _buildClosedOverlayMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.store_mall_directory_outlined,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          const Text(
            "Restaurant is Closed",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "We are not accepting orders right now.",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Text(message, style: const TextStyle(color: Colors.grey)),
    );
  }

  Widget _buildShimmerHeader() {
    return const Center(
      child: CircularProgressIndicator(color: Color(0xFF1A1E43)),
    );
  }

  Widget _buildFilteredMenuTab() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100),
      itemCount: _processedMenuItems.length,
      itemBuilder: (context, index) {
        final doc = _processedMenuItems[index];
        return Selector<CartProvider, int>(
          selector: (_, cart) => cart.getQuantity(doc.id),
          builder: (context, qty, _) => _buildMenuItemCard(
            context,
            doc.id,
            doc.data() as Map<String, dynamic>,
            qty,
          ),
        );
      },
    );
  }

  Widget _buildOffersList(
    List<QueryDocumentSnapshot> allItems,
    String offerTag,
  ) {
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
          builder: (context, qty, _) => _buildMenuItemCard(
            context,
            doc.id,
            doc.data() as Map<String, dynamic>,
            qty,
          ),
        );
      },
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar);
  final TabBar _tabBar;
  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: Colors.white, child: _tabBar);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
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
              overflow:
                  _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
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