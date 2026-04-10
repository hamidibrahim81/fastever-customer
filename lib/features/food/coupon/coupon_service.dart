import 'package:cloud_firestore/cloud_firestore.dart';
import 'coupon_model.dart';

class CouponService {
  final _firestore = FirebaseFirestore.instance;

  /// Validate coupon by its code (document ID)
  Future<Coupon?> validateCoupon(String code) async {
    try {
      final doc = await _firestore.collection("coupons").doc(code).get();

      if (!doc.exists) return null;

      final coupon = Coupon.fromDoc(doc);
      final now = DateTime.now();

      if (!coupon.isActive ||
          now.isBefore(coupon.startDate) ||
          now.isAfter(coupon.endDate)) {
        return null; // expired or inactive
      }

      return coupon;
    } catch (e) {
      print("Error validating coupon: $e");
      return null;
    }
  }
}
