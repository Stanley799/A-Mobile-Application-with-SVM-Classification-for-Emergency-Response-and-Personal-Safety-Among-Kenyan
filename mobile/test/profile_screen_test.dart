import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/screens/password_reset_screen.dart';
import 'package:mobile/features/shared/screens/profile_screen.dart';
import 'package:mobile/features/shared/services/profile_repository.dart';
import 'package:image/image.dart' as image;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:mobile/features/auth/services/auth_repository.dart';
import 'package:mobile/features/shared/screens/profile_photo_crop_screen.dart';

void main() {
  for (final accept in [false, true]) {
    testWidgets(
      'cropped photo ${accept ? 'is accepted only after preview' : 'can be cancelled without a result'}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final bytes = Uint8List.fromList(
          image.encodePng(image.Image(width: 96, height: 96)),
        );
        Uint8List? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push<Uint8List>(
                      MaterialPageRoute(
                        builder: (_) => ProfilePhotoCropScreen(bytes: bytes),
                      ),
                    );
                  },
                  child: const Text('Select profile photo'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Select profile photo'));
        await _pumpUntil(
          tester,
          () =>
              find.text('Crop Photo').evaluate().isNotEmpty &&
              tester
                      .widget<FilledButton>(find.byType(FilledButton))
                      .onPressed !=
                  null,
        );
        await tester.tap(find.text('Crop Photo'));
        await _pumpUntil(
          tester,
          () => find.text('Preview profile photo').evaluate().isNotEmpty,
        );
        expect(find.text('Preview profile photo'), findsOneWidget);
        expect(result, isNull);
        if (accept) {
          await tester.tap(find.text('Use Photo'));
        } else {
          await tester.tap(find.text('Cancel'));
        }
        await tester.pumpAndSettle();
        expect(find.text('Select profile photo'), findsOneWidget);
        if (accept) {
          expect(image.decodeJpg(result!)!.width, 512);
        } else {
          expect(result, isNull);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('photo replacement and removal update the profile and clean up stored files', () async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'resident'),
    );
    final firestore = FakeFirebaseFirestore();
    final storage = MockFirebaseStorage();
    final repository = ProfileRepository(
      auth: auth,
      firestore: firestore,
      storage: storage,
    );
    final profile = firestore.collection('users').doc('resident');
    const oldPath = 'profilePhotos/resident/old.jpg';
    final bytes = prepareProfilePhoto(
      Uint8List.fromList(image.encodePng(image.Image(width: 32, height: 32))),
    );
    await profile.set({'profilePhotoPath': oldPath});
    await storage.ref(oldPath).putData(bytes);
    await repository.savePhoto(bytes);
    final newPath = (await profile.get()).data()!['profilePhotoPath'] as String;
    expect(newPath, startsWith('profilePhotos/resident/'));
    expect(newPath, isNot(oldPath));
    expect(await storage.ref(oldPath).getData(), isNull);
    expect(await repository.loadPhoto(newPath), bytes);
    await repository.removePhoto();
    expect((await profile.get()).data()!['profilePhotoPath'], isNull);
    expect(await storage.ref(newPath).getData(), isNull);
    await expectLater(
      repository.loadPhoto('profilePhotos/another-user/photo.jpg'),
      throwsFormatException,
    );
  });

  test('failed profile write rolls back the new photo without deleting the old one', () async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'resident'),
    );
    final firestore = FakeFirebaseFirestore();
    final storage = MockFirebaseStorage();
    final repository = ProfileRepository(
      auth: auth,
      firestore: firestore,
      storage: storage,
    );
    const oldPath = 'profilePhotos/resident/old.jpg';
    final profile = firestore.collection('users').doc('resident');
    final bytes = prepareProfilePhoto(
      Uint8List.fromList(image.encodePng(image.Image(width: 32, height: 32))),
    );
    await profile.set({'profilePhotoPath': oldPath});
    await storage.ref(oldPath).putData(bytes);
    firestore.securityRules = FakeFirebaseFirestore(
      securityRules: '''
      service cloud.firestore {
        match /databases/{database}/documents {
          match /users/{userId} { allow read: if true; allow write: if false; }
        }
      }
    ''',
    ).securityRules;
    await expectLater(repository.savePhoto(bytes), throwsA(isA<Exception>()));
    expect((await profile.get()).data()!['profilePhotoPath'], oldPath);
    expect(await storage.ref(oldPath).getData(), bytes);
    expect(storage.storedDataMap, hasLength(1));
  });

  test('profile repository rejects stale edits and protected fields', () async {
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'resident'),
    );
    final firestore = FakeFirebaseFirestore();
    final repository = ProfileRepository(auth: auth, firestore: firestore);
    final profile = firestore.collection('users').doc('resident');
    await profile.set({'firstName': 'Jane'});
    await expectLater(
      repository.saveDetails({'role': 'SystemAdmin'}, {}),
      throwsArgumentError,
    );
    await expectLater(
      repository.saveDetails({'firstName': 'Amina'}, {'firstName': 'Old name'}),
      throwsStateError,
    );
    expect((await profile.get()).data()!['firstName'], 'Jane');
    await repository.saveDetails({'firstName': 'Amina'}, {'firstName': 'Jane'});
    await Future<void>.delayed(Duration.zero);
    expect((await profile.get()).data()!['firstName'], 'Amina');
  });

  test(
    'password reset hides missing accounts and enforces repository cooldown',
    () async {
      final auth = _ResetTestAuth('user-not-found');
      final repository = AuthRepository(
        firebaseAuth: auth,
        firestore: FakeFirebaseFirestore(),
      );
      await repository.requestPasswordReset(' unknown@example.com ');
      expect(auth.emails, ['unknown@example.com']);
      await expectLater(
        repository.requestPasswordReset('unknown@example.com'),
        throwsA(
          isA<FirebaseAuthException>().having(
            (error) => error.code,
            'code',
            'too-many-requests',
          ),
        ),
      );
      expect(auth.emails, hasLength(1));
    },
  );

  test('password reset network failures allow a later retry', () async {
    final auth = _ResetTestAuth('network-request-failed');
    final repository = AuthRepository(
      firebaseAuth: auth,
      firestore: FakeFirebaseFirestore(),
    );
    await expectLater(
      repository.requestPasswordReset('resident@example.com'),
      throwsA(isA<FirebaseAuthException>()),
    );
    auth.errorCode = null;
    await repository.requestPasswordReset('resident@example.com');
    expect(auth.emails, hasLength(2));
  });

  test(
    'cropped profile photos are resized JPEGs with no original metadata',
    () {
      final source = image.Image(width: 96, height: 96);
      source.exif.imageIfd['ImageDescription'] = 'private metadata';
      final prepared = prepareProfilePhoto(
        Uint8List.fromList(image.encodeJpg(source)),
      );
      final decoded = image.decodeJpg(prepared)!;
      expect(decoded.width, 512);
      expect(decoded.height, 512);
      expect(decoded.exif.imageIfd['ImageDescription'], isNull);
      expect(prepared.length, lessThan(2 * 1024 * 1024));
      expect(
        () => prepareProfilePhoto(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    },
  );

  for (final fails in [false, true]) {
    testWidgets(
      'profile save ${fails ? 'failure retains edits' : 'requires confirmation'}',
      (tester) async {
        final repository = _TestProfileRepository()..failSave = fails;
        addTearDown(repository.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ProfileScreen(repository: repository)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TextFormField), findsNothing);
        await tester.tap(find.byTooltip('Edit profile'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).first, 'Amina');
        await tester.drag(find.byType(ListView), const Offset(0, -650));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Review Changes'));
        await tester.tap(find.text('Review Changes'));
        await tester.pumpAndSettle();
        expect(repository.saves, 0);
        expect(find.text('Current: Jane'), findsOneWidget);
        expect(find.text('New: Amina'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(repository.saves, 0);
        await tester.tap(find.text('Review Changes'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Save Changes'));
        await tester.pumpAndSettle();
        expect(repository.saves, 1);
        if (fails) {
          expect(
            find.textContaining('Your edits have been kept'),
            findsOneWidget,
          );
          expect(find.text('Review Changes'), findsOneWidget);
          expect(repository.data['firstName'], 'Jane');
        } else {
          expect(repository.data['firstName'], 'Amina');
          expect(find.byType(TextFormField), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('profile photo removal requires explicit confirmation', (
    tester,
  ) async {
    final repository = _TestProfileRepository();
    repository.data['profilePhotoPath'] = 'profilePhotos/resident/photo.jpg';
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProfileScreen(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();
    expect(repository.removals, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.removals, 0);
    await tester.tap(find.text('Edit photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove Photo'));
    await tester.pumpAndSettle();
    expect(repository.removals, 1);
    expect(find.text('Add photo'), findsOneWidget);
    expect(
      tester.widget<CircleAvatar>(find.byType(CircleAvatar)).backgroundImage,
      isNull,
    );
  });

  testWidgets(
    'password reset validates email, uses a neutral response and prevents rapid resends',
    (tester) async {
      final emails = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PasswordResetScreen(
            sendResetEmail: (email) async => emails.add(email),
          ),
        ),
      );
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();
      expect(emails, isEmpty);
      expect(find.text('Please enter a valid email address.'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField),
        ' resident@example.com ',
      );
      await tester.tap(find.text('Send reset link'));
      await tester.pumpAndSettle();
      expect(emails, ['resident@example.com']);
      expect(find.textContaining('If an account exists'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 61));
      expect(find.text('Resend reset link'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('password reset network error remains retryable', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PasswordResetScreen(
          initialEmail: 'resident@example.com',
          lockEmail: true,
          sendResetEmail: (_) async {
            attempts += 1;
            if (attempts == 1) {
              throw FirebaseAuthException(code: 'network-request-failed');
            }
          },
        ),
      ),
    );
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Check your email'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() completed) async {
  for (var attempt = 0; attempt < 150; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (completed()) return;
  }
  fail('The crop operation did not finish.');
}

class _TestProfileRepository extends ProfileRepository {
  final data = <String, dynamic>{
    'firstName': 'Jane',
    'lastName': 'Doe',
    'phoneNumber': '+254712345678',
    'preferredLanguage': 'en',
    'role': 'Resident',
    'accountStatus': 'Active',
  };
  final _updates = StreamController<Map<String, dynamic>?>.broadcast();
  bool failSave = false;
  int saves = 0;
  int removals = 0;

  @override
  String? get email => 'resident@example.com';
  @override
  bool get supportsCamera => false;
  @override
  Stream<Map<String, dynamic>?> watchProfile() async* {
    yield Map<String, dynamic>.from(data);
    yield* _updates.stream;
  }

  @override
  Future<Uint8List?> recoverLostPhoto() async => null;
  @override
  Future<Uint8List?> loadPhoto(String path) async =>
      Uint8List.fromList(image.encodePng(image.Image(width: 32, height: 32)));
  @override
  Future<void> saveDetails(
    Map<String, dynamic> changes,
    Map<String, dynamic> original,
  ) async {
    saves += 1;
    if (failSave) throw Exception('Save failed');
    data.addAll(changes);
    _updates.add(Map<String, dynamic>.from(data));
  }

  @override
  Future<void> removePhoto() async {
    removals += 1;
    data['profilePhotoPath'] = null;
    _updates.add(Map<String, dynamic>.from(data));
  }

  Future<void> dispose() => _updates.close();
}

class _ResetTestAuth extends MockFirebaseAuth {
  _ResetTestAuth(this.errorCode);
  String? errorCode;
  final emails = <String>[];

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    emails.add(email);
    if (errorCode != null) throw FirebaseAuthException(code: errorCode!);
  }
}
