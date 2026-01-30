import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_screen.dart';
import 'admin_users_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();

  static const String adminCode = '5736';
  static const String supportChatId = 'support_chat';

  Future<void> enterApp() async {
    String input = nameController.text.trim();
    String email = emailController.text.trim();

    if (input.isEmpty) return;

    bool isAdmin = input == adminCode;
    String displayName = isAdmin ? 'Faekon' : input;

    if (!isAdmin && email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-mail obrigatório para clientes')),
      );
      return;
    }

    // 🔹 Correção: ID previsível
    final chatId = isAdmin ? supportChatId : '${input}_$email';
    final userRef = FirebaseFirestore.instance.collection('users').doc(chatId);

    await userRef.set({
      'name': displayName,
      'isAdmin': isAdmin,
      'email': email,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pendente',
    }, SetOptions(merge: true));

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await userRef.update({'fcmToken': token});
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', chatId);
    await prefs.setString('userName', displayName);
    await prefs.setBool('isAdmin', isAdmin);

    if (!mounted) return;

    // 🔹 Redireciona corretamente para Admin ou Cliente
    if (isAdmin) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            userId: chatId,
            userName: displayName,
            userIsAdmin: false,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Digite seu nome'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'E-mail'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: enterApp,
              child: const Text('Entrar'),
            ),
          ],
        ),
      ),
    );
  }
}
