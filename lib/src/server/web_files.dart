import 'dart:io';

/// The web version of the app, served by a host's app to friends who play
/// in a browser: the folder `dart run tool/build_web.dart --host` makes
/// (shipped next to the Windows app as data/web). Plain http on the game's
/// port: `http://<host>:<port>/?code=ABCDE` opens Play Online at that room.
class WebFiles {
  WebFiles(this.folder);

  final Directory folder;

  /// Whether there is a web version to serve.
  bool get available => File('${folder.path}${Platform.pathSeparator}index.html').existsSync();

  /// Answers [request] with a file of the web version (the app's page for
  /// an address that isn't a file). Returns false if it isn't for this
  /// (not a GET, or not a file path).
  Future<bool> serve(HttpRequest request) async {
    if (request.method != 'GET' && request.method != 'HEAD') return false;
    final segments = request.uri.pathSegments.where((s) => s.isNotEmpty).toList();
    // Nothing outside the folder, nothing hidden.
    if (segments.any((s) => s.startsWith('.') || s.contains(RegExp(r'[\\/:*?"<>|]')))) return false;
    var file = File([folder.path, ...segments].join(Platform.pathSeparator));
    final name = segments.isEmpty ? 'index.html' : segments.last;
    if (segments.isEmpty || (!file.existsSync() && !name.contains('.'))) {
      file = File('${folder.path}${Platform.pathSeparator}index.html');
    } else if (!file.existsSync()) {
      return false;
    }
    final response = request.response;
    final type = _types[_extension(file.path)] ?? 'application/octet-stream';
    response.headers
      ..set(HttpHeaders.contentTypeHeader, type)
      // The page always fresh (it names the build's files), the rest for a while.
      ..set(HttpHeaders.cacheControlHeader, type.startsWith('text/html') ? 'no-cache' : 'max-age=3600');
    if (type.startsWith('text/html')) {
      // Served at the root, whatever base the build was made for.
      final page = (await file.readAsString()).replaceFirst(RegExp(r'<base href="[^"]*">'), '<base href="/">');
      if (request.method == 'GET') response.write(page);
    } else {
      response.contentLength = await file.length();
      if (request.method == 'GET') await response.addStream(file.openRead());
    }
    await response.close();
    return true;
  }

  static String _extension(String path) {
    final dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  }

  static const _types = {
    'html': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'mjs': 'text/javascript; charset=utf-8',
    'json': 'application/json',
    'wasm': 'application/wasm',
    'css': 'text/css; charset=utf-8',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'ico': 'image/x-icon',
    'svg': 'image/svg+xml',
    'otf': 'font/otf',
    'ttf': 'font/ttf',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
    'txt': 'text/plain; charset=utf-8',
  };
}
