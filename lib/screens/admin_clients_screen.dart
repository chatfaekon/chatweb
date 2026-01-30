import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

class AdminClientsScreen extends StatelessWidget {
  const AdminClientsScreen({super.key});

  // 🔹 Exporta lista de clientes para PDF
  Future<void> _exportClients(
      BuildContext context, List<QueryDocumentSnapshot> clients) async {
    if (clients.isEmpty) return;

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Lista de Clientes', style: pw.TextStyle(fontSize: 22)),
            pw.SizedBox(height: 16),
            ...clients.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 4),
                child: pw.Text(
                  'Nome: ${data['name'] ?? ''}\nEmail: ${data['email'] ?? ''}',
                ),
              );
            }),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Clientes exportados com sucesso')),
    );
  }

  // 🔹 Compartilha lista de clientes via Share
  void _shareClients(List<QueryDocumentSnapshot> clients) {
    final buffer = StringBuffer();
    buffer.writeln('Lista de Clientes:\n');

    for (var doc in clients) {
      final data = doc.data() as Map<String, dynamic>;
      buffer.writeln('Nome: ${data['name']}');
      buffer.writeln('Email: ${data['email']}');
      buffer.writeln('---');
    }

    Share.share(buffer.toString());
  }

  @override
  Widget build(BuildContext context) {
    final usersRef = FirebaseFirestore.instance
        .collection('users')
        .where('isAdmin', isEqualTo: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      body: StreamBuilder<QuerySnapshot>(
        stream: usersRef.snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final clients = snapshot.data!.docs;

          if (clients.isEmpty) {
            return const Center(child: Text('Nenhum cliente cadastrado'));
          }

          return Column(
            children: [
              // 🔹 Botões Exportar / Compartilhar
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('Exportar'),
                        onPressed: () => _exportClients(context, clients),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.share),
                        label: const Text('Compartilhar'),
                        onPressed: () => _shareClients(clients),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(),

              // 🔹 Lista de clientes
              Expanded(
                child: ListView.builder(
                  itemCount: clients.length,
                  itemBuilder: (context, index) {
                    final data = clients[index].data() as Map<String, dynamic>;

                    return ListTile(
                      leading: const Icon(Icons.person),
                      title: Text(data['name'] ?? 'Sem nome'),
                      subtitle: Text(data['email'] ?? 'Sem e-mail'),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
