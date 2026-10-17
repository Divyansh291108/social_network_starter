import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// For Flutter Web on the same computer, use 127.0.0.1.
// For Android Emulator, use http://10.0.2.2:8000 instead.
// For a physical phone, use your computer's LAN IP address.
const String apiBaseUrl = 'http://127.0.0.1:8000';

void main() => runApp(const SocialApp());

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();
  String? accessToken;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      };

  String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      final detail = body is Map<String, dynamic> ? body['detail'] : null;
      if (detail is String) return detail;
      if (detail is List) {
        return detail
            .map((e) => e is Map ? (e['msg'] ?? e.toString()) : e.toString())
            .join('\n');
      }
    } catch (_) {}
    return 'Request failed (HTTP ${response.statusCode}).';
  }

  Future<void> register({
    required String email,
    required String username,
    required String password,
    required String displayName,
  }) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/auth/register'),
      headers: _headers,
      body: jsonEncode({
        'email': email.trim(),
        'username': username.trim(),
        'password': password,
        'display_name': displayName.trim(),
      }),
    );
    if (response.statusCode != 201) throw Exception(_errorMessage(response));
  }

  Future<void> login({required String email, required String password}) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/auth/login'),
      headers: _headers,
      body: jsonEncode({'email': email.trim(), 'password': password}),
    );
    if (response.statusCode != 200) throw Exception(_errorMessage(response));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    accessToken = data['access_token'] as String?;
    if (accessToken == null || accessToken!.isEmpty) {
      throw Exception('The server did not return an access token.');
    }
  }

  Future<List<Map<String, dynamic>>> getPosts() async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/posts?offset=0&limit=50'),
      headers: _headers,
    );
    if (response.statusCode != 200) throw Exception(_errorMessage(response));
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<void> logout() async {
    accessToken = null;
  }
}

class SocialApp extends StatelessWidget {
  const SocialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Social Network',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5265D8)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const WelcomeScreen(),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 104,
                    width: 104,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Icon(Icons.people_alt_rounded,
                        size: 60, color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(height: 28),
                  Text('Your community starts here',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          )),
                  const SizedBox(height: 10),
                  Text(
                    'Share what matters, discover people, and stay connected.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const RegisterScreen())),
                      child: const Padding(
                        padding: EdgeInsets.all(13),
                        child: Text('Create account'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const LoginScreen())),
                      child: const Padding(
                        padding: EdgeInsets.all(13),
                        child: Text('Log in'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const FeedScreen(isGuest: true))),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Continue as guest'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _hidePassword = true;

  @override
  void dispose() {
    _displayName.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ApiService.instance.register(
        email: _email.text,
        username: _username.text,
        password: _password.text,
        displayName: _displayName.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created. Please log in.')),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => LoginScreen(initialEmail: _email.text.trim())),
      );
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Create account')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Join the community',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            )),
                    const SizedBox(height: 22),
                    TextFormField(
                      controller: _displayName,
                      decoration: const InputDecoration(labelText: 'Display name', prefixIcon: Icon(Icons.badge_outlined)),
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => v == null || v.trim().isEmpty ? 'Enter your display name' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _username,
                      decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.alternate_email)),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (value.length < 3) return 'Use at least 3 characters';
                        if (!RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch(value)) return 'Use letters, numbers, _ or . only';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => v == null || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim()) ? 'Enter a valid email' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _hidePassword,
                      decoration: InputDecoration(
                        labelText: 'Password (minimum 8 characters)',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _hidePassword = !_hidePassword),
                          icon: Icon(_hidePassword ? Icons.visibility : Icons.visibility_off),
                        ),
                      ),
                      validator: (v) => v == null || v.length < 8 ? 'Password must be at least 8 characters' : null,
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.all(13),
                        child: Text(_loading ? 'Creating account...' : 'Register'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class LoginScreen extends StatefulWidget {
  final String initialEmail;
  const LoginScreen({super.key, this.initialEmail = ''});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  final _password = TextEditingController();
  bool _loading = false;
  bool _hidePassword = true;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ApiService.instance.login(email: _email.text, password: _password.text);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const FeedScreen(isGuest: false)),
        (_) => false,
      );
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Log in')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Welcome back',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 22),
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => v == null || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim()) ? 'Enter a valid email' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _hidePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _hidePassword = !_hidePassword),
                          icon: Icon(_hidePassword ? Icons.visibility : Icons.visibility_off),
                        ),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Enter your password' : null,
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.all(13),
                        child: Text(_loading ? 'Logging in...' : 'Log in'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class FeedScreen extends StatefulWidget {
  final bool isGuest;
  const FeedScreen({super.key, required this.isGuest});
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late Future<List<Map<String, dynamic>>> _posts;

  @override
  void initState() {
    super.initState();
    _posts = ApiService.instance.getPosts();
  }

  Future<void> _refresh() async {
    final next = ApiService.instance.getPosts();
    setState(() => _posts = next);
    await next;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.isGuest ? 'Explore as guest' : 'Your feed'),
          actions: [
            IconButton(
              tooltip: 'Refresh feed',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
            if (!widget.isGuest)
              IconButton(
                tooltip: 'Log out',
                onPressed: () async {
                  await ApiService.instance.logout();
                  if (!context.mounted) return;
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                    (_) => false,
                  );
                },
                icon: const Icon(Icons.logout),
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _posts,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                //return const ListView(children: [SizedBox(height: 220), Center(child: CircularProgressIndicator())]);
                return ListView(children: const [SizedBox(height: 220),Center(child: CircularProgressIndicator(),),],);
              }
              if (snapshot.hasError) {
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 56),
                    const SizedBox(height: 12),
                    const Text('Could not load the public feed.', textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text('${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    Center(child: FilledButton(onPressed: _refresh, child: const Text('Try again'))),
                  ],
                );
              }
              final posts = snapshot.data ?? [];
              if (posts.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: const [
                    SizedBox(height: 110),
                    Icon(Icons.forum_outlined, size: 58),
                    SizedBox(height: 14),
                    Text('No posts yet', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text('Public posts will appear here when people start sharing.', textAlign: TextAlign.center),
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: posts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final post = posts[index];
                  final createdAt = DateTime.tryParse('${post['created_at'] ?? ''}')?.toLocal();
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const CircleAvatar(child: Icon(Icons.person_outline)),
                            const SizedBox(width: 10),
                            Expanded(child: Text('User #${post['author_id'] ?? '?'}', style: const TextStyle(fontWeight: FontWeight.bold))),
                          ]),
                          const SizedBox(height: 14),
                          Text('${post['content'] ?? ''}', style: Theme.of(context).textTheme.bodyLarge),
                          if (createdAt != null) ...[
                            const SizedBox(height: 12),
                            Text(createdAt.toString(), style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        floatingActionButton: widget.isGuest
            ? FloatingActionButton.extended(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                icon: const Icon(Icons.login),
                label: const Text('Log in to post'),
              )
            : null,
      );
}

void _showError(BuildContext context, Object error) {
  final message = error.toString().replaceFirst('Exception: ', '');
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}
