import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseEmailQueueService {
  FirebaseEmailQueueService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<void> queueInviteEmail({
    required String toEmail,
    required String invitedName,
    required String inviteLink,
    required String companyName,
  }) async {
    final safeName = invitedName.trim().isEmpty ? 'there' : invitedName.trim();
    final safeCompany = companyName.trim().isEmpty ? 'BW Fire Door Inspection' : companyName.trim();
    final subject = 'Invitation to join $safeCompany';
    final text = [
      'Hi $safeName,',
      '',
      'You have been invited to join $safeCompany.',
      'Use the link below to accept your invitation and set your password:',
      inviteLink,
      '',
      'If you were not expecting this invitation, please ignore this email.',
    ].join('\n');

    final html = '''
<div style="font-family:Arial,sans-serif;font-size:14px;line-height:1.6;color:#1f2937;">
  <p>Hi ${_escapeHtml(safeName)},</p>
  <p>You have been invited to join <strong>${_escapeHtml(safeCompany)}</strong>.</p>
  <p>
    <a href="${_escapeHtml(inviteLink)}" style="display:inline-block;padding:12px 18px;background:#1565C0;color:#ffffff;text-decoration:none;border-radius:6px;">
      Accept Invitation
    </a>
  </p>
  <p>Or copy this link into your browser:</p>
  <p><a href="${_escapeHtml(inviteLink)}">${_escapeHtml(inviteLink)}</a></p>
  <p>If you were not expecting this invitation, please ignore this email.</p>
</div>
''';

    await _firestore.collection('mail').add({
      'to': [toEmail.trim()],
      'message': {
        'subject': subject,
        'text': text,
        'html': html,
      },
      'meta': {
        'type': 'invite',
        'createdAt': FieldValue.serverTimestamp(),
      },
    });
  }

  String _escapeHtml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}