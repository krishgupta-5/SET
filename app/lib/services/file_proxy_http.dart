import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

import 'app_config.dart';

/// Adds `Authorization: Bearer <Firebase ID token>` to image requests for the
/// backend file proxy (`<API_URL>/files/...`).
///
/// Stored images are rendered with plain `Image.network` / `NetworkImage`,
/// which can't take an async token. This override attaches the cached token
/// only for that host + path, leaving every other request untouched.
class FileProxyHttpOverrides extends HttpOverrides {
  static String? _token;
  static StreamSubscription<User?>? _sub;
  static Timer? _refresh;

  static final Uri _api = Uri.parse(AppConfig.apiUrl);

  /// Keeps a fresh ID token cached (they expire after ~1h).
  static void startTokenRefresh() {
    _sub ??= FirebaseAuth.instance.idTokenChanges().listen((user) async {
      _token = user == null ? null : await user.getIdToken();
    });
    _refresh ??= Timer.periodic(const Duration(minutes: 45), (_) async {
      final u = FirebaseAuth.instance.currentUser;
      _token = u == null ? null : await u.getIdToken(true);
    });
  }

  static bool isProxyUrl(Uri url) =>
      url.host == _api.host &&
      url.port == _api.port &&
      url.path.startsWith('/files/');

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _AuthHttpClient(super.createHttpClient(context));
}

class _AuthHttpClient implements HttpClient {
  _AuthHttpClient(this._inner);
  final HttpClient _inner;

  Future<HttpClientRequest> _withAuth(Future<HttpClientRequest> f) async {
    final req = await f;
    final token = FileProxyHttpOverrides._token;
    if (token != null && FileProxyHttpOverrides.isProxyUrl(req.uri)) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    return req;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _withAuth(_inner.getUrl(url));
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _withAuth(_inner.openUrl(method, url));
  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _withAuth(_inner.get(host, port, path));
  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => _withAuth(_inner.open(method, host, port, path));

  // ---- straight delegation ----
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _inner.delete(host, port, path);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _inner.deleteUrl(url);
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _inner.head(host, port, path);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => _inner.headUrl(url);
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _inner.patch(host, port, path);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => _inner.patchUrl(url);
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _inner.post(host, port, path);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => _inner.postUrl(url);
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      _inner.put(host, port, path);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => _inner.putUrl(url);

  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool v) => _inner.autoUncompress = v;
  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? v) => _inner.connectionTimeout = v;
  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration v) => _inner.idleTimeout = v;
  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? v) => _inner.maxConnectionsPerHost = v;
  @override
  String? get userAgent => _inner.userAgent;
  @override
  set userAgent(String? v) => _inner.userAgent = v;

  @override
  void addCredentials(Uri url, String realm, HttpClientCredentials c) =>
      _inner.addCredentials(url, realm, c);
  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials c,
  ) => _inner.addProxyCredentials(host, port, realm, c);
  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) => _inner.authenticate = f;
  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
    f,
  ) => _inner.authenticateProxy = f;
  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? cb,
  ) => _inner.badCertificateCallback = cb;
  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )?
    f,
  ) => _inner.connectionFactory = f;
  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;
  @override
  set keyLog(Function(String line)? cb) => _inner.keyLog = cb;
  @override
  void close({bool force = false}) => _inner.close(force: force);
}
