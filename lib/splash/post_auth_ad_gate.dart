import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'ad_poster_screen.dart';

class PostAuthAdGate extends StatefulWidget {
  final Widget nextScreen;

  const PostAuthAdGate({
    Key? key,
    required this.nextScreen,
  }) : super(key: key);

  @override
  State<PostAuthAdGate> createState() => _PostAuthAdGateState();
}

class _PostAuthAdGateState extends State<PostAuthAdGate> {
  bool _loading = true;
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  Future<void> _loadAd() async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('ads')
          .where('tag', isEqualTo: 'post_auth')
          .where('active', isEqualTo: true)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _finish();
        return;
      }

      final data = query.docs.first.data();
      final imageUrl = (data['imageUrl'] ?? '').toString().trim();

      if (imageUrl.isEmpty) {
        _finish();
        return;
      }

      // ✅ PRE-CACHE BEFORE SHOWING SCREEN
      try {
        await precacheImage(NetworkImage(imageUrl), context);
      } catch (e) {
        debugPrint('⚠️ Precache failed: $e');
        _finish();
        return;
      }

      if (!mounted) return;

      setState(() {
        _imageUrl = imageUrl;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ PostAuthAdGate error: $e');
      _finish();
    }
  }

  void _finish() {
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    // 🔄 Firestore / precache loading
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white70),
        ),
      );
    }

    // ➡️ No ad
    if (_imageUrl == null) {
      return widget.nextScreen;
    }

    // 🖼️ Ad (instant display, no delay)
    return AdPosterScreen(
      imageUrl: _imageUrl!,
      nextScreen: widget.nextScreen,
    );
  }
}
