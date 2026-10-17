import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

// For Flutter Web on the same computer, use 127.0.0.1.
const String apiBaseUrl = 'http://127.0.0.1:8000';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  ApiService.instance.loadSavedToken();
  themeMode.value = web.window.localStorage.getItem('theme') == 'light'
      ? ThemeMode.light
      : ThemeMode.dark;
  runApp(const SocialApp());
}

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();
  static const _tokenKey = 'access_token';
  String? accessToken;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      };

  void loadSavedToken() {
    accessToken = web.window.localStorage.getItem(_tokenKey);
  }

  void _saveToken(String? token) {
    if (token == null) {
      web.window.localStorage.removeItem(_tokenKey);
    } else {
      web.window.localStorage.setItem(_tokenKey, token);
    }
  }

  Future<bool> restoreSession() async {
    if (accessToken == null || accessToken!.isEmpty) return false;
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/users/me'),
        headers: _headers,
      );
      if (response.statusCode == 200) return true;
      accessToken = null;
      _saveToken(null);
    } catch (_) {}
    return false;
  }

  void _handleUnauthorized(http.Response response) {
    if (response.statusCode == 401 && accessToken != null) {
      accessToken = null;
      _saveToken(null);
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LoginScreen(
            notice: 'Your session expired. Please log in again.',
          ),
        ),
        (_) => false,
      );
    }
  }

  String _errorMessage(http.Response response) {
    _handleUnauthorized(response);
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
    _saveToken(accessToken);
  }

  Future<List<Map<String, dynamic>>> getPosts(
      {int offset = 0, int limit = 20, int? userId}) async {
    final userPart = userId == null ? '' : '&user_id=$userId';
    final response = await http.get(
      Uri.parse(
          '$apiBaseUrl/posts?offset=$offset&limit=$limit$userPart&_=${DateTime.now().millisecondsSinceEpoch}'),
      headers: _headers,
    );
    if (response.statusCode != 200) throw Exception(_errorMessage(response));
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<Map<String, dynamic>> createPost(String content,
      {String? imageUrl}) async {
    if (accessToken == null || accessToken!.isEmpty) {
      throw Exception('Please log in to publish a post.');
    }
    final response = await http.post(
      Uri.parse('$apiBaseUrl/posts'),
      headers: _headers,
      body: jsonEncode({
        'content': content.trim(),
        if (imageUrl != null) 'image_url': imageUrl,
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_errorMessage(response));
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<Map<String, dynamic>> getMe() async {
    final response =
        await http.get(Uri.parse('$apiBaseUrl/users/me'), headers: _headers);
    if (response.statusCode != 200) throw Exception(_errorMessage(response));
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<String> uploadAvatar(Uint8List bytes, String filename) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/users/me/avatar'));
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.files
        .add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode != 200) throw Exception(_errorMessage(response));
    return (jsonDecode(response.body) as Map)['avatar_url'] as String;
  }

  Future<String> uploadImage(Uint8List bytes, String filename) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/posts/upload-image'));
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.files
        .add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode != 200) throw Exception(_errorMessage(response));
    return (jsonDecode(response.body) as Map)['image_url'] as String;
  }

  Future<Map<String, dynamic>> toggleLike(int postId) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/posts/$postId/like'),
      headers: _headers,
    );
    if (response.statusCode != 200) throw Exception(_errorMessage(response));
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<List<Map<String, dynamic>>> getComments(int postId) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/posts/$postId/comments'),
      headers: _headers,
    );
    if (response.statusCode != 200) throw Exception(_errorMessage(response));
    final data = jsonDecode(response.body) as List<dynamic>;
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> addComment(int postId, String content,
      {String? imageUrl}) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/posts/$postId/comments'),
      headers: _headers,
      body: jsonEncode({
        'content': content.trim(),
        if (imageUrl != null) 'image_url': imageUrl,
      }),
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception(_errorMessage(response));
    }
  }

  Future<void> deletePost(int postId) async {
    final response = await http.delete(
      Uri.parse('$apiBaseUrl/posts/$postId'),
      headers: _headers,
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception(_errorMessage(response));
    }
  }

  Future<void> deleteComment(int postId, int commentId) async {
    final response = await http.delete(
      Uri.parse('$apiBaseUrl/posts/$postId/comments/$commentId'),
      headers: _headers,
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception(_errorMessage(response));
    }
  }

  Future<Map<String, dynamic>> getProfile(int userId) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/users/$userId'),
      headers: _headers,
    );
    if (response.statusCode != 200) throw Exception(_errorMessage(response));
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<Map<String, dynamic>> updateProfile({
    required String displayName,
    required String bio,
  }) async {
    final response = await http.patch(
      Uri.parse('$apiBaseUrl/users/me'),
      headers: _headers,
      body: jsonEncode({'display_name': displayName, 'bio': bio}),
    );
    if (response.statusCode != 200) throw Exception(_errorMessage(response));
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Future<void> blockUser(int userId) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/users/$userId/block'),
      headers: _headers,
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception(_errorMessage(response));
    }
  }

  Future<void> unblockUser(int userId) async {
    final response = await http.delete(
      Uri.parse('$apiBaseUrl/users/$userId/block'),
      headers: _headers,
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception(_errorMessage(response));
    }
  }

  Future<void> reportPost(int postId, String reason) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/posts/$postId/report'),
      headers: _headers,
      body: jsonEncode({'reason': reason}),
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception(_errorMessage(response));
    }
  }

  Future<void> reportComment(int postId, int commentId, String reason) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/posts/$postId/comments/$commentId/report'),
      headers: _headers,
      body: jsonEncode({'reason': reason}),
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception(_errorMessage(response));
    }
  }

  Future<void> deleteAccount(String password) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/users/me/delete'),
      headers: _headers,
      body: jsonEncode({'password': password}),
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception(_errorMessage(response));
    }
  }

  Future<void> logout() async {
    accessToken = null;
    _saveToken(null);
  }
}

// ---------------------------------------------------------------------------
// App + startup
// ---------------------------------------------------------------------------

class SocialApp extends StatelessWidget {
  const SocialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'CommonGround',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode,
        home: const StartupScreen(),
      ),
    );
  }
}

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});
  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  late final Future<bool> _check = ApiService.instance.restoreSession();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _check,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data == true
            ? const FeedScreen(isGuest: false)
            : const WelcomeScreen();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Welcome / Register / Login
// ---------------------------------------------------------------------------

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF34136B), Color(0xFF0D0916)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      height: 96,
                      width: 96,
                      decoration: BoxDecoration(
                        gradient: kBrandGradient,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x667C4DFF),
                            blurRadius: 40,
                            offset: Offset(0, 16),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.bolt_rounded,
                          size: 56, color: Colors.white),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Your people.\nYour vibe.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 42,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Drop a thought, share a pic, react with emojis. Keep it real.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Color(0xB3FFFFFF)),
                    ),
                    const SizedBox(height: 36),
                    SizedBox(
                      width: double.infinity,
                      child: GradientButton(
                        expand: true,
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RegisterScreen()),
                        ),
                        child: const Text('Create account'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0x40FFFFFF)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const LoginScreen()),
                        ),
                        child: const Text('Log in'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xB3FFFFFF),
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const FeedScreen(isGuest: true)),
                      ),
                      child: const Text('Just looking? Continue as guest'),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          style: TextButton.styleFrom(
                              foregroundColor: const Color(0x80FFFFFF)),
                          onPressed: () =>
                              openLegal(context, 'Terms of Service', kTermsText),
                          child: const Text('Terms'),
                        ),
                        const Text('·', style: TextStyle(color: Color(0x80FFFFFF))),
                        TextButton(
                          style: TextButton.styleFrom(
                              foregroundColor: const Color(0x80FFFFFF)),
                          onPressed: () =>
                              openLegal(context, 'Privacy Policy', kPrivacyText),
                          child: const Text('Privacy'),
                        ),
                      ],
                    ),
                  ],
                ),
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
        MaterialPageRoute(
            builder: (_) => LoginScreen(initialEmail: _email.text.trim())),
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
                      decoration: const InputDecoration(
                          labelText: 'Display name',
                          prefixIcon: Icon(Icons.badge_outlined)),
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Enter your display name'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _username,
                      decoration: const InputDecoration(
                          labelText: 'Username',
                          prefixIcon: Icon(Icons.alternate_email)),
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (value.length < 3) return 'Use at least 3 characters';
                        if (!RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch(value)) {
                          return 'Use letters, numbers, _ or . only';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined)),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => v == null ||
                              !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                  .hasMatch(v.trim())
                          ? 'Enter a valid email'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _hidePassword,
                      decoration: InputDecoration(
                        labelText: 'Password (minimum 8 characters)',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _hidePassword = !_hidePassword),
                          icon: Icon(_hidePassword
                              ? Icons.visibility
                              : Icons.visibility_off),
                        ),
                      ),
                      validator: (v) => v == null || v.length < 8
                          ? 'Password must be at least 8 characters'
                          : null,
                    ),
                    const SizedBox(height: 22),
                    const AgreementNote(),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.all(13),
                        child: Text(_loading ? 'Creating account...' : 'Register'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const PasswordNote(),
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
  final String? notice;
  const LoginScreen({super.key, this.initialEmail = '', this.notice});
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
      await ApiService.instance
          .login(email: _email.text, password: _password.text);
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
                    if (widget.notice != null) ...[
                      Text(
                        widget.notice!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text('Welcome back',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 22),
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined)),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => v == null ||
                              !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                  .hasMatch(v.trim())
                          ? 'Enter a valid email'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _hidePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _hidePassword = !_hidePassword),
                          icon: Icon(_hidePassword
                              ? Icons.visibility
                              : Icons.visibility_off),
                        ),
                      ),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Enter your password' : null,
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.all(13),
                        child: Text(_loading ? 'Logging in...' : 'Log in'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const PasswordNote(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Feed
// ---------------------------------------------------------------------------

class FeedScreen extends StatefulWidget {
  final bool isGuest;
  const FeedScreen({super.key, required this.isGuest});
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  static const int _pageSize = 20;

  final ScrollController _scroll = ScrollController();
  List<Map<String, dynamic>> _items = [];
  int _nextOffset = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;
  Map<String, dynamic>? _me;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _refresh();
    if (!widget.isGuest) _loadMe();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadMe() async {
    try {
      final me = await ApiService.instance.getMe();
      if (mounted) setState(() => _me = me);
    } catch (_) {}
  }

  Future<void> _changePhoto() async {
    final picked = await pickImageFromBrowser();
    if (picked == null) return;
    try {
      await ApiService.instance.uploadAvatar(picked.bytes, picked.name);
      await _loadMe();
      await _refresh();
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  Future<void> _refresh() async {
    try {
      final data =
          await ApiService.instance.getPosts(offset: 0, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _items = data;
        _nextOffset = data.length;
        _hasMore = data.length == _pageSize;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
      if (_items.isNotEmpty) _showError(context, e);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final data = await ApiService.instance
          .getPosts(offset: _nextOffset, limit: _pageSize);
      if (!mounted) return;
      final known = _items.map((p) => p['id']).toSet();
      setState(() {
        _items = [..._items, ...data.where((p) => !known.contains(p['id']))];
        _nextOffset += data.length;
        _hasMore = data.length == _pageSize;
      });
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _insertPost(Map<String, dynamic> created) {
    setState(() {
      _items = [created, ..._items];
    });
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _removePost(dynamic id) {
    setState(() {
      _items = _items.where((p) => p['id'] != id).toList();
      if (_nextOffset > 0) _nextOffset -= 1;
    });
  }

  Widget _buildList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 60),
          const Icon(Icons.cloud_off_outlined, size: 56),
          const SizedBox(height: 12),
          const Text('Could not load the feed.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(height: 8),
          const Text(
            'The server may be waking up. Try again in a few seconds.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(
              onPressed: () {
                setState(() => _loading = true);
                _refresh();
              },
              child: const Text('Try again'),
            ),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          SizedBox(height: 110),
          Icon(Icons.forum_outlined, size: 58),
          SizedBox(height: 14),
          Text('No posts yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('Be the first to post something.',
              textAlign: TextAlign.center),
        ],
      );
    }
    return ListView.separated(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _items.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          if (_loadingMore) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (_hasMore) {
            return Center(
              child: TextButton(
                onPressed: _loadMore,
                child: const Text('Load more'),
              ),
            );
          }
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: Text("You're all caught up")),
          );
        }
        final post = _items[index];
        return PostCard(
          key: ValueKey(post['id']),
          post: post,
          isGuest: widget.isGuest,
          currentUserId: _me?['id'] as int?,
          onDeleted: () => _removePost(post['id']),
          onChanged: _refresh,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: GradientText(
            widget.isGuest ? 'Explore' : 'For you',
            style: const TextStyle(
                fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.8),
          ),
          actions: [
            if (!widget.isGuest && _me != null)
              IconButton(
                tooltip: 'My profile',
                icon: const Icon(Icons.account_circle_outlined),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(
                        userId: _me!['id'] as int,
                        currentUserId: _me!['id'] as int,
                        isGuest: false,
                      ),
                    ),
                  );
                  if (!mounted) return;
                  _loadMe();
                  _refresh();
                },
              ),
            IconButton(
              tooltip: 'Light / dark',
              onPressed: toggleTheme,
              icon: Icon(Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined),
            ),
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
        body: Column(
          children: [
            if (!widget.isGuest)
              ProfileHeader(me: _me, onChangePhoto: _changePhoto),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: _buildList(),
              ),
            ),
          ],
        ),
        floatingActionButton: GradientButton(
          onPressed: () async {
            if (widget.isGuest) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
              return;
            }

            final created = await Navigator.push<Map<String, dynamic>>(
              context,
              MaterialPageRoute(builder: (_) => const CreatePostScreen()),
            );

            if (!mounted) return;
            if (created != null) _insertPost(created);
          },
          icon: widget.isGuest ? Icons.login : Icons.add,
          child: Text(widget.isGuest ? 'Log in to post' : 'Create post'),
        ),
      );
}

// ---------------------------------------------------------------------------
// Create post
// ---------------------------------------------------------------------------

class CreatePostScreen extends StatelessWidget {
  const CreatePostScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create post')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Composer(
          hint: "What's on your mind?",
          submitLabel: 'Publish post',
          minLines: 5,
          maxLines: 8,
          maxLength: 2000,
          autofocus: true,
          onSubmit: (text, imageUrl) async {
            final created =
                await ApiService.instance.createPost(text, imageUrl: imageUrl);
            if (context.mounted) Navigator.pop(context, created);
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared composer (text + photo + emoji) used by posts and comments
// ---------------------------------------------------------------------------

const List<String> kEmojis = [
  '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '🙂', '😉',
  '😊', '😍', '🥰', '😘', '😎', '🤩', '🥳', '😇', '🤔', '😐',
  '😴', '😢', '😭', '😡', '🤯', '😱', '👍', '👎', '👏', '🙌',
  '🙏', '💪', '🤝', '👋', '🔥', '✨', '🎉', '❤️', '💙', '💯',
  '🌟', '🎂', '🍕', '☕', '⚽', '🏏', '📚', '💻', '🚀', '🌈',
];

void insertAtCursor(TextEditingController c, String text) {
  final sel = c.selection;
  final start = sel.isValid ? sel.start : c.text.length;
  final end = sel.isValid ? sel.end : c.text.length;
  final newText = c.text.replaceRange(start, end, text);
  c.value = TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: start + text.length),
  );
}

class EmojiPanel extends StatelessWidget {
  final ValueChanged<String> onPick;
  const EmojiPanel({super.key, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 170,
      child: GridView.extent(
        maxCrossAxisExtent: 44,
        children: [
          for (final e in kEmojis)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onPick(e),
              child: Center(
                child: Text(e, style: const TextStyle(fontSize: 24)),
              ),
            ),
        ],
      ),
    );
  }
}

class NetworkPhoto extends StatelessWidget {
  final String url;
  final double maxHeight;
  const NetworkPhoto({super.key, required this.url, this.maxHeight = 400});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Image.network(
          mediaUrl(url),
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox(
            height: 80,
            child: Center(child: Icon(Icons.broken_image_outlined)),
          ),
        ),
      ),
    );
  }
}

class Composer extends StatefulWidget {
  final String hint;
  final String submitLabel;
  final int minLines;
  final int maxLines;
  final int maxLength;
  final bool autofocus;
  final Future<void> Function(String text, String? imageUrl) onSubmit;

  const Composer({
    super.key,
    required this.hint,
    required this.submitLabel,
    required this.onSubmit,
    this.minLines = 1,
    this.maxLines = 3,
    this.maxLength = 1000,
    this.autofocus = false,
  });

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _controller = TextEditingController();
  PickedImage? _image;
  bool _busy = false;
  bool _showEmoji = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final picked = await pickImageFromBrowser();
      if (picked == null || !mounted) return;
      if (picked.bytes.length > 5 * 1024 * 1024) {
        _showError(context, 'Image must be under 5 MB.');
        return;
      }
      setState(() => _image = picked);
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _image == null) {
      _showError(context, 'Write something or add a photo.');
      return;
    }
    setState(() => _busy = true);
    try {
      String? imageUrl;
      if (_image != null) {
        imageUrl = await ApiService.instance
            .uploadImage(_image!.bytes, _image!.name);
      }
      await widget.onSubmit(text, imageUrl);
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _image = null;
        _showEmoji = false;
      });
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_image != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(_image!.bytes,
                        height: 150, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: _busy ? null : () => setState(() => _image = null),
                      child: const CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        TextField(
          controller: _controller,
          autofocus: widget.autofocus,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          maxLength: widget.maxLength,
          decoration: InputDecoration(
            hintText: widget.hint,
            alignLabelWithHint: true,
            counterText: widget.minLines == 1 ? '' : null,
          ),
        ),
        Row(
          children: [
            IconButton(
              tooltip: 'Add photo',
              onPressed: _busy ? null : _pickPhoto,
              icon: const Icon(Icons.image_outlined),
            ),
            IconButton(
              tooltip: 'Emoji',
              onPressed: _busy
                  ? null
                  : () => setState(() => _showEmoji = !_showEmoji),
              icon: Icon(_showEmoji
                  ? Icons.keyboard
                  : Icons.emoji_emotions_outlined),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: const Icon(Icons.send, size: 18),
              label: Text(_busy ? 'Sending...' : widget.submitLabel),
            ),
          ],
        ),
        if (_showEmoji)
          EmojiPanel(onPick: (e) => insertAtCursor(_controller, e)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Profile, post card, comments
// ---------------------------------------------------------------------------

class UserAvatar extends StatelessWidget {
  final String? url;
  final double radius;
  final bool ring;
  const UserAvatar({super.key, this.url, this.radius = 20, this.ring = true});

  @override
  Widget build(BuildContext context) {
    final hasImage = url != null && url!.isNotEmpty;
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      backgroundImage: hasImage ? NetworkImage(mediaUrl(url!)) : null,
      child: hasImage ? null : Icon(Icons.person_rounded, size: radius),
    );
    if (!ring) return avatar;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: kBrandGradient,
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: avatar,
      ),
    );
  }
}

class ProfileHeader extends StatelessWidget {
  final Map<String, dynamic>? me;
  final VoidCallback onChangePhoto;
  const ProfileHeader({super.key, required this.me, required this.onChangePhoto});

  @override
  Widget build(BuildContext context) {
    if (me == null) return const SizedBox(height: 8);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: kBrandGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x557C4DFF),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: UserAvatar(
                  url: me!['avatar_url'] as String?,
                  radius: 34,
                  ring: false,
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: InkWell(
                  onTap: onChangePhoto,
                  child: const CircleAvatar(
                    radius: 13,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.camera_alt_rounded,
                        size: 15, color: kViolet),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${me!['display_name'] ?? ''}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  '@${me!['username'] ?? ''}',
                  style: const TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final double scale;
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: dark ? const Color(0x26FFFFFF) : const Color(0x267C4DFF),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: scale,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutBack,
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final bool isGuest;
  final int? currentUserId;
  final VoidCallback? onDeleted;
  final VoidCallback? onChanged;
  const PostCard({
    super.key,
    required this.post,
    required this.isGuest,
    this.currentUserId,
    this.onDeleted,
    this.onChanged,
  });
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late bool _liked;
  late int _likes;
  late int _comments;
  bool _pop = false;

  @override
  void initState() {
    super.initState();
    _liked = widget.post['liked_by_me'] == true;
    _likes = (widget.post['like_count'] as int?) ?? 0;
    _comments = (widget.post['comment_count'] as int?) ?? 0;
  }

  Future<void> _toggleLike() async {
    if (widget.isGuest) {
      _showError(context, 'Log in to like posts.');
      return;
    }
    final wasLiked = _liked;
    setState(() {
      _liked = !wasLiked;
      _likes += wasLiked ? -1 : 1;
      _pop = !wasLiked;
    });
    if (!wasLiked) {
      Future.delayed(const Duration(milliseconds: 180), () {
        if (mounted) setState(() => _pop = false);
      });
    }
    try {
      final result =
          await ApiService.instance.toggleLike(widget.post['id'] as int);
      if (mounted) {
        setState(() {
          _liked = result['liked'] == true;
          _likes = result['like_count'] as int;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liked = wasLiked;
        _likes += wasLiked ? 1 : -1;
      });
      _showError(context, e);
    }
  }

  Future<void> _openComments() async {
    final count = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => CommentsScreen(
          postId: widget.post['id'] as int,
          isGuest: widget.isGuest,
          currentUserId: widget.currentUserId,
        ),
      ),
    );
    if (count != null && mounted) setState(() => _comments = count);
  }

  Future<void> _openProfile() async {
    final authorId = widget.post['author_id'];
    if (authorId is! int) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          userId: authorId,
          currentUserId: widget.currentUserId,
          isGuest: widget.isGuest,
        ),
      ),
    );
    if (changed == true && mounted) widget.onChanged?.call();
  }

  Future<void> _onMenu(String value) async {
    if (value == 'delete') return _confirmDelete();
    if (value == 'report') return _report();
    if (value == 'block') return _block();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ApiService.instance.deletePost(widget.post['id'] as int);
      widget.onDeleted?.call();
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  Future<void> _report() async {
    final reason = await showReportDialog(context);
    if (reason == null || !mounted) return;
    try {
      await ApiService.instance.reportPost(widget.post['id'] as int, reason);
      if (mounted) _showInfo(context, 'Thanks, we received your report.');
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  Future<void> _block() async {
    final authorId = widget.post['author_id'];
    if (authorId is! int) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block this user?'),
        content: const Text(
            'You will no longer see each other\'s posts and comments. You can unblock them any time from their profile.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Block')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ApiService.instance.blockUser(authorId);
      if (mounted) {
        _showInfo(context, 'User blocked.');
        widget.onChanged?.call();
      }
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final author = post['author'] is Map ? post['author'] as Map : const {};
    final createdAt = parseServerTime(post['created_at']);
    final username = author['username'];
    final isMine = widget.currentUserId != null &&
        widget.currentUserId == post['author_id'];
    final content = '${post['content'] ?? ''}';
    final hasText = content.trim().isNotEmpty;
    final hasImage =
        post['image_url'] != null && '${post['image_url']}'.isNotEmpty;
    final meta = [
      if (username != null) '@$username',
      if (createdAt != null) timeAgo(createdAt),
    ].join(' · ');
    final who = '${author['display_name'] ?? 'this user'}';

    return GestureDetector(
      onDoubleTap: () {
        if (!_liked) _toggleLike();
      },
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _openProfile,
                    child: Row(
                      children: [
                        UserAvatar(
                            url: author['avatar_url'] as String?, radius: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${author['display_name'] ?? 'User #${post['author_id']}'}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                              if (meta.isNotEmpty)
                                Text(meta,
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!widget.isGuest)
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    icon: const Icon(Icons.more_horiz_rounded),
                    onSelected: _onMenu,
                    itemBuilder: (_) => isMine
                        ? const [
                            PopupMenuItem(
                                value: 'delete', child: Text('Delete post')),
                          ]
                        : [
                            const PopupMenuItem(
                                value: 'report', child: Text('Report post')),
                            PopupMenuItem(
                                value: 'block', child: Text('Block $who')),
                          ],
                  ),
              ],
            ),
            if (hasText) ...[
              const SizedBox(height: 14),
              RichPostText(
                text: content,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(height: 1.4),
              ),
            ],
            if (hasImage) ...[
              const SizedBox(height: 12),
              NetworkPhoto(url: '${post['image_url']}', maxHeight: 420),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                _ActionPill(
                  icon: _liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: _liked ? kPink : null,
                  label: '$_likes',
                  scale: _pop ? 1.45 : 1.0,
                  onTap: _toggleLike,
                ),
                const SizedBox(width: 8),
                _ActionPill(
                  icon: Icons.mode_comment_outlined,
                  label: '$_comments',
                  onTap: _openComments,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CommentsScreen extends StatefulWidget {
  final int postId;
  final bool isGuest;
  final int? currentUserId;
  const CommentsScreen({
    super.key,
    required this.postId,
    required this.isGuest,
    this.currentUserId,
  });
  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.instance.getComments(widget.postId);
      if (mounted) setState(() => _comments = data);
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _report(int commentId) async {
    final reason = await showReportDialog(context);
    if (reason == null || !mounted) return;
    try {
      await ApiService.instance.reportComment(widget.postId, commentId, reason);
      if (mounted) _showInfo(context, 'Thanks, we received your report.');
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  Future<void> _delete(int commentId) async {
    try {
      await ApiService.instance.deleteComment(widget.postId, commentId);
      await _load();
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _comments.length);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Comments')),
        body: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _comments.isEmpty
                      ? const Center(
                          child: Text('No comments yet. Be the first!'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _comments.length,
                          itemBuilder: (context, i) {
                            final c = _comments[i];
                            final author = c['author'] is Map
                                ? c['author'] as Map
                                : const {};
                            final isMine = widget.currentUserId != null &&
                                widget.currentUserId == author['id'];
                            final hasText =
                                '${c['content'] ?? ''}'.trim().isNotEmpty;
                            final hasImage = c['image_url'] != null &&
                                '${c['image_url']}'.isNotEmpty;
                            return ListTile(
                              leading: UserAvatar(
                                  url: author['avatar_url'] as String?),
                              title: Text('@${author['username'] ?? 'user'}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (hasText) Text('${c['content']}'),
                                  if (hasImage) ...[
                                    const SizedBox(height: 8),
                                    ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 260),
                                      child: NetworkPhoto(
                                        url: '${c['image_url']}',
                                        maxHeight: 220,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              trailing: isMine
                                  ? IconButton(
                                      tooltip: 'Delete comment',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _delete(c['id'] as int),
                                    )
                                  : (widget.isGuest
                                      ? null
                                      : IconButton(
                                          tooltip: 'Report comment',
                                          icon: const Icon(Icons.flag_outlined),
                                          onPressed: () => _report(c['id'] as int),
                                        )),
                            );
                          },
                        ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: widget.isGuest
                    ? const Text('Log in to comment.')
                    : Composer(
                        hint: 'Write a comment...',
                        submitLabel: 'Send',
                        maxLines: 3,
                        maxLength: 1000,
                        onSubmit: (text, imageUrl) async {
                          await ApiService.instance.addComment(
                            widget.postId,
                            text,
                            imageUrl: imageUrl,
                          );
                          await _load();
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

DateTime? parseServerTime(dynamic value) {
  var s = '${value ?? ''}';
  if (s.isEmpty) return null;
  final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(s);
  if (!hasZone) s = '${s}Z'; // the server sends UTC without a zone marker
  return DateTime.tryParse(s)?.toLocal();
}

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return '${t.day}/${t.month}/${t.year}';
}

class PickedImage {
  final Uint8List bytes;
  final String name;
  PickedImage(this.bytes, this.name);
}

Future<PickedImage?> pickImageFromBrowser() {
  final completer = Completer<PickedImage?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/png,image/jpeg,image/webp,image/gif';

  Future<void> readFile() async {
    try {
      final file = input.files?.item(0);
      if (file == null) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      final buffer = await file.arrayBuffer().toDart;
      if (!completer.isCompleted) {
        completer.complete(PickedImage(buffer.toDart.asUint8List(), file.name));
      }
    } catch (e) {
      if (!completer.isCompleted) completer.completeError(e);
    }
  }

  input.addEventListener(
    'change',
    ((web.Event _) {
      readFile();
    }).toJS,
  );
  input.addEventListener(
    'cancel',
    ((web.Event _) {
      if (!completer.isCompleted) completer.complete(null);
    }).toJS,
  );

  input.click();
  return completer.future;
}

// ---------------------------------------------------------------------------
// Theme + visual helpers
// ---------------------------------------------------------------------------

const Color kViolet = Color(0xFF7C4DFF);
const Color kPink = Color(0xFFFF4D8D);
const LinearGradient kBrandGradient = LinearGradient(
  colors: [kViolet, kPink],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

final ValueNotifier<ThemeMode> themeMode =
    ValueNotifier<ThemeMode>(ThemeMode.dark);

void toggleTheme() {
  final next =
      themeMode.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  themeMode.value = next;
  web.window.localStorage
      .setItem('theme', next == ThemeMode.dark ? 'dark' : 'light');
}

String mediaUrl(String url) => url.startsWith('http') ? url : '$apiBaseUrl$url';

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(seedColor: kViolet, brightness: brightness);
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: c, width: w),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor:
        dark ? const Color(0xFF0D0916) : const Color(0xFFF8F5FF),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0x14FFFFFF) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: border(Colors.transparent),
      enabledBorder:
          border(dark ? const Color(0x1AFFFFFF) : const Color(0x1F7C4DFF)),
      focusedBorder: border(kViolet, 1.6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class GradientText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const GradientText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => kBrandGradient
          .createShader(Rect.fromLTWH(0, 0, rect.width, rect.height)),
      child: Text(text, style: style),
    );
  }
}

class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final IconData? icon;
  final bool expand;
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Container(
        decoration: BoxDecoration(
          gradient: kBrandGradient,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: Color(0x667C4DFF),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                  ],
                  DefaultTextStyle(
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    child: child,
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

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: dark ? const Color(0x0FFFFFFF) : Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: dark ? const Color(0x1AFFFFFF) : const Color(0x1A7C4DFF),
        ),
        boxShadow: dark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x147C4DFF),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
      ),
      child: child,
    );
  }
}

class RichPostText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const RichPostText({super.key, required this.text, this.style});

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'[#@][\p{L}\p{N}_]+', unicode: true);
    var last = 0;
    for (final m in regex.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      spans.add(TextSpan(
        text: m.group(0),
        style: const TextStyle(color: kPink, fontWeight: FontWeight.w700),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: style, children: spans));
  }
}

// ---------------------------------------------------------------------------
// Profiles, moderation, settings, legal pages
// ---------------------------------------------------------------------------

class PasswordNote extends StatelessWidget {
  const PasswordNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x1FFFB300),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x66FFB300)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: Color(0xFFFFB300)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "Please remember your password. You can't reset it if you forget it, so keep it somewhere safe.",
              style: TextStyle(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

void _showInfo(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}

const List<String> kReportReasons = [
  'Spam',
  'Harassment or bullying',
  'Hate speech',
  'Nudity or sexual content',
  'Violence or threats',
  'Scam or fake account',
  'Something else',
];

Future<String?> showReportDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Why are you reporting this?'),
      children: [
        for (final r in kReportReasons)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, r),
            child: Text(r),
          ),
      ],
    ),
  );
}

const String kPrivacyText = '''
Last updated: 17 October 2026

This app lets people share posts, photos and comments. This policy explains what we collect and why.

WHAT WE COLLECT
- Account details: email address, username, display name, bio and profile photo.
- Content you add: posts, comments, photos and likes.
- Technical data: your IP address and basic request logs, used to keep the service secure and to limit abuse.
- Your password is stored only as a protected hash. We cannot read it.

HOW WE USE IT
We use this information to run the app, show your content to other people, keep the service secure, prevent spam and respond to reports. We do not sell your personal information and we do not show ads.

WHO CAN SEE WHAT
Your username, display name, bio, profile photo, posts, comments and likes are visible to other people using the app. Your email address is never shown to other users.

SERVICES WE USE
We use hosting, database and image-storage providers to run the app. They process data on our behalf, only to provide their services.

KEEPING AND DELETING YOUR DATA
You can edit your profile at any time. You can delete your account in Settings. This permanently deletes your profile, posts, comments and likes. Copies of uploaded photos may remain with our image provider for a limited time, and we may keep reports and security logs where needed to keep the community safe.

AGE
This app is for people aged 18 and over.

CONTACT
For questions about your data, contact: your-email@example.com

CHANGES
We may update this policy. Significant changes will be shown in the app.
''';

const String kTermsText = '''
Last updated: 17 October 2026

By creating an account or using this app, you agree to these terms.

YOUR ACCOUNT
You must be 18 or older. Keep your password safe. You are responsible for what happens under your account.

WHAT YOU CAN POST
You own what you post, and you allow us to store and display it in the app so the service can work. Do not post anything that:
- is illegal, or sexually explicit, or involves minors in any way
- harasses, threatens or bullies others, or promotes hatred or violence
- is spam, a scam, or pretends to be someone else
- contains other people's private information or content you do not have the right to share

REPORTING AND MODERATION
Anyone can report a post or comment, and block any user. We may remove content, limit features or suspend accounts that break these terms, at our discretion.

THE SERVICE
The app is provided as it is, without promises that it will always be available or error-free. We may change or stop parts of it. To the extent allowed by law, we are not responsible for content posted by users.

LEAVING
You can delete your account at any time in Settings.

CONTACT
Questions or reports: your-email@example.com

CHANGES
We may update these terms. Continuing to use the app after a change means you accept it.
''';

class LegalScreen extends StatelessWidget {
  final String title;
  final String text;
  const LegalScreen({super.key, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SelectableText(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(height: 1.55),
            ),
          ),
        ),
      ),
    );
  }
}

void openLegal(BuildContext context, String title, String text) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => LegalScreen(title: title, text: text)),
  );
}

class AgreementNote extends StatelessWidget {
  const AgreementNote({super.key});

  @override
  Widget build(BuildContext context) {
    Widget link(String label, String title, String text) => GestureDetector(
          onTap: () => openLegal(context, title, text),
          child: Text(
            label,
            style: const TextStyle(color: kPink, fontWeight: FontWeight.w700),
          ),
        );
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        const Text('By creating an account you agree to the '),
        link('Terms', 'Terms of Service', kTermsText),
        const Text(' and '),
        link('Privacy Policy', 'Privacy Policy', kPrivacyText),
        const Text('.'),
      ],
    );
  }
}

class ProfileScreen extends StatefulWidget {
  final int userId;
  final int? currentUserId;
  final bool isGuest;
  const ProfileScreen({
    super.key,
    required this.userId,
    required this.currentUserId,
    required this.isGuest,
  });
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const int _pageSize = 20;

  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _changed = false;
  Object? _error;

  bool get _isMe =>
      widget.currentUserId != null && widget.currentUserId == widget.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await ApiService.instance.getProfile(widget.userId);
      final posts = await ApiService.instance
          .getPosts(offset: 0, limit: _pageSize, userId: widget.userId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _posts = posts;
        _hasMore = posts.length == _pageSize;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final data = await ApiService.instance.getPosts(
          offset: _posts.length, limit: _pageSize, userId: widget.userId);
      if (!mounted) return;
      final known = _posts.map((p) => p['id']).toSet();
      setState(() {
        _posts = [..._posts, ...data.where((p) => !known.contains(p['id']))];
        _hasMore = data.length == _pageSize;
      });
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _toggleBlock() async {
    final blocked = _profile?['is_blocked'] == true;
    try {
      if (blocked) {
        await ApiService.instance.unblockUser(widget.userId);
      } else {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Block this user?'),
            content: const Text(
                'You will no longer see each other\'s posts and comments. You can unblock them any time from their profile.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Block')),
            ],
          ),
        );
        if (ok != true) return;
        await ApiService.instance.blockUser(widget.userId);
      }
      _changed = true;
      if (mounted) await _load();
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  Future<void> _edit() async {
    final updated = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => EditProfileScreen(profile: _profile!)),
    );
    if (updated != null && mounted) {
      _changed = true;
      await _load();
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  Widget _header(Map<String, dynamic> profile) {
    final bio = '${profile['bio'] ?? ''}'.trim();
    final isBlocked = profile['is_blocked'] == true;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: kBrandGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x557C4DFF),
            blurRadius: 30,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: UserAvatar(
              url: profile['avatar_url'] as String?,
              radius: 44,
              ring: false,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${profile['display_name'] ?? ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          Text(
            '@${profile['username'] ?? ''}',
            style: const TextStyle(
              color: Color(0xCCFFFFFF),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              bio,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, height: 1.4),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '${profile['post_count'] ?? 0} posts',
            style: const TextStyle(
              color: Color(0xCCFFFFFF),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          if (_isMe)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: kViolet,
              ),
              onPressed: _edit,
              child: const Text('Edit profile'),
            )
          else if (!widget.isGuest)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0x80FFFFFF)),
              ),
              onPressed: _toggleBlock,
              child: Text(isBlocked ? 'Unblock' : 'Block'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null || profile == null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_off_outlined, size: 56),
              const SizedBox(height: 12),
              const Text('Could not load this profile.',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              const SizedBox(height: 8),
              Text('${_error ?? ''}', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() => _loading = true);
                  _load();
                },
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            _header(profile),
            const SizedBox(height: 16),
            if (profile['is_blocked'] == true)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: Text('You blocked this user.')),
              )
            else if (_posts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No posts yet.')),
              ),
            for (final post in _posts) ...[
              PostCard(
                key: ValueKey(post['id']),
                post: post,
                isGuest: widget.isGuest,
                currentUserId: widget.currentUserId,
                onDeleted: () {
                  setState(() {
                    _posts = _posts.where((p) => p['id'] != post['id']).toList();
                  });
                },
                onChanged: _load,
              ),
              const SizedBox(height: 14),
            ],
            if (_loadingMore)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_hasMore)
              Center(
                child: TextButton(
                  onPressed: _loadMore,
                  child: const Text('Load more'),
                ),
              ),
          ],
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            profile == null ? 'Profile' : '${profile['display_name']}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            if (_isMe && profile != null)
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: _openSettings,
              ),
          ],
        ),
        body: body,
      ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const EditProfileScreen({super.key, required this.profile});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name =
      TextEditingController(text: '${widget.profile['display_name'] ?? ''}');
  late final TextEditingController _bio =
      TextEditingController(text: '${widget.profile['bio'] ?? ''}');
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _showError(context, 'Display name cannot be empty.');
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await ApiService.instance
          .updateProfile(displayName: name, bio: _bio.text.trim());
      if (!mounted) return;
      Navigator.pop(context, updated);
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _bio,
                  maxLength: 300,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Bio',
                    hintText: 'Tell people about yourself',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 20),
                GradientButton(
                  expand: true,
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving...' : 'Save changes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await ApiService.instance.logout();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (_) => false,
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently deletes your profile, posts, comments and likes. It cannot be undone.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Enter your password'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (password == null || password.isEmpty) return;
    try {
      await ApiService.instance.deleteAccount(password);
      await ApiService.instance.logout();
      if (!context.mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (_) => false,
      );
    } catch (e) {
      if (context.mounted) _showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacy Policy'),
                onTap: () => openLegal(context, 'Privacy Policy', kPrivacyText),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Terms of Service'),
                onTap: () => openLegal(context, 'Terms of Service', kTermsText),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Log out'),
                onTap: () => _logout(context),
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_forever_outlined, color: Colors.red),
                title: const Text('Delete my account',
                    style: TextStyle(color: Colors.red)),
                onTap: () => _deleteAccount(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showError(BuildContext context, Object error) {
  final message = error.toString().replaceFirst('Exception: ', '');
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
  );
}