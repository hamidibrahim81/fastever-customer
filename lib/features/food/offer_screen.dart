import 'dart:async';

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

const Color _brandColor = Color(0xFF1A1E43);
const Color _backgroundColor = Color(0xFFF8F8F8);

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

  const OfferScreen({
    super.key,
    required this.title,
    required this.offerTag,
  });

  @override
  State<OfferScreen> createState() => _OfferScreenState();
}

class _OfferScreenState extends State<OfferScreen> {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _offerStream;
  Timer? _loadingWatchdog;
  bool _loadingTimedOut = false;
  int _visibleCount = 25;
  static const int _pageSize = 25;

  @override
  void initState() {
    super.initState();
    _initializeStream();
  }

  void _initializeStream() {
    _loadingWatchdog?.cancel();
    _loadingTimedOut = false;
    _visibleCount = _pageSize;
    _loadingWatchdog = Timer(const Duration(seconds: 18), () {
      if (mounted) setState(() => _loadingTimedOut = true);
    });
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
  void dispose() {
    _loadingWatchdog?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
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
          child: Container(
            color: const Color(0xFFEEEEEE),
            height: 1,
          ),
        ),
      ),
      bottomNavigationBar: const ActiveOrderBottomBar(),
      body: SafeArea(
        top: false,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _offerStream,
          builder: (context, snapshot) {
            // Always handle errors before loading.
            if (snapshot.hasError) {
              _loadingWatchdog?.cancel();
              debugPrint(
                'FASTever OFFER FIRESTORE ERROR: ${snapshot.error}',
              );

              return _buildErrorState();
            }

            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return _loadingTimedOut
                  ? _buildErrorState()
                  : _buildLoadingState();
            }

            if (snapshot.hasData) _loadingWatchdog?.cancel();

            if (snapshot.connectionState == ConnectionState.none) {
              return _buildErrorState();
            }

            final documents = snapshot.data?.docs ?? [];

            if (documents.isEmpty) {
              return _buildEmptyState();
            }

            final visibleCount = documents.length < _visibleCount
                ? documents.length
                : _visibleCount;

            return Stack(
              children: [
                Positioned.fill(
                  child: ListView.builder(
                    key: PageStorageKey(
                      'fastever_offers_${widget.offerTag}',
                    ),
                    padding: const EdgeInsets.fromLTRB(
                      0,
                      8,
                      0,
                      110,
                    ),
                    itemCount: visibleCount +
                        (visibleCount < documents.length ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == visibleCount) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                          child: OutlinedButton(
                            onPressed: () => setState(() {
                              _visibleCount += _pageSize;
                            }),
                            child: const Text('Load More Offers'),
                          ),
                        );
                      }
                      final document = documents[index];

                      return _OfferItemCard(
                        key: ValueKey(document.reference.path),
                        itemDoc: document,
                      );
                    },
                  ),
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
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: 5,
      padding: const EdgeInsets.only(
        bottom: 100,
        top: 8,
      ),
      itemBuilder: (context, index) {
        return _buildShimmerItemCard();
      },
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            const Text(
              'Unable to load offers',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _brandColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Please check your internet connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _initializeStream();
                });
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_offer_outlined,
              size: 55,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            const Text(
              'No offers found.',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerItemCard() {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF0F0F0),
        ),
      ),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade200,
        highlightColor: Colors.grey.shade50,
        child: Row(
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
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
                  Container(
                    width: 100,
                    height: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 80,
                    height: 14,
                    color: Colors.white,
                  ),
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

  const _OfferItemCard({
    super.key,
    required this.itemDoc,
  });

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

  CartProvider? _cartProvider;

  Timer? _offerTimer;

  bool _timerEnabled = false;

  DateTime? _offerStartAt;
  DateTime? _offerEndAt;

  Duration _timeRemaining = Duration.zero;

  String _timerStatus = '';
  String? _timerDescription;

  int _restaurantRequestVersion = 0;

  bool get _offerIsWaiting =>
      _timerEnabled && _timerStatus == 'starts';

  bool get _offerIsActive =>
      _timerEnabled && _timerStatus == 'active';

  bool get _offerIsEnded =>
      _timerEnabled && _timerStatus == 'ended';

  String get _restaurantId =>
      widget.itemDoc.reference.parent.parent?.id ?? '';

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _loadItemData();
    _fetchRestaurantInfo();
  }

  // ==========================================================
  // PROVIDER
  // ==========================================================

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final newProvider = Provider.of<CartProvider>(
      context,
      listen: false,
    );

    if (!identical(_cartProvider, newProvider)) {
      _cartProvider?.removeListener(_updateQuantityFromCart);

      _cartProvider = newProvider;

      _cartProvider?.addListener(_updateQuantityFromCart);
    }

    _syncCartQuantity();
  }

  void _syncCartQuantity() {
    final cart = _cartProvider;

    if (cart == null) return;

    quantity = cart.getQuantity(widget.itemDoc.id);
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
  // WIDGET UPDATE
  // ==========================================================

  @override
  void didUpdateWidget(covariant _OfferItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldPath = oldWidget.itemDoc.reference.path;
    final newPath = widget.itemDoc.reference.path;

    if (oldPath != newPath) {
      _restaurantRequestVersion++;

      restaurantName = null;
      restaurantRating = null;
      status = 'open';

      _loadItemData();
      _fetchRestaurantInfo();
      _syncCartQuantity();
    } else if (oldWidget.itemDoc.data() != widget.itemDoc.data()) {
      _loadItemData();
    }
  }

  void _loadItemData() {
    try {
      itemData = widget.itemDoc.data() ?? {};

      imageUrl = itemData['imageUrl']?.toString().trim() ?? '';

      isAvailable = parseInt(
            itemData['stock'],
            defaultValue: 0,
          ) >
          0;

      _setupOfferTimer();
    } catch (e, stack) {
      debugPrint('FASTever offer item data error: $e');
      debugPrintStack(stackTrace: stack);

      itemData = {};
      imageUrl = '';
      isAvailable = false;
    }
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

    _cartProvider?.removeListener(_updateQuantityFromCart);
    _cartProvider = null;

    super.dispose();
  }

  // ==========================================================
  // OFFER TIMER
  // ==========================================================

  void _setupOfferTimer() {
    _offerTimer?.cancel();
    _offerTimer = null;

    _timerEnabled = itemData['offerTimerEnabled'] == true;

    _timerDescription =
        itemData['offerTimerDescription']?.toString();

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

    if (_offerStartAt != null &&
        now.isBefore(_offerStartAt!)) {
      _timerStatus = 'starts';
      _timeRemaining = _offerStartAt!.difference(now);
      return;
    }

    if (_offerEndAt != null &&
        now.isBefore(_offerEndAt!)) {
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
    final oldRemaining = _timeRemaining.inSeconds;

    _calculateTimerState();

    if (_timerStatus != oldStatus ||
        _timeRemaining.inSeconds != oldRemaining) {
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
    final safe = duration.isNegative ? Duration.zero : duration;

    final hours = safe.inHours;
    final minutes = safe.inMinutes.remainder(60);
    final seconds = safe.inSeconds.remainder(60);

    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$mm:$ss';
    }

    return '$mm:$ss';
  }

  // ==========================================================
  // RESTAURANT INFORMATION
  // ==========================================================

  Future<void> _fetchRestaurantInfo() async {
    final requestVersion = ++_restaurantRequestVersion;

    final restaurantRef =
        widget.itemDoc.reference.parent.parent;

    if (restaurantRef == null) return;

    try {
      final snapshot = await restaurantRef.get();

      if (!mounted ||
          requestVersion != _restaurantRequestVersion) {
        return;
      }

      final data = snapshot.data() ?? {};

      setState(() {
        restaurantName =
            data['name']?.toString() ?? 'Unknown Restaurant';

        restaurantRating = parseDouble(data['rating']);

        status = data['status']?.toString() ?? 'open';
      });
    } catch (e, stack) {
      debugPrint('FASTever restaurant information error: $e');
      debugPrintStack(stackTrace: stack);

      // Do not crash or hide the food item if restaurant
      // information cannot be retrieved.
    }
  }

  // ==========================================================
  // CART OPERATIONS
  // ==========================================================

  void _changeQuantity(int newQuantity) {
    if (!mounted) return;

    if (!requireLoginGlobal(
      'Please login to add items to cart',
    )) {
      return;
    }

    if (newQuantity < 0) return;

    if (!isAvailable || _offerIsWaiting || _offerIsEnded) {
      return;
    }

    final stockAvailable = parseInt(
      itemData['stock'],
      defaultValue: 0,
    );

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
  // QUANTITY SELECTOR
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
              color: Colors.black.withValues(alpha: 0.1),
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
                child: Icon(
                  Icons.remove,
                  size: 16,
                  color: Colors.white,
                ),
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
                child: Icon(
                  Icons.add,
                  size: 16,
                  color: Colors.white,
                ),
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
  // TIMER OVERLAY
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
          color: Colors.white.withValues(alpha: 0.58),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFFF4848),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
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
  // FOOD IMAGE
  // ==========================================================

  Widget _buildFoodImage() {
    return Stack(
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
            child: imageUrl.isEmpty
                ? _buildImageFallback()
                : CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: 90,
                    height: 90,
                    fit: BoxFit.cover,
                    memCacheWidth: 270,
                    memCacheHeight: 270,
                    maxWidthDiskCache: 540,
                    maxHeightDiskCache: 540,
                    fadeInDuration: const Duration(
                      milliseconds: 120,
                    ),
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
                      debugPrint(
                        'FASTever offer image error: $error',
                      );
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
      child: const Icon(
        Icons.fastfood,
        size: 40,
        color: Colors.grey,
      ),
    );
  }

  // ==========================================================
  // OFFER CARD UI
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
                          restaurantRating! > 0) ...[
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
                      '\u20B9${parseDouble(itemData['price']).toStringAsFixed(0)}',
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
                          border: Border.all(
                            color: Colors.red.shade200,
                          ),
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
      margin: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
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
        border: Border.all(
          color: const Color(0xFFF0F0F0),
        ),
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
                  builder: (_) => RestaurantMenuScreen(
                    restaurantId: _restaurantId,
                  ),
                ),
              );
            },
            child: content,
          ),
          if (shouldBlur) _buildOfferTimerOverlay(),
        ],
      ),
    );
  }
}

// ============================================================
// EXPANDABLE ITEM DESCRIPTION
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
  void didUpdateWidget(
    covariant _ExpandableItemDescription oldWidget,
  ) {
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
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              20,
              16,
              20,
              20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
          text: TextSpan(
            text: widget.text,
            style: textStyle,
          ),
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
        );

        textPainter.layout(
          maxWidth: constraints.maxWidth,
        );

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
