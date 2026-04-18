import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app1/services/crypto_service.dart';
import 'package:app1/Screens/addfriend_screen.dart';
import 'package:app1/Screens/chat_screen.dart';
import 'package:app1/Screens/welcome_screen.dart';
import 'package:app1/Screens/creategroup_screen.dart';
import 'package:app1/Screens/groupchat_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _handleLogout(BuildContext context, String uid) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Xác nhận đăng xuất'),
          content: const Text(
              'Bạn có chắc chắn muốn đăng xuất?\n\nMọi khóa bảo mật mã hóa trên thiết bị này sẽ bị xóa để đảm bảo an toàn.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child:
              const Text('Không', style: TextStyle(color: Colors.black)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                try {
                  await CryptoService.clearKeys(uid);
                  await _auth.signOut();
                } catch (e) {
                  print("Lỗi xóa cache bảo mật: $e");
                }
                if (mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => WelcomeScreen()),
                        (route) => false,
                  );
                }
              },
              child: const Text('Đăng xuất',
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ FIX COLD START: Dùng StreamBuilder để chờ Firebase restore session
    return StreamBuilder<User?>(
      stream: _auth.authStateChanges(),
      builder: (context, authSnapshot) {
        // Đang chờ Firebase kiểm tra session đã lưu
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Session hết hạn hoặc chưa đăng nhập -> về WelcomeScreen
        final currentUser = authSnapshot.data;
        if (currentUser == null) {
          // Dùng addPostFrameCallback để tránh navigate trong build()
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => WelcomeScreen()),
                    (route) => false,
              );
            }
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // ✅ Đã có user hợp lệ, render giao diện chính
        return Scaffold(
          appBar: AppBar(
            title: const Text('Chat ECC'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () =>
                    _handleLogout(context, currentUser.uid),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.person), text: "Cá nhân"),
                Tab(icon: Icon(Icons.group), text: "Nhóm"),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildPrivateChatsTab(currentUser.uid),
              _buildGroupChatsTab(currentUser.uid),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            child: Icon(_tabController.index == 0
                ? Icons.person_add
                : Icons.group_add),
            onPressed: () {
              if (_tabController.index == 0) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AddFriendScreen()),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => CreateGroupScreen()),
                );
              }
            },
          ),
        );
      },
    );
  }

  // ==========================================
  // NỘI DUNG TAB 1: CHAT CÁ NHÂN
  // ==========================================
  Widget _buildPrivateChatsTab(String currentUid) {
    return StreamBuilder<DocumentSnapshot>(
      stream:
      _firestore.collection('users').doc(currentUid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
              child:
              Text('Lỗi tải dữ liệu cá nhân: ${snapshot.error}'));
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(
            child: Text('Tài khoản không tồn tại.\nVui lòng đăng nhập lại.',
                textAlign: TextAlign.center),
          );
        }

        final userData =
            snapshot.data!.data() as Map<String, dynamic>? ?? {};
        List<dynamic> rawFriendIds = userData.containsKey('friendIds')
            ? userData['friendIds']
            : [];

        List<String> friendIds = rawFriendIds
            .map((e) => e.toString().trim())
            .where((id) => id.isNotEmpty)
            .toList();

        if (friendIds.isEmpty) {
          return const Center(child: Text('Bạn chưa có bạn bè nào.'));
        }

        if (friendIds.length > 10) {
          friendIds = friendIds.sublist(0, 10);
        }

        return StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: friendIds)
              .snapshots(),
          builder: (context, friendsSnapshot) {
            if (friendsSnapshot.connectionState ==
                ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (friendsSnapshot.hasError) {
              print("DEBUG LỖI: ${friendsSnapshot.error}");
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Lỗi tải bạn bè: ${friendsSnapshot.error}'),
                ),
              );
            }
            if (!friendsSnapshot.hasData ||
                friendsSnapshot.data!.docs.isEmpty) {
              return const Center(
                  child: Text(
                      'Bạn chưa có bạn bè nào tồn tại trên hệ thống.'));
            }

            final friends = friendsSnapshot.data!.docs;

            return ListView.builder(
              itemCount: friends.length,
              itemBuilder: (context, index) {
                final user = friends[index];
                final friendData =
                    user.data() as Map<String, dynamic>? ?? {};
                final friendName = friendData.containsKey('username')
                    ? friendData['username']
                    : (friendData['email'] ?? 'Người dùng Ẩn danh');

                return ListTile(
                  leading:
                  const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(friendName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          currentUserId: currentUid,
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
    );
  }

  // ==========================================
  // NỘI DUNG TAB 2: CHAT NHÓM
  // ==========================================
  Widget _buildGroupChatsTab(String currentUid) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('groups')
          .where('members', arrayContains: currentUid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Lỗi khi tải danh sách: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
              child: Text('Bạn chưa tham gia nhóm nào.'));
        }

        final groups = snapshot.data!.docs;

        return ListView.builder(
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            final groupData =
                group.data() as Map<String, dynamic>? ?? {};
            final groupName = groupData['name'] ?? 'Nhóm không tên';

            return ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.blueAccent,
                child: Icon(Icons.group, color: Colors.white),
              ),
              title: Text(groupName,
                  style:
                  const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupChatScreen(
                      currentUserId: currentUid,
                      groupId: group.id,
                      groupName: groupName,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}