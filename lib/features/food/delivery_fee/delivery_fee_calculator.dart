// lib/utils/delivery_fee_calculator.dart

double calculateDeliveryFee(double distanceKm) {
  const double platformFee = 15.0;

  double deliveryFee;

  if (distanceKm <= 3) {
    deliveryFee = 20;
  } else if (distanceKm <= 4) {
    deliveryFee = 27;
  } else if (distanceKm <= 5) {
    deliveryFee = 34;
  } else if (distanceKm <= 6) {
    deliveryFee = 41;
  } else if (distanceKm <= 7) {
    deliveryFee = 49;
  } else if (distanceKm <= 8) {
    deliveryFee = 56;
  } else if (distanceKm <= 9) {
    deliveryFee = 63;
  } else if (distanceKm <= 10) {
    deliveryFee = 70;
  } else {
    // Optional: if user is out of 10km service area, charge max or return 0
    deliveryFee = 70;
  }

  return deliveryFee + platformFee;
}
