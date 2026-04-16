import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart'; // file được FlutterFire CLI tạo
import 'package:app1/Screens/welcome_screen.dart';
import 'package:app1/Screens/home_screen.dart'; // HomeScreen của bạn

void main() async {
  // Đảm bảo Flutter sẵn sàng
  WidgetsFlutterBinding.ensureInitialized();

  // Khởi tạo Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Chạy ứng dụng
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chat ECC',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key}); // Thêm const

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(), //Theo dõi trạng thái
        builder: (context,snapshot){
          if(snapshot.connectionState==ConnectionState.waiting){
            //Đang chờ kết nối database
            return const Center(child: CircularProgressIndicator());
          }else{
            if(snapshot.hasData){
              return HomeScreen();
            }else{
              return WelcomeScreen();
            }
          }
        }
        );

  }
}



