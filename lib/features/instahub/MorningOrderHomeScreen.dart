import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fastevergo_v1/features/instahub/MorningCategoryScreen.dart';
import 'package:flutter/material.dart';
import 'package:fastevergo_v1/features/profile/profile_screen2.dart';
import 'package:fastevergo_v1/features/instahub/CategoryScreen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../auth/login_screen.dart';

// ✅ IMPORT GLOBAL AUTH GUARD
import 'package:fastevergo_v1/utils/auth_guards.dart';

// ✅ IMPORT NOTIFICATION SCREEN & BELL NAVIGATOR
import 'package:fastevergo_v1/features/notification/NotificationScreen.dart';

// ✅ IMPORT GLOBAL LOADER
import 'package:fastevergo_v1/features/loading/global_loader.dart';

// Use morning cart imports only
import 'package:fastevergo_v1/features/cart/morning_cart_provider.dart';
import 'package:fastevergo_v1/features/cart/morning_cart_bar.dart';
import 'package:fastevergo_v1/features/cart/morning_cart_screen.dart';
import 'package:fastevergo_v1/features/instahub/MorningOrdersListScreen.dart';

class MorningOrderHomeScreen extends StatefulWidget {
  const MorningOrderHomeScreen({super.key});

  @override
  State<MorningOrderHomeScreen> createState() => _MorningOrderHomeScreenState();
}

class _MorningOrderHomeScreenState extends State<MorningOrderHomeScreen>
    with TickerProviderStateMixin {
  DateTime? _lastPressed;
  final Duration _doublePressDuration = const Duration(milliseconds: 2000);

  final PageController _adsPageController = PageController(viewportFraction: 1.0);
  int _currentAdsPage = 0;
  Timer? _adsTimer;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  // Selected filter: 'all', 'tops', 'bo', or specific category tag
  String _selectedFilterTag = 'all';

  // 1-minute throttled cache for item lists to prevent jumpy auto-refreshing
  List<DocumentSnapshot<Map<String, dynamic>>> _cachedDocs = [];
  bool _isLoadingItems = true;
  DateTime? _lastFetchTime;
  Timer? _oneMinuteRefreshTimer;

  // Premium Deep Slate Theme
  static const Color _headerBgColor = Color(0xFF0F172A);
  static const Color _accentOrange = Color(0xFFFF9100);
  static const Color _bgColor = Color(0xFFF8F9FD);

  final List<Map<String, dynamic>> categories = [
    {"name": "Fruits & Vegetables", "image": "assets/icons/fv.jpeg", "tag": "fv"},
    {"name": "Dairy & Eggs", "image": "assets/icons/de.jpeg", "tag": "de"},
    {"name": "Meat & Seafood", "image": "assets/icons/ms.jpeg", "tag": "ms"},
    {"name": "Grocery & Staples", "image": "assets/icons/gs.jpeg", "tag": "gs"},
    {"name": "Bakery & Snacks", "image": "assets/icons/bs.jpeg", "tag": "bs"},
    {"name": "Beverages", "image": "assets/icons/b.jpeg", "tag": "b"},
    {"name": "Household Essentials", "image": "assets/icons/he.jpeg", "tag": "he"},
    {"name": "Baby & Kids", "image": "assets/icons/bk.jpeg", "tag": "bk"},
    {"name": "Pet Care", "image": "assets/icons/pc.jpeg", "tag": "pc"},
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _fetchItemsThrottled(force: true);

    _oneMinuteRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _fetchItemsThrottled(force: true);
    });

    _adsTimer = Timer.periodic(const Duration(seconds: 4), (Timer timer) {
      if (_adsPageController.hasClients) {
        _currentAdsPage++;
        _adsPageController.animateToPage(
          _currentAdsPage,
          duration: const Duration(milliseconds: 1000),
          curve: Curves.fastOutSlowIn,
        );
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _adsPageController.dispose();
    _adsTimer?.cancel();
    _oneMinuteRefreshTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
  }

  Future<void> _fetchItemsThrottled({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastFetchTime != null &&
        now.difference(_lastFetchTime!) < const Duration(minutes: 1)) {
      return;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection("morningitems")
          .limit(100)
          .get(const GetOptions(source: Source.serverAndCache));

      if (mounted) {
        setState(() {
          _cachedDocs = snap.docs;
          _isLoadingItems = false;
          _lastFetchTime = now;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingItems = false);
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (_searchQuery.isNotEmpty) {
      setState(() {
        _searchController.clear();
        _searchQuery = "";
      });
      return false;
    }
    final now = DateTime.now();
    if (_lastPressed == null || now.difference(_lastPressed!) > _doublePressDuration) {
      _lastPressed = now;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Press back again to exit", style: GoogleFonts.inter()),
          backgroundColor: Colors.black,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return false;
    }
    return true;
  }

  List<DocumentSnapshot<Map<String, dynamic>>> _getFilteredCachedDocs() {
    return _cachedDocs.where((doc) {
      final data = doc.data() ?? {};
      final tags = (data['tag'] is List)
          ? List<dynamic>.from(data['tag'])
          : (data['tags'] is List ? List<dynamic>.from(data['tags']) : []);

      if (_selectedFilterTag == 'all') return true;
      if (_selectedFilterTag == 'tops') return tags.contains('tops');
      if (_selectedFilterTag == 'bo') return tags.contains('bo');
      return tags.contains(_selectedFilterTag);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          GlobalLoader.run(
            duration: const Duration(milliseconds: 1800),
            task: () async {
              if (!context.mounted) return;
              Navigator.of(context).pop();
            },
          );
        }
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: _bgColor,
          appBar: AppBar(
            title: Text(
              "MORNING SERVICE",
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: 1.2,
              ),
            ),
            backgroundColor: _headerBgColor,
            foregroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              onPressed: () {
                GlobalLoader.run(
                  duration: const Duration(milliseconds: 1800),
                  task: () async {
                    if (!mounted) return;
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_rounded, size: 26),
                onPressed: () {
                  GlobalLoader.run(
                    duration: const Duration(milliseconds: 1800),
                    task: () async {
                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NotificationScreen()),
                      );
                    },
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.account_circle_outlined, size: 28),
                onPressed: () {
                  if (!requireLoginGlobal("Please login to access profile")) return;
                  GlobalLoader.run(
                    duration: const Duration(milliseconds: 1800),
                    task: () async {
                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ProfileScreen2()),
                      );
                    },
                  );
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  const SizedBox(height: 140),
                ],
              ],
            ),
          ),
          bottomNavigationBar: const MorningCartBar(),
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Container(
      width: double.infinity,
      color: _headerBgColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: _buildSearchBar(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildMyOrdersButtonOnly(),
          ),
          const SizedBox(height: 14),
          _buildAdsRunner(),
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
              separatorBuilder: (_, __) => const SizedBox(width: 18),
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
                            color: isSelected ? _accentOrange : Colors.white24,
                            width: isSelected ? 3 : 2,
                          ),
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            cat["image"],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => const Center(
                              child: Icon(Icons.shopping_bag_outlined, color: Colors.grey),
                            ),
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
                            color: isSelected ? _accentOrange : Colors.white,
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
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildAdsRunner() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ads')
          .where('tag', isEqualTo: 'morn_ads')
          .where('active', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox.shrink();
        final adsDocs = snapshot.data!.docs;

        return Container(
          height: 165,
          color: _headerBgColor,
          child: PageView.builder(
            controller: _adsPageController,
            itemBuilder: (context, index) {
              final ad = adsDocs[index % adsDocs.length].data() as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedNetworkImage(
                      imageUrl: ad['imageUrl'] ?? '',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (_, __) => Container(color: Colors.white10),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.white10,
                        child: const Icon(Icons.broken_image, color: Colors.white54),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMyOrdersButtonOnly() {
    return InkWell(
      onTap: () {
        if (!requireLoginGlobal("Please login to view orders")) return;
        GlobalLoader.run(
          duration: const Duration(milliseconds: 1800),
          task: () async {
            if (!mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const MorningOrdersListScreen()),
            );
          },
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: _accentOrange.withOpacity(0.2),
              child: const Icon(Icons.history_rounded, color: _accentOrange),
            ),
            const SizedBox(width: 14),
            Text(
              "View My Morning Orders",
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, color: Colors.white70),
          ],
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
          hintText: "Search milk, eggs, bread, apple, atta...",
          hintStyle: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded, color: _accentOrange, size: 24),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, color: Colors.grey),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    final List<Map<String, String>> filters = [
      {"label": "✨ All Items", "tag": "all"},
      {"label": "🔥 Daily Essentials", "tag": "tops"},
      {"label": "🏷️ Value Deals", "tag": "bo"},
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
            selectedColor: _accentOrange,
            backgroundColor: Colors.white,
            side: BorderSide(
              color: isSelected ? _accentOrange : Colors.grey.shade300,
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
    if (_isLoadingItems && _cachedDocs.isEmpty) {
      return const SizedBox(
        height: 250,
        child: Center(child: CircularProgressIndicator(color: _accentOrange)),
      );
    }

    final docs = _getFilteredCachedDocs();

    if (docs.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: Text(
          "No items found in this section",
          style: GoogleFonts.inter(color: Colors.grey, fontWeight: FontWeight.w600),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        key: PageStorageKey<String>("morning_grid_$_selectedFilterTag"),
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
          return _MorningItemCard(
            item: {...doc.data()!, 'id': doc.id},
          );
        },
      ),
    );
  }

  Widget _buildSearchResults() {
    final query = _searchQuery.trim().toLowerCase();

    final filtered = _cachedDocs.where((doc) {
      final data = doc.data() ?? {};
      final name = (data['name'] ?? data['productName'] ?? '').toString().toLowerCase();
      final category = (data['category'] ?? '').toString().toLowerCase();
      final tags = (data['tags'] is List ? List<dynamic>.from(data['tags']) : []).join(' ').toLowerCase();

      if (name.startsWith(query)) return true;

      final nameWords = name.split(RegExp(r'\s+'));
      if (nameWords.any((w) => w.startsWith(query))) return true;

      return name.contains(query) || category.contains(query) || tags.contains(query);
    }).toList();

    if (filtered.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        child: Text(
          "No products match '$query'",
          style: GoogleFonts.inter(color: Colors.grey.shade600, fontSize: 14),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final item = filtered[index].data()!;
        final price = (item['price'] as num?)?.toDouble() ?? 0;
        final offerPrice = (item['offerPrice'] as num?)?.toDouble();
        final actualPrice = offerPrice ?? price;
        final bool hasDiscount = offerPrice != null && offerPrice < price;

        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: item['image'] ?? '',
              width: 50,
              height: 50,
              fit: BoxFit.cover,
            ),
          ),
          title: Text(
            item['name'] ?? '',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          subtitle: Row(
            children: [
              Text(
                "₹${actualPrice.toInt()}",
                style: GoogleFonts.inter(color: const Color(0xFF00E676), fontWeight: FontWeight.w800, fontSize: 14),
              ),
              if (hasDiscount) ...[
                const SizedBox(width: 6),
                Text(
                  "₹${price.toInt()}",
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
            child: Consumer<MorningCartProvider>(
              builder: (context, cart, _) {
                final qty = cart.getQuantity(filtered[index].id);
                return _JumboMorningSelector(
                  quantity: qty,
                  onAdd: () {
                    if (!requireLoginGlobal("Please login to add items")) return;
                    cart.addItem(
                      id: filtered[index].id,
                      name: item['name'],
                      price: actualPrice,
                      restaurantId: "morninghub",
                      image: item['image'],
                    );
                  },
                  onRemove: () => cart.reduceQuantity(filtered[index].id),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _MorningItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  const _MorningItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final price = (item['price'] as num?)?.toDouble() ?? 0;
    final offerPrice = (item['offerPrice'] as num?)?.toDouble();
    final actualPrice = offerPrice ?? price;
    final String itemId = item['id'];
    final bool hasDiscount = offerPrice != null && offerPrice < price && price > 0;
    final int discountPercent = hasDiscount ? (((price - offerPrice) / price) * 100).round() : 0;

    return Consumer<MorningCartProvider>(
      builder: (context, cart, _) {
        final qty = cart.getQuantity(itemId);

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
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F7F9),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Hero(
                          tag: "morn_item_$itemId",
                          child: CachedNetworkImage(
                            imageUrl: item['image'] ?? '',
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            placeholder: (_, __) => Container(color: Colors.grey.shade100),
                            errorWidget: (context, url, error) => const Center(
                              child: Icon(Icons.image_not_supported_outlined, color: Colors.grey),
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
                      item['name'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, height: 1.2),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          "₹${actualPrice.toInt()}",
                          style: GoogleFonts.montserrat(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: const Color(0xFF121212),
                          ),
                        ),
                        if (hasDiscount) ...[
                          const SizedBox(width: 6),
                          Text(
                            "₹${price.toInt()}",
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
                    _JumboMorningSelector(
                      quantity: qty,
                      onAdd: () {
                        if (!requireLoginGlobal("Please login to add items")) return;
                        cart.addItem(
                          id: itemId,
                          name: item['name'],
                          price: actualPrice,
                          restaurantId: "morninghub",
                          image: item['image'],
                        );
                      },
                      onRemove: () => cart.reduceQuantity(itemId),
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

class _JumboMorningSelector extends StatelessWidget {
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _JumboMorningSelector({
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: quantity == 0
          ? InkWell(
              key: const ValueKey('morn_add_btn'),
              onTap: onAdd,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF9100), Color(0xFFFF8C00)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF9100).withOpacity(0.25),
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
              key: const ValueKey('morn_counter_btn'),
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: onRemove,
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