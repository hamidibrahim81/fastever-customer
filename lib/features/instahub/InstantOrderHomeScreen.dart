import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'package:fastevergo_v1/features/profile/profile_screen2.dart';
// ✅ IMPORT GLOBAL AUTH GUARD
import 'package:fastevergo_v1/utils/auth_guards.dart';
// ✅ IMPORT NOTIFICATION SCREEN FOR NAVIGATION
import 'package:fastevergo_v1/features/notification/NotificationScreen.dart';
// CORRECTED INSTAHUB IMPORTS
import 'instahub_cart_provider.dart';
import 'instahub_cart_bar.dart';
import 'package:fastevergo_v1/features/instahub/MorningOrderHomeScreen.dart';
import 'request/request_item_list_screen.dart';

class InstantOrderHomeScreen extends StatefulWidget {
  const InstantOrderHomeScreen({super.key});

  @override
  State<InstantOrderHomeScreen> createState() => _InstantOrderHomeScreenState();
}

class _InstantOrderHomeScreenState extends State<InstantOrderHomeScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  DateTime? _lastPressed;

  // Ads loop & soft transition controls
  int _currentAdIndex = 0;
  Timer? _adsTimer;

  // Selected filter: 'all', 'top_sell', 'best_offer', or a specific category tag
  String _selectedFilterTag = 'all';

  // Slate-navy top background container
  static const Color _headerBgColor = Color(0xFF0F172A);
  static const Color _accentColor = Color(0xFF00E676);
  static const Color _bgColor = Color(0xFFF8F9FD);

  final List<Map<String, dynamic>> categories = [
    {"name": "Fruits & Vegetables", "image": "assets/icons/fv.jpeg", "tag": "fv"},
    {"name": "Dairy & Eggs", "image": "assets/icons/de.jpeg", "tag": "de"},
    {"name": "Meat & seafood", "image": "assets/icons/ms.jpeg", "tag": "ms"},
    {"name": "Grocery & staples", "image": "assets/icons/gs.jpeg", "tag": "gs"},
    {"name": "Bakery & snacks", "image": "assets/icons/bs.jpeg", "tag": "bs"},
    {"name": "Beverages", "image": "assets/icons/b.jpeg", "tag": "b"},
    {"name": "Household Essentials", "image": "assets/icons/he.jpeg", "tag": "he"},
    {"name": "Baby & kids", "image": "assets/icons/bk.jpeg", "tag": "bk"},
    {"name": "Pet Care", "image": "assets/icons/pc.jpeg", "tag": "pc"},
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _adsTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() => _searchQuery = _searchController.text.trim());
  }

  void _handlePop(bool didPop, dynamic result) {
    if (didPop) return;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Press back again to return to home", style: GoogleFonts.inter()),
          backgroundColor: Colors.black,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      Future.microtask(() {
        if (!context.mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
      });
    }
  }

  Query<Map<String, dynamic>> _buildItemsQuery() {
    final collection = FirebaseFirestore.instance.collection("instaitems");
    if (_selectedFilterTag == 'all') {
      return collection.limit(50);
    } else if (_selectedFilterTag == 'best_offer') {
      return collection.where("tag", arrayContains: "best_offer");
    } else if (_selectedFilterTag == 'top_sell') {
      return collection.where("tag", arrayContains: "top_sell");
    } else {
      return collection.where("tag", arrayContains: _selectedFilterTag);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handlePop,
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: _bgColor,
          appBar: AppBar(
            title: Text(
              "INSTAHUB",
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                letterSpacing: 1.2,
              ),
            ),
            backgroundColor: _headerBgColor,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              onPressed: () {
                Future.microtask(() {
                  if (!context.mounted) return;
                  Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
                });
              },
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_rounded, size: 26),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationScreen()),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.person_outline_rounded, size: 28),
                onPressed: () {
                  if (!requireLoginGlobal("Please login to access profile")) return;
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen2()));
                },
              ),
            ],
          ),
          body: Stack(
            children: [
              SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    if (_searchQuery.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: _buildSearchBar(),
                      ),
                      _buildSearchResults(),
                    ] else ...[
                      _buildHeaderSection(),
                      const SizedBox(height: 16),
                      _buildFilterChips(),
                      const SizedBox(height: 16),
                      _buildUnifiedItemsGrid(),
                      Consumer<InstahubCartProvider>(
                        builder: (_, cart, __) => SizedBox(height: cart.isNotEmpty ? 120 : 60),
                      ),
                    ],
                  ],
                ),
              ),
              _buildFloatingCartBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: _headerBgColor,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: _buildSearchBar(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: _buildMorningBanner(),
          ),
          _buildFullWidthAdsRunner(),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 8),
            child: Text(
              "Shop by Category",
              style: GoogleFonts.montserrat(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              physics: const BouncingScrollPhysics(),
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 20),
              itemBuilder: (context, index) {
                final cat = categories[index];
                final bool isSelected = _selectedFilterTag == cat["tag"];
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedFilterTag = cat["tag"];
                    });
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 64,
                        width: 64,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(
                            color: isSelected ? Colors.orange : Colors.white24,
                            width: isSelected ? 3 : 2,
                          ),
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            cat["image"],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(Icons.shopping_bag_outlined, color: Colors.grey),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 75,
                        child: Text(
                          cat["name"],
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.montserrat(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: isSelected ? Colors.orange : Colors.white,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildFullWidthAdsRunner() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ads')
          .where('tag', isEqualTo: 'insta_ads')
          .where('active', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox.shrink();
        final adsDocs = snapshot.data!.docs;

        _adsTimer ??= Timer.periodic(const Duration(seconds: 4), (timer) {
          if (mounted && adsDocs.isNotEmpty) {
            setState(() {
              _currentAdIndex = (_currentAdIndex + 1) % adsDocs.length;
            });
          }
        });

        final adData = adsDocs[_currentAdIndex % adsDocs.length].data() as Map<String, dynamic>;

        return SizedBox(
          width: double.infinity,
          height: 165,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 750),
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            transitionBuilder: (child, animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: Container(
              key: ValueKey<int>(_currentAdIndex),
              width: double.infinity,
              height: 165,
              child: CachedNetworkImage(
                imageUrl: adData['imageUrl'] ?? '',
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(color: Colors.black12),
                errorWidget: (context, url, error) => Container(
                  color: Colors.black12,
                  child: const Icon(Icons.broken_image, color: Colors.white54),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChips() {
    final List<Map<String, String>> filters = [
      {"label": "✨ All Items", "tag": "all"},
      {"label": "⚡ Top Selling", "tag": "top_sell"},
      {"label": "💸 Best Offers", "tag": "best_offer"},
      ...categories.map((c) => {"label": c["name"].toString(), "tag": c["tag"].toString()}),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = _selectedFilterTag == filter["tag"];
          return ChoiceChip(
            label: Text(filter["label"]!),
            selected: isSelected,
            selectedColor: Colors.orange,
            backgroundColor: Colors.white,
            side: BorderSide(
              color: isSelected ? Colors.orange : Colors.grey.shade300,
            ),
            labelStyle: GoogleFonts.montserrat(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 12,
            ),
            onSelected: (selected) {
              if (selected) {
                setState(() => _selectedFilterTag = filter["tag"]!);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildUnifiedItemsGrid() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _buildItemsQuery().snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 250,
            child: Center(child: CircularProgressIndicator(color: Colors.orange)),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            height: 200,
            alignment: Alignment.center,
            child: Text(
              "No items found in this section",
              style: GoogleFonts.inter(color: Colors.grey, fontWeight: FontWeight.w600),
            ),
          );
        }

        final docs = snapshot.data!.docs;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: docs.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 0.65,
            ),
            itemBuilder: (context, index) {
              final doc = docs[index];
              return _HomeItemCard(
                item: {...doc.data(), 'id': doc.id},
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMorningBanner() {
    return Row(
      children: [
        _buildQuickActionCard(
          title: "Morning",
          subtitle: "Delivery",
          icon: Icons.wb_sunny_rounded,
          colors: [const Color(0xFFFF9100), const Color(0xFFFF3D00)],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MorningOrderHomeScreen()),
          ),
        ),
        const SizedBox(width: 16),
        _buildQuickActionCard(
          title: "Request",
          subtitle: "Any Item",
          icon: Icons.shopping_basket_rounded,
          colors: [const Color(0xFF00BFA5), const Color(0xFF00796B)],
          onTap: () {
            if (!requireLoginGlobal("Please login to request items")) return;
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RequestItemListScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildQuickActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 105,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: colors.first.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const Spacer(),
              Text(
                title,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.montserrat(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: "Search milk, bread, snacks...",
          hintStyle: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded, color: Colors.orange, size: 24),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("instaitems")
          .where('name', isGreaterThanOrEqualTo: _searchQuery)
          .where('name', isLessThanOrEqualTo: '$_searchQuery\uf8ff')
          .limit(15)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final item = docs[index].data() as Map<String, dynamic>;
            final rawMrp = item["price"] ?? item["mrp"] ?? 0;
            final rawOffer = item["offerPrice"] ?? item["offerSalePrice"] ?? item["price"] ?? 0;
            final double mrp = rawMrp is num ? rawMrp.toDouble() : double.tryParse(rawMrp.toString()) ?? 0.0;
            final double sellingPrice = rawOffer is num ? rawOffer.toDouble() : double.tryParse(rawOffer.toString()) ?? mrp;
            final bool hasDiscount = mrp > sellingPrice && sellingPrice > 0;

            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: item['image'] ?? item['remoteImageUrl'] ?? '',
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                ),
              ),
              title: Text(
                item['name'] ?? item['productName'] ?? '',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              subtitle: Row(
                children: [
                  Text(
                    "₹${sellingPrice.toInt()}",
                    style: GoogleFonts.inter(color: _accentColor, fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  if (hasDiscount) ...[
                    const SizedBox(width: 6),
                    Text(
                      "₹${mrp.toInt()}",
                      style: GoogleFonts.inter(
                        decoration: TextDecoration.lineThrough,
                        color: Colors.grey.shade500,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              trailing: SizedBox(
                width: 100,
                child: _SearchAddButton(item: {...item, 'id': docs[index].id}),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFloatingCartBar() {
    return Consumer<InstahubCartProvider>(
      builder: (context, cart, _) => AnimatedPositioned(
        duration: const Duration(milliseconds: 600),
        curve: Curves.elasticOut,
        bottom: cart.isNotEmpty ? 24 : -120,
        left: 16,
        right: 16,
        child: const InstahubCartBar(),
      ),
    );
  }
}

class _HomeItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isBigDeal;

  const _HomeItemCard({required this.item, this.isBigDeal = false});

  @override
  Widget build(BuildContext context) {
    // Handling MRP & Offer/Sale Price mapping correctly from schema
    final rawMrp = item["price"] ?? item["mrp"] ?? 0;
    final rawOffer = item["offerPrice"] ?? item["offerSalePrice"] ?? item["price"] ?? 0;

    final double mrp = rawMrp is num ? rawMrp.toDouble() : double.tryParse(rawMrp.toString()) ?? 0.0;
    final double sellingPrice = rawOffer is num ? rawOffer.toDouble() : double.tryParse(rawOffer.toString()) ?? mrp;

    final bool hasDiscount = mrp > sellingPrice && sellingPrice > 0;
    final int discountPercent = hasDiscount ? (((mrp - sellingPrice) / mrp) * 100).round() : 0;

    final stock = (item['stock'] ?? item['stockLevels'] as num?)?.toInt() ?? 0;
    final String itemId = item['id'] ?? item['name'] ?? 'item';

    return Consumer<InstahubCartProvider>(
      builder: (context, cart, _) {
        final quantity = cart.getItem(itemId)?.quantity ?? 0;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F7F9),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Hero(
                          tag: "item_$itemId",
                          child: CachedNetworkImage(
                            imageUrl: item['image'] ?? item['remoteImageUrl'] ?? '',
                            fit: BoxFit.contain,
                            width: 90,
                            height: 90,
                            errorWidget: (context, url, error) => const Icon(
                              Icons.image_not_supported_outlined,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (hasDiscount)
                      Positioned(
                        top: 14,
                        left: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            "$discountPercent% OFF",
                            style: GoogleFonts.montserrat(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['name'] ?? item['productName'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          "₹${sellingPrice.toInt()}",
                          style: GoogleFonts.montserrat(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: const Color(0xFF121212),
                          ),
                        ),
                        if (hasDiscount) ...[
                          const SizedBox(width: 6),
                          Text(
                            "₹${mrp.toInt()}",
                            style: GoogleFonts.inter(
                              decoration: TextDecoration.lineThrough,
                              fontSize: 11,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (stock > 0)
                      _JumboQuantitySelector(
                        quantity: quantity,
                        onAdd: () {
                          if (!requireLoginGlobal("Please login to add items")) return;
                          cart.updateItem(
                            id: itemId,
                            name: item['name'] ?? item['productName'],
                            price: sellingPrice,
                            restaurantId: "instahub_store",
                            image: item['image'] ?? item['remoteImageUrl'],
                            quantity: quantity + 1,
                          );
                        },
                        onRemove: () => cart.removeItem(itemId),
                        onUpdate: (newQty) {
                          if (newQty > quantity) {
                            if (!requireLoginGlobal("Please login to update items")) return;
                          }
                          cart.updateItem(
                            id: itemId,
                            name: item['name'] ?? item['productName'],
                            price: sellingPrice,
                            restaurantId: "instahub_store",
                            image: item['image'] ?? item['remoteImageUrl'],
                            quantity: newQty,
                          );
                        },
                      )
                    else
                      Container(
                        height: 40,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "OUT OF STOCK",
                          style: GoogleFonts.inter(
                            color: Colors.red,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _JumboQuantitySelector extends StatelessWidget {
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final Function(int) onUpdate;

  const _JumboQuantitySelector({
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: quantity == 0
          ? InkWell(
              key: const ValueKey('add_btn'),
              onTap: onAdd,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.orange, Color(0xFFFF8C00)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    "ADD",
                    style: GoogleFonts.montserrat(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            )
          : Container(
              key: const ValueKey('counter_btn'),
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => quantity > 1 ? onUpdate(quantity - 1) : onRemove(),
                      child: const Center(
                        child: Icon(Icons.remove_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                  Text(
                    '$quantity',
                    style: GoogleFonts.montserrat(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: onAdd,
                      child: const Center(
                        child: Icon(Icons.add_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SearchAddButton extends StatelessWidget {
  final Map<String, dynamic> item;

  const _SearchAddButton({required this.item});

  @override
  Widget build(BuildContext context) {
    final rawMrp = item["price"] ?? item["mrp"] ?? 0;
    final rawOffer = item["offerPrice"] ?? item["offerSalePrice"] ?? item["price"] ?? 0;
    final double mrp = rawMrp is num ? rawMrp.toDouble() : double.tryParse(rawMrp.toString()) ?? 0.0;
    final double sellingPrice = rawOffer is num ? rawOffer.toDouble() : double.tryParse(rawOffer.toString()) ?? mrp;
    final String itemId = item['id'] ?? item['name'] ?? 'item';

    return Consumer<InstahubCartProvider>(
      builder: (context, cart, _) {
        final quantity = cart.getItem(itemId)?.quantity ?? 0;
        return _JumboQuantitySelector(
          quantity: quantity,
          onAdd: () {
            if (!requireLoginGlobal("Please login to add items")) return;
            cart.updateItem(
              id: itemId,
              name: item['name'] ?? item['productName'],
              price: sellingPrice,
              restaurantId: "instahub_store",
              image: item['image'] ?? item['remoteImageUrl'],
              quantity: quantity + 1,
            );
          },
          onRemove: () => cart.removeItem(itemId),
          onUpdate: (newQty) {
            if (newQty > quantity) {
              if (!requireLoginGlobal("Please login to update items")) return;
            }
            cart.updateItem(
              id: itemId,
              name: item['name'] ?? item['productName'],
              price: sellingPrice,
              restaurantId: "instahub_store",
              image: item['image'] ?? item['remoteImageUrl'],
              quantity: newQty,
            );
          },
        );
      },
    );
  }
}