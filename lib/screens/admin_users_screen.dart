import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import 'chat_screen.dart';
import 'admin_clients_screen.dart';
import 'welcome_screen.dart';
import '../utils/chat_state.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final usersCollection = FirebaseFirestore.instance.collection('users');
  final chatsCollection = FirebaseFirestore.instance.collection('chats');
  final groupsCollection = FirebaseFirestore.instance.collection('groups');

  final ValueNotifier<Map<String, Map<String, dynamic>>> chatCacheNotifier =
      ValueNotifier({});

  String searchQuery = '';
  String statusFilter = 'Todos';
  String chatTypeFilter = 'ativos';

  bool isSelectionMode = false;
  Set<String> selectedChatIds = {};
  Map<String, Map<String, dynamic>> _currentChatsData = {};

  List<QueryDocumentSnapshot>? _cachedUsers;
  bool _isLoadingUsers = false;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadUsersCache();
  }

  Future<void> _loadUsersCache() async {
    if (_isLoadingUsers) return;
    _isLoadingUsers = true;

    try {
      final usersSnapshot =
          await usersCollection.where('isAdmin', isEqualTo: false).get();
      if (mounted) {
        setState(() {
          _cachedUsers = usersSnapshot.docs;
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar cache de usuários: $e');
      _isLoadingUsers = false;
    }
  }

  Color statusColor(String status) {
    switch (status) {
      case 'pendente':
        return Colors.amber;
      case 'open':
      case 'em atendimento':
        return Colors.blue;
      case 'concluído':
        return Colors.green;
      case 'encerrado':
        return Colors.red;
      case 'inactive':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Future<void> _logoutAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  void _toggleSelectionMode() {
    setState(() {
      isSelectionMode = !isSelectionMode;
      if (!isSelectionMode) {
        selectedChatIds.clear();
      }
    });
  }

  void _toggleChatSelection(String chatId) {
    setState(() {
      if (selectedChatIds.contains(chatId)) {
        selectedChatIds.remove(chatId);
      } else {
        selectedChatIds.add(chatId);
      }
    });
  }

  Future<void> _createGroup() async {
    if (_cachedUsers == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Carregando usuários, tente novamente em instantes...')),
      );
      return;
    }

    final nameController = TextEditingController();
    final selectedUsers = <String>[];
    bool isProcessingDialog = false;
    String? nameError;
    String? membersError;

    final users = _cachedUsers!;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Criar Grupo'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Nome do Grupo',
                    hintText: 'Ex: Equipe de Vendas',
                    border: const OutlineInputBorder(),
                    errorText: nameError,
                  ),
                  enabled: !isProcessingDialog,
                  onChanged: (_) {
                    if (nameError != null) {
                      setDialogState(() => nameError = null);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Selecione os membros:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    if (membersError != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          membersError!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      final userData = user.data() as Map<String, dynamic>;
                      final userName = userData['name'] ?? 'Sem Nome';
                      final userId = user.id;

                      return CheckboxListTile(
                        title: Text(userName),
                        value: selectedUsers.contains(userId),
                        enabled: !isProcessingDialog,
                        onChanged: (bool? value) {
                          setDialogState(() {
                            if (value == true) {
                              selectedUsers.add(userId);
                            } else {
                              selectedUsers.remove(userId);
                            }
                            if (membersError != null) {
                              membersError = null;
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isProcessingDialog
                  ? null
                  : () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: isProcessingDialog
                  ? null
                  : () async {
                      bool hasError = false;

                      if (nameController.text.trim().isEmpty) {
                        setDialogState(() => nameError = 'Nome obrigatório');
                        hasError = true;
                      }

                      if (selectedUsers.isEmpty) {
                        setDialogState(
                            () => membersError = 'Selecione ao menos 1 membro');
                        hasError = true;
                      }

                      if (hasError) return;

                      setDialogState(() => isProcessingDialog = true);

                      try {
                        // Garante que o admin esteja sempre no grupo
                        if (!selectedUsers.contains('admin')) {
                          selectedUsers.add('admin');
                        }

                        final newGroupRef = groupsCollection.doc();
                        final String groupId = newGroupRef.id;

                        await newGroupRef.set({
                          'name': nameController.text.trim(),
                          'members': selectedUsers,
                          'lastMessage': '',
                          'timestamp': FieldValue.serverTimestamp(),
                          'status':
                              'open', // Ajustado para 'open' conforme solicitado
                        });

                        // Também cria o documento na coleção 'chats' para controle de arquivamento unificado
                        await chatsCollection.doc(groupId).set({
                          'groupName': nameController.text.trim(),
                          'isGroup': true,
                          'members': selectedUsers,
                          'lastMessage': '',
                          'lastMessageAt': FieldValue.serverTimestamp(),
                          'status':
                              'open', // Define como 'open' para ser reconhecido como chat aberto
                          'isArchived':
                              false, // Garante que não nasça arquivado
                        });

                        if (!mounted) return;
                        Navigator.pop(dialogContext);

                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  'Grupo "${nameController.text.trim()}" criado com sucesso!')),
                        );
                      } catch (e) {
                        setDialogState(() => isProcessingDialog = false);
                        if (!mounted) return;
                        showDialog(
                          context: dialogContext,
                          builder: (_) => AlertDialog(
                            title: const Text('Erro'),
                            content: Text('Erro ao criar grupo: $e'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('OK'),
                              ),
                            ],
                          ),
                        );
                      }
                    },
              child: isProcessingDialog
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Criar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editGroupMembers(
      String groupId, String groupName, Map<String, dynamic> groupData) async {
    if (_cachedUsers == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Carregando usuários, tente novamente em instantes...')),
      );
      return;
    }

    final currentMembers =
        List<String>.from(groupData['members'] as List? ?? []);
    final selectedUsers = <String>[...currentMembers];
    bool isProcessingDialog = false;

    final users = _cachedUsers!;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Editar Membros - $groupName'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];
                final userData = user.data() as Map<String, dynamic>;
                final userName = userData['name'] ?? 'Sem Nome';
                final userId = user.id;

                return CheckboxListTile(
                  title: Text(userName),
                  value: selectedUsers.contains(userId),
                  enabled: !isProcessingDialog,
                  onChanged: (bool? value) {
                    setDialogState(() {
                      if (value == true) {
                        selectedUsers.add(userId);
                      } else {
                        selectedUsers.remove(userId);
                      }
                    });
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: isProcessingDialog
                  ? null
                  : () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: isProcessingDialog
                  ? null
                  : () async {
                      if (selectedUsers.isEmpty) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Selecione pelo menos um membro para o grupo')),
                        );
                        return;
                      }

                      setDialogState(() => isProcessingDialog = true);

                      try {
                        // Garante que o admin continue no grupo
                        if (!selectedUsers.contains('admin')) {
                          selectedUsers.add('admin');
                        }

                        await groupsCollection.doc(groupId).update({
                          'members': selectedUsers,
                        });

                        if (!mounted) return;
                        Navigator.pop(dialogContext);

                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content:
                                  Text('Membros atualizados com sucesso!')),
                        );
                      } catch (e) {
                        setDialogState(() => isProcessingDialog = false);
                        if (!mounted) return;
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                              content: Text('Erro ao atualizar membros: $e')),
                        );
                      }
                    },
              child: isProcessingDialog
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteGroup(String groupId, String groupName) async {
    bool isProcessingDialog = false;

    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Excluir Grupo'),
          content: Text(
              'Tem certeza que deseja excluir o grupo "$groupName"?\n\nEsta ação não pode ser desfeita e todas as mensagens do grupo serão perdidas.'),
          actions: [
            TextButton(
              onPressed: isProcessingDialog
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: isProcessingDialog
                  ? null
                  : () async {
                      setDialogState(() => isProcessingDialog = true);

                      try {
                        final messagesSnapshot = await groupsCollection
                            .doc(groupId)
                            .collection('messages')
                            .get();
                        final batch = FirebaseFirestore.instance.batch();

                        for (var doc in messagesSnapshot.docs) {
                          batch.delete(doc.reference);
                        }

                        batch.delete(groupsCollection.doc(groupId));
                        await batch.commit();

                        if (!mounted) return;
                        Navigator.pop(dialogContext, true);

                        if (!mounted) return;
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  'Grupo "$groupName" excluído com sucesso!')),
                        );
                      } catch (e) {
                        setDialogState(() => isProcessingDialog = false);
                        if (!mounted) return;
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text('Erro ao excluir grupo: $e')),
                        );
                      }
                    },
              child: isProcessingDialog
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Excluir'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _archiveSelectedChats() async {
    if (selectedChatIds.isEmpty) return;

    final count = selectedChatIds.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Arquivar Conversas'),
        content: Text(
            'Deseja arquivar $count conversa(s)?\n\nElas ficarão ocultas na lista principal mas poderão ser restauradas.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Arquivar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final batch = FirebaseFirestore.instance.batch();
        for (final chatId in selectedChatIds) {
          final isGroup = _currentChatsData[chatId]?['isGroup'] ?? false;
          batch.update(chatsCollection.doc(chatId), {
            'isArchived': true,
            'status': 'open',
          });
          if (isGroup) {
            batch.update(groupsCollection.doc(chatId), {
              'isArchived': true,
              'status': 'open',
            });
          }
        }
        await batch.commit();

        setState(() {
          selectedChatIds.clear();
          isSelectionMode = false;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count conversa(s) arquivada(s)')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao arquivar: $e')),
        );
      }
    }
  }

  Future<void> _restoreChat(String chatId, {bool isGroup = false}) async {
    try {
      await chatsCollection.doc(chatId).update({
        'isArchived': false,
        'status': 'open',
      });
      if (isGroup) {
        await groupsCollection.doc(chatId).update({
          'isArchived': false,
          'status': 'open',
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conversa restaurada com sucesso!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao restaurar: $e')),
      );
    }
  }

  Future<void> _changeChatStatus(String chatId, String newStatus) async {
    try {
      if (newStatus == 'encerrado') {
        // Busca o status atual para evitar disparos duplicados
        final userDoc = await usersCollection.doc(chatId).get();
        final currentStatus = userDoc.data()?['status'];
        if (currentStatus == 'encerrado') {
          debugPrint('⚠️ Chat já está encerrado. Ignorando.');
          return;
        }

        await chatsCollection.doc(chatId).collection('messages').add({
          'text': 'Este atendimento foi finalizado.',
          'sender': 'admin',
          'timestamp': FieldValue.serverTimestamp(),
          'readByAdmin': true,
          'readByUser': false,
          'system': true,
        });

        await chatsCollection.doc(chatId).update({
          'status': 'closed',
          'lastMessage': 'Este atendimento foi finalizado.',
          'lastMessageAt': FieldValue.serverTimestamp(),
          'endedAt': FieldValue.serverTimestamp(),
          'feedbackRating': null,
          'feedbackComment': null
        });
      } else {
        await chatsCollection.doc(chatId).update({'status': 'open'});
      }

      await usersCollection.doc(chatId).update({'status': newStatus});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status alterado para: $newStatus')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao alterar status: $e')),
      );
    }
  }

  Future<void> _exportChat(
      BuildContext context, String chatId, String userName) async {
    try {
      final snapshot = await chatsCollection
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp')
          .get();

      if (snapshot.docs.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhuma mensagem para exportar')),
        );
        return;
      }

      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Chat com $userName', style: pw.TextStyle(fontSize: 20)),
              pw.SizedBox(height: 12),
              ...snapshot.docs.map((doc) {
                final data = doc.data();
                final ts = data['timestamp'] as Timestamp?;
                final dateStr = ts != null
                    ? DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate())
                    : '';
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 4),
                  child: pw.Text(
                    '${data['sender']} • $dateStr • ${data['edited'] == true ? "editado" : ""}: ${data['text']}',
                  ),
                );
              }),
            ],
          ),
        ),
      );

      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exportação concluída')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao exportar chat: $e')),
      );
    }
  }

  void _editAdminNotes(String chatId, String currentNotes) {
    final controller = TextEditingController(text: currentNotes);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Notas internas do admin'),
        content: SingleChildScrollView(
          child: TextField(
            controller: controller,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: 'Digite notas internas para este cliente...',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              await chatsCollection.doc(chatId).update({
                'adminNotes': controller.text.trim(),
              });
              chatCacheNotifier.value = {
                ...chatCacheNotifier.value,
                chatId: {
                  ...chatCacheNotifier.value[chatId] ?? {},
                  'adminNotes': controller.text.trim(),
                }
              };
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Salvar'),
          ),
          if (currentNotes.isNotEmpty)
            TextButton(
              onPressed: () async {
                await chatsCollection.doc(chatId).update({'adminNotes': ''});
                chatCacheNotifier.value = {
                  ...chatCacheNotifier.value,
                  chatId: {
                    ...chatCacheNotifier.value[chatId] ?? {},
                    'adminNotes': '',
                  }
                };
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Remover'),
            ),
        ],
      ),
    );
  }

  void _updateChatCacheDebounced(String userId, Timestamp ts) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      final currentCache = chatCacheNotifier.value[userId];
      final updated =
          Map<String, Map<String, dynamic>>.from(chatCacheNotifier.value);
      updated[userId] = {
        ...currentCache ?? {},
        'lastMessageAt': ts,
      };
      chatCacheNotifier.value = updated;
    });
  }

  void _showAllFeedbacks() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("Histórico de Avaliações",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            const Divider(),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collectionGroup('feedbacks')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                        child: Text("Erro ao carregar: ${snapshot.error}"));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final feedbacks = snapshot.data!.docs;
                  if (feedbacks.isEmpty) {
                    return const Center(
                        child: Text("Nenhuma avaliação encontrada."));
                  }

                  double sum = 0;
                  for (var doc in feedbacks) {
                    sum += (doc.data() as Map<String, dynamic>)['rating'] ?? 0;
                  }
                  final double average = sum / feedbacks.length;
                  final int total = feedbacks.length;

                  return Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber[200]!),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                const Text("Média Geral",
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                                Row(
                                  children: [
                                    const Icon(Icons.star,
                                        color: Colors.amber, size: 24),
                                    const SizedBox(width: 4),
                                    Text(
                                      average.toStringAsFixed(1),
                                      style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Container(
                                width: 1, height: 40, color: Colors.amber[200]),
                            Column(
                              children: [
                                const Text("Total Avaliações",
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                                Text(
                                  total.toString(),
                                  style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: feedbacks.length,
                          itemBuilder: (context, index) {
                            final data =
                                feedbacks[index].data() as Map<String, dynamic>;
                            final rating = data['rating'] ?? 0;
                            final comment = data['comment'] ?? '';
                            final userName = data['userName'] ?? 'Usuário';
                            final ts = data['timestamp'] as Timestamp?;
                            final dateStr = ts != null
                                ? DateFormat('dd/MM HH:mm').format(ts.toDate())
                                : '';

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.amber[100],
                                child: Text(rating.toString(),
                                    style: const TextStyle(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.bold)),
                              ),
                              title: Text(userName),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                      children: List.generate(
                                          5,
                                          (i) => Icon(
                                                i < rating
                                                    ? Icons.star
                                                    : Icons.star_border,
                                                size: 16,
                                                color: Colors.amber,
                                              ))),
                                  if (comment.isNotEmpty)
                                    Text(comment,
                                        style: const TextStyle(
                                            fontStyle: FontStyle.italic)),
                                ],
                              ),
                              trailing: Text(dateStr,
                                  style: const TextStyle(fontSize: 10)),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(chatTypeFilter == 'arquivados'
            ? 'Admin - Arquivados'
            : 'Admin - Chats'),
        actions: [
          if (chatTypeFilter == 'ativos') ...[
            IconButton(
              icon: const Icon(Icons.group_add),
              tooltip: 'Criar Grupo',
              onPressed: _createGroup,
            ),
            IconButton(
              icon: Icon(isSelectionMode ? Icons.close : Icons.checklist,
                  color: Colors.green),
              tooltip:
                  isSelectionMode ? 'Cancelar Seleção' : 'Selecionar Múltiplos',
              onPressed: _toggleSelectionMode,
            ),
            if (isSelectionMode && selectedChatIds.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.archive, color: Colors.orange),
                tooltip: 'Arquivar Selecionados',
                onPressed: _archiveSelectedChats,
              ),
          ],
          IconButton(
            icon: const Icon(Icons.star_rate, color: Colors.amber),
            tooltip: 'Feedbacks',
            onPressed: _showAllFeedbacks,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: _logoutAdmin,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => setState(() => chatTypeFilter = 'ativos'),
                    icon: const Icon(Icons.chat),
                    label: const Text('Chats Ativos'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: chatTypeFilter == 'ativos'
                          ? Colors.blue
                          : Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        setState(() => chatTypeFilter = 'arquivados'),
                    icon: const Icon(Icons.archive),
                    label: const Text('Arquivados'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: chatTypeFilter == 'arquivados'
                          ? Colors.orange
                          : Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: chatsCollection.snapshots(),
              builder: (context, chatSnapshot) {
                if (chatSnapshot.hasData) {
                  for (var doc in chatSnapshot.data!.docs) {
                    final data = doc.data() as Map<String, dynamic>;
                    _currentChatsData[doc.id] = {
                      'lastMessageAt': data['lastMessageAt'],
                      'lastMessage': data['lastMessage'] ?? '',
                      'adminNotes': data['adminNotes'] ?? '',
                      'feedbackRating': data['feedbackRating'],
                      'feedbackComment': data['feedbackComment'] ?? '',
                      'status': data['status'] ?? 'open',
                      'isArchived': data['isArchived'] ?? false,
                      'isGroup': data['isGroup'] ?? false,
                      'groupName': data['groupName'] ?? '',
                    };
                  }
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: groupsCollection.snapshots(),
                  builder: (context, groupSnapshot) {
                    return StreamBuilder<QuerySnapshot>(
                      stream: usersCollection
                          .where('isAdmin', isEqualTo: false)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }

                        final users = snapshot.data!.docs;
                        final List<dynamic> combinedList = [...users];

                        if (groupSnapshot.hasData) {
                          for (var groupDoc in groupSnapshot.data!.docs) {
                            combinedList.add({
                              'id': groupDoc.id,
                              'isGroup': true,
                              'data': groupDoc.data(),
                            });
                          }
                        }

                        combinedList.sort((a, b) {
                          DateTime tsA;
                          DateTime tsB;

                          if (a is QueryDocumentSnapshot) {
                            final chatA = _currentChatsData[a.id] ?? {};
                            tsA = chatA['lastMessageAt'] != null
                                ? (chatA['lastMessageAt'] as Timestamp).toDate()
                                : DateTime.fromMillisecondsSinceEpoch(0);
                          } else {
                            final groupData = a as Map;
                            final data =
                                groupData['data'] as Map<String, dynamic>;
                            tsA = data['timestamp'] != null
                                ? (data['timestamp'] as Timestamp).toDate()
                                : DateTime.fromMillisecondsSinceEpoch(0);
                          }

                          if (b is QueryDocumentSnapshot) {
                            final chatB = _currentChatsData[b.id] ?? {};
                            tsB = chatB['lastMessageAt'] != null
                                ? (chatB['lastMessageAt'] as Timestamp).toDate()
                                : DateTime.fromMillisecondsSinceEpoch(0);
                          } else {
                            final groupData = b as Map;
                            final data =
                                groupData['data'] as Map<String, dynamic>;
                            tsB = data['timestamp'] != null
                                ? (data['timestamp'] as Timestamp).toDate()
                                : DateTime.fromMillisecondsSinceEpoch(0);
                          }

                          return tsB.compareTo(tsA);
                        });

                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      decoration: const InputDecoration(
                                        hintText:
                                            'Pesquisar tudo (Nome, Números, Notas)...',
                                        prefixIcon: Icon(Icons.search),
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      onChanged: (value) {
                                        setState(() => searchQuery =
                                            value.trim().toLowerCase());
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (chatTypeFilter == 'ativos')
                                    DropdownButton<String>(
                                      value: statusFilter,
                                      items: <String>[
                                        'Todos',
                                        'pendente',
                                        'em atendimento',
                                        'concluído',
                                        'encerrado'
                                      ]
                                          .map((status) => DropdownMenuItem(
                                                value: status,
                                                child: Text(status),
                                              ))
                                          .toList(),
                                      onChanged: (newStatus) {
                                        if (newStatus != null) {
                                          setState(
                                              () => statusFilter = newStatus);
                                        }
                                      },
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView.separated(
                                itemCount: combinedList.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 4),
                                itemBuilder: (context, index) {
                                  final item = combinedList[index];

                                  final chatData = _currentChatsData[item is Map
                                          ? item['id']
                                          : (item as QueryDocumentSnapshot)
                                              .id] ??
                                      {};
                                  final String chatStatus =
                                      chatData['status'] ?? 'open';
                                  final bool isArchived =
                                      chatData['isArchived'] ?? false;
                                  final bool isGroup =
                                      chatData['isGroup'] ?? false;
                                  final String groupName =
                                      chatData['groupName'] ?? '';

                                  if (chatTypeFilter == 'ativos' &&
                                      isArchived == true) {
                                    return const SizedBox.shrink();
                                  }
                                  if (chatTypeFilter == 'arquivados' &&
                                      isArchived == false) {
                                    return const SizedBox.shrink();
                                  }

                                  if (item is Map && item['isGroup'] == true) {
                                    final groupData =
                                        item['data'] as Map<String, dynamic>;
                                    final groupId = item['id'] as String;
                                    final groupName =
                                        groupData['name'] ?? 'Grupo sem nome';
                                    final lastMessage =
                                        groupData['lastMessage'] ?? '';
                                    final lastReadAdmin =
                                        groupData['lastReadAdmin']
                                            as Timestamp?;

                                    return StreamBuilder<QuerySnapshot>(
                                      stream: groupsCollection
                                          .doc(groupId)
                                          .collection('messages')
                                          .snapshots(),
                                      builder: (context, msgSnapshot) {
                                        int groupUnreadCount = 0;
                                        if (msgSnapshot.hasData) {
                                          groupUnreadCount = msgSnapshot
                                              .data!.docs
                                              .where((msg) {
                                            final data = msg.data()
                                                as Map<String, dynamic>;
                                            final ts =
                                                data['timestamp'] as Timestamp?;
                                            if (ts == null) return false;

                                            // Se não houver data de leitura, todas são não lidas
                                            if (lastReadAdmin == null)
                                              return true;

                                            // Mensagem é não lida se o timestamp for APÓS a última leitura do admin
                                            // Adicionamos uma pequena margem de 1ms para evitar problemas de precisão
                                            return ts.toDate().isAfter(
                                                lastReadAdmin.toDate().add(
                                                    const Duration(
                                                        milliseconds: 1)));
                                          }).length;
                                        }

                                        if (searchQuery.isNotEmpty &&
                                            !groupName
                                                .toLowerCase()
                                                .contains(searchQuery)) {
                                          return const SizedBox.shrink();
                                        }

                                        return Card(
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          child: ListTile(
                                            leading: const CircleAvatar(
                                              backgroundColor: Colors.blue,
                                              child: Icon(Icons.group,
                                                  color: Colors.white),
                                            ),
                                            title: Text(
                                              groupName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue,
                                              ),
                                            ),
                                            subtitle: Text(
                                              lastMessage.isNotEmpty
                                                  ? lastMessage
                                                  : 'Nenhuma mensagem',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (chatTypeFilter ==
                                                    'arquivados')
                                                  IconButton(
                                                    icon: const Icon(
                                                        Icons.restore,
                                                        color: Colors.green),
                                                    tooltip: 'Restaurar Grupo',
                                                    onPressed: () =>
                                                        _restoreChat(groupId,
                                                            isGroup: true),
                                                  ),
                                                if (groupUnreadCount > 0 &&
                                                    ChatState.activeChatId !=
                                                        groupId &&
                                                    !ChatState.isRecentlyClosed(
                                                        groupId))
                                                  Container(
                                                    margin:
                                                        const EdgeInsets.only(
                                                            right: 8),
                                                    padding:
                                                        const EdgeInsets.all(6),
                                                    decoration:
                                                        const BoxDecoration(
                                                      color: Colors.red,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: Text(
                                                      groupUnreadCount
                                                          .toString(),
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                PopupMenuButton<String>(
                                                  icon: const Icon(
                                                      Icons.more_vert,
                                                      color: Colors.blue),
                                                  tooltip: 'Opções do Grupo',
                                                  onSelected:
                                                      (String action) async {
                                                    if (action ==
                                                        'edit_members') {
                                                      _editGroupMembers(groupId,
                                                          groupName, groupData);
                                                    } else if (action ==
                                                        'delete') {
                                                      _deleteGroup(
                                                          groupId, groupName);
                                                    }
                                                  },
                                                  itemBuilder: (context) => [
                                                    const PopupMenuItem(
                                                      value: 'edit_members',
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.people,
                                                              color:
                                                                  Colors.blue),
                                                          SizedBox(width: 8),
                                                          Text(
                                                              'Ver/Editar Membros'),
                                                        ],
                                                      ),
                                                    ),
                                                    const PopupMenuItem(
                                                      value: 'delete',
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.delete,
                                                              color:
                                                                  Colors.red),
                                                          SizedBox(width: 8),
                                                          Text('Excluir Grupo'),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            onTap: () async {
                                              ChatState.isChatOpen = true;
                                              ChatState.activeChatId = groupId;
                                              ChatState.currentChatId =
                                                  groupId; // Adicionado para silenciamento imediato
                                              ChatState.isAdmin = true;

                                              await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => ChatScreen(
                                                    userId: groupId,
                                                    userName: groupName,
                                                    userIsAdmin: true,
                                                    isGroup: true,
                                                  ),
                                                ),
                                              );

                                              // Ao voltar, marcamos como recentemente fechado para o debounce visual
                                              ChatState.recentlyClosedId =
                                                  groupId;
                                              ChatState.closedAt =
                                                  DateTime.now();
                                              ChatState.activeChatId = null;
                                              ChatState.currentChatId =
                                                  null; // Limpa ao voltar
                                              if (mounted) setState(() {});
                                            },
                                          ),
                                        );
                                      },
                                    );
                                  }

                                  final user = item as QueryDocumentSnapshot;
                                  final userData =
                                      user.data() as Map<String, dynamic>;
                                  final String userName =
                                      (userData['name'] ?? '')
                                          .toString()
                                          .toLowerCase();
                                  final String userId = user.id.toLowerCase();

                                  final String adminNotes =
                                      (chatData['adminNotes'] ?? '').toString();
                                  final String adminNotesSearch =
                                      adminNotes.toLowerCase();
                                  final int? feedbackRating =
                                      chatData['feedbackRating'];
                                  final String currentStatus =
                                      userData['status'] ?? 'em atendimento';

                                  return StreamBuilder<QuerySnapshot>(
                                    key: ValueKey(user.id),
                                    stream: chatsCollection
                                        .doc(user.id)
                                        .collection('messages')
                                        .orderBy('timestamp', descending: true)
                                        .limit(50)
                                        .snapshots(),
                                    builder: (context, chatMsgSnapshot) {
                                      if (!chatMsgSnapshot.hasData) {
                                        return const SizedBox.shrink();
                                      }

                                      final messages =
                                          chatMsgSnapshot.data!.docs;

                                      bool matchesSearch =
                                          searchQuery.isEmpty ||
                                              userName.contains(searchQuery) ||
                                              userId.contains(searchQuery) ||
                                              adminNotesSearch
                                                  .contains(searchQuery) ||
                                              (isGroup &&
                                                  groupName
                                                      .toLowerCase()
                                                      .contains(searchQuery));

                                      if (!matchesSearch &&
                                          searchQuery.isNotEmpty) {
                                        matchesSearch = messages.any((msg) {
                                          final text = (msg.data() as Map<
                                                      String, dynamic>)['text']
                                                  ?.toString()
                                                  .toLowerCase() ??
                                              '';
                                          return text.contains(searchQuery);
                                        });
                                      }

                                      final bool matchesStatus =
                                          statusFilter == 'Todos'
                                              ? true
                                              : currentStatus.toLowerCase() ==
                                                  statusFilter.toLowerCase();

                                      if (!matchesSearch || !matchesStatus) {
                                        return const SizedBox.shrink();
                                      }

                                      String lastMessage = '';
                                      String lastMessageTime = '';
                                      int unreadCount = 0;

                                      if (messages.isNotEmpty) {
                                        final lastMsgData = messages.first
                                            .data() as Map<String, dynamic>;
                                        lastMessage =
                                            (lastMsgData['text'] ?? '')
                                                .toString();
                                        final ts = lastMsgData['timestamp']
                                            as Timestamp?;
                                        if (ts != null) {
                                          lastMessageTime = DateFormat('HH:mm')
                                              .format(ts.toDate());
                                          _updateChatCacheDebounced(
                                              user.id, ts);
                                        }

                                        unreadCount = messages.where((msg) {
                                          final data = msg.data()
                                              as Map<String, dynamic>;
                                          return data['readByAdmin'] == false;
                                        }).length;
                                      }

                                      return Card(
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        color: isSelectionMode &&
                                                selectedChatIds
                                                    .contains(user.id)
                                            ? Colors.blue.withOpacity(0.1)
                                            : null,
                                        child: ListTile(
                                          leading: isSelectionMode
                                              ? Checkbox(
                                                  value: selectedChatIds
                                                      .contains(user.id),
                                                  onChanged: (_) =>
                                                      _toggleChatSelection(
                                                          user.id),
                                                )
                                              : CircleAvatar(
                                                  radius: 8,
                                                  backgroundColor: statusColor(
                                                      currentStatus),
                                                ),
                                          title: Text(
                                            isGroup
                                                ? groupName
                                                : (userData['name'] ??
                                                    'Sem Nome'),
                                            style: TextStyle(
                                              fontWeight: isGroup
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color:
                                                  isGroup ? Colors.blue : null,
                                            ),
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (lastMessage.isNotEmpty)
                                                Text(
                                                  '$lastMessage • $lastMessageTime',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              GestureDetector(
                                                onTap: () => _editAdminNotes(
                                                    user.id, adminNotes),
                                                child: Container(
                                                  margin: const EdgeInsets.only(
                                                      top: 4, bottom: 2),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.yellow[50],
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      if (feedbackRating !=
                                                          null) ...[
                                                        const Icon(Icons.star,
                                                            color: Colors.amber,
                                                            size: 14),
                                                        Text(
                                                          ' $feedbackRating ',
                                                          style: TextStyle(
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color: Colors
                                                                  .amber[800]),
                                                        ),
                                                        const SizedBox(
                                                            width: 4),
                                                        Container(
                                                            width: 1,
                                                            height: 12,
                                                            color: Colors
                                                                .grey[300]),
                                                        const SizedBox(
                                                            width: 4),
                                                      ],
                                                      Expanded(
                                                        child: Text(
                                                          adminNotes.isNotEmpty
                                                              ? adminNotes
                                                              : 'Adicionar nota',
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                  fontSize: 12),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (unreadCount > 0 &&
                                                  ChatState.activeChatId !=
                                                      user.id &&
                                                  !ChatState.isRecentlyClosed(
                                                      user.id))
                                                Container(
                                                  margin: const EdgeInsets.only(
                                                      right: 8),
                                                  padding:
                                                      const EdgeInsets.all(6),
                                                  decoration:
                                                      const BoxDecoration(
                                                    color: Colors.red,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Text(
                                                    unreadCount.toString(),
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              chatTypeFilter == 'arquivados'
                                                  ? IconButton(
                                                      icon: const Icon(
                                                          Icons.restore,
                                                          color: Colors.green),
                                                      tooltip:
                                                          'Restaurar Conversa',
                                                      onPressed: () =>
                                                          _restoreChat(user.id,
                                                              isGroup: isGroup),
                                                    )
                                                  : PopupMenuButton<String>(
                                                      icon: Icon(
                                                          Icons.more_vert,
                                                          color: statusColor(
                                                              currentStatus)),
                                                      tooltip: 'Alterar Status',
                                                      onSelected:
                                                          (String newStatus) {
                                                        _changeChatStatus(
                                                            user.id, newStatus);
                                                      },
                                                      itemBuilder: (context) =>
                                                          [
                                                        const PopupMenuItem(
                                                          value: 'pendente',
                                                          child: Text(
                                                              'Aguardando'),
                                                        ),
                                                        const PopupMenuItem(
                                                          value:
                                                              'em atendimento',
                                                          child: Text(
                                                              'Em atendimento'),
                                                        ),
                                                        const PopupMenuItem(
                                                          value: 'concluído',
                                                          child: Text(
                                                              'Finalizado'),
                                                        ),
                                                        const PopupMenuItem(
                                                          value: 'encerrado',
                                                          child:
                                                              Text('Encerrado'),
                                                        ),
                                                      ],
                                                    ),
                                            ],
                                          ),
                                          onTap: () async {
                                            if (isSelectionMode) {
                                              _toggleChatSelection(user.id);
                                            } else {
                                              ChatState.isChatOpen = true;
                                              ChatState.activeChatId = user.id;
                                              ChatState.currentChatId = user
                                                  .id; // Adicionado para silenciamento imediato
                                              ChatState.isAdmin = true;

                                              await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => ChatScreen(
                                                    userId: user.id,
                                                    userName: isGroup
                                                        ? groupName
                                                        : (userData['name'] ??
                                                            ''),
                                                    userIsAdmin: true,
                                                  ),
                                                ),
                                              );

                                              // Ao voltar, marcamos como recentemente fechado para o debounce visual
                                              ChatState.recentlyClosedId =
                                                  user.id;
                                              ChatState.closedAt =
                                                  DateTime.now();
                                              ChatState.activeChatId = null;
                                              ChatState.currentChatId =
                                                  null; // Limpa ao voltar
                                              if (mounted) setState(() {});
                                            }
                                          },
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(8),
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.people),
                                label: const Text('Clientes'),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const AdminClientsScreen(),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
