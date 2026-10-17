import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// Use 127.0.0.1 for Flutter web on the same computer.
// Android emulator: http://10.0.2.2:8000
// Physical phone: use your development computer's LAN IP.
const apiBaseUrl = 'http://127.0.0.1:8000';

void main() {
  runApp(const SocialApp());
}

class SocialApp extends StatelessWidget {
  const SocialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Social Network',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String status = 'Tap the button to check the backend.';
  bool loading = false;

  Future<void> checkBackend() async {
    setState(() {
      loading = true;
      status = 'Connecting...';
    });

    try {
      final response = await http.get(Uri.parse('$apiBaseUrl/health'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        setState(() => status = 'Backend status: ${data['status']}');
      } else {
        setState(() => status = 'Server returned HTTP ${response.statusCode}');
      }
    } catch (error) {
      setState(() => status = 'Connection failed. Check API URL and server.\n$error');
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Social Network')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people_alt_outlined, size: 72),
              const SizedBox(height: 16),
              const Text(
                'Your community starts here',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(status, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: loading ? null : checkBackend,
                child: Text(loading ? 'Checking...' : 'Check backend connection'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
