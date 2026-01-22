importScripts('https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js');
self.addEventListener('message', function(event) {
  if (event && event.data && event.data.type === 'CLOSE_ALL') {
    self.registration.getNotifications().then(function(notifs) {
      notifs.forEach(function(n) { try { n.close(); } catch (e) {} });
    });
  }
});
