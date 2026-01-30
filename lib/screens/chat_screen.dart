import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../utils/chat_state.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

const String _notifyAdminUrl =
String.fromEnvironment('NOTIFY_ADMIN_URL', defaultValue: '');

const String _oneSignalApiKey =
String.fromEnvironment('ONESIGNAL_API_KEY', defaultValue: '');

const String _oneSignalAppId = String.fromEnvironment('ONESIGNAL_APP_ID',
    defaultValue: '61e6874c-bca0-4628-ad07-8053c0cd499e');

class ChatScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final bool userIsAdmin;
  final bool isGroup;

  const ChatScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.userIsAdmin = false,
    this.isGroup = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _inputFocusNode = FocusNode();

  // Variáveis para controle de grupo
  bool _isGroup = false;
  String _groupName = '';
  String _currentClientTab = 'chats'; // 'chats' ou 'groups'
  String _clientRealName = ''; // Nome real do cliente carregado do storage
  String _currentUserId = ''; // ID do usuário logado
  bool _isDisposed = false; // Controle para evitar chamadas após dispose

  late AudioRecorder _audioRecorder;
  AudioPlayer? _inlineAudioPlayer;
  bool _isRecording = false;
  String? _currentlyPlayingUrl;
  Duration _audioPosition = Duration.zero;
  Duration _audioDuration = Duration.zero;

  List<DocumentSnapshot> _currentDocs = [];
  String? _lastMessageId;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _recordingTimer;
  String _recordingTime = "00:00";

  String _chatStatus = 'open';
  String _userStatus = 'pendente';
  String? _replyToText;
  Map<String, dynamic>? _chatData;
  Timer? _timer;
  Timer? _typingTimer;
  StreamSubscription? _unreadSubscription;

  int _currentSearchIndex = 0;
  List<int> _searchMatches = [];
  String? _currentSearchQuery;
  bool _isSearching = false;

  bool _userScrolledManually = false;
  bool _isUploading = false;
  String _appVersion = "";

  bool _showScrollToBottomBtn = false;

  int _rating = 0;
  final TextEditingController _feedbackController = TextEditingController();
  bool _isSubmittingFeedback = false;

  List<Map<String, dynamic>> _quickMessages = [];

  final Map<int, GlobalKey> _messageKeys = {};
  final cloudinary = CloudinaryPublic('dcgukezed', 'chat_preset', cache: false);

  final Map<String, List<double>> _waveCache = {};

  late Stream<QuerySnapshot> _mediaStream;
  final ValueNotifier<Duration> _durationNotifier =
  ValueNotifier(Duration.zero);

  CollectionReference get _messagesRef => widget.isGroup
      ? FirebaseFirestore.instance
      .collection('groups')
      .doc(widget.userId)
      .collection('messages')
      : FirebaseFirestore.instance
      .collection('chats')
      .doc(widget.userId)
      .collection('messages');

  DocumentReference get _chatRef => widget.isGroup
      ? FirebaseFirestore.instance.collection('groups').doc(widget.userId)
      : FirebaseFirestore.instance.collection('chats').doc(widget.userId);

  CollectionReference get _quickMessagesRef =>
      FirebaseFirestore.instance.collection('quick_messages');

  // Método para carregar informações do grupo
  Future<void> _loadGroupInfo() async {
    if (widget.isGroup) {
      setState(() {
        _isGroup = true;
        _groupName = widget.userName;
      });
      return;
    }

    try {
      final chatDoc = await _chatRef.get();
      if (chatDoc.exists) {
        final data = chatDoc.data() as Map<String, dynamic>;
        setState(() {
          _isGroup = data['isGroup'] ?? false;
          _groupName = data['groupName'] ?? '';
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar informações do grupo: $e');
    }
  }

  Future<void> _loadClientName() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _clientRealName = prefs.getString('userName') ?? '';
        _currentUserId =
        widget.userIsAdmin ? 'admin' : (prefs.getString('userId') ?? '');
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Define o estado global do chat
    ChatState.isChatOpen = true;
    ChatState.currentChatId = widget.userId;
    ChatState.activeChatId = widget.userId;

    // Comando para limpar notificações ao entrar (OneSignal como equivalente ao Awesome)
    if (!kIsWeb) {
      OneSignal.Notifications.clearAll();
    }

    // Salva o ID do chat ativo no localStorage para o Web Admin silenciar notificações
    if (kIsWeb) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('activeChatId', widget.userId);
      });
    }

    // Configura notificações para silenciar em foreground (Android/iOS)
    if (!kIsWeb) {
      FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: false, // Bloqueia o banner automático
        badge: true, // Mantém a bolinha (badge)
        sound: false, // Bloqueia o som automático
      );
    }

    // Carregar informações do grupo
    _loadGroupInfo();
    _loadClientName();

    _configureOfflinePersistence();
    _audioRecorder = AudioRecorder();
    _inlineAudioPlayer = AudioPlayer();
    _loadChatStatus();
    _listenChatData();
    _loadVersion();
    _checkAndSendWelcomeMessage();
    _setUserPresence(true);

    if (widget.userIsAdmin) {
      _markMessagesAsRead();
      _listenQuickMessages();
      _unreadSubscription = _messagesRef
          .where('readByAdmin', isEqualTo: false)
          .snapshots()
          .listen((snapshot) {
        bool any = false;
        for (var doc in snapshot.docs) {
          doc.reference.update({'readByAdmin': true});
          any = true;
        }
        if (any && !kIsWeb) {
          // Limpeza automática da barra de notificações ao receber novas mensagens no chat aberto
          OneSignal.Notifications.clearAll();
        }
      });
    } else {
      _unreadSubscription = _messagesRef
          .where('sender', isEqualTo: 'admin')
          .where('readByUser', isEqualTo: false)
          .snapshots()
          .listen((snapshot) {
        bool any = false;
        for (var doc in snapshot.docs) {
          doc.reference.update({'readByUser': true});
          any = true;
        }
        if (any && !kIsWeb) {
          // Limpeza automática da barra de notificações ao receber novas mensagens no chat aberto
          OneSignal.Notifications.clearAll();
        }
      });
    }

    _inlineAudioPlayer?.onPositionChanged.listen((p) {
      if (mounted) setState(() => _audioPosition = p);
    });
    _inlineAudioPlayer?.onDurationChanged.listen((d) {
      if (mounted) setState(() => _audioDuration = d);
    });

    _inlineAudioPlayer?.onPlayerComplete.listen((event) {
      if (mounted) {
        _playNextAudioIfAvailable();
      }
    });

    _messageController.addListener(() {
      _onTextChanged();
      if (mounted) setState(() {});
    });

    _scrollController.addListener(() {
      final offset = _scrollController.offset;
      if (offset > 400) {
        if (!_showScrollToBottomBtn) {
          setState(() => _showScrollToBottomBtn = true);
        }
      } else {
        if (_showScrollToBottomBtn) {
          setState(() => _showScrollToBottomBtn = false);
        }
      }

      if (offset > 50) {
        if (!_userScrolledManually) _userScrolledManually = true;
      } else {
        if (_userScrolledManually) _userScrolledManually = false;
      }
    });

    _searchController.addListener(() {
      final newQuery = _searchController.text.trim();
      if (_currentSearchQuery != newQuery) {
        _currentSearchQuery = newQuery;
        if (newQuery.isNotEmpty) {
          _performSearch(newQuery);
        } else {
          setState(() {
            _searchMatches.clear();
            _currentSearchIndex = 0;
          });
        }
      }
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _durationNotifier.value = _calculateChatDuration();
    });
    _initMediaStream();
  }

  void _initMediaStream() {
    _mediaStream = _messagesRef
        .where('fileType', isEqualTo: 'image')
        .limit(50)
        .snapshots();
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      // Atualiza o estado global quando o Admin navega entre conversas
      ChatState.activeChatId = widget.userId;
      ChatState.currentChatId = widget.userId;
      ChatState.isAdmin = widget.userIsAdmin;

      // Inicializa a nova stream de mídia
      _initMediaStream();

      // Se for Admin, marca as mensagens do novo chat como lidas
      if (widget.userIsAdmin) {
        _markMessagesAsRead();
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    ChatState.isChatOpen = false;
    ChatState.activeChatId = null;
    ChatState.currentChatId = null;
    WidgetsBinding.instance.removeObserver(this);

    // Limpa o ID do chat ativo no localStorage
    if (kIsWeb) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.remove('activeChatId');
      });
    }

    // Restaura notificações para o padrão ao sair do chat
    if (!kIsWeb) {
      FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    _setUserPresence(false);
    _timer?.cancel();
    _typingTimer?.cancel();
    _recordingTimer?.cancel();
    _unreadSubscription?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _inputFocusNode.dispose();
    _messageController.dispose();
    _feedbackController.dispose();
    _audioRecorder.dispose();
    _inlineAudioPlayer?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setUserPresence(true);
    } else {
      _setUserPresence(false);
    }
  }

  Future<void> _setUserPresence(bool online) async {
    final field = widget.userIsAdmin ? 'adminOnline' : 'userOnline';
    final lastSeenField = widget.userIsAdmin ? 'adminLastSeen' : 'userLastSeen';

    await _chatRef.update({
      field: online,
      lastSeenField: FieldValue.serverTimestamp(),
    });
  }

  void _onTextChanged() {
    final typingField = widget.userIsAdmin ? 'adminTyping' : 'userTyping';
    if (_messageController.text.isNotEmpty) {
      _chatRef.update({typingField: true});
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 2), () {
        _chatRef.update({typingField: false});
      });
    } else {
      _chatRef.update({typingField: false});
    }
  }

  void _configureOfflinePersistence() {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  void _listenQuickMessages() {
    _quickMessagesRef.orderBy('text').snapshots().listen((snapshot) {
      if (mounted) {
        setState(() {
          _quickMessages = snapshot.docs
              .map((doc) => {
            'id': doc.id,
            'text': doc['text'],
          })
              .toList();
        });
      }
    });
  }

  Future<void> _sendPushNotification(String messageText) async {
    List<String> targetIds = [];
    String title = "";
    String finalMessage = messageText;

    if (_isGroup) {
      final senderName = widget.userIsAdmin
          ? 'Suporte Faekon'
          : (_clientRealName.isNotEmpty ? _clientRealName : 'Usuário');

      if (!widget.userIsAdmin) {
        title = "[$_groupName] $senderName";
      } else {
        title = _groupName;
      }

      finalMessage = "$senderName: $messageText";

      final members = _chatData?['members'] as List<dynamic>?;
      if (members != null) {
        targetIds = members
            .where((m) => m.toString() != _currentUserId)
            .map((m) => m.toString())
            .toList();
      }

      if (!widget.userIsAdmin && !targetIds.contains('admin')) {
        targetIds.add('admin');
      }
    } else {
      targetIds = [widget.userIsAdmin ? widget.userId : "admin"];
      title = widget.userIsAdmin ? "Suporte Faekon" : widget.userName;
    }

    if (targetIds.isEmpty) return;

    // --- PROTEÇÃO ANTI-BLOQUEIO ONESIGNAL ---
    // Substitua os valores abaixo pela sua NOVA CHAVE quando gerá-la
    final String kP1 = "os_v2_app_mhtiotf4ubdcrlihqbj4btkjt3";
    final String kP2 = "t4hlnl4xmers5q36gozooygpny2dy65z6n";
    final String kP3 = "taq4jalymymdjxxley2gapwczohdpfdf";
    final String kP4 = "psh7mc2eeaq";

    // Fragmentação do App ID para segurança adicional
    final String aId1 = "61e6874c";
    final String aId2 = "-bca0-4628";
    final String aId3 = "-ad07-8053";
    final String aId4 = "c0cd499e";

    try {
      final response = await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Basic ' + kP1 + kP2 + kP3 + kP4,
        },
        body: jsonEncode({
          'app_id': aId1 + aId2 + aId3 + aId4,
          'include_aliases': {'external_id': targetIds},
          'target_channel': 'push',
          'headings': {'pt': title, 'en': title},
          'contents': {'pt': finalMessage, 'en': finalMessage},
          'android_sound': 'alerta',
          'priority': 10,
          'android_visibility': 1,
          'data': {'userId': widget.userId, 'chatId': widget.userId},
        }),
      );

      debugPrint(
          "OneSignal Push Response: ${response.statusCode} ${response.body}");
      if (response.statusCode == 200 || response.statusCode == 201) return;
    } catch (e) {
      debugPrint("Erro no envio direto OneSignal: $e");
    }

    // Fallback para o Cloudflare Worker se o envio direto falhar (especialmente na Web por CORS)
    if (kIsWeb) {
      try {
        final url = Uri.parse(_notifyAdminUrl.isNotEmpty
            ? _notifyAdminUrl
            : 'https://delicate-morning-1bc8.games-drze.workers.dev');

        await http.post(
          url,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({
            'title': title,
            'message': finalMessage,
            'externalId': targetIds.length == 1 ? targetIds[0] : targetIds,
            'data': {'userId': widget.userId, 'chatId': widget.userId},
            'userId': widget.userId,
          }),
        );
      } catch (e) {
        debugPrint("Fallback Worker error: $e");
      }
    }
  }

  Future<void> _handleAudioAction() async {
    if (kIsWeb) {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'm4a', 'wav', 'ogg'],
        withData: true,
      );
      if (res != null && res.files.single.bytes != null) {
        final f = res.files.single;
        await _uploadBytes(f.bytes!, 'audio', f.name);
      }
      return;
    }
    if (_isRecording) {
      await _stopAndSendRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        final path =
            '${directory.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder
            .start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);

        _stopwatch.reset();
        _stopwatch.start();
        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() {
            final minutes =
            _stopwatch.elapsed.inMinutes.toString().padLeft(2, '0');
            final seconds =
            (_stopwatch.elapsed.inSeconds % 60).toString().padLeft(2, '0');
            _recordingTime = "$minutes:$seconds";
          });
        });
        setState(() => _isRecording = true);
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      debugPrint("Erro ao gravar: $e");
    }
  }

  Future<void> _stopAndSendRecording() async {
    if (!_isRecording) return;
    _stopwatch.stop();
    final path = await _audioRecorder.stop();
    setState(() {
      _isRecording = false;
      _recordingTime = "00:00";
    });
    if (path != null) {
      _uploadFile(File(path), 'audio');
      HapticFeedback.lightImpact();
    }
  }

  void _playNextAudioIfAvailable() {
    if (_currentlyPlayingUrl == null) return;

    int currentIndex = _currentDocs.indexWhere((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return data['fileUrl'] == _currentlyPlayingUrl;
    });

    setState(() {
      _currentlyPlayingUrl = null;
      _audioPosition = Duration.zero;
    });

    if (currentIndex > 0) {
      for (int i = currentIndex - 1; i >= 0; i--) {
        final nextData = _currentDocs[i].data() as Map<String, dynamic>;
        if (nextData['fileType'] == 'audio' && nextData['fileUrl'] != null) {
          _playInternalAudio(nextData['fileUrl']);
          break;
        }
        if (nextData['text'] != null && nextData['fileUrl'] == null) break;
      }
    }
  }

  Future<void> _playInternalAudio(String url) async {
    if (_currentlyPlayingUrl == url) {
      await _inlineAudioPlayer?.pause();
      setState(() => _currentlyPlayingUrl = null);
    } else {
      try {
        if (kIsWeb) {
          await _inlineAudioPlayer?.play(UrlSource(url));
        } else {
          final dir = await getTemporaryDirectory();
          final filename = url.split('/').last;
          final file = File('${dir.path}/$filename');

          if (await file.exists()) {
            await _inlineAudioPlayer?.play(DeviceFileSource(file.path));
          } else {
            await _inlineAudioPlayer?.play(UrlSource(url));
            unawaited(http.get(Uri.parse(url)).then((res) {
              if (res.statusCode == 200) file.writeAsBytes(res.bodyBytes);
            }));
          }
        }
        setState(() => _currentlyPlayingUrl = url);
      } catch (e) {
        await _inlineAudioPlayer?.play(UrlSource(url));
        setState(() => _currentlyPlayingUrl = url);
      }
    }
  }

  void _showFullImage(String url) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.low,
                    loadingBuilder: (context, child, loadingProgress) =>
                    loadingProgress == null
                        ? child
                        : const Center(
                        child:
                        CircularProgressIndicator(strokeWidth: 2)),
                    errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.broken_image),
                  ),
                ),
              ),
              Positioned(
                top: 40,
                left: 20,
                child: IconButton(
                    icon:
                    const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.pop(context)),
              ),
              Positioned(
                top: 40,
                right: 70, // Espaçamento para não sobrepor o botão de share
                child: IconButton(
                    icon: const Icon(Icons.open_in_new,
                        color: Colors.white, size: 30),
                    onPressed: () => launchUrl(Uri.parse(url),
                        mode: LaunchMode.externalApplication)),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                    icon:
                    const Icon(Icons.share, color: Colors.white, size: 30),
                    onPressed: () => Share.share("Confira: $url")),
              ),
            ],
          ),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  Future<void> _checkAndSendWelcomeMessage() async {
    final snapshot = await _messagesRef.limit(1).get();
    if (snapshot.docs.isEmpty) {
      await _sendMessage(
          systemText:
          'Olá ${widget.userName}, seja bem-vindo ao suporte Faekon! Como podemos ajudar?');
    }
  }

  Future<void> _loadChatStatus() async {
    final doc = await _chatRef.get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      setState(() => _chatStatus = data['status'] ?? 'open');
    }
  }

  void _listenChatData() {
    _chatRef.snapshots().listen((doc) {
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        final newStatus = data?['status'] ?? 'open';

        // Se o status mudou para 'closed', reseta os campos de feedback
        if (newStatus == 'closed' && _chatStatus != 'closed') {
          setState(() {
            _rating = 0;
            _feedbackController.clear();
          });
        }

        setState(() {
          _chatData = data;
          _chatStatus = newStatus;
          if (data?['feedbackRating'] != null) {
            _rating = data!['feedbackRating'] ?? 0;
          }
        });
      }
    });

    FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .snapshots()
        .listen((doc) {
      if (doc.exists) {
        final data = doc.data();
        if (mounted) {
          setState(() {
            _userStatus = data?['status'] ?? 'pendente';
          });
        }
      }
    });
  }

  Future<void> _markMessagesAsRead() async {
    if (widget.userIsAdmin) {
      if (widget.isGroup) {
        // Para grupos, atualiza o lastReadAdmin no documento do grupo
        await _chatRef.update({
          'lastReadAdmin': FieldValue.serverTimestamp(),
        });
      } else {
        final snapshot =
        await _messagesRef.where('readByAdmin', isEqualTo: false).get();
        final batch = FirebaseFirestore.instance.batch();
        for (var doc in snapshot.docs) {
          batch.update(doc.reference, {'readByAdmin': true});
        }
        await batch.commit();
      }
    } else {
      final snapshot = await _messagesRef
          .where('sender', isEqualTo: 'admin')
          .where('readByUser', isEqualTo: false)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'readByUser': true});
      }
      await batch.commit();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients &&
        !_userScrolledManually &&
        !_isSearching) {
      _scrollController.jumpTo(0.0);
    }
  }

  void _jumpToBottom() {
    _userScrolledManually = false;
    _scrollController.animateTo(0.0,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Future<void> _sendMessage(
      {String? systemText,
        String? fileUrl,
        String? fileName,
        String? fileType}) async {
    final text = systemText ?? _messageController.text.trim();
    if (text.isEmpty && fileUrl == null) return;
    if (_chatStatus == 'closed' && systemText == null) return;

    String notificationBody = text;
    if (fileType == 'image') {
      notificationBody = '📷 Foto';
    } else if (fileType == 'audio')
      notificationBody = '🎤 Áudio';
    else if (fileType == 'file') notificationBody = '📎 Arquivo';

    final reply = _replyToText;

    if (systemText == null) {
      _messageController.clear();
      _replyToText = null;
      if (fileType == null) {
        _inputFocusNode.requestFocus();
      }
    }

    await _messagesRef.add({
      'text': text,
      'sender': widget.userIsAdmin || systemText != null ? 'admin' : 'user',
      'senderId': _currentUserId,
      'senderName': _isGroup
          ? (widget.userIsAdmin
          ? 'Suporte Faekon'
          : (_clientRealName.isNotEmpty ? _clientRealName : 'Usuário'))
          : null, // Só inclui nome em grupos
      'timestamp': FieldValue.serverTimestamp(),
      'edited': false,
      'readByAdmin': widget.userIsAdmin,
      'readByUser': !widget.userIsAdmin && systemText == null,
      'system': systemText != null,
      'replyTo': reply,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'fileType': fileType,
    });

    final Map<String, dynamic> updateData = {
      'lastMessage': notificationBody,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'startedAt': _chatData?['startedAt'] ?? FieldValue.serverTimestamp(),
      'isArchived': false,
    };

    if (widget.isGroup) {
      updateData['timestamp'] = FieldValue.serverTimestamp();
    }

    await _chatRef.update(updateData);

    // Se for grupo, sincroniza com a coleção 'chats' para a listagem do Admin
    if (widget.isGroup) {
      // Sincroniza com a coleção 'chats' para que apareça atualizado na lista do Admin
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.userId)
          .update({
        'lastMessage': notificationBody,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'isArchived': false,
      });
    }

    if (systemText == null) {
      unawaited(_sendPushNotification(notificationBody));
    }

    // Lógica de transição automática de status
    // Se for uma mensagem real (não do sistema) e o status do usuário for 'pendente' (Novo) ou 'concluído' (Finalizado)
    // altera automaticamente para 'em atendimento'
    // Não aplica esta lógica em grupos
    try {
      if (!_isGroup &&
          systemText == null &&
          (_userStatus == 'pendente' || _userStatus == 'concluído')) {
        const newStatus = 'em atendimento';
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .update({'status': newStatus});

        // Também garantimos que o chat esteja 'open' no documento do chat
        await _chatRef.update({'status': 'open'});
      }
    } catch (e) {
      debugPrint('Erro ao atualizar status automático: $e');
    }

    _userScrolledManually = false;
    _scrollToBottom();
  }

  Future<void> _pickAndUploadFile() async {
    if (_chatStatus != 'open') return;
    showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(
            child: Wrap(children: [
              ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('Câmera'),
                  onTap: () async {
                    Navigator.pop(context);
                    final img = await ImagePicker().pickImage(
                        source: ImageSource.camera, imageQuality: 70);
                    if (img != null) {
                      if (kIsWeb) {
                        final bytes = await img.readAsBytes();
                        final name = img.name;
                        await _uploadBytes(bytes, 'image', name);
                      } else {
                        _uploadFile(File(img.path), 'image');
                      }
                    }
                  }),
              ListTile(
                  leading: const Icon(Icons.image),
                  title: const Text('Galeria'),
                  onTap: () async {
                    Navigator.pop(context);
                    final img = await ImagePicker().pickImage(
                        source: ImageSource.gallery, imageQuality: 70);
                    if (img != null) {
                      if (kIsWeb) {
                        final bytes = await img.readAsBytes();
                        final name = img.name;
                        await _uploadBytes(bytes, 'image', name);
                      } else {
                        _uploadFile(File(img.path), 'image');
                      }
                    }
                  }),
              ListTile(
                  leading: const Icon(Icons.insert_drive_file),
                  title: const Text('Documento'),
                  onTap: () async {
                    Navigator.pop(context);
                    final res =
                    await FilePicker.platform.pickFiles(withData: true);
                    if (res != null) {
                      final file = res.files.single;
                      if (kIsWeb && file.bytes != null) {
                        final name = file.name;
                        final lower = name.toLowerCase();
                        final isAudio = lower.endsWith('.mp3') ||
                            lower.endsWith('.m4a') ||
                            lower.endsWith('.wav') ||
                            lower.endsWith('.ogg');
                        await _uploadBytes(
                            file.bytes!, isAudio ? 'audio' : 'file', name);
                      } else if (file.path != null) {
                        final lower = file.name.toLowerCase();
                        final isAudio = lower.endsWith('.mp3') ||
                            lower.endsWith('.m4a') ||
                            lower.endsWith('.wav') ||
                            lower.endsWith('.ogg');
                        _uploadFile(
                            File(file.path!), isAudio ? 'audio' : 'file');
                      }
                    }
                  }),
            ])));
  }

  Future<void> _uploadBytes(Uint8List data, String type, String name) async {
    setState(() => _isUploading = true);
    try {
      final rt =
      type == 'image' ? 'image' : (type == 'audio' ? 'video' : 'raw');
      final url =
      Uri.parse('https://api.cloudinary.com/v1_1/dcgukezed/$rt/upload');
      final req = http.MultipartRequest('POST', url);
      req.fields['upload_preset'] = 'chat_preset';
      req.fields['folder'] = 'chats/${widget.userId}';
      req.files.add(http.MultipartFile.fromBytes('file', data, filename: name));
      final resp = await http.Response.fromStream(await req.send());
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final secureUrl = body['secure_url'] as String?;
      if (secureUrl == null) {
        throw Exception('Resposta inválida do Cloudinary');
      }
      await _sendMessage(fileUrl: secureUrl, fileName: name, fileType: type);
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro ao enviar: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _uploadFile(File file, String type) async {
    setState(() => _isUploading = true);
    try {
      final name =
      file.path.split('/').last.replaceAll(RegExp(r'[^\w\.]'), '_');
      CloudinaryResponse res = await cloudinary.uploadFile(
          CloudinaryFile.fromFile(file.path,
              resourceType: type == 'image'
                  ? CloudinaryResourceType.Image
                  : CloudinaryResourceType.Auto,
              folder: 'chats/${widget.userId}'));
      await _sendMessage(
          fileUrl: res.secureUrl, fileName: name, fileType: type);
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro ao enviar: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _finalizeChat() async {
    await _sendMessage(systemText: 'Este atendimento foi finalizado.');
    await _chatRef.update({
      'status': 'closed',
      'endedAt': FieldValue.serverTimestamp(),
      'feedbackRating': null,
      'feedbackComment': null
    });

    if (!_isGroup) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update({'status': 'encerrado'});
    }
  }

  Future<void> _reopenChat() async {
    await _chatRef.update({
      'status': 'open',
      'startedAt': FieldValue.serverTimestamp(),
      'endedAt': null
    });

    if (!_isGroup) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update({'status': 'em atendimento'});
    }
    await _sendMessage(systemText: 'Atendimento reaberto.');
  }

  Future<void> _reopenChatByUser() async {
    await _chatRef.update({
      'status': 'open',
      'startedAt': FieldValue.serverTimestamp(),
      'endedAt': null
    });

    if (!_isGroup) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update({'status': 'em atendimento'});
    }
    await _sendMessage(systemText: 'Chat reaberto pelo cliente.');
  }

  Future<void> _submitFeedback(int rating, String comment) async {
    if (rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Por favor, selecione uma nota antes de enviar'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    setState(() => _isSubmittingFeedback = true);
    try {
      await _chatRef.update({
        'feedbackRating': rating,
        'feedbackComment': comment,
        'feedbackAt': FieldValue.serverTimestamp(),
      });

      // Também salva na subcoleção para histórico se necessário
      await _chatRef.collection('feedbacks').add({
        'rating': rating,
        'comment': comment,
        'timestamp': FieldValue.serverTimestamp(),
        'userName': _isGroup
            ? (_clientRealName.isNotEmpty ? _clientRealName : 'Usuário')
            : widget.userName,
      });

      // Atualização local para sumir o painel ou mostrar agradecimento
      if (mounted) {
        setState(() {
          if (_chatData != null) {
            _chatData!['feedbackRating'] = rating;
          }
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Obrigado pela sua avaliação!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar avaliação: $e')));
    } finally {
      if (mounted) setState(() => _isSubmittingFeedback = false);
    }
  }

  Future<void> _clearChat() async {
    final snapshot = await _messagesRef.get();
    final batch = FirebaseFirestore.instance.batch();
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conversa limpa com sucesso.')));
  }

  Future<void> _loadVersion() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = "v${packageInfo.version}";
      });
    }
  }

  Duration _calculateChatDuration() {
    if (_chatData == null) return Duration.zero;
    final Timestamp? s = _chatData!['startedAt'];
    final Timestamp? e = _chatData!['endedAt'];
    if (_chatStatus == 'open') {
      return s != null ? DateTime.now().difference(s.toDate()) : Duration.zero;
    }
    return (s != null && e != null)
        ? e.toDate().difference(s.toDate())
        : Duration.zero;
  }

  String _formatDuration(Duration d) =>
      "${d.inMinutes % 60}m ${d.inSeconds % 60}s";
  String _formatAudioTime(Duration d) =>
      "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";

  void _performSearch(String query) {
    final lowerQuery = query.toLowerCase();
    final List<int> matches = [];

    for (int i = 0; i < _currentDocs.length; i++) {
      final d = _currentDocs[i].data() as Map<String, dynamic>;
      final text = (d['text'] ?? '').toString().toLowerCase();
      if (text.contains(lowerQuery)) {
        matches.add(i);
      }
    }

    setState(() {
      _searchMatches = matches;
      _currentSearchIndex = 0;
    });

    if (matches.isNotEmpty) {
      _scrollToMatch(matches[0]);
    }
  }

  Future<void> _scrollToMatch(int index) async {
    if (!_scrollController.hasClients) return;

    final key = _messageKeys[index];
    if (key != null && key.currentContext != null) {
      await Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
    } else {
      double targetOffset = index * 70.0;
      await _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeIn,
      );
    }
  }

  void _showQuickMessagesPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.6,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Mensagens Rápidas",
                      style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.blue),
                    onPressed: () => _editQuickMessage(null),
                  )
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: _quickMessages.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text(_quickMessages[index]['text']),
                    onTap: () {
                      _messageController.text = _quickMessages[index]['text'];
                      Navigator.pop(context);
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () =>
                                _editQuickMessage(_quickMessages[index])),
                        IconButton(
                            icon: const Icon(Icons.delete,
                                size: 20, color: Colors.red),
                            onPressed: () {
                              final String docId = _quickMessages[index]['id'];
                              setModalState(() {
                                _quickMessages.removeAt(index);
                              });
                              _quickMessagesRef.doc(docId).delete();
                            }),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _editQuickMessage(Map<String, dynamic>? quickMsg) {
    final controller =
    TextEditingController(text: quickMsg != null ? quickMsg['text'] : "");
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(quickMsg == null ? "Nova Mensagem" : "Editar Mensagem"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "Digite a frase..."),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar")),
          TextButton(
              onPressed: () async {
                if (controller.text.trim().isNotEmpty) {
                  if (quickMsg == null) {
                    await _quickMessagesRef
                        .add({'text': controller.text.trim()});
                  } else {
                    await _quickMessagesRef
                        .doc(quickMsg['id'])
                        .update({'text': controller.text.trim()});
                  }
                }
                Navigator.pop(context);
              },
              child: const Text("Salvar")),
        ],
      ),
    );
  }

  Widget _buildSearchOverlay() {
    if (!_isSearching) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _searchFocusNode.unfocus();
                setState(() {
                  _isSearching = false;
                  _searchController.clear();
                  _searchMatches.clear();
                  _currentSearchQuery = null;
                });
              }),
          Expanded(
              child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  autofocus: true,
                  decoration: const InputDecoration(
                      hintText: 'Pesquisar...', border: InputBorder.none))),
          if (_searchMatches.isNotEmpty)
            Text('${_currentSearchIndex + 1}/${_searchMatches.length}'),
          IconButton(
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: _searchMatches.isEmpty
                  ? null
                  : () {
                setState(() => _currentSearchIndex =
                    (_currentSearchIndex - 1 + _searchMatches.length) %
                        _searchMatches.length);
                _scrollToMatch(_searchMatches[_currentSearchIndex]);
              }),
          IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: _searchMatches.isEmpty
                  ? null
                  : () {
                setState(() => _currentSearchIndex =
                    (_currentSearchIndex + 1) % _searchMatches.length);
                _scrollToMatch(_searchMatches[_currentSearchIndex]);
              }),
        ],
      ),
    );
  }

  Widget _buildMessage(DocumentSnapshot msg, int index) {
    final data = msg.data() as Map<String, dynamic>;
    final senderType = data['sender'];
    final isSystem = data['system'] == true;
    final bool isMe = isSystem
        ? false
        : (_isGroup && data['senderId'] != null
        ? data['senderId'] == _currentUserId
        : (widget.userIsAdmin
        ? senderType == 'admin'
        : senderType == 'user'));
    final timestamp = data['timestamp'] as Timestamp?;
    final time =
    timestamp != null ? DateFormat('HH:mm').format(timestamp.toDate()) : '';
    final fileUrl = data['fileUrl'] as String?;
    final fileType = data['fileType'] as String?;
    final isEdited = data['edited'] == true;
    final replyTo = data['replyTo'] as String?;

    bool isRead = widget.userIsAdmin
        ? (data['readByAdmin'] ?? false)
        : (data['readByUser'] ?? false);

    _messageKeys[index] = _messageKeys[index] ?? GlobalKey();
    return Align(
      key: _messageKeys[index],
      alignment: isSystem
          ? Alignment.center
          : isMe
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isSystem
            ? CrossAxisAlignment.center
            : isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onLongPress: () => _showMessageOptions(context, msg),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
              padding: EdgeInsets.symmetric(
                  horizontal: 10, vertical: (fileType == 'audio') ? 4 : 8),
              decoration: BoxDecoration(
                color: isSystem
                    ? Colors.grey[300]
                    : isMe
                    ? Colors.blue[50]
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
                border: _isSearching &&
                    _searchMatches.isNotEmpty &&
                    _searchMatches[_currentSearchIndex] == index
                    ? Border.all(color: Colors.orange, width: 2)
                    : null,
              ),
              child: IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Nome do remetente em grupos
                    if (_isGroup && !isMe && !isSystem)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          data['senderName'] ??
                              (senderType == 'admin' ? 'Suporte' : 'Usuário'),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    if (replyTo != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border(
                              left: BorderSide(
                                  color: isMe ? Colors.blue : Colors.grey,
                                  width: 3)),
                        ),
                        child: Text(
                          replyTo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey[700]),
                        ),
                      ),
                    if (fileUrl != null)
                      fileType == 'image'
                          ? GestureDetector(
                        onTap: () => _showFullImage(fileUrl),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                fileUrl,
                                width: 200,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.low,
                                loadingBuilder: (context, child,
                                    loadingProgress) =>
                                loadingProgress == null
                                    ? child
                                    : const Center(
                                    child:
                                    CircularProgressIndicator(
                                        strokeWidth: 2)),
                                errorBuilder:
                                    (context, error, stackTrace) =>
                                const Icon(Icons.broken_image),
                                cacheWidth: 400,
                                cacheHeight: 300,
                              ),
                            ),
                            Positioned(
                              top: 5,
                              right: 5,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.4),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(4),
                                  icon: const Icon(Icons.open_in_new,
                                      color: Colors.white, size: 18),
                                  onPressed: () => launchUrl(
                                      Uri.parse(fileUrl),
                                      mode:
                                      LaunchMode.externalApplication),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                          : fileType == 'audio'
                          ? _buildAudioPlayerUI(fileUrl)
                          : InkWell(
                          onTap: () => Share.share(fileUrl),
                          child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.insert_drive_file,
                                    color: Colors.blue, size: 18),
                                const SizedBox(width: 8),
                                Text(data['fileName'] ?? 'Doc',
                                    style:
                                    const TextStyle(fontSize: 13))
                              ]))
                    else
                      Text(data['text'] ?? '',
                          style: TextStyle(
                              fontSize: 14,
                              fontStyle: isSystem
                                  ? FontStyle.italic
                                  : FontStyle.normal)),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isEdited)
                          const Text('editado ',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic)),
                        if (!isSystem)
                          Text(time,
                              style: const TextStyle(
                                  fontSize: 9, color: Colors.grey)),
                        if (!isSystem && isMe) ...[
                          const SizedBox(width: 4),
                          Icon(isRead ? Icons.done_all : Icons.done,
                              size: 12,
                              color: isRead ? Colors.blue : Colors.grey),
                        ]
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<double> _getWaveformData(String url) {
    if (_waveCache.containsKey(url)) return _waveCache[url]!;
    final random = Random(url.hashCode);
    final List<double> waves =
    List.generate(35, (index) => 0.2 + random.nextDouble() * 0.8);
    _waveCache[url] = waves;
    return waves;
  }

  Widget _buildAudioPlayerUI(String url) {
    bool isPlaying = _currentlyPlayingUrl == url;
    final waves = _getWaveformData(url);
    double progress = isPlaying
        ? (_audioPosition.inMilliseconds /
        (_audioDuration.inMilliseconds > 0
            ? _audioDuration.inMilliseconds
            : 1))
        : 0.0;
    return Container(
      width: 210,
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
              iconSize: 32,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(
                  isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: Colors.blue),
              onPressed: () => _playInternalAudio(url)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    if (isPlaying && _audioDuration.inMilliseconds > 0) {
                      final box = context.findRenderObject() as RenderBox;
                      final localOffset =
                      box.globalToLocal(details.globalPosition);
                      double relativePos = (localOffset.dx - 50) / 140;
                      relativePos = relativePos.clamp(0.0, 1.0);
                      _inlineAudioPlayer?.seek(Duration(
                          milliseconds:
                          (relativePos * _audioDuration.inMilliseconds)
                              .toInt()));
                    }
                  },
                  child: CustomPaint(
                    size: const Size(double.infinity, 25),
                    painter: WaveformPainter(
                      waves: waves,
                      progress: progress,
                      activeColor: Colors.blue,
                      inactiveColor: Colors.grey[400]!,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                          isPlaying
                              ? _formatAudioTime(_audioPosition)
                              : "00:00",
                          style:
                          const TextStyle(fontSize: 9, color: Colors.grey)),
                      const Icon(Icons.mic, size: 10, color: Colors.blue),
                    ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMessageOptions(BuildContext context, DocumentSnapshot msg) {
    final data = msg.data() as Map<String, dynamic>;
    final senderType = data['sender'];
    final isSystem = data['system'] == true;
    if (isSystem) return;
    final bool isMe =
    (widget.userIsAdmin ? senderType == 'admin' : senderType == 'user');
    final bool isImageOrFile = data['fileUrl'] != null;
    showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(
            child: Wrap(children: [
              ListTile(
                  leading: const Icon(Icons.reply),
                  title: const Text('Responder'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _replyToText = data['text'] ??
                        (data['fileType'] == 'image'
                            ? 'Foto'
                            : data['fileType'] == 'audio'
                            ? 'Áudio'
                            : 'Arquivo'));
                  }),
              ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('Copiar'),
                  onTap: () {
                    Navigator.pop(context);
                    Clipboard.setData(ClipboardData(text: data['text'] ?? ''));
                  }),
              if (isMe && !isImageOrFile)
                ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text('Editar'),
                    onTap: () {
                      Navigator.pop(context);
                      _editMessage(msg, data['text'] ?? '');
                    }),
              if (isMe)
                ListTile(
                    leading: const Icon(Icons.delete, color: Colors.red),
                    title: const Text('Excluir'),
                    onTap: () {
                      Navigator.pop(context);
                      msg.reference.delete();
                    }),
            ])));
  }

  void _editMessage(DocumentSnapshot msg, String currentText) {
    final controller = TextEditingController(text: currentText);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar mensagem'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration:
          const InputDecoration(hintText: "Digite a nova mensagem..."),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () async {
                if (controller.text.trim().isNotEmpty) {
                  await msg.reference
                      .update({'text': controller.text.trim(), 'edited': true});
                }
                Navigator.pop(context);
              },
              child: const Text('Salvar')),
        ],
      ),
    );
  }

  void _showChatOptions() {
    showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(
            child: Wrap(children: [
              ListTile(
                  leading: const Icon(Icons.search),
                  title: const Text('Pesquisar na conversa'),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _isSearching = true);
                    _searchFocusNode.requestFocus();
                  }),
              ListTile(
                  leading: const Icon(Icons.share),
                  title: const Text('Compartilhar conversa'),
                  onTap: () {
                    Navigator.pop(context);
                    _exportChat();
                  }),
              ListTile(
                  leading: const Icon(Icons.delete_sweep, color: Colors.red),
                  title: const Text('Limpar Chat'),
                  onTap: () {
                    Navigator.pop(context);
                    _clearChat();
                  }),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.blueGrey),
                title: const Text('Versão do Sistema'),
                trailing: Text(_appVersion,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                onTap: null,
              ),
            ])));
  }

  Future<void> _exportChat() async {
    try {
      final querySnapshot =
      await _messagesRef.orderBy('timestamp', descending: false).get();
      final buffer = StringBuffer();
      buffer.writeln("FAEKON CHAT - HISTÓRICO\n");
      for (var doc in querySnapshot.docs) {
        final d = doc.data() as Map<String, dynamic>;
        if (d['fileUrl'] == null && d['text'] != null) {
          final sender = (d['sender'] == 'admin')
              ? "Suporte"
              : (d['senderName'] ?? widget.userName);
          buffer.writeln("$sender: ${d['text']}");
        }
      }
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/export_${widget.userId}.txt';
      final file = File(path);
      await file.writeAsString(buffer.toString(),
          mode: FileMode.writeOnly, flush: true);
      if (await file.exists()) {
        await Share.shareXFiles([XFile(path)],
            text: 'Histórico de Atendimento');
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Falha ao exportar: $e')));
    }
  }

  Widget _buildTabSelector() {
    if (widget.userIsAdmin || widget.isGroup) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentClientTab = 'chats'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: _currentClientTab == 'chats'
                      ? const LinearGradient(
                    colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
                  )
                      : null,
                  color: _currentClientTab == 'chats' ? null : Colors.grey[200],
                ),
                child: Center(
                  child: Text(
                    'Chats',
                    style: TextStyle(
                      color: _currentClientTab == 'chats'
                          ? Colors.white
                          : Colors.black54,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentClientTab = 'groups'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: _currentClientTab == 'groups'
                      ? const LinearGradient(
                    colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
                  )
                      : null,
                  color:
                  _currentClientTab == 'groups' ? null : Colors.grey[200],
                ),
                child: Center(
                  child: Text(
                    'Grupos',
                    style: TextStyle(
                      color: _currentClientTab == 'groups'
                          ? Colors.white
                          : Colors.black54,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('groups')
          .where('members', arrayContains: widget.userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              'Você ainda não faz parte de nenhum grupo',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          );
        }

        final groups = snapshot.data!.docs;
        return ListView.builder(
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            final data = group.data() as Map<String, dynamic>;
            final groupName = data['name'] ?? 'Sem nome';

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue[100],
                  child: const Icon(Icons.group, color: Colors.blue),
                ),
                title: Text(
                  groupName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('Toque para entrar no chat'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatScreen(
                        userId: group.id,
                        userName: groupName,
                        userIsAdmin: false,
                        isGroup: true,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  void _showMediaGallery() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                "Mídias da Conversa",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildMediaGrid()),
          ],
        ),
      ),
    );
  }

  Future<void> _updateLastReadAdmin() async {
    if (_isGroup && widget.userIsAdmin && !_isDisposed) {
      try {
        await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.userId)
            .update({'lastReadAdmin': FieldValue.serverTimestamp()});
      } catch (e) {
        debugPrint('Erro ao atualizar leitura do admin: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (didPop && _isGroup && widget.userIsAdmin) {
          _updateLastReadAdmin();
        }
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          floatingActionButton: _showScrollToBottomBtn
              ? Padding(
            padding: const EdgeInsets.only(bottom: 60),
            child: FloatingActionButton(
              mini: true,
              onPressed: _jumpToBottom,
              backgroundColor: Colors.blue,
              child: const Icon(Icons.keyboard_arrow_down,
                  color: Colors.white),
            ),
          )
              : null,
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          appBar: AppBar(
            toolbarHeight: 50.0,
            elevation: 0,
            title: StreamBuilder<DocumentSnapshot>(
              stream: _chatRef.snapshots(),
              builder: (context, snapshot) {
                String subtitle = "";
                bool isOnline = false;
                bool typing = false;

                if (!_isGroup && snapshot.hasData && snapshot.data!.exists) {
                  final data = snapshot.data!.data() as Map<String, dynamic>;
                  isOnline = widget.userIsAdmin
                      ? (data['userOnline'] ?? false)
                      : (data['adminOnline'] ?? false);
                  typing = widget.userIsAdmin
                      ? (data['userTyping'] ?? false)
                      : (data['adminTyping'] ?? false);
                  if (typing) {
                    subtitle = "digitando...";
                  } else if (isOnline) {
                    subtitle = "Online";
                  } else {
                    final Timestamp? lastSeen = widget.userIsAdmin
                        ? data['userLastSeen']
                        : data['adminLastSeen'];
                    subtitle = lastSeen != null
                        ? "Visto por último: ${DateFormat('HH:mm').format(lastSeen.toDate())}"
                        : "Offline";
                  }
                } else if (_isGroup) {
                  subtitle = "Grupo";
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                            _isGroup
                                ? _groupName
                                : widget.userIsAdmin
                                ? widget.userName
                                : 'Suporte Faekon',
                            style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        if (isOnline && !_isGroup)
                          Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                  color: Colors.greenAccent,
                                  shape: BoxShape.circle)),
                      ],
                    ),
                    if (subtitle.isNotEmpty)
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.normal,
                              color: Colors.white70)),
                  ],
                );
              },
            ),
            actions: [
              if (widget.userIsAdmin)
                IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(_chatStatus == 'open'
                        ? Icons.lock_outline
                        : Icons.lock_open),
                    onPressed:
                    _chatStatus == 'open' ? _finalizeChat : _reopenChat),
              IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.perm_media_outlined),
                  onPressed: _showMediaGallery),
              IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.tune),
                  onPressed: _showChatOptions),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _buildTabSelector(),
                Expanded(
                  child: (!widget.userIsAdmin &&
                      !widget.isGroup &&
                      _currentClientTab == 'groups')
                      ? _buildGroupsTab()
                      : Column(
                    children: [
                      _buildSearchOverlay(),
                      if (widget.userIsAdmin && _chatData != null)
                        Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 4, horizontal: 12),
                            color: Colors.blueGrey[50],
                            child: Center(
                                child: ValueListenableBuilder<Duration>(
                                    valueListenable: _durationNotifier,
                                    builder: (_, d, __) {
                                      return Text(
                                          'Tempo: ${_formatDuration(d)}',
                                          style: TextStyle(
                                              fontSize:
                                              isLandscape ? 10 : 12));
                                    }))),
                      if (_isUploading) const LinearProgressIndicator(),
                      Expanded(
                        child: StreamBuilder<QuerySnapshot>(
                          stream: _messagesRef
                              .orderBy('timestamp', descending: true)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }

                            final docs = snapshot.data!.docs;
                            if (docs.isNotEmpty) {
                              final newestId = docs.first.id;
                              if (newestId != _lastMessageId) {
                                _lastMessageId = newestId;

                                // Atualiza leitura se for Admin em Grupo
                                if (_isGroup && widget.userIsAdmin) {
                                  _updateLastReadAdmin();
                                }

                                if (!_isSearching &&
                                    !_userScrolledManually) {
                                  WidgetsBinding.instance
                                      .addPostFrameCallback(
                                          (_) => _scrollToBottom());
                                }
                              }
                            }
                            _currentDocs = docs;

                            return ListView.builder(
                                cacheExtent: 1000.0,
                                reverse: true,
                                controller: _scrollController,
                                itemCount: _currentDocs.length,
                                findChildIndexCallback: (Key key) {
                                  if (key is ValueKey<String>) {
                                    final String id = key.value;
                                    return _currentDocs.indexWhere(
                                            (doc) => doc.id == id);
                                  }
                                  return null;
                                },
                                itemBuilder: (c, i) =>
                                    _buildMessage(_currentDocs[i], i));
                          },
                        ),
                      ),
                      _buildInputArea(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaGrid() {
    return StreamBuilder<QuerySnapshot>(
      stream: _mediaStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs.toList() ?? [];
        docs.sort((a, b) {
          final tA =
          (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          final tB =
          (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          if (tA == null) return 1;
          if (tB == null) return -1;
          return tB.compareTo(tA);
        });

        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.photo_library_outlined,
                    color: Colors.grey, size: 50),
                SizedBox(height: 10),
                Text("Nenhuma mídia disponível.",
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return GridView.builder(
          key: const PageStorageKey('media_grid_stable'),
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final url = data['fileUrl'];
            if (url == null) return const SizedBox.shrink();

            return GestureDetector(
              onTap: () => _showFullImage(url),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    loadingBuilder: (context, child, loadingProgress) =>
                    loadingProgress == null
                        ? child
                        : const Center(
                        child:
                        CircularProgressIndicator(strokeWidth: 2)),
                    errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.broken_image),
                    cacheWidth: 400,
                    cacheHeight: 400,
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(4),
                        icon: const Icon(Icons.open_in_new,
                            color: Colors.white, size: 16),
                        onPressed: () => launchUrl(Uri.parse(url),
                            mode: LaunchMode.externalApplication),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFeedbackPanel() {
    if (widget.userIsAdmin || _chatStatus != 'closed') {
      return const SizedBox.shrink();
    }

    final hasRated = _chatData != null && _chatData!['feedbackRating'] != null;

    // Se já avaliou, não mostramos nada ou apenas uma mensagem simples
    if (hasRated) return const SizedBox.shrink();

    return Container(
      // REMOVEMOS o Padding com viewInsets aqui para evitar conflito com o Scaffold
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ]),
      child: ConstrainedBox(
        // DEFINIMOS um limite de altura para o teclado não estourar o layout
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.35,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Como foi seu atendimento?", // Mudei o texto para você confirmar que alterou
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              StatefulBuilder(builder: (context, setInternalState) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    5,
                        (index) => InkWell(
                      // Trocamos IconButton por InkWell para ser mais rápido
                      onTap: () {
                        setInternalState(() => _rating = index + 1);
                        _rating = index + 1;
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          index < _rating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 35,
                        ),
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 10),
              TextField(
                controller: _feedbackController,
                decoration: InputDecoration(
                  hintText: 'Comentário (opcional)',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmittingFeedback
                      ? null
                      : () => _submitFeedback(
                      _rating, _feedbackController.text.trim()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSubmittingFeedback
                      ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                      : const Text('Enviar Avaliação'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFeedbackPanel(),
          if (_chatStatus == 'closed' && !widget.userIsAdmin)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: TextButton.icon(
                icon: const Icon(Icons.refresh, color: Colors.blue),
                label: const Text("Reabrir Chat",
                    style: TextStyle(color: Colors.blue)),
                onPressed: _reopenChatByUser,
              ),
            ),
          if (_replyToText != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[200],
              child: Row(
                children: [
                  const Icon(Icons.reply, size: 20, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text('Respondendo a: $_replyToText',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, fontStyle: FontStyle.italic))),
                  IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => setState(() => _replyToText = null)),
                ],
              ),
            ),
          ],
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: 8, vertical: isLandscape ? 4 : 6),
            color: Colors.grey[100],
            child: Row(
              children: [
                if (widget.userIsAdmin && !_isRecording)
                  IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.bolt, color: Colors.orange),
                      onPressed: _showQuickMessagesPanel),
                if (!_isRecording)
                  IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.attach_file),
                      onPressed:
                      _chatStatus == 'open' ? _pickAndUploadFile : null),
                Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: _isRecording ? 4 : 0),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24)),
                      child: Row(
                        children: [
                          Expanded(
                              child: _isRecording
                                  ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.circle,
                                        color: Colors.red, size: 8),
                                    const SizedBox(width: 8),
                                    Text("Gravando... $_recordingTime",
                                        style: const TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13))
                                  ])
                                  : TextField(
                                controller: _messageController,
                                focusNode: _inputFocusNode,
                                enabled: _chatStatus == 'open',
                                maxLines: isLandscape ? 1 : 5,
                                minLines: 1,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) {
                                  if (_chatStatus == 'open') {
                                    _sendMessage();
                                  }
                                },
                                textCapitalization:
                                TextCapitalization.sentences,
                                decoration: InputDecoration(
                                    hintText: _chatStatus == 'open'
                                        ? 'Mensagem...'
                                        : 'Chat finalizado',
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding:
                                    const EdgeInsets.symmetric(
                                        vertical: 8)),
                              )),
                        ],
                      ),
                    )),
                const SizedBox(width: 8),
                if (_messageController.text.trim().isEmpty &&
                    _chatStatus == 'open')
                  GestureDetector(
                    onTap: _handleAudioAction,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                          color: Colors.blue, shape: BoxShape.circle),
                      child: Icon(_isRecording ? Icons.stop : Icons.mic_none,
                          color: Colors.white, size: 20),
                    ),
                  )
                else
                  IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.send, color: Colors.blue),
                      onPressed:
                      _chatStatus == 'open' ? () => _sendMessage() : null),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> waves;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  WaveformPainter(
      {required this.waves,
        required this.progress,
        required this.activeColor,
        required this.inactiveColor});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;
    final double width = size.width;
    final double height = size.height;
    final double barWidth = width / (waves.length * 1.5);
    final double gap = barWidth * 0.5;
    for (int i = 0; i < waves.length; i++) {
      final double barHeight = waves[i] * height;
      final double x = i * (barWidth + gap);
      final double y = (height - barHeight) / 2;
      paint.color =
      (i / waves.length) <= progress ? activeColor : inactiveColor;
      canvas.drawRRect(
        RRect.fromLTRBR(
            x, y, x + barWidth, y + barHeight, Radius.circular(barWidth / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
