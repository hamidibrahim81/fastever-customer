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

class _InstantOrderHomeScreenState extends State<InstantOrderHomeScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  DateTime? _lastPressed;

  // --- ADS & ANIMATION CONTROLLERS ---
  final PageController _adsPageController = PageController(viewportFraction: 0.9);
  int _currentAdsPage = 0;
  Timer? _adsTimer;
  late AnimationController _pulseController;
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
    final instahubCartProvider = Provider.of<InstahubCartProvider>(context);

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
                  color: _bgColor,
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
                    // ISSUE 1 FIX: Logic to only show results when searching
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildSearchBar(),
                    ),

                    if (_searchQuery.isNotEmpty)
                      _buildSearchResults()
                    else ...[
                      _buildCreativeBlock(),
                      const SizedBox(height: 20),
                      _buildCategoryGridSection(),
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
                                      height: 260,
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
                      
                      SizedBox(height: instahubCartProvider.isNotEmpty ? 100 : 40),
                    ],
                  ],
                ),
              ),
              
              // Animated Cart Bar
              AnimatedPositioned(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutBack,
                bottom: instahubCartProvider.isNotEmpty ? 16 : -100, 
                left: 16,
                right: 16,
                child: const InstahubCartBar(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildCreativeBlock() {
    return Container(
      color: _bgColor,
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
      child: Column(
        children: [
          // ✅ Morning Delivery Banner
          TweenAnimationBuilder<double>(
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
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE65100), Color(0xFFFF8F00)], 
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -15, top: -15,
                      child: Icon(Icons.wb_sunny, size: 120, color: Colors.white.withOpacity(0.15)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          const Icon(Icons.wb_sunny_rounded, size: 40, color: Colors.white),
                          const SizedBox(width: 20),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text("Switch to", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
                              Text("Morning Delivery", 
                                style: GoogleFonts.poppins(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, height: 1.1)),
                            ],
                          ),
                          const Spacer(),
                          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 20),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 24),

          // ✅ Auto-Loop Pulse Ads Runner
          _buildAdsRunner(),
        ],
      ),
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
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
          filled: true,
          fillColor: Colors.grey.shade50,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.black, width: 1.8),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryGridSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFB71C1C), // Royal Red
            Color(0xFF7F0000), // Deep Dark Red
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          const SizedBox(height: 20),
          GridView.builder(
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
        ],
      ),
    );
  }

  // ISSUE 2 FIX: Images now BoxFit.cover and ClipRRect used for perfect fit
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
            height: 260, 
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
// PRETTY ITEM CARD - METHOD 1 (STRING CONSTANT) LOGIC
// ----------------------------------------------------------------------

class _HomeItemCard extends StatefulWidget {
  final Map<String, dynamic> item;
  const _HomeItemCard({required this.item});

  @override
  State<_HomeItemCard> createState() => _HomeItemCardState();
}

class _HomeItemCardState extends State<_HomeItemCard> {
  int quantity = 0;
  late String selectedValue; 
  late List<String> options;
  bool _showSelector = true;
  
  // Method 1: STRING CONSTANT LOGIC with specific ranges
  void _setupOptions() {
    // UPDATED: Check for hasVariations toggle from Firestore
    final bool hasVariations = widget.item['hasVariations'] ?? true;
    final String type = widget.item['unitType']?.toString().toLowerCase() ?? 'kg';

    if (!hasVariations) {
      _showSelector = false;
      options = ['Standard'];
      selectedValue = 'Standard';
    } else if (type == 'litre') {
      options = ['50 ml', '100 ml', '200 ml', '250 ml', '500 ml', '1 Litre', '2 Litre', '5 Litre'];
      selectedValue = '1 Litre';
    } else if (type == 'pc') {
      options = ['1 pc', '2 pc', '3 pc', '4 pc', '5 pc', '6 pc', '7 pc', '8 pc', '9 pc', '10 pc', '15 pc', '25 pc'];
      selectedValue = '1 pc';
    } else if (type == 'kg') {
      options = ['50 g', '100 g', '200 g', '250 g', '500 g', '1 kg', '2 kg', '5 kg'];
      selectedValue = '1 kg';
    } else {
      _showSelector = false;
      options = ['Standard'];
      selectedValue = 'Standard';
    }
  }

  static const String storeId = "instahub_store";
  static const Color _accentColor = Color(0xFF00C853);

  @override
  void initState() {
    super.initState();
    _setupOptions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialCartState();
    });
  }

  void _loadInitialCartState() {
    try {
      final cart = Provider.of<InstahubCartProvider>(context, listen: false);
      final itemId = widget.item["id"] ?? widget.item["name"];
      final cartItem = cart.getItem(itemId); 
      if (cartItem != null) {
        setState(() { quantity = cartItem.quantity; });
      }
    } catch (e) {
      debugPrint("Provider error: $e");
    }
  }

  double _calculatePrice(double basePrice) {
    if (!_showSelector) return basePrice;
    
    // Weight & Volume logic based on Litre / KG being base
    String unit = selectedValue.toLowerCase();
    if (unit.contains('50 g') || unit.contains('50 ml')) return basePrice * 0.05;
    if (unit.contains('100 g') || unit.contains('100 ml')) return basePrice * 0.1;
    if (unit.contains('200 g') || unit.contains('200 ml')) return basePrice * 0.2;
    if (unit.contains('250 g') || unit.contains('250 ml')) return basePrice * 0.25;
    if (unit.contains('500 g') || unit.contains('500 ml')) return basePrice * 0.5;
    if (unit.contains('2 kg') || unit.contains('2 litre')) return basePrice * 2.0;
    if (unit.contains('5 kg') || unit.contains('5 litre')) return basePrice * 5.0;
    
    // PC logic based on 1 pc being base
    if (unit.contains('pc')) {
       double count = double.tryParse(unit.split(' ')[0]) ?? 1.0;
       return basePrice * count;
    }
    
    return basePrice;
  }

  void _updateCartItem({required int newQuantity}) {
    final cart = Provider.of<InstahubCartProvider>(context, listen: false);
    final item = widget.item;
    final itemId = item["id"] ?? item["name"];
    
    final basePrice = (item["offerPrice"] ?? item["price"] ?? 0.0).toDouble();
    final currentDisplayPrice = _calculatePrice(basePrice);

    setState(() { quantity = newQuantity; });

    if (newQuantity > 0) {
      cart.updateItem(
        id: itemId,
        name: _showSelector ? "${item["name"]} ($selectedValue)" : item["name"], 
        price: currentDisplayPrice, 
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
    final itemName = item['name'];
    final imageUrl = item['image'];
    final stock = (item['stock'] as num?)?.toInt() ?? 0;
    
    final price = (item['price'] as num?)?.toDouble() ?? 0;
    final offerPrice = (item['offerPrice'] as num?)?.toDouble();
    double actualBasePrice = offerPrice ?? price;
    final displayPrice = _calculatePrice(actualBasePrice);
    
    return Container(
      width: 160,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Image.network(imageUrl, fit: BoxFit.contain),
              ),
            ),
          ),

          Expanded(
            flex: 4, 
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(itemName,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  
                  if (_showSelector)
                    Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedValue,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down, size: 14),
                          style: GoogleFonts.poppins(fontSize: 11, color: Colors.black87),
                          items: options.map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => selectedValue = val);
                              if (quantity > 0) _updateCartItem(newQuantity: quantity);
                            }
                          },
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 26),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text("₹${displayPrice.toStringAsFixed(0)}",
                              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87)),
                            if(offerPrice != null)
                              Text("₹${_calculatePrice(price).toStringAsFixed(0)}",
                                style: GoogleFonts.poppins(fontSize: 10, decoration: TextDecoration.lineThrough, color: Colors.grey)),
                        ],
                      ),
                      
                      // STOCK LOGIC
                      stock <= 0 
                      ? Text("Out of Stock", style: GoogleFonts.poppins(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 9))
                      : quantity == 0
                        ? SizedBox(
                            height: 32, width: 60,
                            child: ElevatedButton(
                              onPressed: () => _updateCartItem(newQuantity: 1),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: _accentColor,
                                side: const BorderSide(color: _accentColor),
                                elevation: 0,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: Text("ADD", style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          )
                        : Container(
                            height: 32,
                            decoration: BoxDecoration(
                              color: _accentColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                InkWell(
                                  onTap: () => _updateCartItem(newQuantity: quantity - 1),
                                  child: const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.remove, size: 14, color: Colors.white)),
                                ),
                                Text('$quantity', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                InkWell(
                                  onTap: () {
                                    if (quantity < stock) {
                                      _updateCartItem(newQuantity: quantity + 1);
                                    } else {
                                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Only limited stock available")));
                                    }
                                  },
                                  child: const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.add, size: 14, color: Colors.white)),
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
  int quantity = 0;
  static const Color _accentColor = Color(0xFF00C853);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadState();
    });
  }

  void _loadState() {
    final cart = Provider.of<InstahubCartProvider>(context, listen: false);
    final itemId = widget.item["id"] ?? widget.item["name"];
    final cartItem = cart.getItem(itemId);
    if (cartItem != null && mounted) {
      setState(() { quantity = cartItem.quantity; });
    }
  }

  void _update(int newQty) {
    final cart = Provider.of<InstahubCartProvider>(context, listen: false);
    final itemId = widget.item["id"] ?? widget.item["name"];
    final price = (widget.item["offerPrice"] ?? widget.item["price"] ?? 0.0).toDouble();

    setState(() { quantity = newQty; });

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

    return quantity == 0
        ? OutlinedButton(
            onPressed: () => _update(1),
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
                InkWell(onTap: () => _update(quantity - 1), child: const Icon(Icons.remove, size: 14, color: Colors.white)),
                Text('$quantity', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                InkWell(
                  onTap: () {
                    if (quantity < stock) {
                       _update(quantity + 1);
                    }
                  }, 
                  child: const Icon(Icons.add, size: 14, color: Colors.white)
                ),
              ],
            ),
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