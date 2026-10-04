import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';

import 'cake_cart_screen.dart'; // Navigates to your standalone cart file

// ============================================================================
// APP COLORS & UTILITIES
// ============================================================================

class AppColors {
  static const Color primary = Color(0xFF111827);
  static const Color accent = Color(0xFFFF4D6D);
  static const Color background = Color(0xFFF7F8FA);
  static const Color surface = Colors.white;
  static const Color textDark = Color(0xFF1F2937);
  static const Color textLight = Color(0xFF6B7280);
  static const Color green = Color(0xFF16A34A);
  static const Color orange = Color(0xFFF59E0B);
  static const Color descRed = Color(0xFFDC2626); // Clean red for item descriptions
}

double parseDouble(dynamic value, {double defaultValue = 0}) {
  if (value == null) return defaultValue;
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.replaceAll(',', '').trim()) ?? defaultValue;
  }
  return defaultValue;
}

int parseInt(dynamic value, {int defaultValue = 0}) {
  if (value == null) return defaultValue;
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value.trim()) ?? defaultValue;
  }
  return defaultValue;
}

String capitalize(String text) {
  if (text.isEmpty) return text;
  return text
      .split(' ')
      .map((word) => word.isNotEmpty
          ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
          : '')
      .join(' ');
}

// ============================================================================
// EXPANDABLE DESCRIPTION WIDGET
// ============================================================================

class ExpandableDescriptionText extends StatefulWidget {
  final String text;

  const ExpandableDescriptionText({super.key, required this.text});

  @override
  State<ExpandableDescriptionText> createState() => _ExpandableDescriptionTextState();
}

class _ExpandableDescriptionTextState extends State<ExpandableDescriptionText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textSpan = TextSpan(
          text: widget.text,
          style: const TextStyle(
            color: AppColors.descRed,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            height: 1.35,
            letterSpacing: 0.1,
          ),
        );

        final textPainter = TextPainter(
          text: textSpan,
          maxLines: 2,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);

        final isOverflowing = textPainter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              maxLines: _isExpanded ? null : 2,
              overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.descRed,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.35,
                letterSpacing: 0.1,
              ),
            ),
            if (isOverflowing) ...[
              const SizedBox(height: 2),
              GestureDetector(
                onTap: () => setState(() => _isExpanded = !_isExpanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    _isExpanded ? 'View less ▲' : 'View more ▼',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
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

// ============================================================================
// CART ITEM MODEL
// ============================================================================

class CartItem {
  final String id;
  final String name;
  final String? description;
  final double price;
  final double mrp;
  final String imageUrl;
  final String shopId;
  final String shopName;
  final String category;
  final int stock;
  final String preparationTime;
  int quantity;

  CartItem({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    required this.mrp,
    required this.imageUrl,
    required this.shopId,
    required this.shopName,
    required this.category,
    required this.stock,
    required this.preparationTime,
    this.quantity = 1,
  });
}

// ============================================================================
// CAKE MENU ITEM MODEL
// ============================================================================

class CakeMenuItem {
  final String id;
  final String shopId;
  final String shopName;
  final String centreId;
  final String name;
  final String? description;
  final String category;
  final String imageUrl;
  final double price;
  final double mrp;
  final int stock;
  final String preparationTime;
  final bool available;
  final List<String> tags;

  CakeMenuItem({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.centreId,
    required this.name,
    this.description,
    required this.category,
    required this.imageUrl,
    required this.price,
    required this.mrp,
    required this.stock,
    required this.preparationTime,
    required this.available,
    required this.tags,
  });

  factory CakeMenuItem.fromDocument(
    DocumentSnapshot doc, {
    required String shopId,
    required String shopName,
    required String centreId,
  }) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final rawTags = data['tags'];
    List<String> parsedTags = [];

    if (rawTags is List) {
      parsedTags = rawTags
          .map((e) => e.toString().trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toList();
    } else if (rawTags is String) {
      parsedTags = rawTags
          .split(',')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    final rawDesc = data['description']?.toString().trim();

    return CakeMenuItem(
      id: doc.id,
      shopId: shopId,
      shopName: shopName,
      centreId: centreId,
      name: data['name']?.toString() ?? '',
      description: (rawDesc != null && rawDesc.isNotEmpty) ? rawDesc : null,
      category: data['category']?.toString() ?? '',
      imageUrl: data['imageUrl']?.toString() ?? '',
      price: parseDouble(data['price']),
      mrp: parseDouble(data['mrp']),
      stock: parseInt(data['stock']),
      preparationTime: data['preparationTime']?.toString() ?? '2 Hours',
      available: data['available'] is bool ? data['available'] : true,
      tags: parsedTags,
    );
  }
}

// ============================================================================
// CAKE SCREEN
// ============================================================================

class CakeScreen extends StatefulWidget {
  const CakeScreen({super.key});

  @override
  State<CakeScreen> createState() => _CakeScreenState();
}

class _CakeScreenState extends State<CakeScreen> {
  final Map<String, CartItem> _cart = {};
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  String _selectedFilter = 'All';
  String _selectedCategory = 'All';
  bool _showSearchResults = false;
  String? _selectedShopId;
  String? _selectedShopName;

  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _determinePosition();
    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _showSearchResults = _searchController.text.trim().isNotEmpty;
        });
      }
    });
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    Position position = await Geolocator.getCurrentPosition();
    if (mounted) {
      setState(() {
        _currentPosition = position;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  int get _totalCartItems =>
      _cart.values.fold(0, (sum, item) => sum + item.quantity);

  double get _totalCartPrice =>
      _cart.values.fold(0, (sum, item) => sum + (item.price * item.quantity));

  int get _activeFilterCount {
    int count = 0;
    if (_selectedFilter != 'All') count++;
    if (_selectedCategory != 'All') count++;
    return count;
  }

  void _resetFilters() {
    setState(() {
      _selectedFilter = 'All';
      _selectedCategory = 'All';
    });
  }

  Future<void> _addItem(CakeMenuItem item) async {
    try {
      final shopDoc = await FirebaseFirestore.instance
          .collection('cakeshop')
          .doc(item.shopId)
          .get();

      bool isShopAvailable = false;
      if (shopDoc.exists) {
        final shopData = shopDoc.data() as Map<String, dynamic>? ?? {};
        isShopAvailable = shopData['isavailable'] == true;
      }

      if (!isShopAvailable) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  '🔴 Shop not available right now',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                ),
                SizedBox(height: 2),
                Text(
                  'This shop is currently not accepting orders. Please try again later.',
                  style: TextStyle(fontSize: 11),
                ),
              ],
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      setState(() {
        if (_cart.containsKey(item.id)) {
          if (_cart[item.id]!.quantity < item.stock) {
            _cart[item.id]!.quantity++;
          }
        } else {
          _cart[item.id] = CartItem(
            id: item.id,
            name: item.name,
            description: item.description,
            price: item.price,
            mrp: item.mrp,
            imageUrl: item.imageUrl,
            shopId: item.shopId,
            shopName: item.shopName,
            category: item.category,
            stock: item.stock,
            preparationTime: item.preparationTime,
            quantity: 1,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not verify shop status. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _changeQuantity(CakeMenuItem item, int delta) {
    if (!_cart.containsKey(item.id)) {
      if (delta > 0 && item.stock > 0) {
        _addItem(item);
      }
      return;
    }

    if (delta > 0) {
      _addItem(item);
      return;
    }

    setState(() {
      final cartItem = _cart[item.id]!;
      final newQuantity = cartItem.quantity + delta;

      if (newQuantity <= 0) {
        _cart.remove(item.id);
      } else {
        cartItem.quantity = newQuantity;
      }
    });
  }

  void _changeCartQuantity(String itemId, int delta) {
    setState(() {
      if (!_cart.containsKey(itemId)) return;
      final cartItem = _cart[itemId]!;
      final newQuantity = cartItem.quantity + delta;

      if (newQuantity <= 0) {
        _cart.remove(itemId);
      } else if (newQuantity <= cartItem.stock) {
        cartItem.quantity = newQuantity;
      }
    });
  }

  int _quantityFor(String id) => _cart[id]?.quantity ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: const Text(
          'Cakes & Treats 🎂',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _selectedShopId == null
          ? _buildMainCakePage()
          : _buildShopDetailPage(_selectedShopId!, _selectedShopName!),
      bottomNavigationBar:
          _totalCartItems > 0 ? _buildViewCartBar() : null,
    );
  }

  Widget _buildMainCakePage() {
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 30),
          children: [
            _buildSearchBar(),
            _buildNearbyCakeShops(),
            _buildAllCakeItems(),
          ],
        ),
        if (_showSearchResults) _buildSearchPredictionOverlay(),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search cakes, vanilla, chocolate...',
            hintStyle: const TextStyle(
              color: AppColors.textLight,
              fontSize: 13,
            ),
            prefixIcon:
                const Icon(Icons.search_rounded, color: AppColors.primary),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      _searchFocusNode.unfocus();
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchPredictionOverlay() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return const SizedBox.shrink();

    return Positioned(
      left: 16,
      right: 16,
      top: 70,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(14),
        color: AppColors.surface,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 350),
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collectionGroup('menu')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  ),
                );
              }

              final results = <CakeMenuItem>[];

              for (final doc in snapshot.data!.docs) {
                final parent = doc.reference.parent.parent;
                if (parent == null) continue;

                if (parent.parent.id != 'cakeshop') continue;

                final data = doc.data() as Map<String, dynamic>? ?? {};
                final shopName = data['shopName']?.toString() ?? 'Cake Shop';

                final item = CakeMenuItem.fromDocument(
                  doc,
                  shopId: parent.id,
                  shopName: shopName,
                  centreId: data['centre_id']?.toString() ?? parent.id,
                );

                if (item.name.toLowerCase().contains(query) ||
                    item.category.toLowerCase().contains(query) ||
                    (item.description != null &&
                        item.description!.toLowerCase().contains(query))) {
                  results.add(item);
                }
              }

              if (results.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No cakes found.',
                    style: TextStyle(color: AppColors.textLight, fontSize: 13),
                  ),
                );
              }

              final limited = results.take(10).toList();

              return ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: limited.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = limited[index];
                  return ListTile(
                    dense: true,
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: item.imageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: item.imageUrl,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 40,
                              height: 40,
                              color: AppColors.background,
                              child: const Icon(Icons.cake_rounded,
                                  size: 20, color: AppColors.accent),
                            ),
                    ),
                    title: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.primary,
                      ),
                    ),
                    subtitle: Text(
                      item.shopName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textLight,
                      ),
                    ),
                    trailing: Text(
                      '₹${item.price.toInt()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent,
                        fontSize: 13,
                      ),
                    ),
                    onTap: () {
                      _searchController.text = item.name;
                      setState(() => _showSearchResults = false);
                      _searchFocusNode.unfocus();
                      _showSearchItemModal(item);
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showSearchItemModal(CakeMenuItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              const SizedBox(height: 16),
              _buildCakeItemCard(item),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNearbyCakeShops() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('cakeshop').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const SizedBox.shrink();
          }

          final shops = snapshot.data!.docs;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Row(
                  children: const [
                    Icon(Icons.storefront_rounded,
                        color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Nearby Cake Shops',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                    Spacer(),
                    Row(
                      children: [
                        Text(
                          'Swipe left',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textLight,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded,
                            size: 12, color: AppColors.textLight),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 195,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: shops.length,
                  itemBuilder: (context, index) {
                    final doc = shops[index];
                    final data = doc.data() as Map<String, dynamic>? ?? {};
                    final shopName = data['name']?.toString() ?? 'Cake Shop';
                    final location = data['location']?.toString() ?? '';
                    final imageUrl = data['image']?.toString() ?? '';

                    final bool isShopAvailable = data['isavailable'] == true;

                    String distanceStr = '';
                    final latStr = data['latitude']?.toString();
                    final lonStr = data['longitude']?.toString();

                    if (_currentPosition != null &&
                        latStr != null &&
                        lonStr != null) {
                      final shopLat = double.tryParse(latStr) ?? 0.0;
                      final shopLon = double.tryParse(lonStr) ?? 0.0;
                      if (shopLat != 0.0 && shopLon != 0.0) {
                        final distanceInMeters = Geolocator.distanceBetween(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude,
                          shopLat,
                          shopLon,
                        );
                        if (distanceInMeters >= 1000) {
                          distanceStr =
                              '${(distanceInMeters / 1000).toStringAsFixed(1)} km';
                        } else {
                          distanceStr = '${distanceInMeters.toInt()} m';
                        }
                      }
                    }

                    return GestureDetector(
                      onTap: isShopAvailable
                          ? () {
                              setState(() {
                                _selectedShopId = doc.id;
                                _selectedShopName = shopName;
                                _selectedCategory = 'All';
                                _selectedFilter = 'All';
                              });
                            }
                          : null,
                      child: Container(
                        width: 260,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Stack(
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      height: 140,
                                      color: const Color(0xFFF1F3F5),
                                      child: imageUrl.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: imageUrl,
                                              width: double.infinity,
                                              height: 140,
                                              fit: BoxFit.contain,
                                              errorWidget: (_, __, ___) =>
                                                  Container(
                                                width: double.infinity,
                                                height: 140,
                                                color: AppColors.background,
                                                child: const Icon(
                                                    Icons.storefront,
                                                    size: 40,
                                                    color: AppColors.accent),
                                              ),
                                            )
                                          : const Center(
                                              child: Icon(
                                                Icons.storefront,
                                                size: 40,
                                                color: AppColors.accent,
                                              ),
                                            ),
                                    ),
                                    if (distanceStr.isNotEmpty)
                                      Positioned(
                                        right: 8,
                                        top: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color:
                                                Colors.black.withOpacity(0.7),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                  Icons.navigation_rounded,
                                                  size: 10,
                                                  color: Colors.white),
                                              const SizedBox(width: 3),
                                              Text(
                                                distanceStr,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        shopName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w900,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                      if (location.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            const Icon(
                                                Icons.location_on_outlined,
                                                size: 11,
                                                color: AppColors.textLight),
                                            const SizedBox(width: 2),
                                            Expanded(
                                              child: Text(
                                                location,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: AppColors.textLight,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (!isShopAvailable)
                              Positioned.fill(
                                child: Container(
                                  color: Colors.black.withOpacity(0.6),
                                  alignment: Alignment.center,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  child: const Text(
                                    "Currently we are not delivering",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ==========================================================================
  // FILTERS & CAKE ITEMS
  // ==========================================================================

  Widget _buildAllCakeItems() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collectionGroup('menu').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
                child: CircularProgressIndicator(color: AppColors.accent)),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(30),
            child: Center(
                child: Text('No cakes available right now.',
                    style: TextStyle(color: AppColors.textLight))),
          );
        }

        final allItems = <CakeMenuItem>[];
        final Set<String> categories = {'All'};

        for (final doc in snapshot.data!.docs) {
          final parent = doc.reference.parent.parent;
          if (parent == null) continue;
          if (parent.parent.id != 'cakeshop') continue;

          final data = doc.data() as Map<String, dynamic>? ?? {};
          final shopName = data['shopName']?.toString() ?? 'Cake Shop';
          final centreId = data['centre_id']?.toString() ?? parent.id;

          final item = CakeMenuItem.fromDocument(
            doc,
            shopId: parent.id,
            shopName: shopName,
            centreId: centreId,
          );

          allItems.add(item);
          if (item.category.trim().isNotEmpty) {
            categories.add(item.category.trim());
          }
        }

        final filteredItems =
            allItems.where((item) => _passesFilters(item)).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFilterHeader(filteredItems.length, categories.toList()),
            if (filteredItems.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.cake_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text(
                        'No cakes match your filters.',
                        style: TextStyle(
                          color: AppColors.textDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: _resetFilters,
                        child: const Text('Reset all filters',
                            style: TextStyle(
                                color: AppColors.accent, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: filteredItems.length,
                itemBuilder: (context, index) =>
                    _buildCakeItemCard(filteredItems[index]),
              ),
          ],
        );
      },
    );
  }

  Widget _buildFilterHeader(int itemCount, List<String> availableCategories) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Browse Cakes',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$itemCount cake${itemCount == 1 ? '' : 's'} available',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textLight,
                    ),
                  ),
                ],
              ),
              if (_activeFilterCount > 0)
                TextButton(
                  onPressed: _resetFilters,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.accent,
                  ),
                  child: const Text(
                    'Reset',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildFilterActionButton(
                icon: Icons.tune_rounded,
                label: 'Filters',
                count: _activeFilterCount,
                isSelected: _activeFilterCount > 0,
                onTap: () => _showCategoryBottomSheet(availableCategories),
              ),
              const SizedBox(width: 8),
              _buildCategoryDropdownButton(availableCategories),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Quick filters',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textLight,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildQuickFilterChip(
                  label: 'All',
                  isSelected: _selectedFilter == 'All',
                  onTap: () => setState(() => _selectedFilter = 'All'),
                ),
                _buildQuickFilterChip(
                  label: 'Available',
                  isSelected: _selectedFilter == 'Available',
                  onTap: () => setState(() => _selectedFilter = 'Available'),
                ),
                _buildQuickFilterChip(
                  label: 'Offers',
                  isSelected: _selectedFilter == 'Best Offers',
                  onTap: () => setState(() => _selectedFilter = 'Best Offers'),
                ),
                _buildQuickFilterChip(
                  label: 'Deals',
                  isSelected: _selectedFilter == 'Best Deals',
                  onTap: () => setState(() => _selectedFilter = 'Best Deals'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterActionButton({
    required IconData icon,
    required String label,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.black.withOpacity(0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : AppColors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : AppColors.primary,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryDropdownButton(List<String> categories) {
    final isFiltered = _selectedCategory != 'All';
    final labelText = isFiltered ? capitalize(_selectedCategory) : 'Category';

    return InkWell(
      onTap: () => _showCategoryBottomSheet(categories),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isFiltered ? AppColors.accent.withOpacity(0.08) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isFiltered ? AppColors.accent : Colors.black.withOpacity(0.08),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              labelText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: isFiltered ? AppColors.accent : AppColors.primary,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: isFiltered ? AppColors.accent : AppColors.textLight,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.primary : Colors.black.withOpacity(0.06),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : AppColors.textDark,
            ),
          ),
        ),
      ),
    );
  }

  void _showCategoryBottomSheet(List<String> categories) {
    String tempSelected = _selectedCategory;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Categories',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                          ),
                        ),
                        if (tempSelected != 'All')
                          GestureDetector(
                            onTap: () => setModalState(() => tempSelected = 'All'),
                            child: const Text(
                              'Clear',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        final cat = categories[index];
                        final isChosen = tempSelected.toLowerCase() == cat.toLowerCase();
                        final displayName = cat == 'All' ? 'All Cakes' : capitalize(cat);

                        return ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          leading: Icon(
                            isChosen
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 20,
                            color: isChosen ? AppColors.accent : Colors.grey.shade400,
                          ),
                          title: Text(
                            displayName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isChosen ? FontWeight.w800 : FontWeight.w600,
                              color: isChosen ? AppColors.primary : AppColors.textDark,
                            ),
                          ),
                          onTap: () => setModalState(() => tempSelected = cat),
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _selectedCategory = tempSelected;
                            });
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Apply',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================================================
  // FILTER LOGIC
  // ==========================================================================

  bool _passesFilters(CakeMenuItem item) {
    if (_selectedFilter == 'Best Deals') {
      if (!_hasTag(item, ['bestdeal', 'best_deal', 'deal'])) return false;
    } else if (_selectedFilter == 'Best Offers') {
      if (!_hasTag(item, ['bestoffer', 'best_offer', 'offer'])) return false;
    } else if (_selectedFilter == 'Available') {
      if (!item.available || item.stock <= 0) return false;
    }

    if (_selectedFilter == 'All') {
      if (!item.available || item.stock <= 0) return false;
    }

    if (_selectedCategory != 'All') {
      if (item.category.trim().toLowerCase() != _selectedCategory.trim().toLowerCase()) {
        return false;
      }
    }

    return true;
  }

  bool _hasTag(CakeMenuItem item, List<String> wanted) {
    return item.tags.any((tag) => wanted.contains(tag.toLowerCase()));
  }

  // ==========================================================================
  // CAKE CARD & DETAIL UI
  // ==========================================================================

  Widget _buildCakeItemCard(CakeMenuItem item) {
    final quantity = _quantityFor(item.id);
    final hasDiscount = item.mrp > item.price && item.mrp > 0;
    final hasDescription = item.description != null && item.description!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: item.imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: item.imageUrl,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _cakePlaceholder(),
                    )
                  : _cakePlaceholder(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (item.category.isNotEmpty)
                        Text(
                          capitalize(item.category),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      if (item.preparationTime.isNotEmpty)
                        Row(
                          children: [
                            const Icon(Icons.access_time_rounded,
                                size: 10, color: AppColors.textLight),
                            const SizedBox(width: 3),
                            Text(
                              item.preparationTime,
                              style: const TextStyle(
                                color: AppColors.textLight,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.name.isEmpty ? 'Cake' : item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),

                  // Expandable Red Description Block
                  if (hasDescription) ...[
                    const SizedBox(height: 4),
                    ExpandableDescriptionText(text: item.description!),
                  ],

                  const SizedBox(height: 4),
                  if (item.shopName.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.storefront_outlined,
                            size: 12, color: AppColors.textLight),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item.shopName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textLight,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '₹${item.price.toInt()}',
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (hasDiscount) ...[
                        const SizedBox(width: 6),
                        Text(
                          '₹${item.mrp.toInt()}',
                          style: const TextStyle(
                            color: AppColors.textLight,
                            fontSize: 11,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: item.stock <= 0 || !item.available
                        ? const Text('Out of Stock',
                            style: TextStyle(
                                color: Colors.red,
                                fontSize: 10,
                                fontWeight: FontWeight.w800))
                        : quantity == 0
                            ? _addButton(item)
                            : _quantitySelector(item),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cakePlaceholder() {
    return Container(
      width: 90,
      height: 90,
      color: AppColors.background,
      child: const Icon(Icons.cake_rounded, color: AppColors.accent, size: 30),
    );
  }

  Widget _addButton(CakeMenuItem item) {
    return SizedBox(
      height: 34,
      child: ElevatedButton(
        onPressed: () => _addItem(item),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: const Text('ADD',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget _quantitySelector(CakeMenuItem item) {
    final quantity = _quantityFor(item.id);
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 34),
            onPressed: () => _changeQuantity(item, -1),
            icon: const Icon(Icons.remove, color: Colors.white, size: 14),
          ),
          Text('$quantity',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12)),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 34),
            onPressed: quantity < item.stock
                ? () => _changeQuantity(item, 1)
                : null,
            icon: Icon(Icons.add,
                color: quantity < item.stock ? Colors.white : Colors.white38,
                size: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildShopDetailPage(String shopId, String shopName) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cakeshop')
          .doc(shopId)
          .snapshots(),
      builder: (context, shopSnapshot) {
        bool isShopAvailable = true;
        if (shopSnapshot.hasData && shopSnapshot.data!.exists) {
          final shopData =
              shopSnapshot.data!.data() as Map<String, dynamic>? ?? {};
          isShopAvailable = shopData['isavailable'] == true;
        }

        return Column(
          children: [
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => setState(() {
                      _selectedShopId = null;
                      _selectedShopName = null;
                    }),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Text(
                      shopName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!isShopAvailable)
              Container(
                width: double.infinity,
                color: Colors.red.shade700,
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: const Text(
                  "Shop not available right now\nThis shop is currently not accepting orders.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('cakeshop')
                    .doc(shopId)
                    .collection('menu')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child:
                            CircularProgressIndicator(color: AppColors.accent));
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(
                        child: Text('No cakes available in this shop.',
                            style: TextStyle(color: AppColors.textLight)));
                  }

                  final items = snapshot.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>? ?? {};
                    return CakeMenuItem.fromDocument(
                      doc,
                      shopId: shopId,
                      shopName: shopName,
                      centreId: data['centre_id']?.toString() ?? shopId,
                    );
                  }).toList();

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: items.map((item) {
                      return Opacity(
                        opacity: isShopAvailable ? 1.0 : 0.5,
                        child: _buildCakeItemCard(item),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildViewCartBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.primary,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_totalCartItems item${_totalCartItems == 1 ? '' : 's'} added',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '₹${_totalCartPrice.toInt()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CakeCartScreen(
                      cartItems: _cart,
                      onUpdateQuantity: _changeCartQuantity,
                      userPosition: _currentPosition,
                    ),
                  ),
                ).then((_) => setState(() {}));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('View Cart & Continue →',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}