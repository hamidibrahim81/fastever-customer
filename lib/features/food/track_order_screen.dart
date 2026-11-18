import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const _orange = Color(0xFFFF6B00);
  static const _dark = Color(0xFF111827);
  static const _staleAfter = Duration(minutes: 2);
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _orderSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _deliverySub;
  Timer? _clock;
  Timer? _animation;
  maps.GoogleMapController? _controller;
  maps.BitmapDescriptor _scooterIcon = maps.BitmapDescriptor.defaultMarkerWithHue(maps.BitmapDescriptor.hueOrange);
  Map<String, dynamic> _order = {};
  Map<String, dynamic> _delivery = {};
  bool _loading = true;
  String? _error;
  String? _assignedPartnerId;
  bool _mapReady = false;
  bool _cameraInitialized = false;
  bool _userMovedCamera = false;
  maps.LatLng? _driver;
  maps.LatLng? _displayedDriver;
  maps.LatLng? _destination;
  DateTime? _driverUpdatedAt;
  double _bearingDegrees = 0;

  @override
  void initState() {
    super.initState();
    _loadMarker();
    _listenToOrder();
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  void _listenToOrder() {
    _orderSub = FirebaseFirestore.instance
        .collection('order_status').doc(widget.orderId).snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      if (!snapshot.exists) {
        setState(() { _loading = false; _error = 'Order tracking is not available yet.'; });
        return;
      }
      final data = snapshot.data() ?? <String, dynamic>{};
      final partnerId = _string(data['deliveryPartnerId'] ?? data['driverId'] ??
          _asMap(data['deliveryPartner'])['id'] ?? _asMap(data['delivery'])['partnerId']);
      if (_assignedPartnerId != partnerId) {
        _assignedPartnerId = partnerId;
        _delivery = {};
        _deliverySub?.cancel();
        _deliverySub = null;
        // This is an order-scoped read, not a global partner position.
        // It only works if the delivery app updates this document.
        if (partnerId.isNotEmpty) {
          _deliverySub = FirebaseFirestore.instance
              .collection('delivery_partner_orders').doc(widget.orderId)
              .snapshots().listen((s) {
            if (!mounted) return;
            setState(() => _delivery = s.data() ?? {});
            _processLocation();
          }, onError: (Object e) { debugPrint('Delivery tracking read: $e'); });
        }
      }
      setState(() { _order = data; _loading = false; _error = null; });
      _processLocation();
    }, onError: (Object e) {
      if (mounted) setState(() { _loading = false; _error = 'Unable to load tracking. Please try again.'; });
      debugPrint('Order tracking read: $e');
    });
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }

  static String _string(dynamic value) => value?.toString().trim() ?? '';
  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(_string(value));
  }

  static maps.LatLng? _coordinate(dynamic value) {
    if (value is GeoPoint) return _valid(value.latitude, value.longitude);
    if (value is Map) {
      final map = _asMap(value);
      if (map['geoPoint'] != null) {
        final nested = _coordinate(map['geoPoint']);
        if (nested != null) return nested;
      }
      final lat = _number(map['latitude'] ?? map['lat']);
      final lng = _number(map['longitude'] ?? map['lng'] ?? map['lon']);
      if (lat != null && lng != null) return _valid(lat, lng);
    }
    return null;
  }

  static maps.LatLng? _valid(double lat, double lng) {
    if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180 ||
        (lat == 0 && lng == 0)) return null;
    return maps.LatLng(lat, lng);
  }

  static DateTime? _date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value < 100000000000 ? value * 1000 : value);
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  // Use a location's own timestamp, never the order's updatedAt timestamp.
  static DateTime? _locationTime(Map<String, dynamic> source) {
    final nested = _asMap(source['driverLocation']);
    final partner = _asMap(source['deliveryPartner']);
    final location = _asMap(source['partnerLocation']);
    for (final candidate in [
      source['driverLocationUpdatedAt'], source['locationUpdatedAt'],
      source['lastLocationUpdate'], source['lastLocationUpdatedAt'],
      source['gpsUpdatedAt'], nested['updatedAt'], nested['timestamp'],
      location['updatedAt'], location['timestamp'], partner['locationUpdatedAt'],
    ]) {
      final date = _date(candidate);
      if (date != null) return date;
    }
    return null;
  }

  maps.LatLng? _extractDriver(Map<String, dynamic> source) {
    final partner = _asMap(source['deliveryPartner']);
    final delivery = _asMap(source['delivery']);
    for (final value in [
      source['driverLocation'], source['deliveryPartnerLocation'],
      source['partnerLocation'], source['currentLocation'],
      partner['location'], partner['currentLocation'],
      delivery['driverLocation'], delivery['partnerLocation'],
    ]) {
      final point = _coordinate(value);
      if (point != null) return point;
    }
    final lat = _number(source['driverLatitude'] ?? source['partnerLatitude']);
    final lng = _number(source['driverLongitude'] ?? source['partnerLongitude']);
    return lat == null || lng == null ? null : _valid(lat, lng);
  }

  maps.LatLng? _extractDestination() {
    for (final value in [
      _order['destinationLocation'], _order['location'],
      _asMap(_order['customer'])['location'],
      _asMap(_order['delivery'])['destinationLocation'],
    ]) {
      final point = _coordinate(value);
      if (point != null) return point;
    }
    final lat = _number(_order['deliveryLatitude']);
    final lng = _number(_order['deliveryLongitude']);
    return lat == null || lng == null ? null : _valid(lat, lng);
  }

  void _processLocation() {
    if (!mounted) return;
    final destination = _extractDestination();
    // Prefer master order_status. Use order-scoped delivery record only as fallback.
    final primary = _extractDriver(_order);
    final secondary = _extractDriver(_delivery);
    final next = primary ?? secondary;
    final source = primary != null ? _order : _delivery;
    final time = next == null ? null : _locationTime(source);
    final old = _driver;
    setState(() { _destination = destination; _driverUpdatedAt = time; _driver = next; });
    if (next == null) {
      _animation?.cancel();
      _displayedDriver = null;
      return;
    }
    if (old == null || _displayedDriver == null) {
      _displayedDriver = next;
      _focusIfNeeded();
    } else if (_distanceMeters(old, next) > 1) {
      // Do not animate large GPS jumps; they are often inaccurate fixes.
      if (_distanceMeters(old, next) > 300) {
        _animation?.cancel();
        _displayedDriver = next;
        if (mounted) setState(() {});
      } else {
        _animateTo(next);
      }
    }
  }

  static double _distanceMeters(maps.LatLng a, maps.LatLng b) {
    const r = 6371000.0;
    final p1 = a.latitude * math.pi / 180;
    final p2 = b.latitude * math.pi / 180;
    final dp = (b.latitude - a.latitude) * math.pi / 180;
    final dl = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return 2 * r * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
  }

  static double _bearing(maps.LatLng a, maps.LatLng b) {
    final p1 = a.latitude * math.pi / 180;
    final p2 = b.latitude * math.pi / 180;
    final dl = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dl) * math.cos(p2);
    final x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  void _animateTo(maps.LatLng target) {
    _animation?.cancel();
    final start = _displayedDriver ?? target;
    _bearingDegrees = _bearing(start, target);
    const frames = 20;
    var frame = 0;
    _animation = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      if (!mounted) { timer.cancel(); return; }
      frame++;
      final t = (frame / frames).clamp(0.0, 1.0);
      final smooth = t * t * (3 - 2 * t);
      setState(() => _displayedDriver = maps.LatLng(
        start.latitude + (target.latitude - start.latitude) * smooth,
        start.longitude + (target.longitude - start.longitude) * smooth,
      ));
      if (frame >= frames) timer.cancel();
    });
  }

  bool get _freshLocation => _driver != null && _driverUpdatedAt != null &&
      DateTime.now().difference(_driverUpdatedAt!) <= _staleAfter &&
      !DateTime.now().isBefore(_driverUpdatedAt!.subtract(const Duration(seconds: 30)));

  Future<void> _loadMarker() async {
    try {
      final bytes = await rootBundle.load('assets/images/scooter_pin.png');
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List(), targetWidth: 110);
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      if (!mounted || png == null) return;
      setState(() => _scooterIcon = maps.BitmapDescriptor.fromBytes(png.buffer.asUint8List()));
    } catch (e) { debugPrint('Scooter icon fallback: $e'); }
  }

  void _focusIfNeeded() {
    if (!_mapReady || _controller == null || _cameraInitialized || _userMovedCamera) return;
    final driver = _displayedDriver;
    final destination = _destination;
    if (driver == null && destination == null) return;
    _cameraInitialized = true;
    if (driver != null && destination != null) {
      final sw = maps.LatLng(math.min(driver.latitude, destination.latitude), math.min(driver.longitude, destination.longitude));
      final ne = maps.LatLng(math.max(driver.latitude, destination.latitude), math.max(driver.longitude, destination.longitude));
      if (_distanceMeters(driver, destination) < 50) {
        _controller!.animateCamera(maps.CameraUpdate.newLatLngZoom(driver, 16));
      } else {
        _controller!.animateCamera(maps.CameraUpdate.newLatLngBounds(maps.LatLngBounds(southwest: sw, northeast: ne), 70));
      }
    } else {
      _controller!.animateCamera(maps.CameraUpdate.newLatLngZoom(driver ?? destination!, 15));
    }
  }

  String get _status => _string(_order['status']).isEmpty ? 'pending' : _string(_order['status']).toLowerCase();
  bool get _finished => ['delivered', 'cancelled', 'canceled'].contains(_status);

  String _prettyStatus() {
    switch (_status) {
      case 'pending': return 'Order Placed';
      case 'accepted': case 'confirmed': return 'Order Confirmed';
      case 'preparing': return 'Preparing Your Order';
      case 'ready': return 'Food is Ready';
      case 'partner_accepted': case 'assigned': return 'Delivery Partner Assigned';
      case 'arrived_at_pickup': return 'Partner at Restaurant';
      case 'out_for_delivery': case 'on_the_way': case 'picked': return 'Out for Delivery';
      case 'delivered': return 'Delivered';
      case 'cancelled': case 'canceled': return 'Order Cancelled';
      default: return _status.replaceAll('_', ' ').toUpperCase();
    }
  }

  String _etaLabel() {
    if (_status == 'delivered') return 'Delivered';
    if (_status == 'cancelled' || _status == 'canceled') return 'Cancelled';
    final value = _order['deliveryPartnerETA'] ?? _order['estimatedMinutes'];
    final eta = int.tryParse(_string(value));
    if (eta != null && eta > 0 && eta <= 240) return '$eta min estimated';
    return 'ETA updating';
  }

  int get _step {
    switch (_status) {
      case 'accepted': case 'confirmed': case 'preparing': return 1;
      case 'ready': return 2;
      case 'partner_accepted': case 'assigned': case 'arrived_at_pickup': return 3;
      case 'out_for_delivery': case 'on_the_way': case 'picked': return 4;
      case 'delivered': return 5;
      default: return 0;
    }
  }

  Widget _timeline() {
    const labels = ['Placed', 'Kitchen', 'Pickup', 'On Way'];
    final current = _step;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) Expanded(child: Container(height: 3, color: current >= i ? _orange : Colors.grey.shade200)),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 18, height: 18, decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: current > i ? _dark : (current == i ? _orange : Colors.grey.shade300),
            ), child: current > i ? const Icon(Icons.check, size: 12, color: Colors.white) : null),
            const SizedBox(height: 6),
            Text(labels[i], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: current >= i ? _dark : Colors.grey)),
          ]),
        ],
      ]),
    );
  }

  Set<maps.Marker> _markers() {
    final result = <maps.Marker>{};
    if (_destination != null) {
      result.add(maps.Marker(markerId: const maps.MarkerId('destination'), position: _destination!,
        infoWindow: const maps.InfoWindow(title: 'Delivery address'),
        icon: maps.BitmapDescriptor.defaultMarkerWithHue(maps.BitmapDescriptor.hueRed)));
    }
    if (_displayedDriver != null && !_finished) {
      result.add(maps.Marker(markerId: const maps.MarkerId('partner'), position: _displayedDriver!,
        icon: _scooterIcon, flat: true, anchor: const Offset(0.5, 0.5),
        rotation: _bearingDegrees,
        infoWindow: maps.InfoWindow(title: 'Delivery partner', snippet: _freshLocation ? 'Live GPS update' : 'Last reported position')));
    }
    return result;
  }

  Widget _map() {
    final initial = _displayedDriver ?? _destination;
    if (initial == null) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(height: 120, child: Lottie.asset('assets/animations/waiting.json',
          errorBuilder: (_, __, ___) => const Icon(Icons.location_searching, size: 64, color: _orange))),
        const SizedBox(height: 12),
        const Text('Waiting for tracking coordinates', style: TextStyle(color: Colors.black54)),
      ]));
    }
    return maps.GoogleMap(
      initialCameraPosition: maps.CameraPosition(target: initial, zoom: 15),
      onMapCreated: (controller) {
        _controller = controller;
        _mapReady = true;
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _focusIfNeeded(); });
      },
      onCameraMoveStarted: () { _userMovedCamera = true; },
      markers: _markers(),
      // No fabricated straight-line route. Road routing requires Directions/Routes API.
      polylines: const <maps.Polyline>{},
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
    );
  }

  String get _trackingMessage {
    if (_finished) return _prettyStatus();
    if (_driver == null) return 'Waiting for partner GPS location';
    if (_driverUpdatedAt == null) return 'Location received - freshness unverified';
    if (!_freshLocation) return 'Partner location is not updating';
    return 'Partner location updating';
  }

  Widget _partnerCard() {
    final partner = _asMap(_order['deliveryPartner']);
    final name = _string(_order['driverName'] ?? _order['deliveryPartnerName'] ?? partner['name'] ?? _delivery['deliveryPartnerName']);
    final phone = _string(_order['driverPhone'] ?? _order['deliveryPartnerPhone'] ?? partner['phone'] ?? _delivery['deliveryPartnerPhone']);
    if (name.isEmpty && phone.isEmpty && _driver == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
      decoration: const BoxDecoration(color: Color(0xFF1A1A1A), borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      child: SafeArea(top: false, child: Row(children: [
        const CircleAvatar(radius: 24, backgroundColor: Colors.white12, child: Icon(Icons.delivery_dining, color: _orange)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name.isEmpty ? 'Delivery Partner' : name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text(_trackingMessage, style: TextStyle(color: _freshLocation ? Colors.greenAccent : Colors.white70, fontSize: 12)),
          if (_driverUpdatedAt != null) Text('GPS: ${_driverUpdatedAt!.toLocal().hour.toString().padLeft(2, '0')}:${_driverUpdatedAt!.toLocal().minute.toString().padLeft(2, '0')}',
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ])),
        if (phone.isNotEmpty) IconButton(
          onPressed: () async {
            final uri = Uri(scheme: 'tel', path: phone);
            if (await canLaunchUrl(uri)) await launchUrl(uri);
          },
          icon: const Icon(Icons.phone, color: Colors.greenAccent),
        ),
      ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Track Your Order', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white, foregroundColor: _dark, centerTitle: true, elevation: 0,
        actions: [IconButton(tooltip: 'Recenter map', onPressed: () {
          _cameraInitialized = false;
          _userMovedCamera = false;
          _focusIfNeeded();
        }, icon: const Icon(Icons.my_location))]),
      body: _loading ? const Center(child: CircularProgressIndicator(color: _orange))
        : _error != null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
        : Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 2), child: Column(children: [
              Text(_prettyStatus().toUpperCase(), style: const TextStyle(color: _orange, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const SizedBox(height: 3),
              Text(_etaLabel(), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: _dark)),
            ])),
            _timeline(),
            if (_driver != null && !_freshLocation && !_finished)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5), child: Row(children: [
                const Icon(Icons.info_outline, color: Colors.deepOrange, size: 17),
                const SizedBox(width: 8),
                Expanded(child: Text(_trackingMessage, style: const TextStyle(fontSize: 12, color: Colors.deepOrange))),
              ])),
            Expanded(child: Container(margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.black12)),
              child: _map())),
            _partnerCard(),
          ]),
    );
  }

  @override
  void dispose() {
    _orderSub?.cancel();
    _deliverySub?.cancel();
    _clock?.cancel();
    _animation?.cancel();
    _controller?.dispose();
    super.dispose();
  }
}
