import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui; // Added for precise image scaling
import 'package:flutter/services.dart'; // Added for byte loading
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lottie/lottie.dart';
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
  
  // Default fallback marker instantly prepared so it never disappears
  maps.BitmapDescriptor _scooterIcon = maps.BitmapDescriptor.defaultMarkerWithHue(maps.BitmapDescriptor.hueOrange);

  @override
  void initState() {
    super.initState();
    _loadCustomMarker();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  // ✅ FIXED: High-accuracy pixel bytes resize helper method to fix huge sizing/ghosting issues
  Future<void> _loadCustomMarker() async {
    try {
      // 120 width/height provides a crisp, standardized pin size matching the target standard destination indicator
      final Uint8List markerIcon = await _getBytesFromAsset('assets/images/scooter_pin.png', 120);
      setState(() {
        _scooterIcon = maps.BitmapDescriptor.fromBytes(markerIcon);
      });
    } catch (e) {
      // Safe fallback mechanism if image file cannot be resolved or parsed
      _scooterIcon = maps.BitmapDescriptor.defaultMarkerWithHue(maps.BitmapDescriptor.hueOrange);
    }
  }

  // ✅ Helper framework utility to scale PNG directly onto the engine graphics pipeline layer
  Future<Uint8List> _getBytesFromAsset(String path, int width) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // ================= MAP HANDLING LOGIC =================

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

    const steps = 40;
    int current = 0;
    _driverRotation = _bearing(start, next);

    _animTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
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
        anchor: const Offset(0.5, 0.5), // ✅ FIXED: Keeps center pivot lock so icon stays attached when zooming
        icon: _scooterIcon, 
      ),
    );

    if (_destLatLng != null) {
      _markers.removeWhere((m) => m.markerId.value == 'dest');
      _markers.add(
        maps.Marker(
          markerId: const maps.MarkerId('dest'),
          position: _destLatLng!,
          anchor: const Offset(0.5, 1.0), // Classic bottom drop pinpoint anchor balance
          icon: maps.BitmapDescriptor.defaultMarkerWithHue(maps.BitmapDescriptor.hueRed),
        ),
      );

      _polylines.clear();
      _polylines.add(
        maps.Polyline(
          polylineId: const maps.PolylineId("route"),
          points: [driver, _destLatLng!],
          width: 6,
          color: Colors.orange,
          jointType: maps.JointType.round,
        ),
      );
    }
  }

  void _moveCamera(maps.LatLng pos) {
    if (_mapController == null) return;
    _mapController!.animateCamera(maps.CameraUpdate.newLatLngZoom(pos, 15.5));
  }

  String _getDynamicTime(Map<String, dynamic> data) {
    final String status = (data['status'] ?? 'pending').toLowerCase().trim();
    if (status == 'delivered') return "Delivered";

    if (status == 'out_for_delivery' || status == 'on_the_way' || status == 'picked') {
      if (data['deliveryPartnerETA'] != null) {
        int transit = int.tryParse(data['deliveryPartnerETA'].toString()) ?? 12;
        return transit <= 1 ? "1 min" : "$transit mins";
      }
      return "12 mins";
    }

    final created = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
    final elapsedMins = DateTime.now().difference(created).inMinutes;

    int baseRemainingMins = 40;

    if (status == 'accepted') {
      baseRemainingMins = 35;
    } else if (status.contains('preparing')) {
      baseRemainingMins = 30;
    } else if (status == 'ready') {
      baseRemainingMins = 25;
    } else if (status == 'partner_accepted') {
      baseRemainingMins = 20;
    } else if (status == 'arrived_at_pickup') {
      baseRemainingMins = 15;
    }

    int finalRemaining = baseRemainingMins - elapsedMins;
    return finalRemaining <= 0 ? "Shortly" : "$finalRemaining Mins";
  }

  String _prettyStatus(String status) {
    final s = status.toLowerCase().trim();
    switch (s) {
      case 'pending': return "Order Placed";
      case 'accepted': return "Order Confirmed";
      case 'ready': return "Food is Ready";
      case 'partner_accepted': return "Driver Assigned";
      case 'arrived_at_pickup': return "Driver at Restaurant";
      case 'out_for_delivery': 
      case 'on_the_way':
      case 'picked': return "Out For Delivery";
      case 'delivered': return "Delivered";
      default: return status.toUpperCase().replaceAll('_', ' ');
    }
  }

  // ================= TIMELINE UI =================

  Widget _buildTimelineStep(String label, bool isDone, bool isCurrent) {
    Color itemColor = isCurrent ? Colors.orange : (isDone ? Colors.black87 : Colors.grey.shade300);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: isCurrent ? 24 : 16,
          height: isCurrent ? 24 : 16,
          decoration: BoxDecoration(
            color: isCurrent ? Colors.white : itemColor,
            shape: BoxShape.circle,
            border: isCurrent ? Border.all(color: Colors.orange, width: 6) : null,
            boxShadow: isCurrent ? [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 10)] : null,
          ),
          child: !isCurrent && isDone 
              ? const Icon(Icons.check, color: Colors.white, size: 10) 
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: (isCurrent || isDone) ? FontWeight.w800 : FontWeight.w500,
            color: isCurrent ? Colors.orange : (isDone ? Colors.black87 : Colors.grey.shade400),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineDivider(bool isDone) {
    return Expanded(
      child: Container(
        height: 3,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: isDone ? Colors.orange : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _statusShower(String status) {
    final s = status.toLowerCase().trim();
    int idx = 0;
    
    if (s == 'accepted') idx = 1;
    if (s == 'ready') idx = 2;
    if (s == 'partner_accepted' || s == 'arrived_at_pickup') idx = 3;
    if (s == 'out_for_delivery' || s == 'on_the_way' || s == 'picked') idx = 4;
    if (s == 'delivered') idx = 5;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _buildTimelineStep("Placed", idx >= 0, idx == 0),
          _buildTimelineDivider(idx >= 1),
          _buildTimelineStep("Kitchen", idx >= 1, idx == 1 || idx == 2),
          _buildTimelineDivider(idx >= 3),
          _buildTimelineStep("Pickup", idx >= 3, idx == 3),
          _buildTimelineDivider(idx >= 4),
          _buildTimelineStep("On Way", idx >= 4, idx == 4),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Track Your Order", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.3)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
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
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.grey.shade200, width: 1.5),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15)],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _map(driverLoc),
                ),
              ),
              _driverCard(data),
            ],
          );
        },
      ),
    );
  }

  Widget _header(String time, String status) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text(
            _prettyStatus(status).toUpperCase(),
            style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5),
          ),
          const SizedBox(height: 2),
          Text(
            time,
            style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: -1),
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
              height: 160,
              child: Lottie.asset(
                'assets/animations/waiting.json',
                errorBuilder: (context, error, stackTrace) => 
                    const CircularProgressIndicator(color: Colors.orange),
              ),
            ),
            Text("Preparing setup details...", style: TextStyle(color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    final initial = maps.LatLng(driverLoc.latitude, driverLoc.longitude);

    return maps.GoogleMap(
      initialCameraPosition: maps.CameraPosition(target: initial, zoom: 15.5),
      onMapCreated: (c) {
        _mapController = c;
        _isMapReady = true;
        if (_lastDriverGeo != null) {
          _updateMarkers(maps.LatLng(_lastDriverGeo!.latitude, _lastDriverGeo!.longitude));
        }
      },
      markers: _markers,
      polylines: _polylines,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
    );
  }

  Widget _driverCard(Map<String, dynamic> data) {
    final name = data['driverName'] ?? data['deliveryPartnerName'] ?? "Delivery Partner";
    final phone = data['driverPhone'] ?? data['deliveryPartnerPhone'] ?? "";

    if (name == "Delivery Partner" && phone == "") return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.orange.withOpacity(0.5), width: 2)),
                child: const CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.white10,
                  child: Icon(Icons.person, color: Colors.orange, size: 24),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        const Text("Active Now", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
              ),
              if (phone.isNotEmpty)
                GestureDetector(
                  onTap: () => launchUrl(Uri.parse('tel:$phone')),
                  child: Container(
                    height: 46,
                    width: 46,
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.phone_forwarded_rounded, color: Colors.green, size: 18),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}