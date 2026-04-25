import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fastevergo_v1/features/instahub/MorningCategoryScreen.dart';
import 'package:flutter/material.dart';
import 'package:fastevergo_v1/features/profile/profile_screen2.dart'; 
import 'package:fastevergo_v1/features/instahub/CategoryScreen.dart'; 
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:async';

// Use morning cart imports only
import 'package:fastevergo_v1/features/cart/morning_cart_provider.dart';
import 'package:fastevergo_v1/features/cart/morning_cart_bar.dart';
import 'package:fastevergo_v1/features/cart/morning_cart_screen.dart'; 
// IMPORTANT: Ensure this import path matches your project structure
import 'package:fastevergo_v1/features/instahub/MorningOrdersListScreen.dart';

class MorningOrderHomeScreen extends StatefulWidget {
  const MorningOrderHomeScreen({super.key});

  @override
  State<MorningOrderHomeScreen> createState() => _MorningOrderHomeScreenState();
}

class _MorningOrderHomeScreenState extends State<MorningOrderHomeScreen> with SingleTickerProviderStateMixin {
  // --- DOUBLE-TAP TO EXIT VARIABLES ---
  DateTime? _lastPressed;
  final Duration _doublePressDuration = const Duration(milliseconds: 2000);
  // -------------------------------------

  // --- ADS RUNNER CONTROLLERS ---
  final PageController _adsPageController = PageController(viewportFraction: 1.0);
  int _currentAdsPage = 0;
  Timer? _adsTimer;
  late AnimationController _pulseController;
  // ------------------------------
  
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

    // Pulse animation for Ads
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Auto-scroll Timer for Ads Runner
    _adsTimer = Timer.periodic(const Duration(seconds: 4), (Timer timer) {
      if (_adsPageController.hasClients) {
        _currentAdsPage++;
        _adsPageController.animateToPage(
          _currentAdsPage,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOutQuart,
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

  // --- DOUBLE-TAP TO EXIT LOGIC ---
  Future<bool> _onWillPop() async {
    final now = DateTime.now();
    if (_lastPressed == null || now.difference(_lastPressed!) > _doublePressDuration) {
      _lastPressed = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Press back again to exit"),
          duration: Duration(seconds: 2),
        ),
      );
      return false; 
    }
    return true; 
  }

  Future<List<Map<String, dynamic>>> fetchTopSellingItems() async {
    final snapshot = await FirebaseFirestore.instance
        .collection("morningitems")
        .where("tag", arrayContains: "tops")
        .get();
    return snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
  }

  Future<List<Map<String, dynamic>>> fetchBestOfferItems() async {
    final snapshot = await FirebaseFirestore.instance
        .collection("morningitems")
        .where("tag", arrayContains: "bo")
        .get();
    return snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
  }

  Future<List<Map<String, dynamic>>> fetchCategoryItems(String tag) async {
    final snapshot = await FirebaseFirestore.instance
        .collection("morningitems")
        .where("tag", arrayContains: tag)
        .get();
    return snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(
            "Morning Service",
            style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 22),
          ),
          backgroundColor: const Color(0xFFB71C1C), // Matching Red Background Top
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(10),
            child: Container(
              height: 10,
              color: const Color(0xFFB71C1C),
            ),
          ),
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              
              // ✅ INTEGRATED SECTION (RED BACKGROUND)
              _buildUnifiedHeaderSection(),

              const SizedBox(height: 24),

              // ✅ MY ORDERS BUTTON (White Styled, moved here)
              _buildMyOrdersButtonOnly(),

              const SizedBox(height: 30),
              
              _buildFirestoreSection(
                title: "🔥 Daily Must-Haves",
                color: Colors.red.shade50,
                titleColor: Colors.red.shade700,
                future: fetchTopSellingItems(),
              ),
              const SizedBox(height: 30),
              _buildFirestoreSection(
                title: "🏷️ Best Value Deals",
                color: Colors.green.shade50,
                titleColor: Colors.green.shade700,
                future: fetchBestOfferItems(),
              ),
              const SizedBox(height: 30),
              ...categories.map((cat) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          "Popular in ${cat['name']}",
                          style: GoogleFonts.poppins(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: fetchCategoryItems(cat['tag']),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const SizedBox(
                              height: 255,
                              child: Center(child: CircularProgressIndicator(color: Colors.deepOrange)),
                            );
                          } else if (snapshot.hasError) {
                            return Center(child: Text('Error: ${snapshot.error}'));
                          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return const Center(child: Text('No items found.'));
                          } else {
                            final docs = snapshot.data!;
                            return SizedBox(
                              height: 255,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: docs.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 16),
                                itemBuilder: (context, index) {
                                  final item = docs[index];
                                  return _buildPopularItemCard(
                                    itemId: item['id'],
                                    itemName: item['name'],
                                    imageUrl: item['image'],
                                    weight: item['weight'] ?? '-',
                                    price: (item['price'] as num?)?.toDouble() ?? 0,
                                    offerPrice: (item['offerPrice'] as num?)?.toDouble(),
                                  );
                                },
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
              const SizedBox(height: 100),
            ],
          ),
        ),
        bottomNavigationBar: const MorningCartBar(),
      ),
    );
  }

  // ------------------ UNIFIED HEADER SECTION ------------------

  Widget _buildUnifiedHeaderSection() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFB71C1C), // Royal Premium Red
            Color(0xFF7F0000), // Deep Dark Red
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Ads Runner (Top)
          _buildAdsRunner(),

          const SizedBox(height: 24),

          // 2. Shop by Category Header and Grid
          _buildAttractiveCategoryContent(),
          
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ------------------ UPDATED WIDGETS ------------------

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

        return AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Container(
              height: 170,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2 * _pulseController.value),
                    blurRadius: 15 * _pulseController.value,
                    spreadRadius: 2 * _pulseController.value,
                  )
                ],
              ),
              child: child,
            );
          },
          child: PageView.builder(
            controller: _adsPageController,
            itemBuilder: (context, index) {
              final ad = adsDocs[index % adsDocs.length].data() as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.network(
                    ad['imageUrl'],
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.grey[200],
                      child: const Icon(Icons.broken_image, color: Colors.grey),
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
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MorningOrdersListScreen()),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.shopping_bag_outlined, color: Color(0xFFB71C1C)),
              const SizedBox(width: 12),
              Text(
                "My Orders",
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: const Color(0xFFB71C1C),
                ),
              ),
              const Spacer(),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFFB71C1C)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttractiveCategoryContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Shop by Category",
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4, 
              crossAxisSpacing: 10, 
              mainAxisSpacing: 16, 
              childAspectRatio: 0.75, 
            ),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              return _buildCategoryGridItem(
                image: cat["image"],
                name: cat["name"],
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MorningCategoryScreen(categoryName: cat["name"]),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryGridItem({required String image, required String name, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            height: 65, 
            width: 65,
            decoration: BoxDecoration(
              shape: BoxShape.circle, 
              color: Colors.white.withOpacity(0.15),
              border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
            ),
            child: ClipOval( 
              child: Image.asset(
                image,
                fit: BoxFit.cover, 
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFirestoreSection({required String title, required Color color, required Color titleColor, required Future<List<Map<String, dynamic>>> future}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(color: color, boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Text(title, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: titleColor))),
          const SizedBox(height: 16),
          SizedBox(
            height: 255,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Colors.deepOrange));
                else if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('No items found.'));
                else {
                  final docs = snapshot.data!;
                  return ListView.separated(
                    scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: docs.length, separatorBuilder: (_, __) => const SizedBox(width: 16),
                    itemBuilder: (context, index) {
                      final item = docs[index];
                      return _buildPopularItemCard(itemId: item['id'], itemName: item['name'], imageUrl: item['image'], weight: item['weight'] ?? '-', price: (item['price'] as num?)?.toDouble() ?? 0, offerPrice: (item['offerPrice'] as num?)?.toDouble());
                    },
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPopularItemCard({required String itemId, required String itemName, required String imageUrl, required String weight, required double price, double? offerPrice}) {
    return Consumer<MorningCartProvider>(
      builder: (context, cart, _) {
        final qty = cart.getQuantity(itemId);
        double actualPrice = offerPrice ?? price;

        return Container(
          width: 150,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.grey.shade300, blurRadius: 10, offset: const Offset(0, 5)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Use Expanded for image area
              Expanded(
                flex: 4,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.image),
                  ),
                ),
              ),
              // Use Expanded for details area
              Expanded(
                flex: 6,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(itemName, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(weight, style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text("₹${actualPrice.toStringAsFixed(0)}", style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                              if (offerPrice != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Text("₹${price.toStringAsFixed(0)}", style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey, decoration: TextDecoration.lineThrough)),
                                ),
                            ],
                          ),
                        ],
                      ),
                      qty == 0
                          ? ElevatedButton(
                              onPressed: () {
                                cart.addItem(id: itemId, name: itemName, price: actualPrice, restaurantId: "morninghub", image: imageUrl);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.deepOrange,
                                minimumSize: const Size(double.infinity, 32),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text("ADD", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            )
                          : Container(
                              height: 32,
                              decoration: BoxDecoration(color: Colors.deepOrange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.deepOrange.shade200)),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  InkWell(
                                    onTap: () => cart.reduceQuantity(itemId),
                                    child: const Icon(Icons.remove, color: Colors.deepOrange, size: 18),
                                  ),
                                  Text('$qty', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  InkWell(
                                    onTap: () => cart.addItem(
                                      id: itemId,
                                      name: itemName,
                                      price: actualPrice,
                                      restaurantId: "morninghub",
                                      image: imageUrl,
                                    ),
                                    child: const Icon(Icons.add, color: Colors.deepOrange, size: 18),
                                  ),
                                ],
                              ),
                            ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}