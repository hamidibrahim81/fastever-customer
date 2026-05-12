import 'package:cloud_firestore/cloud_firestore.dart';
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

  final PageController _adsPageController =
      PageController(viewportFraction: 0.9);
  int _currentAdsPage = 0;
  Timer? _adsTimer;
  late AnimationController _pulseController;
  late AnimationController _bigDealsController;

  static const Color _primaryColor = Color(0xFF121212); 
  static const Color _accentColor = Color(0xFF00E676); 
  static const Color _bgColor = Color(0xFFF8F9FD);

  final List<Map<String, dynamic>> categories = [
    {"name": "Fruits & Vegetables", "image": "assets/icons/fv.jpeg", "tag": "fv"},
    {"name": "Dairy & Eggs", "image": "assets/icons/de.jpeg", "tag": "de"},
    {"name": "Meat & seafood", "image": "assets/icons/ms.jpeg", "tag": "ms"},
    {"name": "Grocery & staples", "image": "assets/icons/gs.jpeg", "tag": "gs"},
    {"name": "Bakery & snacks", "image": "assets/icons/bs.jpeg", "tag": "bs"},
    {"name": "Beverages", "image": "assets/icons/b.jpeg", "tag": "b"},
    {"name": "household Essentials", "image": "assets/icons/he.jpeg", "tag": "he"},
    {"name": "Baby & kids", "image": "assets/icons/bk.jpeg", "tag": "bk"},
    {"name": "Pet Care", "image": "assets/icons/pc.jpeg", "tag": "pc"},
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _bigDealsController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _adsTimer = Timer.periodic(const Duration(seconds: 4), (Timer timer) {
      if (_adsPageController.hasClients) {
        _currentAdsPage++;
        _adsPageController.animateToPage(
          _currentAdsPage,
          duration: const Duration(milliseconds: 1000),
          curve: Curves.fastLinearToSlowEaseIn,
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
    _pulseController.dispose();
    _bigDealsController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() => _searchQuery = _searchController.text.trim());
  }

  void _handlePop(bool didPop) {
    if (didPop) return;
    if (_searchQuery.isNotEmpty) {
      setState(() {
        _searchController.clear();
        _searchQuery = "";
      });
      return;
    }
    final now = DateTime.now();
    if (_lastPressed == null ||
        now.difference(_lastPressed!) > const Duration(milliseconds: 2000)) {
      _lastPressed = now;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Press back again to exit", style: GoogleFonts.inter()),
        backgroundColor: Colors.black,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } else {
      if (Navigator.canPop(context)) Navigator.pop(context);
    }
  }

  Future<List<Map<String, dynamic>>> fetchBigDeals() async {
    final snapshot = await FirebaseFirestore.instance
        .collection("instaitems")
        .where("tag", arrayContains: "bigdeal")
        .get();
    return snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
  }

  Future<List<Map<String, dynamic>>> fetchTopSellingItems() async {
    final snapshot = await FirebaseFirestore.instance
        .collection("instaitems")
        .where("tag", arrayContains: "tops")
        .get();
    return snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
  }

  Future<List<Map<String, dynamic>>> fetchBestOfferItems() async {
    final snapshot = await FirebaseFirestore.instance
        .collection("instaitems")
        .where("tag", arrayContains: "bo")
        .get();
    return snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
  }

  Future<List<Map<String, dynamic>>> fetchCategoryItems(String tag) async {
    final snapshot = await FirebaseFirestore.instance
        .collection("instaitems")
        .where("tag", arrayContains: tag)
        .get();
    return snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: _handlePop,
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: _bgColor,
          appBar: AppBar(
            title: Text("INSTAHUB",
                style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    letterSpacing: 1.2)),
            backgroundColor: _primaryColor,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
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
                      _buildSyncedCategorySystem(),
                      const SizedBox(height: 20),
                      _buildAdsRunner(), 
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildMorningBanner(),
                      ),
                      const SizedBox(height: 32),
                      _buildBigDealsSection(),
                      const SizedBox(height: 32),
                      _buildFirestoreSection(
                          title: "⚡ Best Sellers",
                          subtitle: "Fastest moving items",
                          future: fetchTopSellingItems()),
                      const SizedBox(height: 12),
                      _buildFirestoreSection(
                          title: "💸 Super Savings",
                          subtitle: "Limited time offers",
                          color: const Color(0xFFE8F5E9),
                          future: fetchBestOfferItems()),
                      const SizedBox(height: 32),
                      ...categories.map((cat) => _buildCategoryRail(cat)).toList(),
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

  Widget _buildSyncedCategorySystem() {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: 160, 
          decoration: const BoxDecoration(
            color: _primaryColor,
            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), child: _buildSearchBar()),
            Padding(padding: const EdgeInsets.only(left: 20, bottom: 8), child: Text("Shop by Category", style: GoogleFonts.montserrat(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1))),
            SizedBox(
              height: 140, 
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                physics: const BouncingScrollPhysics(),
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 20),
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  return GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryScreen(categoryName: cat["name"]))),
                    child: Column(
                      children: [
                        Container(
                          height: 70, width: 70,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 5))],
                            border: Border.all(color: Colors.white24, width: 2),
                          ),
                          child: ClipOval(child: Image.asset(cat["image"], fit: BoxFit.cover)),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: 75,
                          child: Text(
                            cat["name"],
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: GoogleFonts.montserrat(
                              fontSize: 10, 
                              fontWeight: FontWeight.w800, 
                              color: Colors.black87,
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
          ],
        ),
      ],
    );
  }

  Widget _buildAdsRunner() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('ads').where('tag', isEqualTo: 'insta_ads').where('active', isEqualTo: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox.shrink();
        final adsDocs = snapshot.data!.docs;
        return SizedBox(
          height: 170,
          child: PageView.builder(
            controller: _adsPageController,
            itemBuilder: (context, index) {
              final ad = adsDocs[index % adsDocs.length].data() as Map<String, dynamic>;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: CachedNetworkImage(imageUrl: ad['imageUrl'], fit: BoxFit.cover),
                ),
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
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MorningOrderHomeScreen())),
        ),
        const SizedBox(width: 16),
        _buildQuickActionCard(
          title: "Request",
          subtitle: "Any Item",
          icon: Icons.shopping_basket_rounded,
          colors: [const Color(0xFF00BFA5), const Color(0xFF00796B)],
          onTap: () {
            if (!requireLoginGlobal("Please login to request items")) return;
            Navigator.push(context, MaterialPageRoute(builder: (_) => const RequestItemListScreen()));
          },
        ),
      ],
    );
  }

  Widget _buildQuickActionCard({required String title, required String subtitle, required IconData icon, required List<Color> colors, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 120,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: colors.first.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 28),
              const Spacer(),
              Text(title, style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              Text(subtitle, style: GoogleFonts.montserrat(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, height: 1)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBigDealsSection() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: fetchBigDeals(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
        final docs = snapshot.data!;
        return AnimatedBuilder(
          animation: _bigDealsController,
          builder: (context, child) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              gradient: const LinearGradient(colors: [Color(0xFF2C3E50), Color(0xFF000000)]),
              boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.1 * _pulseController.value), blurRadius: 20, spreadRadius: 5)],
            ),
            child: child,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    const Icon(Icons.flash_on, color: Colors.amber, size: 32),
                    const SizedBox(width: 12),
                    Text("BIG DEALS", style: GoogleFonts.montserrat(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 290,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => _HomeItemCard(item: docs[index], isBigDeal: true),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryRail(Map<String, dynamic> cat) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(cat['name'], style: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.w800, color: _primaryColor)),
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryScreen(categoryName: cat["name"]))),
                  child: Text("VIEW ALL", style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.orange)),
                ),
              ],
            ),
          ),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: fetchCategoryItems(cat['tag']),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
              if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
              final docs = snapshot.data!;
              return SizedBox(
                height: 290,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => _HomeItemCard(item: docs[index]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 5))],
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
            return ListTile(
              leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: item['image'] ?? '', width: 50, height: 50, fit: BoxFit.cover)),
              title: Text(item['name'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: Text("₹${item['offerPrice'] ?? item['price']}", style: GoogleFonts.inter(color: _accentColor, fontWeight: FontWeight.w800)),
              trailing: SizedBox(width: 100, child: _SearchAddButton(item: {...item, 'id': docs[index].id})),
            );
          },
        );
      },
    );
  }

  Widget _buildFirestoreSection({required String title, String? subtitle, Color? color, required Future<List<Map<String, dynamic>>> future}) {
    return Container(
      width: double.infinity,
      color: color ?? Colors.transparent,
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.montserrat(fontSize: 20, fontWeight: FontWeight.w800, color: _primaryColor)),
                if (subtitle != null) Text(subtitle, style: GoogleFonts.inter(fontSize: 13, color: Colors.grey.shade600)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 290,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
                final docs = snapshot.data!;
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => _HomeItemCard(item: docs[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingCartBar() {
    return Consumer<InstahubCartProvider>(
      builder: (context, cart, _) => AnimatedPositioned(
        duration: const Duration(milliseconds: 600),
        curve: Curves.elasticOut,
        bottom: cart.isNotEmpty ? 24 : -120,
        left: 16, right: 16,
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
    final rawPrice = item["offerPrice"] ?? item["price"] ?? 0;
    final price = rawPrice is num ? rawPrice.toDouble() : double.tryParse(rawPrice.toString()) ?? 0.0;
    final stock = (item['stock'] as num?)?.toInt() ?? 0;

    return Consumer<InstahubCartProvider>(
      builder: (context, cart, _) {
        final quantity = cart.getItem(item['id'] ?? item['name'])?.quantity ?? 0;

        return Container(
          width: 170,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFFF5F5F7), borderRadius: BorderRadius.circular(20)),
                  child: Center(child: Hero(tag: "item_${item['id']}", child: CachedNetworkImage(imageUrl: item['image'] ?? '', fit: BoxFit.contain, width: 100))),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['name'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, height: 1.2)),
                    const SizedBox(height: 8),
                    Text("₹${price.toInt()}", style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 18)),
                    const SizedBox(height: 12),
                    if (stock > 0)
                      _JumboQuantitySelector(
                        quantity: quantity,
                        onAdd: () {
                          if (!requireLoginGlobal("Please login to add items")) return;
                          cart.updateItem(id: item['id'] ?? item['name'], name: item['name'], price: price, restaurantId: "instahub_store", image: item['image'], quantity: quantity + 1);
                        },
                        onRemove: () => cart.removeItem(item['id'] ?? item['name']),
                        onUpdate: (newQty) {
                          if (newQty > quantity) {
                            if (!requireLoginGlobal("Please login to update items")) return;
                          }
                          cart.updateItem(id: item['id'] ?? item['name'], name: item['name'], price: price, restaurantId: "instahub_store", image: item['image'], quantity: newQty);
                        },
                      )
                    else
                      Text("OUT OF STOCK", style: GoogleFonts.inter(color: Colors.red, fontSize: 10, fontWeight: FontWeight.w800)),
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

  const _JumboQuantitySelector({required this.quantity, required this.onAdd, required this.onRemove, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: quantity == 0
          ? InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                height: 48, 
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Colors.orange, Color(0xFFFF8C00)]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
                ),
                child: Center(child: Text("ADD", style: GoogleFonts.montserrat(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15))),
              ),
            )
          : Container(
              height: 48, 
              decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => quantity > 1 ? onUpdate(quantity - 1) : onRemove(),
                      child: const Center(child: Icon(Icons.remove_rounded, color: Colors.white, size: 26)),
                    ),
                  ),
                  Text('$quantity', style: GoogleFonts.montserrat(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                  Expanded(
                    child: InkWell(
                      onTap: onAdd,
                      child: const Center(child: Icon(Icons.add_rounded, color: Colors.white, size: 26)),
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
    final rawPrice = item["offerPrice"] ?? item["price"] ?? 0;
    final price = rawPrice is num ? rawPrice.toDouble() : double.tryParse(rawPrice.toString()) ?? 0.0;
    return Consumer<InstahubCartProvider>(
      builder: (context, cart, _) {
        final quantity = cart.getItem(item['id'] ?? item['name'])?.quantity ?? 0;
        return _JumboQuantitySelector(
          quantity: quantity,
          onAdd: () {
            // ✅ LOGIN GUARD ADDED TO SEARCH RESULTS
            if (!requireLoginGlobal("Please login to add items")) return;
            cart.updateItem(id: item['id'] ?? item['name'], name: item['name'], price: price, restaurantId: "instahub_store", image: item['image'], quantity: quantity + 1);
          },
          onRemove: () => cart.removeItem(item['id'] ?? item['name']),
          onUpdate: (newQty) {
            // ✅ LOGIN GUARD ADDED TO INCREMENT IN SEARCH RESULTS
            if (newQty > quantity) {
               if (!requireLoginGlobal("Please login to update items")) return;
            }
            cart.updateItem(id: item['id'] ?? item['name'], name: item['name'], price: price, restaurantId: "instahub_store", image: item['image'], quantity: newQty);
          },
        );
      },
    );
  }
}