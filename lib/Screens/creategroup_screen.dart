import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app1/services/crypto_service.dart';

class CreateGroupScreen extends StatefulWidget {
  @override
  _CreateGroupScreenState createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final TextEditingController _groupNameController = TextEditingController();
  List<String> _selectedMemberIds = [];
  bool _isCreating = false;

  // HÀM XỬ LÝ TẠO NHÓM
  Future<void> _handleCreateGroup() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    String groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng nhập tên nhóm')));
      return;
    }

    if (_selectedMemberIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hãy chọn ít nhất 1 thành viên')));
      return;
    }

    setState(() => _isCreating = true);

    try {
      // 1. Tạo ID nhóm mới
      DocumentReference groupRef = _firestore.collection('groups').doc();
      String groupId = groupRef.id;

      // 2. Danh sách tất cả thành viên (bao gồm cả mình)
      List<String> allMembers = [currentUser.uid, ..._selectedMemberIds];

      // 3. Lưu thông tin nhóm lên Firestore
      await groupRef.set({
        'name': groupName,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': currentUser.uid,
        'members': allMembers,
        'lastMessage': 'Nhóm đã được tạo',
      });

      // 4. LOGIC QUAN TRỌNG: Khởi tạo và Phân phối khóa nhóm
      // Tạo khóa Sender Key cho chính mình trong nhóm này
      await CryptoService.generateMySenderKey(groupId, currentUser.uid);

      // Phân phối khóa này cho các thành viên.
      // Đã sửa lại cú pháp truyền Named Parameters cho khớp với CryptoService
      await CryptoService.distributeMyKeyToMembers(
        groupId: groupId,
        myId: currentUser.uid,
      );

      if (mounted) {
        Navigator.pop(context); // Quay lại sau khi tạo xong
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tạo nhóm bảo mật thành công!')));
      }
    } catch (e) {
      print("Lỗi tạo nhóm: $e");
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tạo nhóm mới'),
        actions: [
          if (_isCreating)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: Colors.white),
              ),
            )
          else
            TextButton(
              onPressed: _handleCreateGroup, // Gọi thẳng hàm đã được tối ưu
              child: const Text('TẠO', style: TextStyle(
                  color: Colors.black)),
            )
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _firestore
            .collection('users')
            .doc(currentUser!.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // Ép kiểu an toàn để lấy mảng dữ liệu
          final userData = snapshot.data!.data() as Map<String, dynamic>?;
          final myFriendIds = (userData?['friendIds'] as List<dynamic>? ?? []);

          return Column(
            children: [
              // Ô NHẬP TÊN NHÓM
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _groupNameController,
                  decoration: InputDecoration(
                    labelText: 'Tên nhóm',
                    prefixIcon: const Icon(Icons.group),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('CHỌN THÀNH VIÊN', style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.grey)),
              ),
              // DANH SÁCH BẠN BÈ ĐỂ CHỌN
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _firestore
                      .collection('users')
                      .where(FieldPath.documentId,


                      whereIn: myFriendIds.isEmpty
                          ? ['none']
                          : myFriendIds.take(10).toList())
                      .snapshots(),
                  builder: (context, userSnapshot) {
                    if (!userSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final friends = userSnapshot.data!.docs;

                    return ListView.builder(
                      itemCount: friends.length,
                      itemBuilder: (context, index) {
                        final friend = friends[index];
                        final data = friend.data() as Map<String, dynamic>;

                        // Xử lý an toàn phòng trường hợp mất field
                        final friendName = data['username'] ?? data['email'] ?? 'Người dùng Ẩn danh';
                        final isSelected = _selectedMemberIds.contains(friend.id);

                        return CheckboxListTile(
                          secondary: const CircleAvatar(
                              child: Icon(Icons.person)),
                          title: Text(friendName),
                          value: isSelected,
                          onChanged: (bool? value) {
                            setState(() {
                              if (value == true) {
                                _selectedMemberIds.add(friend.id);
                              } else {
                                _selectedMemberIds.remove(friend.id);
                              }
                            });
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}