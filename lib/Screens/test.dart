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
  static final sha256 = Sha256();

  // Lưu private key vào Secure Storage
  static const _secureStorage = FlutterSecureStorage();

  // CACHE
  static final Map<String, SimplePublicKey> _friendXPubCache = {};
  static final Map<String, SimplePublicKey> _friendEdPubCache = {};

  static final Map<String, SimpleKeyPair> _x25519KeyPairCache = {};
  static final Map<String, SimpleKeyPair> _ed25519KeyPairCache = {};
  static final Map<String, SecretKey> _sharedSecretCache = {};

  // === BƯỚC 1: TẠO & LƯU KHÓA LOCAL BẰNG SECURE STORAGE ===
  static Future<void> initKeys(String userId,String passphrase) async {
    final hasKey = await _secureStorage.read(key: 'x25519_priv_$userId');
    if (hasKey != null) return; // Đã có khóa thì bỏ qua

    final xPair = await x25519.newKeyPair();
    final edPair = await ed25519.newKeyPair();

    final xPriv = await xPair.extractPrivateKeyBytes();
    final edPriv = await edPair.extractPrivateKeyBytes();

    final xPub = await xPair.extractPublicKey();
    final edPub = await edPair.extractPublicKey();

    final combinedKeys=jsonEncode({
      'x':base64Encode(xPriv),
      'ed':base64Encode(edPriv)
    });
    final nonce = aesGcm.newNonce();
    final hash = await sha256.hash(utf8.encode(passphrase));
    final secretKey = SecretKey(hash.bytes);
    final backup_key = await aesGcm.encrypt(
      Uint8List.fromList(utf8.encode(combinedKeys)),
      secretKey: secretKey,
      nonce: nonce,
    );
    await FirebaseFirestore.instance.collection('users').doc(userId).set({
      'mac': base64Encode(backup_key.mac.bytes),
      'nonce': base64Encode(nonce),
      'backup_key': base64Encode(backup_key.cipherText),
      'x25519_pub': base64Encode(xPub.bytes),
      'ed25519_pub': base64Encode(edPub.bytes),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

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

  static Future<void> restoreKeys(String userId,String passphrase) async{
    final doc= await FirebaseFirestore.instance.collection('users').doc(userId).get();
    if(!doc.exists||doc.data()==null) throw Exception('Không tìm thấy tài khoản');
    final data=doc.data()!;
    if(!data.containsKey('backup_key')) throw Exception('Không tìm bản sao');
    final nonce=base64Decode(data['nonce']);
    final mac=base64Decode(data['mac']);
    final encrypted=base64Decode(data['backup_key']);
    var passphraseBytes = utf8.encode(passphrase); // Trả về List<int>
    final hash = await sha256.hash(passphraseBytes);
    final secretKey = SecretKey(hash.bytes);

    // Giải mã AES-GCM
    try {
      final secretBox = SecretBox(
        encrypted,
        nonce: nonce,
        mac: Mac(mac),
      );

      var decryptedBytes = await aesGcm.decrypt(secretBox, secretKey: secretKey);
      String decryptedJson = utf8.decode(decryptedBytes);

      final Map<String, dynamic> keys = jsonDecode(decryptedJson);
      // Lưu vào Keystore (Android) / Keychain (iOS)
      await _secureStorage.write(key: 'x25519_priv_$userId', value: keys['x']);
      await _secureStorage.write(key: 'ed25519_priv_$userId', value: keys['ed']);
    }catch (e){
      throw Exception('Sai Passphrase');
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
  static Future<void> sendMessage({
    required String myId,
    required String friendId,
    required String message,
  }) async {
    final sharedSecret= await getSharedSecret(myId: myId, friendId: friendId);
    final myEd =await getEd25519KeyPair(myId);
    final nonce =aesGcm.newNonce();
    final encrypted =await aesGcm.encrypt(
        Uint8List.fromList(utf8.encode(message)),
        secretKey: sharedSecret,
        nonce: nonce);
    final signature=await ed25519.sign(encrypted.cipherText, keyPair: myEd);
    final chatId = myId.compareTo(friendId) < 0
    ? '${myId}_$friendId' 
    : '${friendId}_$myId';
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('message')
        .add({
      'ciphertext': base64Encode(encrypted.cipherText),
      'nonce': nonce,
      'mac':base64Encode(encrypted.mac.bytes),
      'signature':signature,
       'sender':myId,
       'recipient':friendId,
       'timestamp':FieldValue.serverTimestamp() });
}
  static Future<String?> decrytAndVerify(
      DocumentSnapshot msg,
      String myId
      )async{
      try{
        final senderId=msg['sender'] as String;
        final isMe =senderId== myId;
        final friendId=isMe?msg['recipient']:senderId;

        late Uint8List ciphertext,nonce,macBytes, sigBytes;
        try{
          ciphertext=base64Decode(msg['ciphertext']);
          nonce=base64Decode(msg['nonce']);
          macBytes=base64Decode(msg['mac']);
          sigBytes=base64Decode(msg['signature']);
        }catch(e){
          return "Lỗi decode base64";
        }
        final fetchedKeys=await Future.wait(
          [
            getSharedSecret(myId: myId, friendId: friendId),
            getFriendEd25519Pub(friendId)
          ]
        );
        final sharedSecret =fetchedKeys[0] as SecretKey;
        final friendEdPub=fetchedKeys[1] as SimplePublicKey;
        final secretBox=SecretBox(ciphertext, nonce: nonce, mac: Mac(macBytes));
        final cryptoTaks=await Future.wait(
          [
            ed25519.verify(ciphertext,
                signature: Signature(sigBytes, publicKey: friendEdPub)
            ).catchError((_)=>false),
            aesGcm.decrypt(secretBox, secretKey: sharedSecret
            ).catchError((_)=><int>[])
          ]
        );
        final isValid=cryptoTaks[0] as bool;
        final decryptedBytes=cryptoTaks[1] as List<int>;
        if(!isValid) return 'Tin giả!';
        if(decryptedBytes.isEmpty) return "Lỗi giải mã AES";
        return utf8.decode(decryptedBytes);
      }catch (e){
        return "Lỗi giải mã chung";
      }
  }
  // === XÓA KHÓA VÀ XÓA CACHE (khi logout) ===
  static Future<void> clearKeys(String userId) async {
    await _secureStorage.delete(key: 'x25519_priv_$userId');
    await _secureStorage.delete(key: 'ed25519_priv_$userId');

    // Clear cache để tránh rò rỉ bộ nhớ hoặc lỗi khi đổi tài khoản
    _friendXPubCache.clear();
    _friendEdPubCache.clear();
    _sharedSecretCache.clear();
    _x25519KeyPairCache.clear();
    _ed25519KeyPairCache.clear();
  }
}