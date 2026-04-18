import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class WelcomeScreen extends StatelessWidget{
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chat ECC')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Chào mừng bạn đến với Chat ECC',),
            SizedBox(height: 40),
            ElevatedButton(
                onPressed:(){
                  Navigator.push(context,
                  MaterialPageRoute(builder: (_)=>LoginScreen()),);
            },
                child: Text('Đăng nhập'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed:(){
                Navigator.push(context,
                  MaterialPageRoute(builder: (_)=>RegisterScreen()),);
              },
              child: Text('Đăng ký'),
            ),
          ],
        )
      )
    );
  }
}