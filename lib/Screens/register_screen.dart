import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app1/Screens/login_screen.dart';
import 'package:app1/services/crypto_service.dart'; // thêm dòng này

class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final passWordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final passphraseController = TextEditingController();
  final confirmPassphraseController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  bool loading = false;

  void register() async {
    if (passWordController.text != confirmPasswordController.text) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Mật khẩu không khớp')));
      return;
    }
    if (passphraseController.text != confirmPassphraseController.text) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Mật khẩu khôi phục')));
      return;
    }
    setState(() => loading = true);
    final email = emailController.text.trim();
    final password = passWordController.text.trim();
    String passphrase = passphraseController.text.trim();

    passphraseController.clear();
    try {
      // 1. Tạo tài khoản
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final currentUser = userCredential.user!;
      final userId = currentUser.uid;

      // === 2. Lưu thông tin cơ bản lên Firestore ===
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'username': usernameController.text.trim(),
        'email': email,
        'friendIds': [],
        'created_at': FieldValue.serverTimestamp(),
      });

      // === 3. Sinh & lưu khóa cục bộ ===
      await CryptoService.initKeys(userId,passphrase);
      passphrase="";

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Tạo tài khoản thành công')));

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => LoginScreen()),
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message ?? 'Lỗi đăng ký')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }

    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Đăng ký")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: usernameController,
              decoration: InputDecoration(labelText: 'Username'),
            ),
            TextField(
              controller: emailController,
              decoration: InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: passWordController,
              obscureText: true,
              decoration: InputDecoration(labelText: 'Password'),
            ),
            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              decoration: InputDecoration(labelText: 'Confirm Password'),
            ),
            TextField(
              controller: passphraseController,
              obscureText: true,
              decoration: InputDecoration(labelText: 'Passphrase'),
            ),
            TextField(
              controller: confirmPassphraseController,
              obscureText: true,
              decoration: InputDecoration(labelText: 'Confirm Passphrase'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: loading ? null : register,
              child: Text(loading ? 'Đang xử lý...' : 'Đăng ký'),
            ),
          ],
        ),
      ),
    );
  }
}
