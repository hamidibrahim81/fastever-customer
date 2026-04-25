import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lottie/lottie.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as maps;

class TrackOrderScreen extends StatefulWidget {
  final String orderId;

  const TrackOrderScreen({super.key, required this.orderId});

  @override
  State<TrackOrderScreen> createState() => _TrackOrderScreenState();
}

class _TrackOrderScreenState extends State<TrackOrderScreen> {
  Timer? _timer;
  Timer? _animTimer;

  maps.GoogleMapController? _mapController;
  final Set<maps.Marker> _markers = {};
  final Set<maps.Polyline> _polylines = {};

  bool _isMapReady = false;

  GeoPoint? _lastDriverGeo;
  maps.LatLng? _animatedDriverLatLng;
  maps.LatLng? _destLatLng;

  double _driverRotation = 0.0;

  @override
  void initState() {
    super.initState();
    _saveDeviceToken();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _saveDeviceToken() async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance
            .collection('order_status')
            .doc(widget.orderId)
            .set({'fcmToken': token}, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // ================= MAP LOGIC =================

  double _bearing(maps.LatLng a, maps.LatLng b) {
    final lat1 = a.latitude * math.pi / 180;
    final lon1 = a.longitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final lon2 = b.longitude * math.pi / 180;

    final dLon = lon2 - lon1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  void _animateDriverTo(maps.LatLng next) {
    final start = _animatedDriverLatLng ?? next;

    _animTimer?.cancel();

    const steps = 50;
    int current = 0;

    _driverRotation = _bearing(start, next);

    _animTimer = Timer.periodic(const Duration(milliseconds: 60), (t) {
      current++;
      double f = current / steps;

      final lat = start.latitude + (next.latitude - start.latitude) * f;
      final lng = start.longitude + (next.longitude - start.longitude) * f;

      final pos = maps.LatLng(lat, lng);
      _animatedDriverLatLng = pos;

      _updateMarkers(pos);

      if (mounted) setState(() {});

      if (current >= steps) t.cancel();
    });
  }

  void _updateMarkers(maps.LatLng driver) {
    _markers.removeWhere((m) => m.markerId.value == 'driver');

    _markers.add(
      maps.Marker(
        markerId: const maps.MarkerId('driver'),
        position: driver,
        rotation: _driverRotation,
        flat: true,
        icon: maps.BitmapDescriptor.defaultMarkerWithHue(
          maps.BitmapDescriptor.hueOrange,
        ),
      ),
    );

    if (_destLatLng != null) {
      _polylines.clear();
      _polylines.add(
        maps.Polyline(
          polylineId: const maps.PolylineId("route"),
          points: [driver, _destLatLng!],
          width: 5,
          color: Colors.orange,
        ),
      );
    }
  }

  void _moveCamera(maps.LatLng pos) {
    if (_mapController == null) return;
    _mapController!.animateCamera(
      maps.CameraUpdate.newLatLngZoom(pos, 15),
    );
  }

  // ================= SWIGGY STYLE DYNAMIC ETA =================

  String _getDynamicTime(Map<String, dynamic> data) {
    final String status = (data['status'] ?? 'pending').toLowerCase();
    if (status == 'delivered') return "Delivered";

    final created = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
    final elapsedMins = DateTime.now().difference(created).inMinutes;

    int baseMins = 40; // Default

    if (status == 'accepted') {
      baseMins = 35;
    } else if (status.contains('accepted') || status.contains('preparing') || status == 'ready') {
      baseMins = 25;
    } else if (status.contains('out_for_delivery') || status.contains('picked')) {
      int transit = int.tryParse(data['deliveryPartnerETA']?.toString() ?? "12") ?? 12;
      return transit <= 1 ? "1 min" : "$transit mins";
    }

    int remaining = baseMins - elapsedMins;
    return remaining <= 0 ? "Arriving shortly" : "$remaining mins";
  }

  String _prettyStatus(String status) {
    final s = status.toLowerCase().trim();
    switch (s) {
      case 'accepted': return "ORDER ACCEPTED";
      case 'ready': return "YOUR FOOD IS READY";
      case 'partner_accepted': return "PARTNER ASSIGNED";
      case 'arrived_at_pickup': return "PARTNER AT RESTAURANT";
      case 'out_for_delivery': 
      case 'on_the_way': return "ON THE WAY";
      case 'delivered': return "DELIVERED";
      default: return status.toUpperCase().replaceAll('_', ' ');
    }
  }

  // ================= UI COMPONENTS =================

  Widget _buildStatusDot(String label, bool isActive) {
    return Column(
      children: [
        Icon(
          isActive ? Icons.check_circle : Icons.circle_outlined,
          color: isActive ? Colors.orange : Colors.grey[300],
          size: 20,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? Colors.black : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusLine(bool isActive) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 15),
        color: isActive ? Colors.orange : Colors.grey[200],
      ),
    );
  }

  Widget _statusShower(String status) {
    final s = status.toLowerCase().trim();
    int currentIdx = 0;
    
    // Mapping internal database statuses to UI milestones
    if (s == 'accepted') currentIdx = 0;
    if (s == 'ready') currentIdx = 1;
    if (s == 'partner_accepted' || s == 'arrived_at_pickup') currentIdx = 2;
    if (s == 'out_for_delivery' || s == 'on_the_way' || s == 'picked') currentIdx = 3;
    if (s == 'delivered') currentIdx = 4;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildStatusDot("Accepted", currentIdx >= 0),
          _buildStatusLine(currentIdx >= 1),
          _buildStatusDot("Ready", currentIdx >= 1),
          _buildStatusLine(currentIdx >= 2),
          _buildStatusDot("Partner", currentIdx >= 2),
          _buildStatusLine(currentIdx >= 3),
          _buildStatusDot("On Way", currentIdx >= 3),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Track Order", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('order_status')
            .doc(widget.orderId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: Colors.orange));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};

          final status = data['status'] ?? 'processing';
          final timeLabel = _getDynamicTime(data);

          GeoPoint? driverLoc = data['driverLocation'];
          final dest = data['destinationLocation'];

          if (dest != null) {
            _destLatLng = maps.LatLng(dest.latitude, dest.longitude);
            _markers.removeWhere((m) => m.markerId.value == 'dest');
            _markers.add(
              maps.Marker(
                markerId: const maps.MarkerId('dest'),
                position: _destLatLng!,
              ),
            );
          }

          if (driverLoc != null && _isMapReady) {
            final next = maps.LatLng(driverLoc.latitude, driverLoc.longitude);
            if (_lastDriverGeo == null ||
                _lastDriverGeo!.latitude != driverLoc.latitude ||
                _lastDriverGeo!.longitude != driverLoc.longitude) {
              _lastDriverGeo = driverLoc;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _animateDriverTo(next);
                _moveCamera(next);
              });
            }
          }

          return Column(
            children: [
              _header(timeLabel, status),
              _statusShower(status),
              Expanded(child: _map(driverLoc)),
              _driver(data),
            ],
          );
        },
      ),
    );
  }

  Widget _header(String time, String status) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 5),
      child: Column(
        children: [
          Text(
            "ESTIMATED ARRIVAL",
            style: TextStyle(color: Colors.grey[600], fontSize: 12, letterSpacing: 1.2),
          ),
          const SizedBox(height: 4),
          Text(
            time,
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _prettyStatus(status),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _map(GeoPoint? driverLoc) {
    if (driverLoc == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 200,
              child: Lottie.asset(
                'assets/animations/waiting.json',
                errorBuilder: (context, error, stackTrace) => 
                    const CircularProgressIndicator(color: Colors.orange),
              ),
            ),
            const Text("Waiting for partner assignment...", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final initial = maps.LatLng(driverLoc.latitude, driverLoc.longitude);

    return maps.GoogleMap(
      initialCameraPosition: maps.CameraPosition(target: initial, zoom: 15),
      onMapCreated: (c) {
        _mapController = c;
        _isMapReady = true;
      },
      markers: _markers,
      polylines: _polylines,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
    );
  }

  Widget _driver(Map<String, dynamic> data) {
    final name = data['driverName'] ?? data['deliveryPartnerName'] ?? "Delivery Partner";
    final phone = data['driverPhone'] ?? data['deliveryPartnerPhone'] ?? "";

    if (name == "Delivery Partner" && phone == "") return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Colors.orange,
            child: Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Text("Your delivery hero", style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          if (phone.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.call, color: Colors.green),
              onPressed: () => launchUrl(Uri.parse('tel:$phone')),
              style: IconButton.styleFrom(backgroundColor: Colors.green.withOpacity(0.1)),
            ),
        ],
      ),
    );
  }
}