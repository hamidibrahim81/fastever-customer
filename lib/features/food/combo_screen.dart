import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:provider/provider.dart';

// ✅ IMPORT AUTH GUARD
import 'package:fastevergo_v1/utils/auth_guards.dart';
import '../food/cart/cart_provider.dart';
import '../food/cart/cart_bar.dart';
import 'active_order_bottom_bar.dart';

/// ------------------------------
/// Helper Parsers
/// ------------------------------
double parseDouble(dynamic value, {double defaultValue = 0.0}) {
  if (value is String) return double.tryParse(value) ?? defaultValue;
  if (value is num) return value.toDouble();
  return defaultValue;
}

int parseInt(dynamic value, {int defaultValue = 0}) {
  if (value is String) return int.tryParse(value) ?? defaultValue;
  if (value is num) return value.toInt();
  return defaultValue;
}

class ComboScreen extends StatefulWidget {
  const ComboScreen({super.key});

  @override
  State<ComboScreen> createState() => _ComboScreenState();
}

class _ComboScreenState extends State<ComboScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    // ✅ Setup background animation loop for pulsing card outlines
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double cartBarHeightPadding = 110.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        title: const Text(
          "MEGA COMBO DEALS",
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Color(0xFF1A1E43),
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1A1E43)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: const Color(0xFFEEEEEE),
            height: 1,
          ),
        ),
      ),
      bottomNavigationBar: const ActiveOrderBottomBar(),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collectionGroup('menu')
                .where('tags', arrayContains: 'combo_deals')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return ListView.builder(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 12,
                    bottom: cartBarHeightPadding,
                  ),
                  itemCount: 5,
                  itemBuilder: (context, index) => const ComboShimmerCard(),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.local_offer_outlined,
                          size: 72,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "No Active Combos Available",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1E43),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Check back later for exclusive multi-item savings!",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final comboDeals = snapshot.data!.docs;

              return ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: cartBarHeightPadding,
                ),
                itemCount: comboDeals.length,
                itemBuilder: (context, index) {
                  final doc = comboDeals[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final id = doc.id;

                  final String imageUrl = data['imageUrl'] ?? '';
                  final String comboName = data['name'] ?? 'Combo Deal';
                  final String restaurantName =
                      data['restaurantName'] ?? 'Unknown Restaurant';

                  final double price = parseDouble(data['price']);
                  // ✅ Read 'mrp' field directly from database setup
                  final double mrp = parseDouble(
                    data['mrp'] ?? data['promoOfferPrice'] ?? price,
                  );

                  final String restaurantId =
                      data['restaurantId'] ??
                      doc.reference.parent.parent?.id ??
                      '';
                  final int stockAvailable =
                      parseInt(data['stock'], defaultValue: 0);
                  final String offerPriority = data['offerPriority'] ?? 'low';
                  final String? description = data['description']?.toString();

                  return AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return ComboCard(
                        id: id,
                        imageUrl: imageUrl,
                        comboName: comboName,
                        restaurantName: restaurantName,
                        price: price,
                        mrp: mrp,
                        restaurantId: restaurantId,
                        stockAvailable: stockAvailable,
                        isInstaHub: data['isInstaHub'] == true,
                        offerPriority: offerPriority,
                        description: description,
                        pulseValue: _pulseAnimation.value,
                      );
                    },
                  );
                },
              );
            },
          ),

          /// 🛒 Bottom Cart Bar
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: CartBar(),
          ),
        ],
      ),
    );
  }
}

class ComboCard extends StatelessWidget {
  final String id;
  final String imageUrl;
  final String comboName;
  final String restaurantName;
  final String restaurantId;
  final double price;
  final double mrp;
  final int stockAvailable;
  final bool isInstaHub;
  final String offerPriority;
  final String? description;
  final double pulseValue;

  const ComboCard({
    super.key,
    required this.id,
    required this.imageUrl,
    required this.comboName,
    required this.restaurantName,
    required this.price,
    required this.mrp,
    required this.restaurantId,
    required this.stockAvailable,
    required this.isInstaHub,
    required this.offerPriority,
    this.description,
    required this.pulseValue,
  });

  // ✅ Maps priority parameters to target colors smoothly
  Color _getPriorityBlinkColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return const Color(0xFFFF2442).withOpacity(pulseValue);
      case 'medium':
        return const Color(0xFFFFB300).withOpacity(pulseValue);
      case 'low':
      default:
        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasDiscount = mrp > price;

    int discountPercent = 0;
    if (hasDiscount && mrp > 0) {
      discountPercent = (((mrp - price) / mrp) * 100).round();
    }

    final bool isMegaOffer =
        discountPercent >= 50 || offerPriority.toLowerCase() == 'high';
    final Color activeBlinkColor = _getPriorityBlinkColor(offerPriority);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      // ✅ Dynamic pulsing layout wrappers for promotional priorities
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: offerPriority != 'low'
              ? activeBlinkColor
              : (isMegaOffer ? Colors.amber.shade400 : const Color(0xFFF0F0F0)),
          width: (offerPriority != 'low' || isMegaOffer) ? 2.0 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Image Block
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                  child: ColorFiltered(
                    colorFilter: stockAvailable <= 0
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
                      width: 110,
                      height: 110,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Shimmer.fromColors(
                        baseColor: Colors.grey.shade200,
                        highlightColor: Colors.grey.shade50,
                        child: Container(
                          width: 110,
                          height: 110,
                          color: Colors.white,
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 110,
                        height: 110,
                        color: Colors.grey.shade100,
                        child: const Icon(
                          Icons.broken_image,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                ),
                if (discountPercent > 0 && stockAvailable > 0)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        gradient: isMegaOffer
                            ? const LinearGradient(
                                colors: [Color(0xFF1A1E43), Color(0xFF2E7D32)],
                              )
                            : const LinearGradient(
                                colors: [Color(0xFF2E7D32), Color(0xFF388E3C)],
                              ),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        isMegaOffer
                            ? "🔥 $discountPercent% OFF"
                            : "$discountPercent% OFF",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            // Details Block
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comboName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: stockAvailable <= 0
                            ? Colors.grey
                            : const Color(0xFF1A1E43),
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      restaurantName,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (hasDiscount)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              "₹${mrp.toStringAsFixed(0)}",
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.lineThrough,
                                decorationThickness: 1.8,
                              ),
                            ),
                          ),
                        Text(
                          "₹${price.toStringAsFixed(0)}",
                          style: const TextStyle(
                            color: Color(0xFF2E7D32),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),

                    // 🔴 OPTIONAL RED DESCRIPTION
                    if (description != null &&
                        description!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _ExpandableItemDescription(
                        text: description!.trim(),
                        itemName: comboName,
                        maxLines: 2,
                        openDialogOnMore: false,
                      ),
                    ],

                    const SizedBox(height: 8),

                    // Price and Button Layout
                    Align(
                      alignment: Alignment.centerRight,
                      child: Selector<CartProvider, int>(
                        selector: (_, cart) => cart.getQuantity(id),
                        builder: (context, quantity, child) {
                          final cartProvider =
                              Provider.of<CartProvider>(context, listen: false);

                          if (stockAvailable <= 0) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                "SOLD OUT",
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            );
                          }

                          if (quantity > 0) {
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  InkWell(
                                    onTap: () {
                                      if (!requireLoginGlobal(
                                        "Please login to update cart",
                                      )) return;
                                      cartProvider.reduceQuantity(id);
                                    },
                                    child: const Icon(
                                      Icons.remove,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    '$quantity',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () {
                                      if (!requireLoginGlobal(
                                        "Please login to update cart",
                                      )) return;
                                      if (quantity >= stockAvailable) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              "Only $stockAvailable left in stock!",
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      cartProvider.addItem(
                                        id: id,
                                        name: comboName,
                                        price: price,
                                        restaurantId: restaurantId,
                                        image: imageUrl,
                                        isInstaHub: isInstaHub,
                                      );
                                    },
                                    child: const Icon(
                                      Icons.add,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return SizedBox(
                            height: 36,
                            width: 100,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1A1E43),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: () {
                                if (!requireLoginGlobal(
                                  "Please login to add combo deals",
                                )) return;
                                cartProvider.addItem(
                                  id: id,
                                  name: comboName,
                                  price: price,
                                  restaurantId: restaurantId,
                                  image: imageUrl,
                                  isInstaHub: isInstaHub,
                                );
                              },
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
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ComboShimmerCard extends StatelessWidget {
  const ComboShimmerCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
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
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade200,
        highlightColor: Colors.grey.shade50,
        child: Row(
          children: [
            const SizedBox(
              width: 110,
              height: 110,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 16,
                      width: double.infinity,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 8),
                    Container(height: 14, width: 100, color: Colors.white),
                    const SizedBox(height: 8),
                    Container(height: 14, width: 80, color: Colors.white),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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