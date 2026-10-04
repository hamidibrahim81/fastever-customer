// offer_screen.dart

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

// ✅ IMPORT AUTH GUARD
import 'package:fastevergo_v1/utils/auth_guards.dart';

import 'cart/cart_provider.dart';
import 'RestaurantMenuScreen.dart';
import 'cart/cart_bar.dart';
import 'active_order_bottom_bar.dart';

// Safe parsers for Firestore types
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

class OfferScreen extends StatefulWidget {
  final String title;
  final String offerTag;

  const OfferScreen({
    super.key,
    required this.title,
    required this.offerTag,
  });

  @override
  State<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends State<OfferScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(
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
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collectionGroup('menu')
            .where('tags', arrayContains: widget.offerTag)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView.builder(
              itemCount: 5,
              padding: const EdgeInsets.only(bottom: 100, top: 8),
              itemBuilder: (context, index) => _buildShimmerItemCard(),
            );
          }
          if (snapshot.hasError) {
            debugPrint("🔥 Firestore Offer Items Error: ${snapshot.error}");
            return const Center(
              child: Text(
                'Error loading offers.',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'No offers found.',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }

          final offerItems = snapshot.data!.docs;

          return Stack(
            children: [
              ListView.builder(
                itemCount: offerItems.length,
                padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 100.0),
                itemBuilder: (context, index) {
                  final itemDoc = offerItems[index];
                  return _OfferItemCard(
                    key: ValueKey(itemDoc.id),
                    itemDoc: itemDoc,
                  );
                },
              ),
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: CartBar(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildShimmerItemCard() => Container(
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
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade200,
          highlightColor: Colors.grey.shade50,
          child: Row(
            children: [
              const SizedBox(
                width: 90,
                height: 90,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 8),
                    Container(width: 100, height: 14, color: Colors.white),
                    const SizedBox(height: 8),
                    Container(width: 80, height: 14, color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _OfferItemCard extends StatefulWidget {
  final DocumentSnapshot itemDoc;

  const _OfferItemCard({
    required this.itemDoc,
    Key? key,
  }) : super(key: key);

  @override
  State<_OfferItemCard> createState() => _OfferItemCardState();
}

class _OfferItemCardState extends State<_OfferItemCard> {
  late Map<String, dynamic> itemData;
  late String imageUrl;
  int quantity = 0;
  String? restaurantName;
  double? restaurantRating;
  late bool isAvailable;
  String status = 'open';

  // Scheduled Timer State
  Timer? _offerTimer;
  bool _timerEnabled = false;
  DateTime? _offerStartAt;
  DateTime? _offerEndAt;
  Duration _timeRemaining = Duration.zero;
  String _timerStatus = ''; // 'starts', 'active', 'ended'
  String? _timerDescription;

  bool get _offerIsWaiting => _timerEnabled && _timerStatus == 'starts';
  bool get _offerIsActive => _timerEnabled && _timerStatus == 'active';
  bool get _offerIsEnded => _timerEnabled && _timerStatus == 'ended';

  @override
  void initState() {
    super.initState();
    itemData = widget.itemDoc.data() as Map<String, dynamic>;
    imageUrl = itemData['imageUrl'] ?? 'https://via.placeholder.com/150';
    isAvailable = parseInt(itemData['stock']) > 0;

    _setupOfferTimer();
    _fetchRestaurantInfo();

    final cart = Provider.of<CartProvider>(context, listen: false);
    cart.addListener(_updateQuantityFromCart);
    quantity = cart.getQuantity(widget.itemDoc.id);
  }

  @override
  void didUpdateWidget(covariant _OfferItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemDoc != widget.itemDoc) {
      itemData = widget.itemDoc.data() as Map<String, dynamic>;
      imageUrl = itemData['imageUrl'] ?? 'https://via.placeholder.com/150';
      isAvailable = parseInt(itemData['stock']) > 0;
      _setupOfferTimer();
    }
  }

  @override
  void dispose() {
    _offerTimer?.cancel();
    Provider.of<CartProvider>(context, listen: false)
        .removeListener(_updateQuantityFromCart);
    super.dispose();
  }

  void _setupOfferTimer() {
    _offerTimer?.cancel();
    _timerEnabled = itemData['offerTimerEnabled'] == true;
    _timerDescription = itemData['offerTimerDescription']?.toString();

    if (!_timerEnabled) {
      _timerStatus = '';
      return;
    }

    final startValue = itemData['offerStartAt'];
    final endValue = itemData['offerEndAt'];

    if (startValue is Timestamp) {
      _offerStartAt = startValue.toDate();
    } else {
      _offerStartAt = null;
    }

    if (endValue is Timestamp) {
      _offerEndAt = endValue.toDate();
    } else {
      _offerEndAt = null;
    }

    if (_offerStartAt == null || _offerEndAt == null) {
      _timerEnabled = false;
      return;
    }

    _updateOfferTimer();

    _offerTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateOfferTimer(),
    );
  }

  void _updateOfferTimer() {
    if (!mounted || !_timerEnabled) return;

    final now = DateTime.now();

    if (_offerStartAt != null && now.isBefore(_offerStartAt!)) {
      setState(() {
        _timerStatus = 'starts';
        _timeRemaining = _offerStartAt!.difference(now);
      });
      return;
    }

    if (_offerEndAt != null && now.isBefore(_offerEndAt!)) {
      setState(() {
        _timerStatus = 'active';
        _timeRemaining = _offerEndAt!.difference(now);
      });
      return;
    }

    setState(() {
      _timerStatus = 'ended';
      _timeRemaining = Duration.zero;
    });

    _offerTimer?.cancel();
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _fetchRestaurantInfo() async {
    try {
      final restaurantDocRef = widget.itemDoc.reference.parent.parent;
      if (restaurantDocRef != null) {
        final restaurantSnapshot = await restaurantDocRef.get();
        final restaurantData =
            restaurantSnapshot.data() as Map<String, dynamic>?;
        if (mounted && restaurantData != null) {
          setState(() {
            restaurantName =
                restaurantData['name']?.toString() ?? 'Unknown Restaurant';
            restaurantRating =
                parseDouble(restaurantData['rating'], defaultValue: 0.0);
            status = restaurantData['status'] ?? 'open';
          });
        }
      }
    } catch (e) {
      debugPrint("🔥 Error fetching restaurant info: $e");
    }
  }

  void _updateQuantityFromCart() {
    final cart = Provider.of<CartProvider>(context, listen: false);
    final newQuantity = cart.getQuantity(widget.itemDoc.id);
    if (newQuantity != quantity) {
      setState(() {
        quantity = newQuantity;
      });
    }
  }

  void _changeQuantity(int newQuantity) {
    if (!requireLoginGlobal("Please login to add items to cart")) return;

    if (newQuantity < 0) return;

    final int stockAvailable = parseInt(itemData['stock'], defaultValue: 0);
    if (newQuantity > stockAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Only $stockAvailable left in stock!"),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final cart = Provider.of<CartProvider>(context, listen: false);
    final itemId = widget.itemDoc.id;
    final restaurantId = widget.itemDoc.reference.parent.parent?.id ?? '';
    final price = parseDouble(itemData['price'], defaultValue: 0.0);

    if (newQuantity == 0) {
      cart.removeItem(itemId);
    } else {
      cart.updateItem(
        id: itemId,
        name: itemData['name'] ?? 'Unknown',
        price: price,
        restaurantId: restaurantId,
        image: imageUrl,
        qty: newQuantity,
        isInstaHub: itemData['isInstaHub'] ?? false,
      );
    }
  }

  Widget _buildQuantitySelector() {
    if (!isAvailable || _offerIsWaiting || _offerIsEnded) {
      return const SizedBox.shrink();
    }

    return quantity > 0
        ? Container(
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
                  onTap: () => _changeQuantity(quantity - 1),
                  child: const Icon(Icons.remove, size: 16, color: Colors.white),
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
                  onTap: () => _changeQuantity(quantity + 1),
                  child: const Icon(Icons.add, size: 16, color: Colors.white),
                ),
              ],
            ),
          )
        : SizedBox(
            height: 36,
            width: 100,
            child: ElevatedButton(
              onPressed: () => _changeQuantity(1),
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
                'ADD',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          );
  }

  Widget _buildOfferTimerOverlay() {
    if (!_timerEnabled || _offerIsActive) {
      return const SizedBox.shrink();
    }

    final bool ended = _offerIsEnded;

    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: Colors.white.withOpacity(0.58),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ended ? 'OFFER ENDED' : 'OFFER STARTS IN',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  if (!ended) ...[
                    const SizedBox(height: 3),
                    Text(
                      _formatDuration(_timeRemaining),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    // 🔴 ONLY shown before start, right under the countdown timer
                    if (_offerIsWaiting &&
                        _timerDescription != null &&
                        _timerDescription!.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        _timerDescription!.trim(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFFF4848),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (status == 'closed') {
      return const SizedBox.shrink();
    }

    final String itemName = itemData['name']?.toString() ?? 'N/A';
    final String? description = itemData['description']?.toString();
    final bool shouldBlur = _offerIsWaiting || _offerIsEnded;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
      child: Stack(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              final restaurantId = widget.itemDoc.reference.parent.parent?.id;
              if (restaurantId != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        RestaurantMenuScreen(restaurantId: restaurantId),
                  ),
                );
              }
            },
            child: ImageFiltered(
              imageFilter: shouldBlur
                  ? ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2)
                  : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            itemName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isAvailable
                                  ? const Color(0xFF1A1E43)
                                  : Colors.grey,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          if (restaurantName != null &&
                              restaurantName!.isNotEmpty &&
                              restaurantName != 'Unknown Restaurant')
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    restaurantName!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (restaurantRating != null &&
                                    restaurantRating! > 0)
                                  Row(
                                    children: [
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.star_rounded,
                                        color: Color(0xFF2E7D32),
                                        size: 14,
                                      ),
                                      Text(
                                        restaurantRating!.toStringAsFixed(1),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF2E7D32),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          const SizedBox(height: 4),
                          Text(
                            (itemData['isVeg'] == true) ? "Veg" : "Non-Veg",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: (itemData['isVeg'] == true)
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                "₹${parseDouble(itemData['price']).toStringAsFixed(0)}",
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF2E7D32),
                                ),
                              ),
                              // Live active countdown indicator (ends in ...)
                              if (_offerIsActive) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border:
                                        Border.all(color: Colors.red.shade200),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.timer_outlined,
                                          size: 11, color: Colors.red.shade700),
                                      const SizedBox(width: 3),
                                      Text(
                                        "Ends in ${_formatDuration(_timeRemaining)}",
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),

                          // Standard Item Description
                          if (description != null &&
                              description.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            _ExpandableItemDescription(
                              text: description.trim(),
                              itemName: itemName,
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
                                colorFilter: isAvailable
                                    ? const ColorFilter.mode(
                                        Colors.transparent,
                                        BlendMode.multiply,
                                      )
                                    : const ColorFilter.mode(
                                        Colors.grey,
                                        BlendMode.saturation,
                                      ),
                                child: CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  width: 90,
                                  height: 90,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) =>
                                      Shimmer.fromColors(
                                    baseColor: Colors.grey.shade200,
                                    highlightColor: Colors.grey.shade50,
                                    child: Container(
                                      width: 90,
                                      height: 90,
                                      color: Colors.white,
                                    ),
                                  ),
                                  errorWidget: (context, url, error) =>
                                      const Icon(
                                    Icons.fastfood,
                                    size: 40,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                            if (!isAvailable)
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
                        _buildQuantitySelector(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildOfferTimerOverlay(),
        ],
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