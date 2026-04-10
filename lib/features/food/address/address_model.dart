import 'package:cloud_firestore/cloud_firestore.dart' show GeoPoint;
import 'package:flutter/material.dart'; // Often included in Flutter projects, useful for parsing helpers

class Address {
  final String line1;
  final String? line2;
  final String city;
  final String pincode;
  // 📍 CRITICAL FIELDS for delivery calculation
  final double latitude;
  final double longitude;

  Address({
    required this.line1,
    this.line2,
    required this.city,
    required this.pincode,
    required this.latitude,
    required this.longitude,
  });

  // Helper function for safe double parsing, with GeoPoint support
  static double _parseDouble(dynamic value, {double defaultValue = 0.0, bool isLatitude = true}) {
    if (value is GeoPoint) {
      return isLatitude ? value.latitude : value.longitude;
    }
    if (value is String) return double.tryParse(value) ?? defaultValue;
    if (value is num) return value.toDouble();
    return defaultValue;
  }

  /// Converts the Address object to a Map for storage in Firestore.
  Map<String, dynamic> toMap() {
    return {
      'line1': line1,
      'line2': line2,
      'city': city,
      'pincode': pincode,
      // 💾 Storing coordinates as native doubles
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  /// Creates an Address object from a Map (e.g., from Firestore).
  factory Address.fromMap(Map<String, dynamic> map) {
    // Map accessors for coordinates might return a double, String, or GeoPoint.
    final latData = map['latitude'];
    final lonData = map['longitude'];

    return Address(
      line1: map['line1'] ?? '',
      line2: map['line2'],
      city: map['city'] ?? '',
      pincode: map['pincode'] ?? '',
      // 🌍 Safely read new fields
      latitude: _parseDouble(latData, isLatitude: true),
      longitude: _parseDouble(lonData, isLatitude: false),
    );
  }

  @override
  String toString() {
    return 'Address: $line1, ${line2 ?? ''}, $city, $pincode. Coords: ($latitude, $longitude)';
  }
}