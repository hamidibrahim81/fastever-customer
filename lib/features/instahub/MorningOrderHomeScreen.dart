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
  late AnimationController _pulseController;

  static const Color _morningRed = Color(0xFFD32F2F);
  static const Color _bgColor = Color(0xFFFBFBFB);

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
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

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
    _adsPageController.dispose();
    _adsTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // LOGIC UNTOUCHED
  Future<bool> _onWillPop() async {
    final now = DateTime.now();
    if (_lastPressed == null || now.difference(_lastPressed!) > _doublePressDuration) {
      _lastPressed = now;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Press back again to exit")));
      return false;
    }
    return true;
  }

  Future<List<Map<String, dynamic>>> fetchTopSellingItems() async {
    final snapshot = await FirebaseFirestore.instance.collection("morningitems").where("tag", arrayContains: "tops").get();
    return snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
  }

  Future<List<Map<String, dynamic>>> fetchBestOfferItems() async {
    final snapshot = await FirebaseFirestore.instance.collection("morningitems").where("tag", arrayContains: "bo").get();
    return snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
  }

  Future<List<Map<String, dynamic>>> fetchCategoryItems(String tag) async {
    final snapshot = await FirebaseFirestore.instance.collection("morningitems").where("tag", arrayContains: tag).get();
    return snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: _bgColor,
        appBar: AppBar(
          title: Text("MORNING SERVICE",
              style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 1)),
          backgroundColor: _morningRed,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.account_circle_outlined, size: 28),
              onPressed: () {
                if (!requireLoginGlobal("Please login to access profile")) return;
                Navigator.push(context, MaterialPageRoute(builder: (context) => const ProfileScreen2()));
              },
            ),
          ],
        ),
        body: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSyncedCategorySystem(), // 🔄 Unified horizontal unit
              const SizedBox(height: 24),
              _buildAdsRunner(), // Ads moved down
              const SizedBox(height: 24),
              _buildMyOrdersButtonOnly(),
              const SizedBox(height: 32),
              _buildFirestoreSection(
                title: "🔥 Daily Essentials",
                color: const Color(0xFFFFF5F5),
                titleColor: _morningRed,
                future: fetchTopSellingItems(),
              ),
              const SizedBox(height: 12),
              _buildFirestoreSection(
                title: "🏷️ Value Deals",
                color: const Color(0xFFF1F8E9),
                titleColor: Colors.green.shade800,
                future: fetchBestOfferItems(),
              ),
              const SizedBox(height: 32),
              ...categories.map((cat) => _buildCategoryRail(cat)).toList(),
              const SizedBox(height: 120),
            ],
          ),
        ),
        bottomNavigationBar: const MorningCartBar(),
      ),
    );
  }

  // 🔄 FULLY SYNCED CATEGORY UI (Image and Name scroll as one unit)
  Widget _buildSyncedCategorySystem() {
    return Stack(
      children: [
        // Background Header Box
        Container(
          width: double.infinity,
          height: 120, 
          decoration: const BoxDecoration(
            color: _morningRed,
            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
          ),
        ),
        // Unified Scrollable List
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 15),
            Padding(padding: const EdgeInsets.only(left: 20, bottom: 8), child: Text("Shop by Category", style: GoogleFonts.montserrat(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1))),
            SizedBox(
              height: 145, // Total height for Image + Spacing + Name
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                physics: const BouncingScrollPhysics(),
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 18),
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  return GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MorningCategoryScreen(categoryName: cat["name"]))),
                    child: Column(
                      children: [
                        // Image Pod (Over Red area)
                        Container(
                          height: 70, width: 70,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))],
                            border: Border.all(color: Colors.white24, width: 2),
                          ),
                          child: ClipOval(child: Image.asset(cat["image"], fit: BoxFit.cover)),
                        ),
                        const SizedBox(height: 15), // Pushes text down onto the white area
                        // Name Pod (Scrolls with the image)
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
                              height: 1.1
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
      stream: FirebaseFirestore.instance
          .collection('ads')
          .where('tag', isEqualTo: 'morn_ads')
          .where('active', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox.shrink();
        final adsDocs = snapshot.data!.docs;
        return Container(
          height: 180,
          margin: const EdgeInsets.only(top: 10),
          child: PageView.builder(
            controller: _adsPageController,
            itemBuilder: (context, index) {
              final ad = adsDocs[index % adsDocs.length].data() as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: CachedNetworkImage(
                      imageUrl: ad['imageUrl'],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (_, __) => Container(color: Colors.white10),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: () {
          if (!requireLoginGlobal("Please login to view orders")) return;
          Navigator.push(context, MaterialPageRoute(builder: (context) => const MorningOrdersListScreen()));
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
            ],
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFFFFEBEE),
                child: Icon(Icons.history_rounded, color: _morningRed),
              ),
              const SizedBox(width: 16),
              Text("View My Morning Orders",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.black87)),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
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
                Text(cat['name'], style: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.w800)),
                Text("View All", style: GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.w700, color: _morningRed)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 290,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: fetchCategoryItems(cat['tag']),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
                final docs = snapshot.data!;
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => _MorningItemCard(item: docs[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFirestoreSection({required String title, required Color color, required Color titleColor, required Future<List<Map<String, dynamic>>> future}) {
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(title, style: GoogleFonts.montserrat(fontSize: 20, fontWeight: FontWeight.w900, color: titleColor)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 290,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('No items found.'));
                final docs = snapshot.data!;
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) => _MorningItemCard(item: docs[index]),
                );
              },
            ),
          ),
        ],
      ),
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

    return Consumer<MorningCartProvider>(
      builder: (context, cart, _) {
        final qty = cart.getQuantity(itemId);

        return Container(
          width: 170,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFFF5F5F7), borderRadius: BorderRadius.circular(20)),
                  child: Center(
                    child: CachedNetworkImage(imageUrl: item['image'] ?? '', fit: BoxFit.contain, width: 100),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['name'] ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, height: 1.2)),
                    const SizedBox(height: 4),
                    Text(item['weight'] ?? '', style: GoogleFonts.inter(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text("₹${actualPrice.toInt()}",
                            style: GoogleFonts.montserrat(fontWeight: FontWeight.w900, fontSize: 18)),
                        if (offerPrice != null) ...[
                          const SizedBox(width: 4),
                          Text("₹${price.toInt()}",
                              style: GoogleFonts.inter(
                                  fontSize: 11, color: Colors.grey, decoration: TextDecoration.lineThrough)),
                        ]
                      ],
                    ),
                    const SizedBox(height: 12),
                    _JumboMorningSelector(
                      quantity: qty,
                      onAdd: () {
                        if (!requireLoginGlobal("Please login to add items")) return;
                        cart.addItem(id: itemId, name: item['name'], price: actualPrice, restaurantId: "morninghub", image: item['image']);
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

  const _JumboMorningSelector({required this.quantity, required this.onAdd, required this.onRemove});

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
                  gradient: const LinearGradient(colors: [Color(0xFFD32F2F), Color(0xFFB71C1C)]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
                ),
                child: Center(
                    child: Text("ADD",
                        style: GoogleFonts.montserrat(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14))),
              ),
            )
          : Container(
              height: 48,
              decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: onRemove,
                      child: const Center(child: Icon(Icons.remove_rounded, color: Colors.white, size: 24)),
                    ),
                  ),
                  Text('$quantity',
                      style: GoogleFonts.montserrat(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                  Expanded(
                    child: InkWell(
                      onTap: onAdd,
                      child: const Center(child: Icon(Icons.add_rounded, color: Colors.white, size: 24)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}