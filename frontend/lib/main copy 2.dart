

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;


// For Flutter Web on the same computer, use 127.0.0.1.
// For Android Emulator, use http://10.0.2.2:8000 instead.
// For a physical phone, use your computer's LAN IP address.
const String apiBaseUrl = 'http://127.0.0.1:8000';

//void main() => runApp(const SocialApp());
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

 void loadSavedToken() {
    accessToken = web.window.localStorage.getItem(_tokenKey);
  }

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
      await getMe();
      return true;
    } catch (_) {
      accessToken = null;
      _saveToken(null);
      return false;
    }
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

  
Future<void> createPost(String content) async {
  if (accessToken == null || accessToken!.isEmpty) {
    throw Exception('Please log in to publish a post.');
  }

  final response = await http.post(
    Uri.parse('$apiBaseUrl/posts'),
    headers: _headers,
    body: jsonEncode({'content': content.trim()}),
  );

  if (response.statusCode != 200 &&
      response.statusCode != 201) {
    throw Exception(_errorMessage(response));
  }
}

 Future<Map<String, dynamic>> getMe() async {
    final response = await http.get(Uri.parse('$apiBaseUrl/users/me'), headers: _headers);
    if (response.statusCode != 200) throw Exception(_errorMessage(response));
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

    Future<String> uploadAvatar(Uint8List bytes, String filename) async {
    final request = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/users/me/avatar'));
    request.headers['Authorization'] = 'Bearer $accessToken';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final response = await http.Response.fromStream(await request.send());
    if (response.statusCode != 200) throw Exception(_errorMessage(response));
    return (jsonDecode(response.body) as Map)['avatar_url'] as String;
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

  Future<void> addComment(int postId, String content) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/posts/$postId/comments'),
      headers: _headers,
      body: jsonEncode({'content': content.trim()}),
    );
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception(_errorMessage(response));
    }
  }

 Future<void> logout() async {
    accessToken = null;
    _saveToken(null);
  }
}

class SocialApp extends StatelessWidget {
  const SocialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
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
                    if (widget.notice != null) ...[
                      Text(widget.notice!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 12),
                    ],
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
  Map<String, dynamic>? _me;

  @override
  void initState() {
    super.initState();
    _posts = ApiService.instance.getPosts();
     await Navigator.push<bool>(
              context,
              MaterialPageRoute(builder: (_) => const CreatePostScreen()),
            );

            if (!mounted) return;
            await _refresh();
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
        body: Column(
          children: [
            if (!widget.isGuest)
              ProfileHeader(me: _me, onChangePhoto: _changePhoto),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _posts,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return ListView(
                        children: const [
                          SizedBox(height: 220),
                          Center(child: CircularProgressIndicator()),
                        ],
                      );
                    }
                    if (snapshot.hasError) {
                      return ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          const Icon(Icons.cloud_off_outlined, size: 56),
                          const SizedBox(height: 12),
                          const Text('Could not load the public feed.',
                              textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          Text('${snapshot.error}', textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          Center(
                            child: FilledButton(
                              onPressed: _refresh,
                              child: const Text('Try again'),
                            ),
                          ),
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
                          Text('No posts yet',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          SizedBox(height: 8),
                          Text(
                              'Public posts will appear here when people start sharing.',
                              textAlign: TextAlign.center),
                        ],
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: posts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) =>
                          PostCard(key: ValueKey(posts[index]['id']),post: posts[index], isGuest: widget.isGuest,currentUserId: _me?['id'] as int?,
                        onDeleted: _refresh,),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
                floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            if (widget.isGuest) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
              return;
            }

            await Navigator.push<bool>(
              context,
              MaterialPageRoute(builder: (_) => const CreatePostScreen()),
            );

            if (!mounted) return;
            await _refresh();
          },
          icon: Icon(widget.isGuest ? Icons.login : Icons.add),
          label: Text(widget.isGuest ? 'Log in to post' : 'Create post'),
        ),
}

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() =>
      _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _controller = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final content = _controller.text.trim();

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write something first.')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      await ApiService.instance.createPost(content);

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create post')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 7,
              maxLength: 2000,
              decoration: const InputDecoration(
                hintText: "What's on your mind?",
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _publish,
                icon: const Icon(Icons.send),
                label: Text(
                  _loading ? 'Publishing...' : 'Publish post',
                ),
              ),
            ),
          ],
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
String _authorUsername(Map<String, dynamic> post) {
  final author = post['author'];
  if (author is Map && author['username'] != null) {
    final username = '${author['username']}'.trim();
    if (username.isNotEmpty) return '@$username';
  }
  return 'NO AUTHOR DATA (id ${post['author_id'] ?? '?'})';
}

class UserAvatar extends StatelessWidget {
  final String? url;
  final double radius;
  const UserAvatar({super.key, this.url, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final hasImage = url != null && url!.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundImage: hasImage ? NetworkImage('$apiBaseUrl$url') : null,
      child: hasImage ? null : Icon(Icons.person_outline, size: radius),
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
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Stack(
              children: [
                UserAvatar(url: me!['avatar_url'] as String?, radius: 34),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: InkWell(
                    onTap: onChangePhoto,
                    child: CircleAvatar(
                      radius: 12,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
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
                  Text('${me!['display_name'] ?? ''}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  Text('@${me!['username'] ?? ''}', style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
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
  const PostCard({super.key, required this.post, required this.isGuest,this.currentUserId,
    this.onDeleted,
});
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late bool _liked;
  late int _likes;
  late int _comments;

  @override
  void initState() {
    super.initState();
    _liked = widget.post['liked_by_me'] == true;
    _likes = (widget.post['like_count'] as int?) ?? 0;
    _comments = (widget.post['comment_count'] as int?) ?? 0;
  }

    Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
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

  Future<void> _toggleLike() async {
    if (widget.isGuest) {
      _showError(context, 'Log in to like posts.');
      return;
    }
    final wasLiked = _liked;
    setState(() {
      _liked = !wasLiked;
      _likes += wasLiked ? -1 : 1;
    });
    try {
      final result = await ApiService.instance.toggleLike(widget.post['id'] as int);
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
        builder: (_) => CommentsScreen(postId: widget.post['id'] as int, isGuest: widget.isGuest,
          currentUserId: widget.currentUserId,),
      ),
    );
    if (count != null && mounted) setState(() => _comments = count);
  }

  @override
  Widget build(BuildContext context) {
    final createdAt = parseServerTime(post['created_at']);
    final post = widget.post;
    final author = post['author'] is Map ? post['author'] as Map : const {};
    final username = author['username'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              UserAvatar(url: author['avatar_url'] as String?),
              const SizedBox(width: 10),
              Expanded(
                    if (widget.currentUserId != null &&
                        widget.currentUserId == post['author_id'])
                      IconButton(
                        tooltip: 'Delete post',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _confirmDelete,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${author['display_name'] ?? 'User #${post['author_id']}'}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (username != null)
                      Text('@$username', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Text('${post['content'] ?? ''}', style: Theme.of(context).textTheme.bodyLarge),
            if (createdAt != null) ...[
              const SizedBox(height: 12),
              Text(createdAt.toString(), style: Theme.of(context).textTheme.bodySmall),
            ],
            const Divider(height: 24),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _toggleLike,
                  icon: Icon(_liked ? Icons.favorite : Icons.favorite_border,
                      color: _liked ? Colors.red : null),
                  label: Text('$_likes'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _openComments,
                  icon: const Icon(Icons.mode_comment_outlined),
                  label: Text('$_comments'),
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
  const CommentsScreen({super.key, required this.postId, required this.isGuest,this.currentUserId,});
  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ApiService.instance.addComment(widget.postId, text);
      _controller.clear();
      await _load();
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
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
                      ? const Center(child: Text('No comments yet. Be the first!'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _comments.length,
                          itemBuilder: (context, i) {
                            final c = _comments[i];
                            final author = c['author'] is Map ? c['author'] as Map : const {};
                            return ListTile(
                              leading: UserAvatar(url: author['avatar_url'] as String?),
                              title: Text('@${author['username'] ?? 'user'}',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${c['content'] ?? ''}'),
                              trailing: widget.currentUserId != null &&
                                      widget.currentUserId == author['id']
                                  ? IconButton(
                                      tooltip: 'Delete comment',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _delete(c['id'] as int),
                                    )
                                  : null,
                            );
                            
                          },
                        ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: widget.isGuest
                    ? const Text('Log in to comment.')
                    : Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              maxLength: 1000,
                              decoration: const InputDecoration(
                                hintText: 'Write a comment...',
                                counterText: '',
                              ),
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: _sending ? null : _send,
                            icon: const Icon(Icons.send),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
    ..accept = 'image/png,image/jpeg,image/webp';

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
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data == true
            ? const FeedScreen(isGuest: false)
            : const WelcomeScreen();
      },
    );
  }
}

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