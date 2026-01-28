importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyB1Vdl_ns_MoJQ5cXx8_E740C4X2PagRoY",
  authDomain: "chatfaekon-806e9.firebaseapp.com",
  projectId: "chatfaekon-806e9",
  storageBucket: "chatfaekon-806e9.firebasestorage.app",
  messagingSenderId: "111503786110",
  appId: "1:111503786110:web:e54d18901e78db995dd82f"
});

const messaging = firebase.messaging();

// Background messages
messaging.onBackgroundMessage((payload) => {
  console.log("[firebase-messaging-sw.js] Received background message ", payload);
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: "/favicon.png",
    data: payload.data
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});
