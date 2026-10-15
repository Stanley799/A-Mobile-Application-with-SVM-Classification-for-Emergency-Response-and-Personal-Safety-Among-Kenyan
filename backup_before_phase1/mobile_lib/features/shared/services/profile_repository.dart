import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

image.Image _decodePhoto(Uint8List bytes) {
  try {
    if (bytes.length < 16) throw const FormatException();
    final decoded = image.decodeImage(bytes);
    if (decoded == null) throw const FormatException();
    return decoded;
  } catch (_) {
    throw const FormatException(
      'Unable to read this image. Please choose another photo.',
    );
  }
}

Uint8List prepareCropSource(Uint8List bytes) {
  final decoded = _decodePhoto(bytes);
  final oriented = image.bakeOrientation(decoded);
  final resized = oriented.width > 1600 || oriented.height > 1600
      ? image.copyResize(
          oriented,
          width: oriented.width >= oriented.height ? 1600 : null,
          height: oriented.height > oriented.width ? 1600 : null,
        )
      : oriented;
  return Uint8List.fromList(image.encodePng(resized));
}

Uint8List prepareProfilePhoto(Uint8List bytes) {
  final decoded = _decodePhoto(bytes);
  if (decoded.width != decoded.height) {
    throw const FormatException('A square image is required.');
  }
  final resized = image.copyResize(
    image.bakeOrientation(decoded),
    width: 512,
    height: 512,
  );
  final clean = image.Image(width: 512, height: 512, numChannels: 3);
  image.fill(clean, color: image.ColorRgb8(255, 255, 255));
  image.compositeImage(clean, resized);
  return Uint8List.fromList(image.encodeJpg(clean, quality: 85));
}

class ProfileRepository {
  ProfileRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    ImagePicker? picker,
  }) : _authOverride = auth,
       _firestoreOverride = firestore,
       _storageOverride = storage,
       _picker = picker ?? ImagePicker();

  final FirebaseAuth? _authOverride;
  final FirebaseFirestore? _firestoreOverride;
  final FirebaseStorage? _storageOverride;
  final ImagePicker _picker;

  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;
  String get userId => _auth.currentUser!.uid;
  String? get email => _auth.currentUser?.email;
  bool get supportsCamera =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);
  DocumentReference<Map<String, dynamic>> get _profile =>
      _firestore.collection('users').doc(userId);

  Stream<Map<String, dynamic>?> watchProfile() =>
      _profile.snapshots().map((snapshot) => snapshot.data());

  Future<void> saveDetails(
    Map<String, dynamic> changes,
    Map<String, dynamic> original,
  ) async {
    const allowed = {
      'firstName',
      'lastName',
      'phoneNumber',
      'preferredLanguage',
    };
    if (!changes.keys.every(allowed.contains)) {
      throw ArgumentError('Unsupported profile field.');
    }
    await _firestore.runTransaction((transaction) async {
      final current = (await transaction.get(_profile)).data();
      if (current == null) throw StateError('Profile unavailable.');
      if (changes.keys.any((key) => current[key] != original[key])) {
        throw StateError(
          'Your profile changed elsewhere. Cancel editing and try again.',
        );
      }
      transaction.update(_profile, {
        ...changes,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<Uint8List> _readSelection(XFile file) async {
    if (await file.length() > 12 * 1024 * 1024) {
      throw const FormatException('Choose a photo smaller than 12 MB.');
    }
    return compute(prepareCropSource, await file.readAsBytes());
  }

  Future<Uint8List?> pickPhoto(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 90,
      requestFullMetadata: false,
    );
    return file == null ? null : _readSelection(file);
  }

  Future<Uint8List?> recoverLostPhoto() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    final response = await _picker.retrieveLostData();
    if (response.exception != null) throw response.exception!;
    if (response.files?.isNotEmpty != true) return null;
    return _readSelection(response.files!.first);
  }

  bool _ownsPath(String path) =>
      path.startsWith('profilePhotos/$userId/') &&
      RegExp(r'^profilePhotos/[^/]+/[A-Za-z0-9-]+\.jpg$').hasMatch(path);

  Future<Uint8List?> loadPhoto(String path) async {
    if (!_ownsPath(path)) throw const FormatException('Invalid photo path.');
    return _storage.ref(path).getData(2 * 1024 * 1024);
  }

  Future<void> _deletePhoto(String? path) async {
    if (path == null || !_ownsPath(path)) return;
    try {
      await _storage.ref(path).delete();
    } on FirebaseException {
      return;
    }
  }

  Future<void> savePhoto(Uint8List bytes) async {
    if (bytes.length > 2 * 1024 * 1024) {
      throw const FormatException('The cropped photo is too large.');
    }
    final oldPath =
        (await _profile.get()).data()?['profilePhotoPath'] as String?;
    final path = 'profilePhotos/$userId/${const Uuid().v4()}.jpg';
    final reference = _storage.ref(path);
    try {
      await reference.putData(
        bytes,
        SettableMetadata(
          contentType: 'image/jpeg',
          cacheControl: 'private,max-age=3600',
        ),
      );
      await _profile.update({
        'profilePhotoPath': path,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      await _deletePhoto(path);
      rethrow;
    }
    await _deletePhoto(oldPath);
  }

  Future<void> removePhoto() async {
    final oldPath =
        (await _profile.get()).data()?['profilePhotoPath'] as String?;
    await _profile.update({
      'profilePhotoPath': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _deletePhoto(oldPath);
  }

  Future<void> signOut() => _auth.signOut();
}
