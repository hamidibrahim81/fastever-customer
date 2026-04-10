import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddressScreen extends StatefulWidget {
  const AddressScreen({Key? key}) : super(key: key);

  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen> {
  GoogleMapController? _mapController;
  final TextEditingController _searchController = TextEditingController();

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CameraPosition _initialCamera = const CameraPosition(
    target: LatLng(9.2268, 76.8496), // Centered on Konni area
    zoom: 14,
  );

  String _selectedAddress = "";
  LatLng? _selectedLatLng;
  CameraPosition? _cameraPosition;
  bool _isServiceable = false;
  List<Map<String, dynamic>> _availableServiceAreas = [];

  @override
  void initState() {
    super.initState();
    _loadServiceData();
  }

  Future<void> _loadServiceData() async {
    await _fetchServiceAreas();
    await _getCurrentLocation();
  }

  Future<void> _fetchServiceAreas() async {
    var snapshot = await FirebaseFirestore.instance.collection('service_areas').get();
    setState(() {
      _availableServiceAreas = snapshot.docs.map((doc) => doc.data()).toList();
    });
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    LatLng currentLatLng = LatLng(position.latitude, position.longitude);

    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(currentLatLng, 16));
    _cameraPosition = CameraPosition(target: currentLatLng, zoom: 16);
    await _updateAddress(currentLatLng);
  }

  bool _isPointInPolygon(LatLng point, List<dynamic> polygonPoints) {
    int intersectCount = 0;
    for (int i = 0; i < polygonPoints.length; i++) {
      var p1 = polygonPoints[i];
      var p2 = polygonPoints[(i + 1) % polygonPoints.length];
      if (((p1['lng'] > point.longitude) != (p2['lng'] > point.longitude)) &&
          (point.latitude <
              (p2['lat'] - p1['lat']) *
                      (point.longitude - p1['lng']) /
                      (p2['lng'] - p1['lng']) +
                  p1['lat'])) {
        intersectCount++;
      }
    }
    return (intersectCount % 2) == 1;
  }

  Future<void> _updateAddress(LatLng latLng) async {
    bool foundService = false;

    for (var area in _availableServiceAreas) {
      if (area['polygon'] != null) {
        if (_isPointInPolygon(latLng, area['polygon'])) {
          foundService = true;
          break;
        }
      } else {
        double dist = _calculateDistanceKm(
            area['latitude'], area['longitude'], latLng.latitude, latLng.longitude);
        if (dist <= (area['radiusKm'] ?? 8)) {
          foundService = true;
          break;
        }
      }
    }

    List<Placemark> placemarks =
        await placemarkFromCoordinates(latLng.latitude, latLng.longitude);
    final place = placemarks.first;

    if (!mounted) return;

    setState(() {
      _selectedLatLng = latLng;
      _isServiceable = foundService;
      _selectedAddress = "${place.street ?? place.name}, ${place.locality}, ${place.postalCode}";
    });

    if (!foundService) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Delivery not available in this area"),
            backgroundColor: Colors.red),
      );
    }
  }

  double _calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  Future<void> _onCameraIdle() async {
    if (_cameraPosition == null) return;
    await _updateAddress(_cameraPosition!.target);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              SafeArea(
                child: Column(
                  children: [
                    _buildSearchBar(),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: _initialCamera,
                      myLocationEnabled: true,
                      onMapCreated: (controller) => _mapController = controller,
                      onCameraMove: (pos) => _cameraPosition = pos,
                      onCameraIdle: _onCameraIdle,
                    ),
                    const Center(child: Icon(Icons.location_pin, size: 45, color: Colors.orange)),
                  ],
                ),
              ),
            ],
          ),
          Positioned(bottom: 0, left: 0, right: 0, child: _buildConfirmButton()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300, width: 1),
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 5))
          ]),
      child: GooglePlaceAutoCompleteTextField(
        textEditingController: _searchController,
        googleAPIKey: "AIzaSyB01Cnq_GNgcPXFHFPTWFmK-sS5WahXDNE",
        inputDecoration: InputDecoration(
          hintText: "Search for area, street name...",
          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 15),
          prefixIcon: const Icon(Icons.search, color: Colors.orange),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        countries: const ["in"],
        isLatLngRequired: true,
        getPlaceDetailWithLatLng: (prediction) async {
          final latStr = prediction.lat;
          final lngStr = prediction.lng;

          if (latStr == null || lngStr == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Location details not available. Please select another result."),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }

          final lat = double.tryParse(latStr);
          final lng = double.tryParse(lngStr);

          if (lat == null || lng == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Invalid location received. Please try again."),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }

          LatLng newLatLng = LatLng(lat, lng);
          _mapController?.animateCamera(CameraUpdate.newLatLngZoom(newLatLng, 16));
          await _updateAddress(newLatLng);
          FocusScope.of(context).unfocus();
        },
      ),
    );
  }

  Widget _buildConfirmButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: _isServiceable ? Colors.orange : Colors.grey,
          minimumSize: const Size(double.infinity, 55),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: (_selectedLatLng == null || !_isServiceable)
            ? null
            : () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AddressDetailsScreen(
                            address: _selectedAddress,
                            lat: _selectedLatLng!.latitude,
                            lng: _selectedLatLng!.longitude,
                          )),
                );

                if (result != null && mounted) {
                  Navigator.pop(context, result);
                }
              },
        child: Text(_isServiceable ? "Confirm Location" : "Area Not Serviceable"),
      ),
    );
  }
}

// ================= PROFESSIONAL ADDRESS DETAILS SCREEN =================

class AddressDetailsScreen extends StatefulWidget {
  final String address;
  final double lat, lng;
  const AddressDetailsScreen({required this.address, required this.lat, required this.lng});

  @override
  State<AddressDetailsScreen> createState() => _AddressDetailsScreenState();
}

class _AddressDetailsScreenState extends State<AddressDetailsScreen> {
  final _formKey = GlobalKey<FormState>();

  final nameCtrl = TextEditingController();
  final houseCtrl = TextEditingController();
  final streetCtrl = TextEditingController();
  final landmarkCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  String _selectedCategory = "Home"; // Default
  bool _isDefault = false;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  Future<bool> _ensureUnderLimitOrDeleteOne(String uid) async {
    var snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('addresses')
        .orderBy('updatedAt', descending: true)
        .limit(3)
        .get();

    if (snapshot.size < 3) return true;

    bool? deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Saved limit reached"),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("You can save only 3 addresses. Delete one to add a new address."),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: snapshot.docs.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                  itemBuilder: (context, i) {
                    var data = snapshot.docs[i].data();
                    return ListTile(
                      dense: true,
                      title: Text(data['category'] ?? "Saved", style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        data['full_display_address'] ?? "",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .collection('addresses')
                              .doc(snapshot.docs[i].id)
                              .delete();
                          Navigator.pop(context, true);
                        },
                        child: const Text("Delete", style: TextStyle(color: Colors.red)),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
        ],
      ),
    );

    return deleted == true;
  }

  Future<void> _saveAddress() async {
    if (_formKey.currentState!.validate()) {
      String uid = _uid;

      bool okToSave = await _ensureUnderLimitOrDeleteOne(uid);
      if (!okToSave) return;

      DocumentReference docRef = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('addresses')
          .add({
        'recipient_name': nameCtrl.text,
        'house_no': houseCtrl.text,
        'street_area': streetCtrl.text,
        'landmark': landmarkCtrl.text,
        'phone': phoneCtrl.text,
        'category': _selectedCategory,
        'lat': widget.lat,
        'lng': widget.lng,
        'full_display_address': widget.address,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (_isDefault) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'defaultAddressId': docRef.id,
        });
      }

      Navigator.pop(context, {
        'addressId': docRef.id,
        'category': _selectedCategory,
        'full_display_address': widget.address,
        'recipient_name': nameCtrl.text,
        'house_no': houseCtrl.text,
        'street_area': streetCtrl.text,
        'landmark': landmarkCtrl.text,
        'phone': phoneCtrl.text,
        'lat': widget.lat,
        'lng': widget.lng,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Enter Address Details",
            style: TextStyle(fontSize: 18, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(widget.address,
                        style: const TextStyle(color: Colors.black54, fontSize: 13))),
              ],
            ),
            const SizedBox(height: 25),

            _buildCategorySelector(),
            const SizedBox(height: 20),

            _buildSectionLabel("CONTACT DETAILS"),
            _buildField(nameCtrl, "Recipient Name *", Icons.person_outline, true),
            _buildField(phoneCtrl, "Phone Number (Optional)", Icons.phone_android_outlined,
                false,
                type: TextInputType.phone),

            const SizedBox(height: 10),
            _buildSectionLabel("ADDRESS DETAILS"),
            _buildField(houseCtrl, "House No. / Flat / Building *", Icons.apartment, true),
            _buildField(streetCtrl, "Street / Road / Area *", Icons.streetview, true),
            _buildField(landmarkCtrl, "Nearby Landmark (Optional)",
                Icons.assistant_navigation, false),

            const SizedBox(height: 10),
            CheckboxListTile(
              title: const Text("Set as default address", style: TextStyle(fontSize: 14)),
              value: _isDefault,
              onChanged: (val) => setState(() => _isDefault = val!),
              activeColor: Colors.orange,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),

            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saveAddress,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 2,
              ),
              child: const Text("SAVE ADDRESS",
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySelector() {
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: ["Home", "Office", "Other"].map((cat) {
        bool isSelected = _selectedCategory == cat;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat),
            child: Column(
              children: [
                CircleAvatar(
                  backgroundColor: isSelected ? Colors.orange : Colors.grey.shade100,
                  child: Icon(
                    cat == "Home"
                        ? Icons.home
                        : cat == "Office"
                            ? Icons.work
                            : Icons.location_on,
                    color: isSelected ? Colors.white : Colors.grey,
                  ),
                ),
                const SizedBox(height: 5),
                Text(cat,
                    style: TextStyle(
                        color: isSelected ? Colors.orange : Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
              letterSpacing: 0.5)),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label, IconData icon, bool isMandatory,
      {TextInputType type = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: ctrl,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20, color: Colors.orange.shade400),
          labelStyle: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.orange, width: 1.5)),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
        validator: (v) => (isMandatory && v!.isEmpty) ? "Field required" : null,
      ),
    );
  }
}