import 'package:cloud_firestore/cloud_firestore.dart';

class Coupon {
  final String code; // coupon code = document ID
  final String type; // "percentage" or "flat"
  final double value;
  final DateTime startDate;
  final DateTime endDate;
  final bool isActive;

  Coupon({
    required this.code,
    required this.type,
    required this.value,
    required this.startDate,
    required this.endDate,
    required this.isActive,
  });

  factory Coupon.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Coupon(
      code: doc.id, // ✅ use document ID as the coupon code
      type: data['type'] ?? "percentage",
      value: (data['value'] as num).toDouble(),
      startDate: (data['startDate'] as Timestamp).toDate(),
      endDate: (data['endDate'] as Timestamp).toDate(),
      isActive: data['isActive'] ?? true,
    );
  }
}
