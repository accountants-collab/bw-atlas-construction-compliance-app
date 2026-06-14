import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'auth_state.dart';

class MemberProfile {
  final String companyId;
  final UserRole role;
  const MemberProfile({required this.companyId, required this.role});
}

class FirebaseAuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  FirebaseAuthRepository({FirebaseAuth? auth, FirebaseFirestore? db})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<UserCredential> signInWithEmailPassword({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() => _auth.signOut();

  DocumentReference<Map<String, dynamic>> _inviteDoc(String code) =>
      _db.collection('invites').doc(code);

  DocumentReference<Map<String, dynamic>> _memberDoc(
          {required String companyId, required String uid}) =>
      _db.collection('companies').doc(companyId).collection('members').doc(uid);

  Future<MemberProfile?> getMemberProfile(String uid) async {
    final tenantSnap = await _db.collection('userTenants').doc(uid).get();
    final companyId = (tenantSnap.data()?['companyId'] as String?)?.trim();
    if (companyId == null || companyId.isEmpty) return null;

    final memberSnap = await _memberDoc(companyId: companyId, uid: uid).get();
    final data = memberSnap.data();
    if (data == null) return null;

    final active = data['active'] as bool?;
    if (active == false) return null;

    final roleStr = (data['role'] as String?)?.toLowerCase().trim();
    if (roleStr == 'owner') {
      return MemberProfile(companyId: companyId, role: UserRole.owner);
    }
    if (roleStr == 'admin') {
      return MemberProfile(companyId: companyId, role: UserRole.admin);
    }
    if (roleStr == 'manager') {
      return MemberProfile(companyId: companyId, role: UserRole.manager);
    }
    if (roleStr == 'worker') {
      return MemberProfile(companyId: companyId, role: UserRole.worker);
    }
    return null;
  }

  Future<void> registerWorkerWithInvite({
    required String inviteCode,
    required String email,
    required String password,
  }) async {
    if (inviteCode.isEmpty) throw Exception('Missing invite code.');

    final inviteRef = _inviteDoc(inviteCode);

    // Reserve a use
    await _db.runTransaction((tx) async {
      final snap = await tx.get(inviteRef);
      final data = snap.data();
      if (data == null) throw Exception('Invalid invite code.');

      if (data['active'] == false) throw Exception('Invite inactive.');

      final expiresAt = data['expiresAt'];
      if (expiresAt is Timestamp &&
          expiresAt.toDate().isBefore(DateTime.now())) {
        throw Exception('Invite expired.');
      }

      final maxUses = (data['maxUses'] as num?)?.toInt();
      final usedCount = (data['usedCount'] as num?)?.toInt() ?? 0;
      if (maxUses != null && usedCount >= maxUses) {
        throw Exception('Invite max uses reached.');
      }

      final companyId = (data['companyId'] as String?)?.trim();
      if (companyId == null || companyId.isEmpty) {
        throw Exception('Invite missing companyId.');
      }

      final role = (data['role'] as String?)?.toLowerCase().trim() ?? 'worker';
      if (role != 'worker') throw Exception('Invite not for workers.');

      tx.update(inviteRef, {
        'usedCount': usedCount + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    // Create auth user
    final cred = await _auth.createUserWithEmailAndPassword(
        email: email, password: password);
    final uid = cred.user?.uid;
    if (uid == null) throw Exception('Registration failed.');

    // Read companyId
    final inviteSnap = await inviteRef.get();
    final companyId = (inviteSnap.data()?['companyId'] as String?)?.trim();
    if (companyId == null || companyId.isEmpty) {
      throw Exception('Invite missing companyId.');
    }

    // Write membership
    final batch = _db.batch();
    batch.set(_db.collection('userTenants').doc(uid), {
      'companyId': companyId,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(_memberDoc(companyId: companyId, uid: uid), {
      'role': 'worker',
      'active': true,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  // -------------------------
  // Manager: create invite
  // -------------------------

  static const _inviteAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0,O,1,I
  static final _rng = Random.secure();

  String _randomInviteCode({int length = 8}) {
    return List.generate(
      length,
      (_) => _inviteAlphabet[_rng.nextInt(_inviteAlphabet.length)],
    ).join();
  }

  Future<String> createWorkerInvite({
    required String companyId,
    required String createdByUid,
    int? maxUses,
    Duration? validFor,
  }) async {
    if (companyId.trim().isEmpty) throw Exception('Missing companyId.');
    if (createdByUid.trim().isEmpty) throw Exception('Missing createdByUid.');

    // Try a few times in case of collision
    for (var i = 0; i < 10; i++) {
      final code = _randomInviteCode(length: 8);
      final ref = _inviteDoc(code);

      try {
        await _db.runTransaction((tx) async {
          final existing = await tx.get(ref);
          if (existing.exists) {
            throw Exception('Invite code collision. Retry.');
          }

          final now = Timestamp.now();
          final expiresAt = validFor == null
              ? null
              : Timestamp.fromDate(DateTime.now().add(validFor));

          tx.set(ref, {
            'active': true,
            'companyId': companyId.trim(),
            'role': 'worker',
            'usedCount': 0,
            if (maxUses != null) 'maxUses': maxUses,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'createdByUid': createdByUid.trim(),
            if (expiresAt != null) 'expiresAt': expiresAt,
            'createdAtClient': now, // optional debug
          });
        });

        return code;
      } catch (_) {
        // continue retry
      }
    }

    throw Exception('Failed to generate invite code (too many collisions).');
  }
}