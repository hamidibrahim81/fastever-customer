import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;

/// Helper to safely parse a dynamic value to a double.
double _parseDouble(dynamic value, {double defaultValue = 0.0}) {
  if (value is String) return double.tryParse(value) ?? defaultValue;
  if (value is num) return value.toDouble();
  return defaultValue;
}

/// Calculates the delivery fee based on the distance.
double _getSlabDeliveryFee(double distanceKm) {
  if (distanceKm <= 3) return 20;
  if (distanceKm <= 4) return 27;
  if (distanceKm <= 5) return 34;
  if (distanceKm <= 6) return 41;
  if (distanceKm <= 7) return 49;
  if (distanceKm <= 8) return 56;
  if (distanceKm <= 9) return 63;
  if (distanceKm <= 10) return 70;
  return 0; // Outside service area
}

/// Finds the distance to the nearest Instahub store that has a specific item.
Future<double> _findNearestStoreDistance(
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
      final storeLat = _parseDouble(data['latitude']);
      final storeLon = _parseDouble(data['longitude']);

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
    debugPrint('Error finding nearest store: $e');
    return double.infinity;
  }
}

/// Calculates the total delivery fee based on the single farthest location.
Future<double> calculateDeliveryFee({
  required Position userPos,
  required List<Map<String, dynamic>> cartItems,
}) async {
  double maxDistanceKm = 0.0;
  final firestore = FirebaseFirestore.instance;

  for (var item in cartItems) {
    double distanceKm = 0.0;
    final restaurantId = item['restaurantId'] as String;

    if (restaurantId == 'instahub') {
      distanceKm = await _findNearestStoreDistance(item['id'], userPos);
    } else {
      final restaurantDoc = await firestore
          .collection('restaurants')
          .doc(restaurantId)
          .get();
      final rdata = restaurantDoc.data();
      if (rdata != null) {
        final rlat = _parseDouble(rdata['latitude']);
        final rlon = _parseDouble(rdata['longitude']);
        distanceKm = Geolocator.distanceBetween(
              userPos.latitude,
              userPos.longitude,
              rlat,
              rlon,
            ) /
            1000.0;
      }
    }
    if (distanceKm != double.infinity && distanceKm > maxDistanceKm) {
      maxDistanceKm = distanceKm;
    }
  }

  final double deliveryFee = _getSlabDeliveryFee(maxDistanceKm);
  const double platformFee = 15.0;

  return deliveryFee + platformFee;
}