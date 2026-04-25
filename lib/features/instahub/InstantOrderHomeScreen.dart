import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fastevergo_v1/features/profile/profile_screen2.dart';
import 'package:fastevergo_v1/features/instahub/CategoryScreen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';

// CORRECTED INSTAHUB IMPORTS
import 'instahub_cart_provider.dart';
import 'instahub_cart_bar.dart';
import 'package:fastevergo_v1/features/instahub/MorningOrderHomeScreen.dart';
import 'request/request_item_list_screen.dart'; // Ensure this file exists

// Custom Clipper for the hexagonal button shape
class HexagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(size.width * 0.1, 0);
    path.lineTo(size.width * 0.9, 0);
    path.lineTo(size.width, size.height * 0.5);
    path.lineTo(size.width * 0.9, size.height);
    path.lineTo(size.width * 0.1, size.height);
    path.lineTo(0, size.height * 0.5);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class InstantOrderHomeScreen extends StatefulWidget {
  const InstantOrderHomeScreen({super.key});

  @override
  State<InstantOrderHomeScreen> createState() => _InstantOrderHomeScreenState();
}

class _InstantOrderHomeScreenState extends State<InstantOrderHomeScreen> with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  DateTime? _lastPressed;

  // --- ADS & ANIMATION CONTROLLERS ---
  final PageController _adsPageController = PageController(viewportFraction: 0.9);
  int _currentAdsPage = 0;
  Timer? _adsTimer;
  late AnimationController _pulseController;
  late AnimationController _bigDealsController; // For Big Deals shimmer effect
  // -------------------------------------

  // --- THEME COLORS (MODERN PALETTE) ---
  static const Color _primaryColor = Color(0xFF1E1E1E); // Matte Black for headers
  static const Color _accentColor = Color(0xFF00C853); // Fresh Green for actions
  static const Color _bgColor = Color(0xFFF5F7FA); // Very light grey-blue for background
  static const Color _cardColor = Colors.white;

  final List<String> lottieAssets = [
    'assets/animations/m3.json',
  ];

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

    // ✅ Pulse Animation for Ads
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // ✅ Animation for Big Deals Section
    _bigDealsController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // ✅ Auto-scroll Timer for Ads Runner
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
    setState(() {
      _searchQuery = _searchController.text.trim();
    });
  }

  // --- MODERN POP SCOPE LOGIC ---
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
    const doublePressDuration = Duration(milliseconds: 2000);

    if (_lastPressed == null || now.difference(_lastPressed!) > doublePressDuration) {
      _lastPressed = now;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Press back again to exit", style: GoogleFonts.poppins()),
          backgroundColor: Colors.black87,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } else {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  // --- FIRESTORE FETCHERS ---
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
    final instahubCartProvider = Provider.of<InstahubCartProvider>(context, listen: false);

    // ✅ ANDROID 14 SAFE POP SCOPE
    return PopScope(
      canPop: false,
      onPopInvoked: _handlePop,
      child: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          _searchFocusNode.unfocus();
        },
        child: Scaffold(
          backgroundColor: _bgColor,
          
          // --- MODERN APP BAR ---
          appBar: AppBar(
            title: Text("InstaHub",
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 24, letterSpacing: -0.5)),
            backgroundColor: _primaryColor,
            foregroundColor: Colors.white,
            elevation: 0,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(10),
              child: Container(
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFFB71C1C), // Matches top of red section
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.account_circle, size: 28),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ProfileScreen2()),
                  );
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
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildSearchBar(),
                      ),
                      _buildSearchResults(),
                    ] else ...[
                      // INTEGRATED RED SECTION (Search + Category + Ads)
                      _buildCategoryGridSection(),
                      
                      const SizedBox(height: 24),

                      // MORNING SERVICE NAVIGATOR + REQUEST ITEM (Now below the red section)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildMorningBanner(),
                      ),

                      const SizedBox(height: 24),

                      // 🔥 DEDICATED BIG DEALS SECTION (HIGHLY ATTRACTIVE)
                      _buildBigDealsSection(),

                      const SizedBox(height: 30),

                      // Top Selling Section
                      _buildFirestoreSection(
                          title: "⚡ Instant Best Sellers",
                          subtitle: "Most loved items in your area",
                          color: Colors.white, 
                          future: fetchTopSellingItems()),

                      const SizedBox(height: 15),

                      // Best Offer Section
                      _buildFirestoreSection(
                          title: "💸 Steal Deals",
                          subtitle: "Prices drop, happiness rises",
                          color: const Color(0xFFF0F4FF),
                          future: fetchBestOfferItems()),

                      const SizedBox(height: 30),

                      // Dynamic Category Sections
                      ...categories.map((cat) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(cat['name'],
                                        style: GoogleFonts.poppins(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.black87)),
                                    Text("See All",
                                        style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: _accentColor)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              FutureBuilder<List<Map<String, dynamic>>>(
                                future: fetchCategoryItems(cat['tag']),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const SizedBox(
                                        height: 240, 
                                        child: Center(child: CircularProgressIndicator(color: _primaryColor)));
                                  } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                                    return const SizedBox.shrink();
                                  } else {
                                    final docs = snapshot.data!;
                                    return SizedBox(
                                      height: 275, 
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        padding: const EdgeInsets.symmetric(horizontal: 16),
                                        itemCount: docs.length,
                                        separatorBuilder: (_, __) => const SizedBox(width: 16),
                                        itemBuilder: (context, index) {
                                          final item = docs[index];
                                          return _HomeItemCard(item: item); 
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
                      
                      Consumer<InstahubCartProvider>(
                        builder: (context, cart, child) {
                          return SizedBox(height: cart.isNotEmpty ? 100 : 40);
                        },
                      ),
                    ],
                  ],
                ),
              ),
              
              // Animated Cart Bar
              Consumer<InstahubCartProvider>(
                builder: (context, cart, child) {
                  return AnimatedPositioned(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutBack,
                    bottom: cart.isNotEmpty ? 16 : -100, 
                    left: 16,
                    right: 16,
                    child: const InstahubCartBar(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGETS ---

  // 🔥 BIG DEALS ATTRACTIVE SECTION
  Widget _buildBigDealsSection() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: fetchBigDeals(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
        final docs = snapshot.data!;

        return AnimatedBuilder(
          animation: _bigDealsController,
          builder: (context, child) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: const [
                    Color(0xFF311B92), // Deep Purple
                    Color(0xFF4527A0), // Indigo
                    Color(0xFF1A237E), // Navy Blue
                  ],
                  stops: [0.0, 0.5 + (0.2 * _bigDealsController.value), 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.indigo.withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: child,
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Colors.amber, size: 28),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("BIG DEALS",
                            style: GoogleFonts.poppins(
                                fontSize: 24, 
                                fontWeight: FontWeight.w900, 
                                color: Colors.white, 
                                letterSpacing: 1.2)),
                        Text("MASSIVE SAVINGS • LIVE NOW",
                            style: GoogleFonts.poppins(
                                fontSize: 10, 
                                fontWeight: FontWeight.bold, 
                                color: Colors.amberAccent)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 280,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                  itemBuilder: (context, index) {
                    return _HomeItemCard(item: docs[index], isBigDeal: true);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // INTEGRATED SECTION WITH RED BACKGROUND
  Widget _buildCategoryGridSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 30),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFB71C1C), // Royal Red
            Color(0xFF7F0000), // Deep Dark Red
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: _buildSearchBar(),
          ),

          const SizedBox(height: 15),

          // 2. Category Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Shop by Category",
                    style: GoogleFonts.poppins(
                        fontSize: 20, 
                        fontWeight: FontWeight.bold, 
                        color: Colors.white,
                        letterSpacing: 0.5)),
                const Icon(Icons.grid_view_rounded, color: Colors.white70),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 3. Category Grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4, 
                crossAxisSpacing: 10, 
                mainAxisSpacing: 16, 
                childAspectRatio: 0.7, 
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
                        builder: (_) => CategoryScreen(categoryName: cat["name"]),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // 4. Ads Runner inside red section (Swapped here)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildAdsRunner(),
          ),
        ],
      ),
    );
  }

  Widget _buildMorningBanner() {
    return Row(
      children: [
        Expanded(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: -1.0, end: 0.0),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutQuart,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(value * MediaQuery.of(context).size.width, 0),
                child: child,
              );
            },
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const MorningOrderHomeScreen()),
                );
              },
              child: Container(
                height: 110,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE65100), Color(0xFFFF8F00)], 
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -10, top: -10,
                      child: Icon(Icons.wb_sunny, size: 70, color: Colors.white.withOpacity(0.15)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.wb_sunny_rounded, size: 24, color: Colors.white),
                          const SizedBox(height: 8),
                          Text("Morning", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 10)),
                          Text("Delivery", 
                            style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, height: 1.1)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RequestItemListScreen(),
                ),
              );
            },
            child: Container(
              height: 110,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00796B), Color(0xFF004D40)], 
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -10, top: -10,
                    child: Icon(Icons.shopping_bag, size: 70, color: Colors.white.withOpacity(0.15)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_shopping_cart, size: 24, color: Colors.white),
                        const SizedBox(height: 8),
                        Text("Request", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 10)),
                        Text("Any Item", 
                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, height: 1.1)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ✅ WIDGET FOR ADS CAROUSEL WITH PULSE EFFECT
  Widget _buildAdsRunner() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ads')
          .where('tag', isEqualTo: 'insta_ads')
          .where('active', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox.shrink();
        
        final adsDocs = snapshot.data!.docs;

        return AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return Container(
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: _accentColor.withOpacity(0.2 * _pulseController.value),
                    blurRadius: 15 * _pulseController.value,
                    spreadRadius: 2 * _pulseController.value,
                  )
                ],
              ),
              child: child,
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: PageView.builder(
              controller: _adsPageController,
              itemBuilder: (context, index) {
                final ad = adsDocs[index % adsDocs.length].data() as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Image.network(
                    ad['imageUrl'],
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.grey[200],
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 55,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onTapOutside: (event) => _searchFocusNode.unfocus(),
        onSubmitted: (value) => _searchFocusNode.unfocus(),
        style: GoogleFonts.poppins(fontSize: 15, color: Colors.black87),
        decoration: InputDecoration(
          hintText: "Search milk, bread, eggs...",
          hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400),
          prefixIcon: const Icon(Icons.search, color: Colors.black87),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: () {
                    _searchController.clear();
                    _searchFocusNode.unfocus(); 
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  Widget _buildCategoryGridItem({
    required String image,
    required String name,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            height: 65, 
            width: 65, 
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15), 
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(image, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 11, 
                fontWeight: FontWeight.w500, 
                color: Colors.white),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("instaitems")
            .where('name', isGreaterThanOrEqualTo: _searchQuery)
            .where('name', isLessThanOrEqualTo: '$_searchQuery\uf8ff')
            .limit(15)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
                child: Padding(
              padding: const EdgeInsets.only(top: 24.0),
              child: Text('No matching items found.', style: GoogleFonts.poppins(color: Colors.grey)),
            ));
          }

          final docs = snapshot.data!.docs;
          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: docs.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final item = doc.data() as Map<String, dynamic>;
              
              final itemName = item['name'] ?? 'Item';
              final itemPrice = (item['offerPrice'] ?? item['price'] ?? 0).toString();
              final itemImage = item['image'] ?? '';

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                leading: Container(
                  width: 50, height: 50,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.grey[100]),
                  child: Image.network(itemImage, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.image, color: Colors.grey)),
                ),
                title: Text(itemName, 
                  maxLines: 2, 
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                subtitle: Text("₹$itemPrice",
                    style: GoogleFonts.poppins(color: _accentColor, fontWeight: FontWeight.bold)),
                trailing: SizedBox(
                   width: 85, 
                   child: _SearchAddButton(item: {...item, 'id': doc.id})
                ), 
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFirestoreSection({
    required String title,
    String? subtitle,
    required Color color,
    Color? titleColor,
    required Future<List<Map<String, dynamic>>> future,
  }) {
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: titleColor ?? Colors.black87)),
                if (subtitle != null)
                  Text(subtitle,
                      style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 275, 
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(child: Text('No items yet.', style: GoogleFonts.poppins(color: Colors.grey)));
                } else {
                  final docs = snapshot.data!;
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 16),
                    itemBuilder: (context, index) {
                      final item = docs[index];
                      return _HomeItemCard(item: item); 
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
}

// ----------------------------------------------------------------------
// MODERN PRETTY ITEM CARD - UI OVERHAUL
// ----------------------------------------------------------------------

class _HomeItemCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final bool isBigDeal; // Added to handle Big Deals UI
  const _HomeItemCard({required this.item, this.isBigDeal = false});

  @override
  State<_HomeItemCard> createState() => _HomeItemCardState();
}

class _HomeItemCardState extends State<_HomeItemCard> {
  static const String storeId = "instahub_store";
  static const Color _accentColor = Color(0xFF00C853);
  static const Color _primaryColor = Color(0xFF1E1E1E);

  void _updateCartItem({required int newQuantity, required double currentPrice}) {
    final cart = Provider.of<InstahubCartProvider>(context, listen: false);
    final item = widget.item;
    final itemId = item["id"] ?? item["name"];

    if (newQuantity > 0) {
      cart.updateItem(
        id: itemId,
        name: item["name"], 
        price: currentPrice, 
        restaurantId: storeId,
        image: item["image"],
        quantity: newQuantity, 
      );
    } else {
      cart.removeItem(itemId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final itemName = item['name'] ?? 'Unknown Item';
    final imageUrl = item['image'] ?? '';
    final stock = (item['stock'] as num?)?.toInt() ?? 0;
    
    final price = (item['price'] as num?)?.toDouble() ?? 0;
    final offerPrice = (item['offerPrice'] as num?)?.toDouble();
    double currentDisplayPrice = offerPrice ?? price;
    
    final bool isBestSeller = (item['tag'] as List?)?.contains("tops") ?? false;
    final bool hasOffer = offerPrice != null;

    return Consumer<InstahubCartProvider>(
      builder: (context, cart, child) {
        final itemId = item["id"] ?? item["name"];
        final cartItem = cart.getItem(itemId);
        final quantity = cartItem?.quantity ?? 0;

        return Container(
          width: 165,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.isBigDeal ? Colors.amber.shade400 : Colors.grey.withOpacity(0.15), 
              width: widget.isBigDeal ? 2 : 1
            ),
            boxShadow: [
              BoxShadow(
                color: widget.isBigDeal ? Colors.amber.withOpacity(0.2) : Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // 1. CONTENT LAYER
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // IMAGE SECTION
                  Expanded(
                    flex: 6,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: widget.isBigDeal ? Colors.amber.shade50 : Colors.grey.shade50,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Hero(
                        tag: "item_${item['id']}",
                        child: Image.network(
                          imageUrl, 
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(Icons.shopping_basket, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),

                  // TEXT & ACTION SECTION
                  Expanded(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Item Name
                          Text(
                            itemName,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600, 
                              fontSize: 13, 
                              color: Colors.black87,
                              height: 1.2
                            ),
                            maxLines: 2, 
                            overflow: TextOverflow.ellipsis
                          ),

                          // Price Row
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text("₹${currentDisplayPrice.toStringAsFixed(0)}",
                                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black)),
                                  if(hasOffer) ...[
                                    const SizedBox(width: 6),
                                    Text("₹${price.toStringAsFixed(0)}",
                                      style: GoogleFonts.poppins(
                                        fontSize: 11, 
                                        decoration: TextDecoration.lineThrough, 
                                        color: Colors.grey.shade500
                                      )),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              
                              // ADD / QUANTITY BUTTON
                              stock <= 0 
                              ? Text("OUT OF STOCK", style: GoogleFonts.poppins(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 10))
                              : quantity == 0
                                ? SizedBox(
                                    height: 34, width: double.infinity,
                                    child: OutlinedButton(
                                      onPressed: () => _updateCartItem(newQuantity: 1, currentPrice: currentDisplayPrice),
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: _accentColor,
                                        side: const BorderSide(color: _accentColor, width: 1.5),
                                        elevation: 0,
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      child: Text("ADD", style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 13)),
                                    ),
                                  )
                                : Container(
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: _accentColor,
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(color: _accentColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        InkWell(
                                          onTap: () => _updateCartItem(newQuantity: quantity - 1, currentPrice: currentDisplayPrice),
                                          child: const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Icon(Icons.remove, size: 16, color: Colors.white)),
                                        ),
                                        Text('$quantity', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                                        InkWell(
                                          onTap: () {
                                            if (quantity < stock) {
                                              _updateCartItem(newQuantity: quantity + 1, currentPrice: currentDisplayPrice);
                                            } else {
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stock limit reached")));
                                            }
                                          },
                                          child: const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Icon(Icons.add, size: 16, color: Colors.white)),
                                        ),
                                      ],
                                    ),
                                  )
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // 2. BADGE OVERLAY
              if (widget.isBigDeal || isBestSeller || hasOffer)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: widget.isBigDeal 
                          ? Colors.amber 
                          : (hasOffer ? const Color(0xFFD32F2F) : _primaryColor),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.isBigDeal ? "BIG DEAL" : (hasOffer ? "OFFER" : "BEST SELLER"),
                      style: GoogleFonts.poppins(
                          color: widget.isBigDeal ? Colors.black : Colors.white, 
                          fontSize: 8, 
                          fontWeight: FontWeight.w800, 
                          letterSpacing: 0.5),
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

// SEARCH TRAILING WIDGET
class _SearchAddButton extends StatefulWidget {
  final Map<String, dynamic> item;
  const _SearchAddButton({required this.item});

  @override
  State<_SearchAddButton> createState() => _SearchAddButtonState();
}

class _SearchAddButtonState extends State<_SearchAddButton> {
  static const Color _accentColor = Color(0xFF00C853);

  void _update(InstahubCartProvider cart, int newQty) {
    final itemId = widget.item["id"] ?? widget.item["name"];
    final price = (widget.item["offerPrice"] ?? widget.item["price"] ?? 0.0).toDouble();

    if (newQty > 0) {
      cart.updateItem(
        id: itemId,
        name: widget.item["name"],
        price: price,
        restaurantId: "instahub_store",
        image: widget.item["image"],
        quantity: newQty,
      );
    } else {
      cart.removeItem(itemId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stock = (widget.item['stock'] as num?)?.toInt() ?? 0;

    if (stock <= 0) return const Text("Out of Stock", style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold));

    return Consumer<InstahubCartProvider>(
      builder: (context, cart, child) {
        final itemId = widget.item["id"] ?? widget.item["name"];
        final cartItem = cart.getItem(itemId);
        final quantity = cartItem?.quantity ?? 0;

        return quantity == 0
            ? OutlinedButton(
                onPressed: () => _update(cart, 1),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accentColor,
                  side: const BorderSide(color: _accentColor),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(60, 32),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text("ADD", style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold)),
              )
            : Container(
                height: 32,
                decoration: BoxDecoration(
                  color: _accentColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    InkWell(onTap: () => _update(cart, quantity - 1), child: const Icon(Icons.remove, size: 14, color: Colors.white)),
                    Text('$quantity', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    InkWell(
                      onTap: () {
                        if (quantity < stock) {
                          _update(cart, quantity + 1);
                        }
                      }, 
                      child: const Icon(Icons.add, size: 14, color: Colors.white)
                    ),
                  ],
                ),
              );
      },
    );
  }
}

class RequestItemSheet extends StatefulWidget {
  const RequestItemSheet({super.key});

  @override
  State<RequestItemSheet> createState() => _RequestItemSheetState();
}

class _RequestItemSheetState extends State<RequestItemSheet> {
  final _productController = TextEditingController();
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Can't find an item?", style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text("Let us know what you're looking for, and we'll try to stock it.", style: GoogleFonts.poppins(color: Colors.grey)),
          const SizedBox(height: 20),
          TextField(
            controller: _productController,
            decoration: InputDecoration(
              hintText: "E.g. Almond Milk, Tofu...",
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request sent!")));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text("Submit Request", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}