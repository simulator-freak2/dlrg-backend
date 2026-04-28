import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:sqlite3/sqlite3.dart';

const _serviceName = 'dlrg-backend';
const _pbkdf2Iterations = 120000;
const _pbkdf2Length = 32;

enum UserRole { nutzer, admin, vorsitz, kassenwart }

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final address = InternetAddress.anyIPv4;
  final dbPath = Platform.environment['DB_PATH'] ?? 'data/dlrg_backend.db';
  final serverPepper = Platform.environment['SERVER_PEPPER'] ?? 'dlrg-default-pepper-change-me';
  final adminUsername = Platform.environment['ADMIN_USERNAME'] ?? 'admin';
  final adminPassword = Platform.environment['ADMIN_PASSWORD'] ?? 'Admin123!';

  final database = _openDatabase(dbPath);
  _createSchema(database);
  await _seedAdminUser(
    database: database,
    adminUsername: adminUsername,
    adminPassword: adminPassword,
    serverPepper: serverPepper,
  );

  final server = await HttpServer.bind(address, port);
  stdout.writeln('$_serviceName listening on ${server.address.address}:$port');
  stdout.writeln('Database path: $dbPath');

  ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('Received SIGINT, shutting down backend...');
    await server.close(force: true);
    database.dispose();
    exit(0);
  });

  await for (final request in server) {
    _addCorsHeaders(request.response);

    if (request.method == 'OPTIONS') {
      request.response
        ..statusCode = HttpStatus.noContent
        ..close();
      continue;
    }

    if (request.method == 'GET' && request.uri.path == '/health') {
      _json(request.response, HttpStatus.ok, {
        'status': 'ok',
        'service': _serviceName,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
      continue;
    }

    if (request.method == 'GET' && request.uri.path == '/') {
      _json(request.response, HttpStatus.ok, {
        'name': _serviceName,
        'message': 'Backend service is running.',
        'health': '/health',
      });
      continue;
    }

    if (request.method == 'POST' && request.uri.path == '/auth/login') {
      await _handleLogin(request, database, serverPepper);
      continue;
    }

    if (request.method == 'GET' && request.uri.path == '/roles') {
      _json(request.response, HttpStatus.ok, {
        'roles': UserRole.values.map((role) => role.name).toList(),
      });
      continue;
    }

    if (request.method == 'POST' && request.uri.path == '/admin/users') {
      await _handleAdminCreateUser(request, database, serverPepper);
      continue;
    }

    _json(
      request.response,
      HttpStatus.notFound,
      {'error': 'Not found', 'path': request.uri.path},
    );
  }
}

Future<void> _handleLogin(
  HttpRequest request,
  Database database,
  String serverPepper,
) async {
  final response = request.response;

  try {
    final body = await utf8.decoder.bind(request).join();
    final parsed = jsonDecode(body);
    if (parsed is! Map<String, dynamic>) {
      _json(response, HttpStatus.badRequest, {'error': 'Invalid request body'});
      return;
    }

    final localUsernameHash = (parsed['usernameHash'] ?? '').toString();
    final localPasswordHash = (parsed['passwordHash'] ?? '').toString();

    if (localUsernameHash.isEmpty || localPasswordHash.isEmpty) {
      _json(
        response,
        HttpStatus.badRequest,
        {'error': 'usernameHash and passwordHash are required'},
      );
      return;
    }

    final auth = _authenticateUser(
      database: database,
      localUsernameHash: localUsernameHash,
      localPasswordHash: localPasswordHash,
      serverPepper: serverPepper,
    );

    if (auth == null) {
      _json(response, HttpStatus.unauthorized, {'error': 'Invalid credentials'});
      return;
    }

    _json(response, HttpStatus.ok, {
      'ok': true,
      'role': auth.role.name,
      'message': 'Login successful',
    });
  } catch (_) {
    _json(
      response,
      HttpStatus.internalServerError,
      {'error': 'Internal server error'},
    );
  }
}

Future<void> _handleAdminCreateUser(
  HttpRequest request,
  Database database,
  String serverPepper,
) async {
  final response = request.response;

  try {
    final body = await utf8.decoder.bind(request).join();
    final parsed = jsonDecode(body);
    if (parsed is! Map<String, dynamic>) {
      _json(response, HttpStatus.badRequest, {'error': 'Invalid request body'});
      return;
    }

    final adminUsernameHash = (parsed['adminUsernameHash'] ?? '').toString();
    final adminPasswordHash = (parsed['adminPasswordHash'] ?? '').toString();
    final newUsernameHash = (parsed['newUsernameHash'] ?? '').toString();
    final newPasswordHash = (parsed['newPasswordHash'] ?? '').toString();
    final roleRaw = (parsed['role'] ?? '').toString();

    if (adminUsernameHash.isEmpty ||
        adminPasswordHash.isEmpty ||
        newUsernameHash.isEmpty ||
        newPasswordHash.isEmpty ||
        roleRaw.isEmpty) {
      _json(response, HttpStatus.badRequest, {
        'error': 'admin and new user hashes plus role are required',
      });
      return;
    }

    final adminAuth = _authenticateUser(
      database: database,
      localUsernameHash: adminUsernameHash,
      localPasswordHash: adminPasswordHash,
      serverPepper: serverPepper,
    );

    if (adminAuth == null || adminAuth.role != UserRole.admin) {
      _json(response, HttpStatus.forbidden, {'error': 'Admin authorization required'});
      return;
    }

    final targetRole = _roleFromString(roleRaw);
    if (targetRole == null) {
      _json(response, HttpStatus.badRequest, {'error': 'Invalid role'});
      return;
    }

    final newUserLookupHash = _serverLookupHash(newUsernameHash, serverPepper);
    final exists = database.select(
      'SELECT id FROM users WHERE username_lookup_hash = ? LIMIT 1',
      [newUserLookupHash],
    );
    if (exists.isNotEmpty) {
      _json(response, HttpStatus.conflict, {'error': 'User already exists'});
      return;
    }

    final salt = _randomBytes(16);
    final passwordHash = _derivePasswordHash(newPasswordHash, salt);
    final encryptedUsernameHash = await _encryptUsernameHash(newUsernameHash, serverPepper);

    database.execute(
      '''
      INSERT INTO users (
        username_lookup_hash,
        username_encrypted,
        password_salt,
        password_hash,
        role,
        created_at
      ) VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [
        newUserLookupHash,
        encryptedUsernameHash,
        Uint8List.fromList(salt),
        Uint8List.fromList(passwordHash),
        targetRole.name,
        DateTime.now().toUtc().toIso8601String(),
      ],
    );

    _json(response, HttpStatus.created, {
      'ok': true,
      'role': targetRole.name,
      'message': 'User created',
    });
  } catch (_) {
    _json(
      response,
      HttpStatus.internalServerError,
      {'error': 'Internal server error'},
    );
  }
}

Database _openDatabase(String dbPath) {
  final dbFile = File(dbPath);
  dbFile.parent.createSync(recursive: true);
  return sqlite3.open(dbPath);
}

void _createSchema(Database database) {
  database.execute('''
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username_lookup_hash TEXT NOT NULL UNIQUE,
      username_encrypted BLOB NOT NULL,
      password_salt BLOB NOT NULL,
      password_hash BLOB NOT NULL,
      role TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
}

Future<void> _seedAdminUser({
  required Database database,
  required String adminUsername,
  required String adminPassword,
  required String serverPepper,
}) async {
  final normalizedUsername = adminUsername.trim().toLowerCase();
  final localUsernameHash = sha256.convert(utf8.encode(normalizedUsername)).toString();
  final localPasswordHash = sha256.convert(utf8.encode(adminPassword)).toString();
  final usernameLookupHash = _serverLookupHash(localUsernameHash, serverPepper);

  final exists = database.select(
    'SELECT id FROM users WHERE username_lookup_hash = ? LIMIT 1',
    [usernameLookupHash],
  );
  if (exists.isNotEmpty) return;

  final salt = _randomBytes(16);
  final passwordHash = _derivePasswordHash(localPasswordHash, salt);
  final usernameEncrypted = await _encryptUsernameHash(localUsernameHash, serverPepper);

  database.execute(
    '''
    INSERT INTO users (
      username_lookup_hash,
      username_encrypted,
      password_salt,
      password_hash,
      role,
      created_at
    ) VALUES (?, ?, ?, ?, ?, ?)
    ''',
    [
      usernameLookupHash,
      usernameEncrypted,
      Uint8List.fromList(salt),
      Uint8List.fromList(passwordHash),
      UserRole.admin.name,
      DateTime.now().toUtc().toIso8601String(),
    ],
  );

  stdout.writeln('Seeded admin user "$adminUsername" with role "admin".');
}

String _serverLookupHash(String localUsernameHash, String serverPepper) {
  return sha256.convert(utf8.encode('$localUsernameHash:$serverPepper')).toString();
}

List<int> _derivePasswordHash(String localPasswordHash, List<int> salt) {
  var block = <int>[...utf8.encode(localPasswordHash), ...salt];
  for (var i = 0; i < _pbkdf2Iterations; i++) {
    block = sha256.convert(block).bytes;
  }
  return block.take(_pbkdf2Length).toList();
}

_AuthResult? _authenticateUser({
  required Database database,
  required String localUsernameHash,
  required String localPasswordHash,
  required String serverPepper,
}) {
  final usernameLookupHash = _serverLookupHash(localUsernameHash, serverPepper);
  final result = database.select(
    '''
    SELECT role, password_salt, password_hash
    FROM users
    WHERE username_lookup_hash = ?
    LIMIT 1
    ''',
    [usernameLookupHash],
  );

  if (result.isEmpty) {
    return null;
  }

  final row = result.first;
  final salt = row['password_salt'] as Uint8List;
  final expectedHash = row['password_hash'] as Uint8List;
  final actualHash = _derivePasswordHash(localPasswordHash, salt);
  if (!_constantTimeEquals(actualHash, expectedHash)) {
    return null;
  }

  final roleRaw = (row['role'] ?? '').toString();
  final role = _roleFromString(roleRaw);
  if (role == null) {
    return null;
  }

  return _AuthResult(role: role);
}

UserRole? _roleFromString(String roleRaw) {
  for (final role in UserRole.values) {
    if (role.name == roleRaw) return role;
  }
  return null;
}

Future<String> _encryptUsernameHash(String value, String serverPepper) async {
  final keyBytes = sha256.convert(utf8.encode(serverPepper)).bytes;
  final algorithm = AesGcm.with256bits();
  final nonce = _randomBytes(12);
  final secretKey = SecretKey(keyBytes);
  final secretBox = await algorithm.encrypt(
    utf8.encode(value),
    secretKey: secretKey,
    nonce: nonce,
  );
  final nonceB64 = base64Encode(secretBox.nonce);
  final cipherB64 = base64Encode(secretBox.cipherText);
  final macB64 = base64Encode(secretBox.mac.bytes);
  return '$nonceB64:$cipherB64:$macB64';
}

List<int> _randomBytes(int length) {
  final rnd = Random.secure();
  return List<int>.generate(length, (_) => rnd.nextInt(256));
}

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

void _addCorsHeaders(HttpResponse response) {
  response.headers
    ..set('Access-Control-Allow-Origin', '*')
    ..set('Access-Control-Allow-Methods', 'GET,POST,OPTIONS')
    ..set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
}

void _json(HttpResponse response, int statusCode, Map<String, Object?> body) {
  response
    ..statusCode = statusCode
    ..headers.contentType = ContentType.json;
  response.write(jsonEncode(body));
  response.close();
}

class _AuthResult {
  const _AuthResult({required this.role});

  final UserRole role;
}
