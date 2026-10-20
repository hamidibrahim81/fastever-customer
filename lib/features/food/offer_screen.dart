import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

import 'package:fastevergo_v1/utils/auth_guards.dart';

import 'cart/cart_provider.dart';
import 'RestaurantMenuScreen.dart';
import 'cart/cart_bar.dart';
import 'active_order_bottom_bar.dart';

// ============================================================
// FASTever - OFFER SCREEN
// Stable cart listeners, optimized images, scheduled offers
// ============================================================

const Color _brandColor = Color(0xFF1A1E43);

double parseDouble(dynamic value, {double defaultValue = 0.0}) {
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.trim()) ?? defaultValue;
  }
  return defaultValue;
}

int parseInt(dynamic value, {int defaultValue = 0}) {
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value.trim()) ?? defaultValue;
  }
  return defaultValue;
}

// ============================================================
// OFFER SCREEN
// ============================================================

class OfferScreen extends StatefulWidget {
  final String title;
  final String offerTag;

  const OfferScreen({super.key, required this.title, required this.offerTag});

  @override
  State<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends State<OfferScreen> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _offerStream;

  @override
  void initState() {
    super.initState();
    _initializeStream();
  }

  void _initializeStream() {
    _offerStream = FirebaseFirestore.instance
        .collectionGroup('menu')
        .where('tags', arrayContains: widget.offerTag)
        .snapshots();
  }

  @override
  void didUpdateWidget(covariant OfferScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.offerTag != widget.offerTag) {
      _initializeStream();
    }
  }

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
            color: _brandColor,
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: _brandColor),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFEEEEEE), height: 1),
        ),
      ),
      bottomNavigationBar: const ActiveOrderBottomBar(),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _offerStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return ListView.builder(
              itemCount: 5,
              padding: const EdgeInsets.only(bottom: 100, top: 8),
              itemBuilder: (context, index) {
                return _buildShimmerItemCard();
              },
            );
          }

          if (snapshot.hasError) {
            debugPrint('FASTever offers Firestore error: ${snapshot.error}');

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

          final offerItems = snapshot.data?.docs ?? [];

          if (offerItems.isEmpty) {
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

          return Stack(
            children: [
              ListView.builder(
                key: PageStorageKey('fastever_offers_${widget.offerTag}'),
                itemCount: offerItems.length,

                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemBuilder: (context, index) {
                  final itemDoc = offerItems[index];

                  return _OfferItemCard(
                    key: ValueKey(itemDoc.reference.path),
                    itemDoc: itemDoc,
                  );
                },
              ),
              const Positioned(bottom: 0, left: 0, right: 0, child: CartBar()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildShimmerItemCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
}

// ============================================================
// OFFER ITEM CARD
// ============================================================

class _OfferItemCard extends StatefulWidget {
  final DocumentSnapshot<Map<String, dynamic>> itemDoc;

  const _OfferItemCard({super.key, required this.itemDoc});

  @override
  State<_OfferItemCard> createState() => _OfferItemCardState();
}

class _OfferItemCardState extends State<_OfferItemCard>
    with WidgetsBindingObserver {
  Map<String, dynamic> itemData = {};

  String imageUrl = '';
  int quantity = 0;

  String? restaurantName;
  double? restaurantRating;

  bool isAvailable = false;
  String status = 'open';

  // Cart provider retained while widget is active.
  CartProvider? _cartProvider;

  // Scheduled offer timer state.
  Timer? _offerTimer;

  bool _timerEnabled = false;
  DateTime? _offerStartAt;
  DateTime? _offerEndAt;

  Duration _timeRemaining = Duration.zero;
  String _timerStatus = '';
  String? _timerDescription;

  // Prevent stale async restaurant requests.
  int _restaurantRequestVersion = 0;

  bool get _offerIsWaiting => _timerEnabled && _timerStatus == 'starts';

  bool get _offerIsActive => _timerEnabled && _timerStatus == 'active';

  bool get _offerIsEnded => _timerEnabled && _timerStatus == 'ended';

  String get _restaurantId => widget.itemDoc.reference.parent.parent?.id ?? '';

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _loadItemData();
    _fetchRestaurantInfo();
  }

  // ==========================================================
  // SAFE PROVIDER LIFECYCLE
  // ==========================================================

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final newCartProvider = Provider.of<CartProvider>(context, listen: false);

    if (!identical(_cartProvider, newCartProvider)) {
      _cartProvider?.removeListener(_updateQuantityFromCart);

      _cartProvider = newCartProvider;

      _cartProvider?.addListener(_updateQuantityFromCart);
    }

    _syncCartQuantity();
  }

  void _syncCartQuantity() {
    final cart = _cartProvider;

    if (cart == null) return;

    final newQuantity = cart.getQuantity(widget.itemDoc.id);

    if (newQuantity != quantity) {
      quantity = newQuantity;
    }
  }

  void _updateQuantityFromCart() {
    if (!mounted) return;

    final cart = _cartProvider;

    if (cart == null) return;

    final newQuantity = cart.getQuantity(widget.itemDoc.id);

    if (newQuantity != quantity) {
      setState(() {
        quantity = newQuantity;
      });
    }
  }

  // ==========================================================
  // FIRESTORE ITEM UPDATES
  // ==========================================================

  @override
  void didUpdateWidget(covariant _OfferItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldPath = oldWidget.itemDoc.reference.path;
    final newPath = widget.itemDoc.reference.path;

    final itemChanged = oldPath != newPath;

    if (oldWidget.itemDoc != widget.itemDoc) {
      _loadItemData();

      if (itemChanged) {
        restaurantName = null;
        restaurantRating = null;
        status = 'open';

        _fetchRestaurantInfo();
      }

      _syncCartQuantity();
    }
  }

  void _loadItemData() {
    itemData = widget.itemDoc.data() ?? {};

    imageUrl = itemData['imageUrl']?.toString() ?? '';

    isAvailable = parseInt(itemData['stock'], defaultValue: 0) > 0;

    _setupOfferTimer();
  }

  // ==========================================================
  // APP LIFECYCLE
  // ==========================================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    if (state == AppLifecycleState.resumed) {
      _refreshOfferTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _restaurantRequestVersion++;

    _offerTimer?.cancel();
    _offerTimer = null;

    // IMPORTANT:
    // Never look up Provider through context inside dispose().
    _cartProvider?.removeListener(_updateQuantityFromCart);

    _cartProvider = null;

    super.dispose();
  }

  // ==========================================================
  // SCHEDULED OFFER TIMER
  // ==========================================================

  void _setupOfferTimer() {
    _offerTimer?.cancel();
    _offerTimer = null;

    _timerEnabled = itemData['offerTimerEnabled'] == true;

    _timerDescription = itemData['offerTimerDescription']?.toString();

    _offerStartAt = null;
    _offerEndAt = null;

    _timeRemaining = Duration.zero;
    _timerStatus = '';

    if (!_timerEnabled) return;

    final startValue = itemData['offerStartAt'];
    final endValue = itemData['offerEndAt'];

    if (startValue is Timestamp) {
      _offerStartAt = startValue.toDate();
    } else if (startValue is DateTime) {
      _offerStartAt = startValue;
    }

    if (endValue is Timestamp) {
      _offerEndAt = endValue.toDate();
    } else if (endValue is DateTime) {
      _offerEndAt = endValue;
    }

    if (_offerStartAt == null ||
        _offerEndAt == null ||
        !_offerEndAt!.isAfter(_offerStartAt!)) {
      _timerEnabled = false;
      return;
    }

    // Calculate initial state without calling setState
    // during initState or didUpdateWidget.
    _calculateTimerState();

    if (_timerStatus != 'ended') {
      _offerTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _updateOfferTimer(),
      );
    }
  }

  void _calculateTimerState() {
    if (!_timerEnabled) return;

    final now = DateTime.now();

    if (_offerStartAt != null && now.isBefore(_offerStartAt!)) {
      _timerStatus = 'starts';
      _timeRemaining = _offerStartAt!.difference(now);
      return;
    }

    if (_offerEndAt != null && now.isBefore(_offerEndAt!)) {
      _timerStatus = 'active';
      _timeRemaining = _offerEndAt!.difference(now);
      return;
    }

    _timerStatus = 'ended';
    _timeRemaining = Duration.zero;
  }

  void _updateOfferTimer() {
    if (!mounted || !_timerEnabled) return;

    final oldStatus = _timerStatus;
    final oldRemainingSeconds = _timeRemaining.inSeconds;

    _calculateTimerState();

    if (_timerStatus != oldStatus ||
        _timeRemaining.inSeconds != oldRemainingSeconds) {
      setState(() {});
    }

    if (_timerStatus == 'ended') {
      _offerTimer?.cancel();
      _offerTimer = null;
    }
  }

  void _refreshOfferTimer() {
    if (!_timerEnabled) return;

    _updateOfferTimer();

    if (_timerStatus != 'ended' && _offerTimer == null) {
      _offerTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _updateOfferTimer(),
      );
    }
  }

  String _formatDuration(Duration duration) {
    final safeDuration = duration.isNegative ? Duration.zero : duration;

    final hours = safeDuration.inHours;
    final minutes = safeDuration.inMinutes.remainder(60);
    final seconds = safeDuration.inSeconds.remainder(60);

    final minuteText = minutes.toString().padLeft(2, '0');
    final secondText = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '$minuteText:$secondText';
    }

    return '$minuteText:$secondText';
  }

  // ==========================================================
  // RESTAURANT DETAILS
  // ==========================================================

  Future<void> _fetchRestaurantInfo() async {
    final requestVersion = ++_restaurantRequestVersion;

    final restaurantDocRef = widget.itemDoc.reference.parent.parent;

    if (restaurantDocRef == null) return;

    try {
      final restaurantSnapshot = await restaurantDocRef.get();

      if (!mounted || requestVersion != _restaurantRequestVersion) {
        return;
      }

      final restaurantData = restaurantSnapshot.data() ?? {};

      setState(() {
        restaurantName =
            restaurantData['name']?.toString() ?? 'Unknown Restaurant';

        restaurantRating = parseDouble(restaurantData['rating']);

        status = restaurantData['status']?.toString() ?? 'open';
      });
    } catch (e) {
      debugPrint('FASTever restaurant information error: $e');
    }
  }

  // ==========================================================
  // CART OPERATIONS
  // ==========================================================

  void _changeQuantity(int newQuantity) {
    if (!mounted) return;

    if (!requireLoginGlobal('Please login to add items to cart')) {
      return;
    }

    if (newQuantity < 0) return;

    if (!isAvailable || _offerIsWaiting || _offerIsEnded) {
      return;
    }

    final stockAvailable = parseInt(itemData['stock'], defaultValue: 0);

    if (newQuantity > stockAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Only $stockAvailable left in stock!'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final cart = _cartProvider;

    if (cart == null) return;

    final itemId = widget.itemDoc.id;
    final price = parseDouble(itemData['price']);

    if (newQuantity == 0) {
      cart.removeItem(itemId);
    } else {
      cart.updateItem(
        id: itemId,
        name: itemData['name']?.toString() ?? 'Unknown',
        price: price,
        restaurantId: _restaurantId,
        image: imageUrl,
        qty: newQuantity,
        isInstaHub: itemData['isInstaHub'] == true,
      );
    }
  }

  // ==========================================================
  // ADD / REMOVE QUANTITY CONTROLS
  // ==========================================================

  Widget _buildQuantitySelector() {
    if (!isAvailable || _offerIsWaiting || _offerIsEnded) {
      return const SizedBox.shrink();
    }

    if (quantity > 0) {
      return Container(
        height: 36,
        width: 100,
        decoration: BoxDecoration(
          color: _brandColor,
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
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.remove, size: 16, color: Colors.white),
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
              onTap: () => _changeQuantity(quantity + 1),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.add, size: 16, color: Colors.white),
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
        onPressed: () => _changeQuantity(1),
        style: ElevatedButton.styleFrom(
          backgroundColor: _brandColor,
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

  // ==========================================================
  // OFFER COUNTDOWN OVERLAY
  // ==========================================================

  Widget _buildOfferTimerOverlay() {
    if (!_timerEnabled || _offerIsActive) {
      return const SizedBox.shrink();
    }

    final ended = _offerIsEnded;

    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: Colors.white.withOpacity(0.58),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
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

  // ==========================================================
  // FOOD IMAGE - MEMORY OPTIMIZED
  // ==========================================================

  Widget _buildFoodImage() {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColorFiltered(
            colorFilter: isAvailable
                ? const ColorFilter.mode(Colors.transparent, BlendMode.multiply)
                : const ColorFilter.mode(Colors.grey, BlendMode.saturation),
            child: imageUrl.isEmpty
                ? _buildImageFallback()
                : CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: 90,
                    height: 90,
                    fit: BoxFit.cover,

                    // Decode near the actual display size
                    // rather than keeping full-resolution images.
                    memCacheWidth: 270,
                    memCacheHeight: 270,
                    maxWidthDiskCache: 540,
                    maxHeightDiskCache: 540,

                    fadeInDuration: const Duration(milliseconds: 120),
                    fadeOutDuration: Duration.zero,

                    placeholder: (context, url) {
                      return Container(
                        width: 90,
                        height: 90,
                        color: Colors.grey.shade100,
                        child: const Center(
                          child: Icon(
                            Icons.fastfood_outlined,
                            size: 25,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    },
                    errorWidget: (context, url, error) {
                      return _buildImageFallback();
                    },
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
                  'SOLD OUT',
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
    );
  }

  Widget _buildImageFallback() {
    return Container(
      width: 90,
      height: 90,
      color: Colors.grey.shade100,
      child: const Icon(Icons.fastfood, size: 40, color: Colors.grey),
    );
  }

  // ==========================================================
  // OFFER CARD MAIN UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    if (status.toLowerCase() == 'closed') {
      return const SizedBox.shrink();
    }

    final itemName = itemData['name']?.toString() ?? 'N/A';

    final description = itemData['description']?.toString();

    final shouldBlur = _offerIsWaiting || _offerIsEnded;

    final content = Padding(
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
                    color: isAvailable ? _brandColor : Colors.grey,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),

                // Restaurant name and rating
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
                      if (restaurantRating != null && restaurantRating! > 0)
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
                  itemData['isVeg'] == true ? 'Veg' : 'Non-Veg',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: itemData['isVeg'] == true
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                ),

                const SizedBox(height: 6),

                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      '₹${parseDouble(itemData['price']).toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                    if (_offerIsActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 11,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'Ends in ${_formatDuration(_timeRemaining)}',
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
                ),

                if (description != null && description.trim().isNotEmpty) ...[
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
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFoodImage(),
              const SizedBox(height: 8),
              _buildQuantitySelector(),
            ],
          ),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
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
              if (_restaurantId.isEmpty) return;

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      RestaurantMenuScreen(restaurantId: _restaurantId),
                ),
              );
            },
            child: shouldBlur
                ? ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2),
                    child: content,
                  )
                : content,
          ),
          if (shouldBlur) _buildOfferTimerOverlay(),
        ],
      ),
    );
  }
}

// ============================================================
// EXPANDABLE RED DESCRIPTION
// ============================================================

class _ExpandableItemDescription extends StatefulWidget {
  final String text;
  final String? itemName;
  final int maxLines;
  final bool openDialogOnMore;

  const _ExpandableItemDescription({
    super.key,
    required this.text,
    this.itemName,
    this.maxLines = 2,
    this.openDialogOnMore = false,
  });

  @override
  State<_ExpandableItemDescription> createState() =>
      _ExpandableItemDescriptionState();
}

class _ExpandableItemDescriptionState
    extends State<_ExpandableItemDescription> {
  bool _isExpanded = false;

  @override
  void didUpdateWidget(covariant _ExpandableItemDescription oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.text != widget.text) {
      _isExpanded = false;
    }
  }

  void _showFullDescriptionModal(BuildContext context) {
    final itemName = widget.itemName ?? 'Description';
    final description = widget.text;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
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
                        itemName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _brandColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(
                        Icons.close,
                        size: 20,
                        color: Colors.grey,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Text(
                  description,
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
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final textStyle = TextStyle(
          fontSize: 10.5,
          color: Colors.red.shade700,
          height: 1.2,
          fontWeight: FontWeight.w500,
        );

        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: textStyle),
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);

        final isOverflowing = textPainter.didExceedMaxLines;

        textPainter.dispose();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.text,
              style: textStyle,
              maxLines: _isExpanded ? null : widget.maxLines,
              overflow: _isExpanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
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
                  _isExpanded ? 'View Less' : 'View More',
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
