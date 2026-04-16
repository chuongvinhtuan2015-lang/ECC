import 'package:app1/Screens/home_screen.dart';
import 'package:app1/Screens/register_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app1/services/crypto_service.dart';
import 'dart:typed_data';
import 'dart:convert';
class LoginScreen extends StatefulWidget{
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final usernameController =TextEditingController();
  final passwordController =TextEditingController();
  final passphraseController =TextEditingController();
  final _auth=FirebaseAuth.instance;
  bool loading =false;
  void login() async {
    final username = usernameController.text.trim();
    final password = passwordController.text.trim();
    String passphrase = passphraseController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng nhập mật khẩu và tài khoản'))
      );
      return;
    }

    setState(() => loading = true); // Bắt đầu loading

    try {
      // 1. Tìm user theo username
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: username)
          .get();

      if (querySnapshot.docs.isEmpty) {
        throw 'Người dùng không tồn tại'; // Ném lỗi để nhảy vào catch
      }

      final userDoc = querySnapshot.docs.first;
      final email = userDoc['email'];

      // 2. Đăng nhập Firebase Auth
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      final userId = _auth.currentUser!.uid;

        if (passphrase.isEmpty) {
          await _auth.signOut();
          throw 'Thiết bị mới! Vui lòng nhập Passphrase.';
        }
        // Hàm này sẽ ném Exception nếu sai passphrase
        await CryptoService.restoreKeys(userId, passphrase);

      // Thành công
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đăng nhập thành công'))
        );
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => HomeScreen())
        );
      }

    } catch (e) {
      // Bắt TẤT CẢ các loại lỗi (Auth, Firestore, Crypto, hoặc String)
      String message = 'Đã xảy ra lỗi';

      if (e is FirebaseAuthException) {
        if (e.code == 'user-not-found') message = 'Người dùng không tồn tại';
        else if (e.code == 'wrong-password') message = 'Sai mật khẩu';
        else message = e.message ?? message;
      } else {
        message = e.toString().replaceAll('Exception: ', '');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      // Luôn luôn chạy dù thành công hay thất bại
      if (mounted) {
        setState(() => loading = false);
        passphraseController.clear(); // Xóa passphrase sau khi xử lý xong
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Đăng nhập")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20) ,
        child: Column(
          children: [
            TextField(controller:usernameController ,decoration:InputDecoration (labelText: 'Username')),
            TextField(controller:passwordController ,obscureText: true,decoration:InputDecoration (labelText: 'Password')),
            TextField(controller:passphraseController ,obscureText: true,decoration:InputDecoration (labelText: 'Passphrase')),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: (){
                loading ? null : login();
              },
              child: Text(loading ? 'Đang xử lý...' :'Đăng nhập'),
            ),
            TextButton(onPressed: ()
            {
              Navigator.push(context, MaterialPageRoute(builder: (_) =>RegisterScreen()));
            },
                child: Text('Chưa có tài khoản? Đăng ký'))
          ],
        ),

    ),
    );
  }
}