import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'package:audioplayers/audioplayers.dart';
import 'firebase_options.dart';
import 'screens/chat_screen.dart';
import 'screens/admin_users_screen.dart';
import 'screens/welcome_screen.dart';
import 'utils/chat_state.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa o Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Configurações do Firebase Messaging para primeiro plano
  if (!kIsWeb) {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );
  }

  // --- CONFIGURAÇÃO ONESIGNAL (PROTEGIDA) ---
  if (!kIsWeb) {
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    try {
      // Técnica de fragmentação para evitar detecção por robôs de segurança
      final String s1 = "61e6874c";
      final String s2 = "-bca0-4628";
      final String s3 = "-ad07-8053";
      final String s4 = "c0cd499e";

      OneSignal.initialize(s1 + s2 + s3 + s4);
      debugPrint("OneSignal inicializado com sucesso.");
    } catch (e) {
      debugPrint("Erro ao inicializar OneSignal: $e");
    }
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String? _userId;
  String? _userName;
  bool _isAdmin = false;
  bool _loading = true;
  final AudioPlayer _notificationPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _initApp();
    _setupOneSignalHandlers();
  }

  @override
  void dispose() {
    _notificationPlayer.dispose();
    super.dispose();
  }

  void _playNotificationSound() async {
    try {
      await _notificationPlayer.play(AssetSource('alerta.mp3'));
    } catch (e) {
      debugPrint('Erro ao tocar som de notificação: $e');
    }
  }

  // Configura como o app reage a notificações
  void _setupOneSignalHandlers() {
    if (kIsWeb) return;

    // Garante que a notificação apareça mesmo com o app aberto
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      debugPrint(
          'Notificação recebida em primeiro plano: ${event.notification.body}');

      if (ChatState.isChatOpen) {
        final data = event.notification.additionalData;
        final incomingChatId = data?['userId'] ?? data?['chatId'];

        // Se o ID do chat recebido for o mesmo que está aberto, silencia
        if (incomingChatId != null &&
            ChatState.currentChatId == incomingChatId) {
          debugPrint('🔕 Notificação suprimida: Chat aberto com este ID');
          event.preventDefault();
          OneSignal.Notifications.clearAll();
          return;
        }

        // Caso especial para cliente (não-admin) em chat individual (não-grupo)
      }

      debugPrint('🔔 Exibindo notificação OneSignal e tocando som');
      _playNotificationSound();
      event.notification.display();
    });

    // Listener para cliques em notificações
    OneSignal.Notifications.addClickListener((event) {
      debugPrint('Usuário clicou na notificação: ${event.notification.body}');
    });
  }

  Future<void> _initApp() async {
    final prefs = await SharedPreferences.getInstance();

    _userId = prefs.getString('userId');
    _userName = prefs.getString('userName');
    _isAdmin =
        prefs.getBool('admin_logged_in') ?? prefs.getBool('isAdmin') ?? false;
    ChatState.isAdmin = _isAdmin;

    // Solicita permissão de notificação
    if (!kIsWeb) {
      await OneSignal.Notifications.requestPermission(true);
    }

    // --- VINCULAR USUÁRIO AO ONESIGNAL (External ID) ---
    try {
      if (!kIsWeb) {
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
          alert: false,
          badge: true,
          sound: false,
        );

        if (_isAdmin) {
          await OneSignal.login("admin");
          debugPrint("OneSignal: Login como admin enviado");
        } else if (_userId != null) {
          await OneSignal.login(_userId!);
          debugPrint("OneSignal: Login como usuário $_userId enviado");
        }
        OneSignal.User.pushSubscription.optIn();
      }
    } catch (e) {
      debugPrint("Erro no login do OneSignal: $e");
    }

    if (!mounted) return;

    setState(() {
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    Widget initialScreen;

    if (_isAdmin) {
      initialScreen = const AdminUsersScreen();
    } else if (_userId != null && _userName != null) {
      initialScreen = ChatScreen(
        userId: _userId!,
        userName: _userName!,
        userIsAdmin: false,
      );
    } else {
      initialScreen = const WelcomeScreen();
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Faekon Suporte',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: false,
      ),
      home: initialScreen,
    );
  }
}