const admin = require('firebase-admin');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');

admin.initializeApp();

exports.sendWorkflowPush = onDocumentCreated(
  'companies/{companyId}/notificationQueue/{queueId}',
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      return;
    }

    const queue = snapshot.data();
    const companyId = event.params.companyId;
    const recipientUserId = (queue.recipientUserId || '').trim();
    const payload = queue.payload || {};
    if (!companyId || !recipientUserId) {
      return;
    }

    const db = admin.firestore();
    const tokenSnapshot = await db
      .collection('companies')
      .doc(companyId)
      .collection('deviceTokens')
      .where('userId', '==', recipientUserId)
      .where('active', '==', true)
      .get();

    const tokens = tokenSnapshot.docs
      .map((doc) => (doc.get('token') || '').trim())
      .filter(Boolean);

    if (tokens.length === 0) {
      await snapshot.ref.set({ status: 'no_tokens', processedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
      return;
    }

    const message = {
      tokens,
      notification: {
        title: payload.title || 'Workflow update',
        body: payload.body || 'Open the app for details.',
      },
      data: Object.entries(payload).reduce((acc, [key, value]) => {
        acc[key] = value == null ? '' : String(value);
        return acc;
      }, {}),
      android: {
        priority: 'high',
        notification: {
          channelId: 'workflow_updates',
          priority: 'high',
          defaultSound: true,
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    const invalidTokens = [];
    response.responses.forEach((result, index) => {
      if (!result.success) {
        const code = result.error && result.error.code;
        if (code === 'messaging/invalid-registration-token' || code === 'messaging/registration-token-not-registered') {
          invalidTokens.push(tokens[index]);
        }
      }
    });

    if (invalidTokens.length > 0) {
      const batch = db.batch();
      for (const token of invalidTokens) {
        const deviceId = require('crypto').createHash('sha1').update(token).digest('hex');
        batch.delete(db.collection('companies').doc(companyId).collection('deviceTokens').doc(deviceId));
      }
      await batch.commit();
    }

    await snapshot.ref.set(
      {
        status: response.failureCount > 0 ? 'partial' : 'sent',
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
        successCount: response.successCount,
        failureCount: response.failureCount,
      },
      { merge: true },
    );
  },
);
