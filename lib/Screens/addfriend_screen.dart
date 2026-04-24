import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app1/Screens/creategroup_screen.dart';
class AddFriendScreen extends StatefulWidget {
  @override
  _AddFriendScreenState createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // === HÀM THÊM BẠN (1 CHIỀU) ===
  Future<void> addFriend(String friendId, String friendName) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    await _firestore.collection('users').doc(currentUser.uid).update({
      'friendIds': FieldValue.arrayUnion([friendId])
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã thêm $friendName vào danh sách!'),
            backgroundColor: Colors.green,
          )
      );
    }
  }

  // === HÀM XÓA BẠN (1 CHIỀU) ===
  Future<void> removeFriend(String friendId, String friendName) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    // CHỈ xóa ID khỏi mảng của CHÍNH MÌNH
    await _firestore.collection('users').doc(currentUser.uid).update({
      'friendIds': FieldValue.arrayRemove([friendId])
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã xóa $friendName.'),
            backgroundColor: Colors.redAccent,
          )
      );
    }
  }

  // === HỘP THOẠI XÁC NHẬN TRƯỚC KHI XÓA ===
  void confirmRemove(String friendId, String friendName) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Xóa liên hệ?'),
          content: Text('Bạn có chắc muốn xóa $friendName? Hai người sẽ không thể tiếp tục trò chuyện cho đến khi kết bạn lại.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                removeFriend(friendId, friendName);
              },
              child: const Text('Xóa', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;

    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('Vui lòng đăng nhập')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý liên hệ'),
        actions: [
          // NÚT TẠO NHÓM MỚI
          IconButton(
            icon: const Icon(Icons.group_add),
            tooltip: 'Tạo nhóm mới',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => CreateGroupScreen()));
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          // THANH TÌM KIẾM
          Container(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Nhập email hoặc tên...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase().trim();
                });
              },
            ),
          ),

          // DANH SÁCH NGƯỜI DÙNG
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: _firestore.collection('users').doc(currentUser.uid).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                final currentData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
                final myFriendIds = (currentData['friendIds'] ?? []) as List<dynamic>;

                return StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('users').snapshots(),
                  builder: (context, userSnapshot) {
                    if (!userSnapshot.hasData) return const Center(child: CircularProgressIndicator());

                    final allUsers = userSnapshot.data!.docs;

                    // 1. NẾU ĐANG TÌM KIẾM
                    if (_searchQuery.isNotEmpty) {
                      final searchResults = allUsers.where((doc) {
                        if (doc.id == currentUser.uid) return false;
                        final data = doc.data() as Map<String, dynamic>? ?? {};
                        final email = (data['email'] ?? '').toString().toLowerCase();
                        final name = (data['username'] ?? '').toString().toLowerCase();
                        return email == _searchQuery || name == _searchQuery; // Gõ chính xác mới ra
                      }).toList();

                      if (searchResults.isEmpty) {
                        return const Center(child: Text('Không tìm thấy!'));
                      }

                      return ListView.builder(
                        itemCount: searchResults.length,
                        itemBuilder: (context, index) {
                          return _buildUserTile(searchResults[index], myFriendIds, currentUser.uid);
                        },
                      );
                    }

                    // 2. NẾU KHÔNG TÌM KIẾM: PHÂN LOẠI DANH SÁCH
                    List<QueryDocumentSnapshot> pendingRequests = [];
                    List<QueryDocumentSnapshot> myFriends = [];

                    for (var doc in allUsers) {
                      if (doc.id == currentUser.uid) continue;

                      final data = doc.data() as Map<String, dynamic>? ?? {};
                      final theirFriendIds = (data['friendIds'] ?? []) as List<dynamic>;

                      final iAddedThem = myFriendIds.contains(doc.id);
                      final theyAddedMe = theirFriendIds.contains(currentUser.uid);

                      if (iAddedThem) {
                        // Mình đã add họ (Cho dù họ có add lại hay không, mình vẫn quản lý được)
                        myFriends.add(doc);
                      } else if (theyAddedMe && !iAddedThem) {
                        // Họ add mình, nhưng mình CHƯA add lại -> Nằm ở mục chờ duyệt
                        pendingRequests.add(doc);
                      }
                    }

                    // HIỂN THỊ GIAO DIỆN CHIA KHU VỰC
                    List<Widget> listItems = [];

                    if (pendingRequests.isNotEmpty) {
                      listItems.add(
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Text('NGƯỜI ĐÃ THÊM BẠN'),
                          )
                      );
                      listItems.addAll(pendingRequests.map((doc) => _buildUserTile(doc, myFriendIds, currentUser.uid, isPendingMode: true)));
                      listItems.add(const Divider());
                    }

                    if (myFriends.isNotEmpty) {
                      listItems.add(
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Text('BẠN BÈ CỦA BẠN'),
                          )
                      );
                      listItems.addAll(myFriends.map((doc) => _buildUserTile(doc, myFriendIds, currentUser.uid)));
                    }

                    if (listItems.isEmpty) {
                      return const Center(
                        child: Text(
                          'Danh sách trống.\nHãy tìm kiếm email để kết bạn!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }

                    return ListView(children: listItems);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // === WIDGET HIỂN THỊ TỪNG NGƯỜI DÙNG ===
  Widget _buildUserTile(QueryDocumentSnapshot userDoc, List<dynamic> myFriendIds, String currentUserId, {bool isPendingMode = false}) {
    final data = userDoc.data() as Map<String, dynamic>? ?? {};
    final friendName = data['username'] ?? data['email'] ?? 'Ẩn danh';
    final isFriend = myFriendIds.contains(userDoc.id);

    Widget trailingButton;

    if (isFriend) {
      trailingButton = ElevatedButton.icon(
        label: const Text('Xóa'),
        onPressed: () => confirmRemove(userDoc.id, friendName),
      );
    } else if (isPendingMode) {
      trailingButton = ElevatedButton.icon(

        label: const Text('Chấp nhận'),
        onPressed: () => addFriend(userDoc.id, friendName),
      );
    } else {
      trailingButton = ElevatedButton.icon(

        label: const Text('Thêm'),
        onPressed: () => addFriend(userDoc.id, friendName),
      );
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isPendingMode ? Colors.orange[100] : Colors.blue[100],
        child: Icon(Icons.person, color: isPendingMode ? Colors.orange : Colors.blue),
      ),
      title: Text(friendName, style: const TextStyle(fontWeight: FontWeight.bold)),
      trailing: trailingButton,
    );
  }
}