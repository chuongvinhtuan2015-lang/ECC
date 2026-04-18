// lib/services/crypto_service.dart
import 'dart:typed_data';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // Thay SharedPreferences

class CryptoService {
  // === THUẬT TOÁN ===
  static final x25519 = X25519();
  static final ed25519 = Ed25519();
  static final aesGcm = AesGcm.with256bits();

  // Lưu private key vào Secure Storage
  static const _secureStorage = FlutterSecureStorage();

  // CACHE
  static final Map<String, SimplePublicKey> _friendXPubCache = {};
  static final Map<String, SimplePublicKey> _friendEdPubCache = {};

  static final Map<String, SimpleKeyPair> _x25519KeyPairCache = {};
  static final Map<String, SimpleKeyPair> _ed25519KeyPairCache = {};
  static final Map<String, SecretKey> _sharedSecretCache = {};

  // === BƯỚC 1: TẠO & LƯU KHÓA LOCAL BẰNG SECURE STORAGE ===
  static Future<void> initKeys(String userId, String passphrase) async {
    // 1. Kiểm tra local đã có key chưa
    final hasKey = await _secureStorage.read(key: 'x25519_priv_$userId');
    if (hasKey != null) return;

    // 2. Tạo cặp khóa mới
    final xPair = await x25519.newKeyPair();
    final edPair = await ed25519.newKeyPair();

    // 3. PBKDF2: Biến passphrase thành SecretKey an toàn
    // Tạo Salt ngẫu nhiên (ít nhất 16 bytes)
    final salt = Uint8List.fromList(List<int>.generate(16, (i) => DateTime.now().millisecond % 256));

    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );

    final secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );

    // 4. Mã hóa để backup
    final xPriv = await xPair.extractPrivateKeyBytes();
    final edPriv = await edPair.extractPrivateKeyBytes();
    final combinedKeys = jsonEncode({
      'x': base64Encode(xPriv),
      'ed': base64Encode(edPriv)
    });

    final aesNonce = aesGcm.newNonce();
    final encryptedBackup = await aesGcm.encrypt(
      utf8.encode(combinedKeys),
      secretKey: secretKey,
      nonce: aesNonce,
    );

    // 5. Lưu lên Firestore (Lưu cả SALT và ITERATIONS)
    await FirebaseFirestore.instance.collection('users').doc(userId).set({
      'backup_key': base64Encode(encryptedBackup.cipherText),
      'mac': base64Encode(encryptedBackup.mac.bytes),
      'nonce': base64Encode(aesNonce),
      'salt': base64Encode(salt),
      'iterations': 100000,
      'x25519_pub': base64Encode((await xPair.extractPublicKey()).bytes),
      'ed25519_pub': base64Encode((await edPair.extractPublicKey()).bytes),
    }, SetOptions(merge: true));

    await _secureStorage.write(key: 'x25519_priv_$userId', value: base64Encode(xPriv));
    await _secureStorage.write(key: 'ed25519_priv_$userId', value: base64Encode(edPriv));
  }

  // === LẤY KEYPAIR TỪ LOCAL ===
  static Future<SimpleKeyPair> getX25519KeyPair(String userId) async {
    if(_x25519KeyPairCache.containsKey(userId)){
      return _x25519KeyPairCache[userId]!;
    }
    final seedBase64 = await _secureStorage.read(key: 'x25519_priv_$userId');
    if (seedBase64 == null) throw Exception('X25519 private key not found');

    final seed = base64Decode(seedBase64);
    final keyPair = await x25519.newKeyPairFromSeed(seed);
    _x25519KeyPairCache[userId]=keyPair;
    return keyPair;
  }
  static Future<SimpleKeyPair> getEd25519KeyPair(String userId) async {
    if(_ed25519KeyPairCache.containsKey(userId)){
      return _ed25519KeyPairCache[userId]!;
    }
    final seedBase64 = await _secureStorage.read(key: 'ed25519_priv_$userId');
    if (seedBase64 == null) throw Exception('Ed25519 private key not found');

    final seed = base64Decode(seedBase64);
    final keyPair = await ed25519.newKeyPairFromSeed(seed);
    _ed25519KeyPairCache[userId]=keyPair;
    return keyPair;
  }

  static Future<void> restoreKeys(String userId, String passphrase) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
    if (!doc.exists) throw Exception('Không tìm thấy tài khoản');

    final data = doc.data()!;
    final salt = base64Decode(data['salt']);
    final iterations = data['iterations'] as int;
    final encryptedData = base64Decode(data['backup_key']);
    final aesNonce = base64Decode(data['nonce']);
    final mac = base64Decode(data['mac']);

    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );

    final secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );

    // 2. Giải mã
    try {
      final secretBox = SecretBox(encryptedData, nonce: aesNonce, mac: Mac(mac));
      final decryptedBytes = await aesGcm.decrypt(secretBox, secretKey: secretKey);
      final keys = jsonDecode(utf8.decode(decryptedBytes));

      await _secureStorage.write(key: 'x25519_priv_$userId', value: keys['x']);
      await _secureStorage.write(key: 'ed25519_priv_$userId', value: keys['ed']);
    } catch (e) {
      throw Exception('Sai mật khẩu khôi phục hoặc dữ liệu bị lỗi');
    }
  }


  // === LẤY PUBLIC KEY BẠN BÈ ===
  static Future<SimplePublicKey> getFriendX25519Pub(String friendId) async {
    // 1. Kiểm tra Cache
    if (_friendXPubCache.containsKey(friendId)) {
      return _friendXPubCache[friendId]!;
    }
    // 2. Nếu chưa có, tải từ Firestore và lưu vào Cache
    final doc = await FirebaseFirestore.instance.collection('users').doc(friendId).get();
    final bytes = base64Decode(doc['x25519_pub']);
    final pubKey = SimplePublicKey(bytes, type: KeyPairType.x25519);

    _friendXPubCache[friendId] = pubKey; // Lưu vào cacheyy
    return pubKey;
  }

  static Future<SimplePublicKey> getFriendEd25519Pub(String friendId) async {
    if (_friendEdPubCache.containsKey(friendId)) {
      return _friendEdPubCache[friendId]!;
    }

    final doc = await FirebaseFirestore.instance.collection('users').doc(friendId).get();
    final bytes = base64Decode(doc['ed25519_pub']);
    final pubKey = SimplePublicKey(bytes, type: KeyPairType.ed25519);

    _friendEdPubCache[friendId] = pubKey;
    return pubKey;
  }

  // === BƯỚC 3: TÍNH KHÓA CHUNG X25519
  static Future<SecretKey> getSharedSecret({
    required String myId,
    required String friendId,
  }) async {
    final cacheKey = '${myId}_$friendId';

    // Tìm cache
    if (_sharedSecretCache.containsKey(cacheKey)) {
      return _sharedSecretCache[cacheKey]!;
    }

    final myX = await getX25519KeyPair(myId);
    final friendXPub = await getFriendX25519Pub(friendId);

    final secret = await x25519.sharedSecretKey(keyPair: myX, remotePublicKey: friendXPub);
    _sharedSecretCache[cacheKey] = secret; // Cache kết quả
    return secret;
  }

  // === BƯỚC 4 & 5: GỬI TIN NHẮN (MÃ HÓA + KÝ) ===
  static Future<void> sendMessage({
    required String myId,
    required String friendId,
    required String message,
  }) async {
    final sharedSecret = await getSharedSecret(myId: myId, friendId: friendId);
    final myEd = await getEd25519KeyPair(myId);

    final nonce = aesGcm.newNonce();
    final encrypted = await aesGcm.encrypt(
      Uint8List.fromList(utf8.encode(message)),
      secretKey: sharedSecret,
      nonce: nonce,
    );

    final signature = await ed25519.sign(encrypted.cipherText, keyPair: myEd);

    final chatId = myId.compareTo(friendId) < 0
        ? '${myId}_$friendId'
        : '${friendId}_$myId';

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add({
      'ciphertext': base64Encode(encrypted.cipherText),
      'nonce': base64Encode(nonce),
      'mac': base64Encode(encrypted.mac.bytes),
      'signature': base64Encode(signature.bytes),
      'sender': myId,
      'recipient': friendId,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // === BƯỚC 6: NHẬN & GIẢI MÃ + XÁC MINH
  static Future<String?> decryptAndVerify(
      DocumentSnapshot msg,
      String myId,
      ) async {
    try {
      final senderId = msg['sender'] as String;
      final isMe = senderId == myId;
      final friendId = isMe ? msg['recipient'] : senderId;

      //  Thực hiện chuyển đổi Base64 ngay lập tức trong RAM.

      late Uint8List ciphertext, nonce, macBytes, sigBytes;
      try {
        ciphertext = base64Decode(msg['ciphertext']);
        nonce = base64Decode(msg['nonce']);
        macBytes = base64Decode(msg['mac']);
        sigBytes = base64Decode(msg['signature']);
      } catch (e) {
        return 'Lỗi decode base64';
      }

      // 2. CONCURRENT FETCH: Lấy Shared Secret và Public Key cùng một lúc
      final fetchedKeys = await Future.wait([
        getSharedSecret(myId: myId, friendId: friendId),
        getFriendEd25519Pub(senderId),
      ]);

      final sharedSecret = fetchedKeys[0] as SecretKey;
      final friendEdPub = fetchedKeys[1] as SimplePublicKey;

      // 3.  Giải mã AES và Xác minh Ed25519 song song!
      // Cả 2 phép toán đều tốn CPU. Ta đẩy cả 2 vào hàng đợi cùng lúc.
      final secretBox = SecretBox(
        ciphertext,
        nonce: nonce,
        mac: Mac(macBytes),
      );

      final cryptoTasks = await Future.wait([
        // Task 1: Xác minh chữ ký Ed25519
        ed25519.verify(
          ciphertext,
          signature: Signature(sigBytes, publicKey: friendEdPub),
        ).catchError((_) => false),

        // Task 2: Giải mã AES-GCM
        aesGcm.decrypt(
          secretBox,
          secretKey: sharedSecret,
        ).catchError((_) => <int>[]), //Bắt lỗi rỗng
      ]);

      final isValid = cryptoTasks[0] as bool;
      final decryptedBytes = cryptoTasks[1] as List<int>;

      // 4. KIỂM TRA KẾT QUẢ
      if (!isValid) return 'Tin giả!';
      if (decryptedBytes.isEmpty) return 'Lỗi giải mã AES-GCM';

      return utf8.decode(decryptedBytes);

    } catch (e) {
      return 'Lỗi giải mã chung';
    }
  }

  // === XÓA KHÓA VÀ XÓA CACHE (khi logout) ===
  static Future<void> clearKeys(String userId) async {
    await _secureStorage.delete(key: 'x25519_priv_$userId');
    await _secureStorage.delete(key: 'ed25519_priv_$userId');
    _friendXPubCache.clear();
    _friendEdPubCache.clear();
    _sharedSecretCache.clear();
    _x25519KeyPairCache.clear();
    _ed25519KeyPairCache.clear();
    _groupSenderKeyCache.clear();
  }

  //////////
  //Group
  static final Map<String, SecretKey> _groupSenderKeyCache={};
  static Future<SecretKey> generateMySenderKey(String groupId,String myId) async{
    final senderKey =await aesGcm.newSecretKey();
    final keyBytes =await senderKey.extractBytes();
    await _secureStorage.write(
      key: 'sender_key_${groupId}_$myId',
      value: base64Encode(keyBytes),
    );
    _groupSenderKeyCache['${groupId}_$myId']=senderKey;
    return senderKey;
  }


  static Future<void> distributeMyKeyToMembers({
    required String groupId,
    required String myId,
  }) async{
    var senderKey=_groupSenderKeyCache['${groupId}_$myId'];
    if(senderKey==null) {
      final keyStr = await _secureStorage.read(key: 'sender_key_${groupId}_$myId');
      senderKey=SecretKey(base64Decode(keyStr!));
      _groupSenderKeyCache['${groupId}_$myId']=senderKey;
    }
    final senderKeyBytes=await senderKey.extractBytes();
    final groupDoc=await FirebaseFirestore.instance.collection('groups').doc(groupId).get();
    final List<dynamic> members =groupDoc.data()?['members'] ?? [];

    final existingKeysSnapshot =await FirebaseFirestore.instance
      .collection('groups')
      .doc(groupId)
      .collection('senderKeys')
      .where('senderId',isEqualTo: myId)
      .get();

    final membersWithKey=existingKeysSnapshot.docs.map((d) => d['forMemberId'] as String).toSet();
    final batch =FirebaseFirestore.instance.batch();
    bool hasNewMembers=false;
    for(final memberId in members) {
      if(memberId==myId) continue;
      if(membersWithKey.contains(memberId)) continue;
      hasNewMembers=true;

      final shareSecret= await getSharedSecret(myId: myId, friendId: memberId);
      final nonce=aesGcm.newNonce();
      final encryptedKey=await aesGcm.encrypt(
        senderKeyBytes,
        secretKey: shareSecret,
        nonce: nonce
      );
      final docRef = FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('senderKeys')
          .doc('${myId}_$memberId');

      batch.set(docRef, {
        'encryptedKey': base64Encode(encryptedKey.cipherText),
        'nonce': base64Encode(nonce),
        'mac': base64Encode(encryptedKey.mac.bytes),
        'senderId': myId,
        'forMemberId': memberId,
        'timestamp': FieldValue.serverTimestamp(),
      });

    }
    if (hasNewMembers) await batch.commit();
  }

  static Future<void> ensureSenderKeyDistributed({
    required String groupId,
    required String myId,
  }) async {
    final keyStr = await _secureStorage.read(key: 'sender_key_${groupId}_$myId');

    if (keyStr == null) {
      try {
        await restoreMySenderKey(groupId, myId);
      } catch (e) {
        await generateMySenderKey(groupId, myId);
      }
    }
    await distributeMyKeyToMembers(groupId: groupId, myId: myId);
  }

  static Future<SecretKey> restoreMySenderKey(String groupId,String myId) async{
    final recoveryDoc = await FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('senderKeys')
        .where('senderId', isEqualTo: myId)
        .limit(1)
        .get();

    if (recoveryDoc.docs.isEmpty) {
      throw "Lỗi: Không tìm thấy bản sao khóa trên hệ thống để khôi phục.";
    }

    final doc = recoveryDoc.docs.first;
    final friendId = doc['forMemberId'] as String;
    final encKeyBytes = base64Decode(doc['encryptedKey']);
    final keyNonce = base64Decode(doc['nonce']);
    final keyMac = base64Decode(doc['mac']);

    final sharedSecret = await getSharedSecret(myId: myId, friendId: friendId);
    final secretBox = SecretBox(encKeyBytes, nonce: keyNonce, mac: Mac(keyMac));

    final decryptedKeyBytes = await aesGcm.decrypt(secretBox, secretKey: sharedSecret);

    await _secureStorage.write(
      key: 'sender_key_${groupId}_$myId',
      value: base64Encode(decryptedKeyBytes),
    );
    return SecretKey(decryptedKeyBytes);
  }
  // === HÀM 3: GỬI TIN NHẮN NHÓM (CẬP NHẬT) ===
  static Future<void> sendGroupMessage({
    required String groupId,
    required String myId,
    required String message,
  }) async {
    var senderKey = _groupSenderKeyCache['${groupId}_$myId'];
    if (senderKey == null) {
      final keyStr = await _secureStorage.read(key: 'sender_key_${groupId}_$myId');
      if (keyStr == null) {
        throw Exception("Chưa có Sender Key. Nhắn tin thất bại!");
      }
      senderKey = SecretKey(base64Decode(keyStr));
      _groupSenderKeyCache['${groupId}_$myId'] = senderKey;
    }

    final myEd = await getEd25519KeyPair(myId);
    final nonce = aesGcm.newNonce();

    final encrypted = await aesGcm.encrypt(
      Uint8List.fromList(utf8.encode(message)),
      secretKey: senderKey,
      nonce: nonce,
    );

    final signature = await ed25519.sign(encrypted.cipherText, keyPair: myEd);

    await FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .collection('messages')
        .add({
      'ciphertext': base64Encode(encrypted.cipherText),
      'nonce': base64Encode(nonce),
      'mac': base64Encode(encrypted.mac.bytes),
      'signature': base64Encode(signature.bytes),
      'sender': myId,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // === HÀM 4: NHẬN & GIẢI MÃ TIN NHẮN NHÓM ===
  // Lấy Sender Key của người gửi ra để giải mã tin nhắn.
  static Future<String?> decryptGroupMessage(
      DocumentSnapshot msg,
      String myId,
      String groupId,
      ) async {
    try {
      final senderId = msg['sender'] as String;
      final isMe = senderId == myId;

      late Uint8List ciphertext, nonce, macBytes, sigBytes;
      try {
        ciphertext = base64Decode(msg['ciphertext']);
        nonce = base64Decode(msg['nonce']);
        macBytes = base64Decode(msg['mac']);
        sigBytes = base64Decode(msg['signature']);
      } catch (e) {
        return 'Lỗi decode base64';
      }

      SecretKey senderKey;
      final cacheKey = '${groupId}_$senderId';

      if (_groupSenderKeyCache.containsKey(cacheKey)) {
        senderKey = _groupSenderKeyCache[cacheKey]!;
      } else if (isMe) {
        final keyStr = await _secureStorage.read(key: 'sender_key_$cacheKey');

        if (keyStr != null) {
          senderKey = SecretKey(base64Decode(keyStr));
        } else {
          senderKey= await restoreMySenderKey(groupId, myId);
        }
        _groupSenderKeyCache[cacheKey] = senderKey;
      } else {
        // Lấy Sender Key mà người gửi đã mã hóa cho riêng mình
        final keyDoc = await FirebaseFirestore.instance
            .collection('groups')
            .doc(groupId)
            .collection('senderKeys')
            .doc('${senderId}_$myId')
            .get();

        if (!keyDoc.exists) return "Chưa nhận được khóa nhóm từ người gửi.";

        final encKeyBytes = base64Decode(keyDoc['encryptedKey']);
        final keyNonce = base64Decode(keyDoc['nonce']);
        final keyMac = base64Decode(keyDoc['mac']);

        // Giải mã Sender Key đó bằng Shared Secret 1-1
        final sharedSecret = await getSharedSecret(myId: myId, friendId: senderId);
        final secretBox = SecretBox(encKeyBytes, nonce: keyNonce, mac: Mac(keyMac));

        final decryptedKeyBytes = await aesGcm.decrypt(secretBox, secretKey: sharedSecret);
        senderKey = SecretKey(decryptedKeyBytes);
        _groupSenderKeyCache[cacheKey] = senderKey; // Cache lại để dùng cho các tin nhắn sau
      }

      // 2. GIẢI MÃ AES VÀ XÁC MINH ED25519 SONG SONG
      // Lấy Public key của người gửi (nếu là mình thì lấy key cá nhân)
      late SimplePublicKey friendEdPub;
      if (isMe) {
        final myPair = await getEd25519KeyPair(myId);
        friendEdPub = await myPair.extractPublicKey();
      } else {
        friendEdPub = await getFriendEd25519Pub(senderId);
      }

      final msgSecretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(macBytes));

      final cryptoTasks = await Future.wait([
        ed25519.verify(ciphertext, signature: Signature(sigBytes, publicKey: friendEdPub)).catchError((_) => false),
        aesGcm.decrypt(msgSecretBox, secretKey: senderKey).catchError((_) => <int>[]),
      ]);

      final isValid = cryptoTasks[0] as bool;
      final decryptedBytes = cryptoTasks[1] as List<int>;

      if (!isValid) return 'Tin giả! Chữ ký không hợp lệ.';
      if (decryptedBytes.isEmpty) return 'Lỗi giải mã nội dung.';

      return utf8.decode(decryptedBytes);

    } catch (e) {
      return 'Lỗi giải mã chung';
    }
  }
}