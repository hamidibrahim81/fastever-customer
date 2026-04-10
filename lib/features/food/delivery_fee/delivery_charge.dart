// delivery_charge.dart (Corrected structure)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;

// Helper functions (copied from original file for self-contained module)
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

// Data model for the delivery fee structure from Firestore
class DeliveryFeeConfig {
  final double baseFee;
  final double baseKm;
  final double maxDistance;
  final double perKmFee;
  final double platformFee;

  DeliveryFeeConfig({
    required this.baseFee,
    required this.baseKm,
    required this.maxDistance,
    required this.perKmFee,
    required this.platformFee,
  });

  factory DeliveryFeeConfig.fromFirestore(Map<String, dynamic> data) {
    return DeliveryFeeConfig(
      baseFee: parseDouble(data['baseFee']),
      baseKm: parseDouble(data['baseKm']),
      maxDistance: parseDouble(data['maxDistance']),
      perKmFee: parseDouble(data['perKmFee']),
      platformFee: parseDouble(data['platformFee']),
    );
  }
}

// >>> ⚠️ FIX: Move DeliveryChargeResult definition up so it's defined before use 
// Simple class to hold the calculated fees
class DeliveryChargeResult {
  final double deliveryFee;
  final double platformFee;
  final double totalCharge;

  DeliveryChargeResult({
    required this.deliveryFee,
    required this.platformFee,
    this.totalCharge = 0.0,
  });
}
// <<<

// 1. Fetch the delivery fee configuration from Firestore
Future<DeliveryFeeConfig> fetchDeliveryFeeConfig() async {
  final firestore = FirebaseFirestore.instance;
  try {
    // Referencing the structure from your image:
    // Collection: deliveryServices, Document: instahub
    final doc = await firestore
        .collection('deliveryServices')
        .doc('instahub')
        .get();

    if (doc.exists && doc.data() != null) {
      return DeliveryFeeConfig.fromFirestore(doc.data()!);
    }
  } catch (e) {
    // Log error and return a default/fallback configuration
    print('Error fetching delivery fee config: $e');
  }

  // Fallback to the hardcoded values from your Firestore image
  return DeliveryFeeConfig(
    baseFee: 20.0,
    baseKm: 3.0,
    maxDistance: 10.0,
    perKmFee: 8.0,
    platformFee: 15.0,
  );
}

// 2. New calculation method using the Firestore configuration
double calculateDeliveryChargeFromConfig(
    double distanceKm, DeliveryFeeConfig config) {
  if (distanceKm > config.maxDistance) {
    return 0.0; // Outside service area
  }

  double deliveryCharge = 0.0;

  if (distanceKm <= config.baseKm) {
    deliveryCharge = config.baseFee;
  } else {
    // Calculate fee for distance beyond the base distance
    final extraKm = distanceKm - config.baseKm;
    final extraFee = extraKm * config.perKmFee;
    deliveryCharge = config.baseFee + extraFee;
  }

  // Correct method for rounding up a double in Dart
  return deliveryCharge.ceilToDouble();
}

// 3. Method to find nearest Instahub distance (moved from CartScreen.dart)
Future<double> findNearestStoreDistance(
    String itemId, Position userPos) async {
  final firestore = FirebaseFirestore.instance;
  try {
    final instahubStores = await firestore
        .collection('instahubStores')
        .where('items', arrayContains: itemId)
        .get();

    if (instahubStores.docs.isEmpty) {
      return double.infinity;
    }

    double minDistance = double.infinity;
    for (var storeDoc in instahubStores.docs) {
      final data = storeDoc.data();
      final storeLat = parseDouble(data['latitude']);
      final storeLon = parseDouble(data['longitude']);

      if (storeLat != 0 && storeLon != 0) {
        final distance = Geolocator.distanceBetween(
              userPos.latitude,
              userPos.longitude,
              storeLat,
              storeLon,
            ) /
            1000.0; // in km
        minDistance = math.min(minDistance, distance);
      }
    }
    return minDistance;
  } catch (e) {
    print('Error finding nearest store: $e');
    return double.infinity;
  }
}

// 4. Main public function to calculate the total delivery and platform fee
Future<DeliveryChargeResult> calculateTotalDeliveryAndPlatformFee(
    Map<String, dynamic> cartItems, Position? userPos) async {
  
  if (cartItems.isEmpty) {
    return DeliveryChargeResult(deliveryFee: 0.0, platformFee: 0.0);
  }

  // 4a. Fetch configuration
  final config = await fetchDeliveryFeeConfig();
  final firestore = FirebaseFirestore.instance;

  double maxDistanceKm = 0.0;

  // 4b. Find max distance among all items
  for (var item in cartItems.values) {
    double distanceKm = 0.0;
    final restaurantId = item['restaurantId'];
    final itemId = item['id'];

    if (userPos == null) continue; // Cannot calculate distance without position

    if (restaurantId == 'instahub') {
      distanceKm = await findNearestStoreDistance(itemId, userPos);
    } else {
      final restaurantDoc = await firestore
          .collection('restaurants')
          .doc(restaurantId)
          .get();
      final rdata = restaurantDoc.data();
      if (rdata != null) {
        final rlat = parseDouble(rdata['latitude']);
        final rlon = parseDouble(rdata['longitude']);
        distanceKm = Geolocator.distanceBetween(
              userPos.latitude, userPos.longitude, rlat, rlon) /
            1000.0;
      }
    }

    if (distanceKm != double.infinity && distanceKm > maxDistanceKm) {
      maxDistanceKm = distanceKm;
    }
  }

  // 4c. Calculate delivery fee using the new linear model
  final double deliveryCharge =
      calculateDeliveryChargeFromConfig(maxDistanceKm, config);

  // 4d. Return the total result
  return DeliveryChargeResult(
    deliveryFee: deliveryCharge,
    platformFee: config.platformFee,
    totalCharge: deliveryCharge + config.platformFee,
  );
}