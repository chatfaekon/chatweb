import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart'; // Importação adicionada
import 'package:flutter/foundation.dart' show kIsWeb;
import 'chat_screen.dart';

class ClientRegisterScreen extends StatefulWidget {
  const ClientRegisterScreen({super.key});

  @override
  State<ClientRegisterScreen> createState() => _ClientRegisterScreenState();
}

class _ClientRegisterScreenState extends State<ClientRegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  bool _loading = false;
  String _appVersion = "";

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _checkSavedLogin();
  }

  Future<void> _loadVersion() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = "v${packageInfo.version}";
    });
  }

  Future<void> _checkSavedLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    final userName = prefs.getString('userName');

    if (userId != null && userName != null) {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }

      // Vínculo preventivo caso o app seja reaberto
      if (!kIsWeb) {
        OneSignal.login(userId);
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              userId: userId,
              userName: userName,
              userIsAdmin: false,
            ),
          ),
        );
      }
    }
  }

  Future<void> _registerClient() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha todos os campos')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      await FirebaseAuth.instance.signInAnonymously();

      final usersCollection = FirebaseFirestore.instance.collection('users');
      final existingUserQuery =
          await usersCollection.where('email', isEqualTo: email).limit(1).get();

      late DocumentReference userRef;
      String userNameToSave = name;

      if (existingUserQuery.docs.isNotEmpty) {
        userRef = existingUserQuery.docs.first.reference;
        final data =
            existingUserQuery.docs.first.data() as Map<String, dynamic>;
        userNameToSave = data['name'] ?? name;
      } else {
        userRef = usersCollection.doc();

        await userRef.set({
          'name': name,
          'email': email,
          'isAdmin': false,
          'status': 'pendente',
          'createdAt': FieldValue.serverTimestamp(),
        });

        await FirebaseFirestore.instance
            .collection('chats')
            .doc(userRef.id)
            .set({
          'status': 'open',
          'createdAt': FieldValue.serverTimestamp(),
          'userName': name,
        });
      }
      await FirebaseFirestore.instance.collection('chats').doc(userRef.id).set({
        'userName': userNameToSave,
      }, SetOptions(merge: true));

      // --- VINCULAR AO ONESIGNAL ---
      if (!kIsWeb) {
        OneSignal.login(userRef.id);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userId', userRef.id);
      await prefs.setString('userName', userNameToSave);
      await prefs.setBool('isAdmin', false);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            userId: userRef.id,
            userName: userNameToSave,
            userIsAdmin: false,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao cadastrar: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cadastro do Cliente'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Container(
                    width: 120,
                    height: 120,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(12),
                    child: ClipOval(
                      child: kIsWeb
                          ? Image.network(
                              Uri.base
                                  .resolve('assets/assets/logo.png')
                                  .toString(),
                              fit: BoxFit.contain,
                            )
                          : Image.asset(
                              'assets/logo.png',
                              fit: BoxFit.contain,
                            ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'E-mail',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _registerClient,
                      child: _loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Continuar',
                              style: TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            bottom: 20,
            child: Text(
              _appVersion,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
