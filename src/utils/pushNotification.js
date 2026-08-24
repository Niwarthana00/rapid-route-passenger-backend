/**
 * Utility to dispatch Push Notifications via Expo Push Service API
 */
export const sendPushNotification = async ({ to, title, body, sound = 'default', data = {} }) => {
  if (!to || typeof to !== 'string') {
    return null;
  }

  try {
    const response = await fetch('https://exp.host/--/api/v2/push/send', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({
        to,
        sound,
        title,
        body,
        data,
      }),
    });

    const result = await response.json();
    console.log(`[PUSH NOTIFICATION] Sent to ${to}:`, result);
    return result;
  } catch (err) {
    console.error('[PUSH NOTIFICATION ERROR]:', err.message);
    return null;
  }
};
