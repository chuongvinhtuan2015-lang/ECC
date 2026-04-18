import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:app1/services/crypto_service.dart';

class GroupChatScreen extends StatefulWidget {
  final String currentUserId;
  final String groupId;
  final String groupName;

  const GroupChatScreen({
    Key? key,
    required this.currentUserId,
    required this.groupId,
    required this.groupName,
  }) : super(key: key);

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController messageController = TextEditingController();
  final Map<String, String> _decryptedCache = {};
  final Map<String, String> _userNamesCache = {};

  bool _isTransitionFinished = false;

  // THÊM: Biến trạng thái kiểm tra việc phân phối khóa
  bool _isKeyReady = false;

  @override
  void initState() {
    super.initState();

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isTransitionFinished = true;
        });
      }
    });

    // THÊM: Khởi tạo và phân phối khóa ngầm ngay khi vào phòng
    _prepareSenderKey();
  }

  Future<void> _prepareSenderKey() async {
    try {
      await CryptoService.ensureSenderKeyDistributed(
        groupId: widget.groupId,
        myId: widget.currentUserId,
      );
      if (mounted) {
        setState(() {
          _isKeyReady = true; // Sẵn sàng gửi tin nhắn
        });
      }
    } catch (e) {
      debugPrint("Lỗi phân phối khóa: $e");
      // Có thể thử lại (retry) ở đây nếu cần
    }
  }

  Future<String> _getSenderName(String senderId) async {
    if (_userNamesCache.containsKey(senderId)) {
      return _userNamesCache[senderId]!;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(senderId).get();
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final name = data['username'] ?? data['email'] ?? 'Thành viên ẩn danh';
      _userNamesCache[senderId] = name;
      return name;
    } catch (e) {
      return 'Không rõ';
    }
  }

  String _getOrDecrypt(QueryDocumentSnapshot msg) {
    final msgId = msg.id;

    if (_decryptedCache.containsKey(msgId) && _decryptedCache[msgId] != "...") {
      return _decryptedCache[msgId]!;
    }

    if (!_decryptedCache.containsKey(msgId)) {
      _decryptedCache[msgId] = "...";

      CryptoService.decryptGroupMessage(msg, widget.currentUserId, widget.groupId)
          .then((decryptedText) {
        if (mounted) {
          setState(() {
            _decryptedCache[msgId] = decryptedText ?? "Lỗi dữ liệu";
          });
        }
      }).catchError((e) {
        if (mounted) {
          setState(() {
            _decryptedCache[msgId] = "Lỗi hiển thị";
          });
        }
      });
    }

    return "Đang giải mã...";
  }

  Future<void> sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty) return;

    // Tùy chọn: Nếu khóa chưa sẵn sàng, có thể hiện thông báo hoặc block không cho gửi
    if (!_isKeyReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đang thiết lập bảo mật kênh chat, vui lòng đợi giây lát...')),
      );
      return;
    }

    messageController.clear();

    try {
      // ĐÃ BỎ ensureSenderKeyDistributed ở đây vì đã chạy ở initState

      await CryptoService.sendGroupMessage(
        groupId: widget.groupId,
        myId: widget.currentUserId,
        message: text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gửi tin nhắn thất bại: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.groupName)),
      body: Column(
        children: [
          Expanded(
            child: !_isTransitionFinished
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('groups')
                  .doc(widget.groupId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return const Center(child: Text('Lỗi tải tin nhắn.'));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Chưa có tin nhắn nào.\nHãy bắt đầu trò chuyện!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                final messages = snapshot.data!.docs;

                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final data = msg.data() as Map<String, dynamic>? ?? {};
                    final senderId = data.containsKey('sender') ? data['sender'] : '';
                    final isMe = senderId == widget.currentUserId;
                    final String displayText = _getOrDecrypt(msg);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      child: Column(
                        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          if (!isMe)
                            Padding(
                              padding: const EdgeInsets.only(left: 8, bottom: 2),
                              child: FutureBuilder<String>(
                                future: _getSenderName(senderId),
                                builder: (context, nameSnapshot) {
                                  return Text(
                                    nameSnapshot.data ?? '...',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                        fontWeight: FontWeight.w500
                                    ),
                                  );
                                },
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                            decoration: BoxDecoration(
                              color: isMe ? Colors.blue[300] : Colors.grey[300],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              displayText,
                              style: TextStyle(
                                color: displayText == "Đang giải mã..." || displayText == "Lỗi hiển thị"
                                    ? Colors.black54
                                    : Colors.black,
                                fontStyle: displayText == "Đang giải mã..." || displayText == "Lỗi hiển thị"
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      maxLines: null,
                      // Nếu khóa chưa sẵn sàng thì mờ ô nhập đi (Tùy chọn)
                      enabled: _isKeyReady,
                      decoration: InputDecoration(
                        hintText: _isKeyReady ? 'Nhập tin nhắn...' : 'Đang đồng bộ khóa...',
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (value) => sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    // Đổi màu nút gửi tùy theo trạng thái khóa
                    backgroundColor: _isKeyReady ? Colors.blue : Colors.grey,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: _isKeyReady ? sendMessage : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}