import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart'; 
import 'dart:async';

import '../home/home_screen.dart';
import '../profile/profile_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  String _verificationId = "";
  bool _otpSent = false;
  
  // States for polished feedback
  bool _isLoading = false; 
  bool _otpRequestLocked = false;
  bool _isSendingOtp = false;
  bool _isVerifyingOtp = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  Timer? _timer;
  int _secondsRemaining = 30;
  bool _canResend = false;

  final String _privacyUrl = "https://sites.google.com/view/fastever-privacy";
  final String _termsUrl = "https://sites.google.com/view/fastever-termsconditions/home";
  final String _shippingUrl = "https://sites.google.com/view/shipping-and-delivery-policy-k/home";
  final String _refundUrl = "https://sites.google.com/view/refundandcancellationpolicykee/home";

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _timer?.cancel(); 
    super.dispose();
  }

  void _startTimer() {
    if (!mounted) return;
    setState(() {
      _secondsRemaining = 30;
      _canResend = false;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining == 0) {
        if (mounted) {
          setState(() {
            _canResend = true;
            _timer?.cancel();
          });
        }
      } else {
        if (mounted) setState(() => _secondsRemaining--);
      }
    });
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  Future<void> _sendOTP() async {
    if (_otpRequestLocked) return;

    if (_phoneController.text.isEmpty || _phoneController.text.length != 10) {
      _showError("Please enter a valid 10-digit number.");
      return;
    }

    setState(() {
      _isLoading = true;
      _isSendingOtp = true;
      _otpRequestLocked = true;
    });
    FocusScope.of(context).unfocus();

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: "+91${_phoneController.text.trim()}",
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Automatic handling for some Android devices / Instant verification
          if (credential.smsCode != null) {
            if (mounted) {
              setState(() {
                _otpController.text = credential.smsCode!;
                _isVerifyingOtp = true; // Show loading on button during auto-verify
              });
            }
          }
          await _signInWithCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) setState(() { _isLoading = false; _isSendingOtp = false; _otpRequestLocked = false; });
          _showError(e.message ?? "Verification Failed");
        },
        codeSent: (String verificationId, int? resendToken) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _otpSent = true;
              _isLoading = false;
              _isSendingOtp = false;
              _otpRequestLocked = false;
            });
            _startTimer();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(backgroundColor: Colors.green, content: Text("OTP Sent Successfully!")),
            );
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (mounted) setState(() => _verificationId = verificationId);
        },
        timeout: const Duration(seconds: 30),
      );
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _isSendingOtp = false; _otpRequestLocked = false; });
      _showError("Error: $e");
    }
  }

  Future<void> _verifyOTP() async {
    if (_otpController.text.length < 6) {
      _showError("Please enter the full 6-digit OTP.");
      return;
    }

    setState(() {
      _isLoading = true;
      _isVerifyingOtp = true;
    });
    FocusScope.of(context).unfocus();

    PhoneAuthCredential credential = PhoneAuthProvider.credential(
      verificationId: _verificationId,
      smsCode: _otpController.text.trim(),
    );

    await _signInWithCredential(credential);
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      UserCredential userCredential = await _auth.signInWithCredential(credential);
      User? user = userCredential.user;

      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        
        // We only care about the name now
        bool isProfileComplete = prefs.getBool('profile_${user.uid}') ?? false;

        if (!isProfileComplete) {
          final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get().timeout(const Duration(seconds: 8));
          
          if (doc.exists && (doc.data()?['name'] != null && doc.data()?['name'].toString().trim().isNotEmpty == true)) {
            isProfileComplete = true;
            await prefs.setBool('profile_${user.uid}', true);
          }
        }

        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => isProfileComplete ? const HomeScreen() : const ProfileScreen()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
           _isLoading = false;
           _isVerifyingOtp = false;
        });
      }

      _showError(e.message ?? "Login Failed");
    }  catch (e) {
       debugPrint("Login Error: $e");

       if (!mounted) return;

       setState(() {
        _isLoading = false;
        _isVerifyingOtp = false;
       });

       Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
       );  
    }
  }

  

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: Colors.redAccent, content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 40),
                          const Text("Let's Sign you in.", 
                            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.black87)),
                          const SizedBox(height: 10),
                          const Text("Welcome to FASTever.\nYou've been missed!", 
                            style: TextStyle(fontSize: 24, color: Colors.grey, height: 1.2)),
                          const SizedBox(height: 50),

                          AnimatedCrossFade(
                            duration: const Duration(milliseconds: 400),
                            firstChild: _buildPhoneInput(),
                            secondChild: _buildOtpInput(),
                            crossFadeState: _otpSent ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                          ),
                        ],
                      ),
                    ),
                  ),
                  _buildFooter(),
                ],
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhoneInput() {
    return AutofillGroup( // Added for better iOS/Android integration
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Phone Number", style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            maxLength: 10,
            style: const TextStyle(fontSize: 18, letterSpacing: 1.0),
            decoration: InputDecoration(
              prefixIcon: const Padding(
                padding: EdgeInsets.all(15),
                child: Text("+91", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              hintText: "Enter Phone Number",
              counterText: "",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: (_isSendingOtp || _otpRequestLocked) ? null : _sendOTP,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                disabledBackgroundColor: Colors.black54,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSendingOtp
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("Get OTP", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpInput() {
    return AutofillGroup( // Added for iOS Auto-fill from SMS
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Enter OTP", style: TextStyle(fontWeight: FontWeight.w600)),
              TextButton(
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      _otpSent = false;
                      _otpController.clear();
                      _timer?.cancel();
                      _otpRequestLocked = false;
                    });
                  }
                },
                child: const Text("Change Number", style: TextStyle(color: Colors.blueAccent)),
              )
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 4.0, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: "• • • • • •",
              counterText: "",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
          const SizedBox(height: 15),
          Center(
            child: _canResend
                ? TextButton(
                    onPressed: (_isSendingOtp || _otpRequestLocked) ? null : _sendOTP,
                    child: const Text("Resend OTP", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                  )
                : Text("Resend OTP in $_secondsRemaining seconds", style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: _isVerifyingOtp ? null : _verifyOTP,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                disabledBackgroundColor: Colors.black54,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isVerifyingOtp
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("Verify & Login", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          children: [
            const Text("By continuing, you agree to our", style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 4),
            Wrap( // Using Wrap for better overflow handling on smaller screens
              alignment: WrapAlignment.center,
              children: [
                _link("Terms", _termsUrl),
                const Text("  •  ", style: TextStyle(color: Colors.grey, fontSize: 11)),
                _link("Privacy", _privacyUrl),
                const Text("  •  ", style: TextStyle(color: Colors.grey, fontSize: 11)),
                _link("Shipping", _shippingUrl),
              ],
            ),
            const SizedBox(height: 4),
            _link("Refund & Cancellation Policy", _refundUrl),
          ],
        ),
      ),
    );
  }

  Widget _link(String label, String url) {
    return GestureDetector(
      onTap: () => _launchURL(url),
      child: Text(label, 
        style: const TextStyle(
          fontSize: 11, 
          fontWeight: FontWeight.bold, 
          decoration: TextDecoration.underline,
          color: Colors.black87
        )
      ),
    );
  }
}