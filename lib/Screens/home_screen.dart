import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app1/services/crypto_service.dart'; // Đừng quên import file này để dọn cache
import 'package:app1/Screens/addfriend_screen.dart';
import 'chat_screen.dart';
import 'package:app1/Screens/welcome_screen.dart';

class HomeScreen extends StatelessWidget {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;

    // Tránh lỗi văng app nếu currentUser tình cờ bị null
    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Vui lòng đăng nhập lại.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat ECC'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext dialogContext) {
                  return AlertDialog(
                    title: const Text('Xác nhận đăng xuất'),
                    content: const Text(
                        'Bạn có chắc chắn muốn đăng xuất?\n\nMọi khóa bảo mật mã hóa trên thiết bị này sẽ bị xóa để đảm bảo an toàn.'),
                    actions: [
                      TextButton(
                        onPressed: () {
                          // Bấm Hủy
                          Navigator.pop(dialogContext);
                        },
                        child: const Text(
                          'Không',
                          style: TextStyle(color: Colors.black),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          // Bấm Có ->
                          Navigator.pop(dialogContext);

                          // 1. Xóa cache và Private Key của user hiện tại
                          try {
                            await FirebaseAuth.instance.signOut();
                            await CryptoService.clearKeys(currentUser.uid);
                          } catch (e) {
                            print("Lỗi xóa cache bảo mật: $e");
                          }

                          // 2. Đăng xuất Firebase
                          await _auth.signOut();

                          // 3. Quay về màn hình chào
                          if (context.mounted) {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (_) => WelcomeScreen()),
                                  (route) => false,
                            );
                          }
                        },
                        child: const Text(
                          'Đăng xuất',
                          style: TextStyle(
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _firestore.collection('users').doc(currentUser.uid).snapshots(),
        builder: (context, snapshot) {
          // BƯỚC 1: Xử lý trạng thái đang tải
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // BƯỚC 2: Xử lý lỗi kết nối hoặc mất quyền truy cập
          if (snapshot.hasError) {
            return const Center(child: Text('Đã xảy ra lỗi tải dữ liệu.'));
          }

          // BƯỚC 3: XỬ LÝ LỖI FIRESTORE RỖNG/BỊ XÓA (Cực kỳ quan trọng)
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: Text(
                'Tài khoản của bạn không tồn tại trên hệ thống.\nVui lòng đăng nhập bằng tài khoản khác.',
                textAlign: TextAlign.center,
              ),
            );
          }

          // BƯỚC 4: Lấy dữ liệu an toàn (Safe Data Extraction)
          final currentUserDoc = snapshot.data!;
          final userData = currentUserDoc.data() as Map<String, dynamic>? ?? {};

          // Lấy danh sách friendIds an toàn, không sợ bị lỗi "cannot get field"
          List<dynamic> rawFriendIds = userData.containsKey('friendIds') ? userData['friendIds'] : [];
          List<String> friendIds = List<String>.from(rawFriendIds);

          // Nếu không có bạn bè
          if (friendIds.isEmpty) {
            return const Center(child: Text('Bạn chưa có bạn bè nào.'));
          }

          // BƯỚC 5: Tải danh sách người dùng là bạn bè
          return FutureBuilder<QuerySnapshot>(
            future: _firestore
                .collection('users')
                .where(FieldPath.documentId, whereIn: friendIds)
                .get(),
            builder: (context, friendsSnapshot) {
              if (friendsSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (friendsSnapshot.hasError) {
                return const Center(child: Text('Lỗi khi tải danh sách bạn bè.'));
              }

              if (!friendsSnapshot.hasData || friendsSnapshot.data!.docs.isEmpty) {
                return const Center(child: Text('Bạn chưa có bạn bè nào tồn tại trên hệ thống.'));
              }

              final friends = friendsSnapshot.data!.docs;

              return ListView.builder(
                itemCount: friends.length,
                itemBuilder: (context, index) {
                  final user = friends[index];

                  // Tiếp tục lấy dữ liệu an toàn cho từng người bạn
                  final friendData = user.data() as Map<String, dynamic>? ?? {};

                  // Lấy tên, nếu không có thì lấy email, nếu không có nữa thì ghi Ẩn danh
                  final friendName = friendData.containsKey('username')
                      ? friendData['username']
                      : (friendData['email'] ?? 'Người dùng Ẩn danh');

                  return ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.person),
                    ),
                    title: Text(friendName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            currentUserId: currentUser.uid,
                            friendId: user.id,
                            friendName: friendName,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.person_add),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AddFriendScreen()),
          );
        },
      ),
    );
  }
}