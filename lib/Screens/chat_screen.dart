import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:app1/services/crypto_service.dart';

class ChatScreen extends StatefulWidget {
  final String currentUserId;
  final String friendId;
  final String friendName;

  const ChatScreen({
    Key? key,
    required this.currentUserId,
    required this.friendId,
    required this.friendName,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController messageController = TextEditingController();
  late String chatId;

  final Map<String, String> _decryptedCache = {};

  // Cờ kiểm tra xem hiệu ứng chuyển trang đã xong chưa
  bool _isTransitionFinished = false;

  @override
  void initState() {
    super.initState();
    chatId = widget.currentUserId.compareTo(widget.friendId) < 0
        ? '${widget.currentUserId}_${widget.friendId}'
        : '${widget.friendId}_${widget.currentUserId}';

    // Đợi 300ms (thời gian hoạt hình chuyển trang) rồi mới cho phép render dữ liệu
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isTransitionFinished = true;
        });
      }
    });
  }

  // HÀM MỚI: Chỉ giải mã những tin nhắn được yêu cầu
  String _getOrDecrypt(QueryDocumentSnapshot msg) {
    final msgId = msg.id;

    // 1. Nếu đã có trong cache bản rõ (hoặc đã đánh dấu lỗi), trả về ngay lập tức
    if (_decryptedCache.containsKey(msgId) && _decryptedCache[msgId] != "...") {
      return _decryptedCache[msgId]!;
    }

    // 2. Nếu chưa có, bắt đầu tiến trình giải mã ngầm
    if (!_decryptedCache.containsKey(msgId)) {
      _decryptedCache[msgId] = "..."; // Đánh dấu placeholder để không gọi giải mã lại

      CryptoService.decryptAndVerify(msg, widget.currentUserId).then((decryptedText) {
        if (mounted) {
          setState(() {
            _decryptedCache[msgId] = decryptedText ?? "Lỗi dữ liệu";
          });
        }
      }).catchError((e) {
        print("Lỗi giải mã tin $msgId: $e");
        if (mounted) {
          setState(() {
            _decryptedCache[msgId] = "Lỗi hiển thị";
          });
        }
      });
    }

    // 3. Trong lúc chờ Future hoàn thành, trả về chữ đang xử lý
    return "Đang giải mã...";
  }

  Future<void> sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty) return;

    // Xóa ngay ô input để tạo cảm giác phản hồi nhanh cho người dùng
    messageController.clear();

    try {
      await CryptoService.sendMessage(
        myId: widget.currentUserId,
        friendId: widget.friendId,
        message: text,
      );
    } catch (e) {
      print("Send message error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Gửi tin nhắn thất bại')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.friendName)),
      body: Column(
        children: [
          Expanded(
            child: !_isTransitionFinished
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(chatId)
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
                      'Chưa có tin nhắn nào.\nHãy gửi lời chào!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                final messages = snapshot.data!.docs;

                // ĐÃ XÓA: WidgetsBinding.instance.addPostFrameCallback
                // Không bắt app giải mã toàn bộ một lúc nữa.

                return ListView.builder(
                  reverse: true, // Cuộn từ dưới lên (chuẩn app chat)
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final msgId = msg.id;

                    final data = msg.data() as Map<String, dynamic>? ?? {};
                    final senderId = data.containsKey('sender') ? data['sender'] : '';
                    final isMe = senderId == widget.currentUserId;

                    // GỌI HÀM TỐI ƯU Ở ĐÂY
                    final String displayText = _getOrDecrypt(msg);

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
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
                    );
                  },
                );
              },
            ),
          ),
          // Sử dụng SafeArea để tự động thêm padding né thanh điều hướng hệ thống
          SafeArea(
            top: false, // Chỉ cần né phía dưới
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      // Cho phép TextField tự giãn nở theo độ dài văn bản
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: 'Nhập tin nhắn...',
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (value) => sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Nút gửi hình tròn trông sẽ "xịn" hơn
                  CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: sendMessage,
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