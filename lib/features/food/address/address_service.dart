import 'package:cloud_firestore/cloud_firestore.dart';
import 'address_model.dart';

class AddressService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> saveAddress(String userId, Address address) async {
    final userDocRef = _db.collection('users').doc(userId);
    
    // ⭐ FIX: Use set with merge: true for reliable saving.
    // This creates the document if it doesn't exist, or safely merges 
    // the 'address' field if it does exist, preventing errors.
    await userDocRef.set({
      'address': address.toMap(),
    }, SetOptions(merge: true));
    
    // address.toMap() now includes latitude and longitude from your updated Address model.
    // This resolves the storage issue.
  }

  Future<Address?> getUserAddress(String userId) async {
    // The retrieval logic remains correct for retrieving the stored Address object
    // (including the new latitude/longitude fields).
    final doc = await _db.collection('users').doc(userId).get();
    if (doc.exists && doc.data()?['address'] != null) {
      // Address.fromMap() will now use the stored lat/lng fields.
      return Address.fromMap(doc.data()!['address']);
    }
    return null;
  }
}