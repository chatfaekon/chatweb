const functions = require("firebase-functions");
const admin = require("firebase-admin");
const axios = require("axios");

admin.initializeApp();

// Dispara quando uma nova mensagem é criada na coleção 'chats'
exports.sendNewMessageNotification = functions.firestore
  .document("chats/{chatId}/messages/{messageId}")
  .onCreate(async (snap, context) => {
    const message = snap.data();
    const chatId = context.params.chatId;

    // 1. Se quem enviou foi o admin ou sistema, NÃO notifica o admin
    if (message.sender === "admin" || message.system) {
      return null;
    }

    // Configurações do OneSignal (Copiadas do seu projeto)
    const ONESIGNAL_APP_ID = "61e6874c-bca0-4628-ad07-8053c0cd499e";
    const ONESIGNAL_API_KEY = "os_v2_app_mhtiotf4ubdcrlihqbj4btkjtzcp3x7kjsvumnno2g5alttjvsoi6sdhoish262moszwyec7vxq62odkztzk5dnzbidhesr2bfjliui";

    try {
      // 2. Busca o nome do usuário para usar no título da notificação
      const chatDoc = await admin.firestore().collection("chats").doc(chatId).get();
      const userName = chatDoc.exists ? (chatDoc.data().userName || "Novo Cliente") : "Novo Cliente";

      let notificationBody = message.text || "Nova mensagem";
      if (message.fileUrl) {
        if (message.fileType === 'image') notificationBody = "📷 Foto";
        else if (message.fileType === 'audio') notificationBody = "🎤 Áudio";
        else notificationBody = "📎 Arquivo";
      }

      // 3. Envia a notificação via API do OneSignal (Server-to-Server funciona 100%)
      await axios.post(
        "https://onesignal.com/api/v1/notifications",
        {
          app_id: ONESIGNAL_APP_ID,
          include_aliases: { external_id: ["admin"] }, // Envia especificamente para o admin
          target_channel: "push",
          headings: { pt: userName, en: userName },
          contents: { pt: notificationBody, en: notificationBody },
          android_sound: "alerta",
          priority: 10,
          data: { 
            userId: chatId,
            chatId: chatId,
          }, // Passa os dados para o admin
        },
        {
          headers: {
            "Content-Type": "application/json; charset=utf-8",
            "Authorization": `Basic ${ONESIGNAL_API_KEY}`,
          },
        }
      );
      console.log(`Notificação enviada para admin sobre mensagem de ${userName}`);
    } catch (error) {
      console.error("Erro ao enviar notificação:", error.response ? error.response.data : error.message);
    }
  });

// Endpoint HTTP para o Web enviar notificação ao Admin com CORS liberado
exports.notifyAdmin = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }
  try {
    const { chatId, title, message } = req.body || {};
    if (!chatId || !message) {
      res.status(400).json({ error: "Parâmetros ausentes: chatId e message são obrigatórios" });
      return;
    }
    const ONESIGNAL_APP_ID = "61e6874c-bca0-4628-ad07-8053c0cd499e";
    const ONESIGNAL_API_KEY = "os_v2_app_mhtiotf4ubdcrlihqbj4btkjtzcp3x7kjsvumnno2g5alttjvsoi6sdhoish262moszwyec7vxq62odkztzk5dnzbidhesr2bfjliui";
    const heading = title || "Novo Cliente";
    await axios.post(
      "https://onesignal.com/api/v1/notifications",
      {
        app_id: ONESIGNAL_APP_ID,
        include_aliases: { external_id: ["admin"] },
        target_channel: "push",
        headings: { pt: heading, en: heading },
        contents: { pt: message, en: message },
        android_sound: "alerta",
        priority: 10,
        data: { 
          userId: chatId, 
          chatId: chatId,
        },
      },
      {
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "Authorization": `Basic ${ONESIGNAL_API_KEY}`,
        },
      }
    );
    res.status(200).json({ ok: true });
  } catch (error) {
    console.error("notifyAdmin error:", error.response ? error.response.data : error.message);
    res.status(500).json({ error: "Falha ao enviar notificação" });
  }
});
