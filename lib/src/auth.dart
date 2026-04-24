import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:shelf/shelf.dart';

import 'models.dart';

const _jwtSecret = 'change-me-for-production';

class AuthService {
  String issueToken({
    required String userId,
    required AppRole role,
  }) {
    final jwt = JWT(
      <String, dynamic>{
        'userId': userId,
        'role': role.name,
      },
    );
    return jwt.sign(SecretKey(_jwtSecret), expiresIn: const Duration(hours: 8));
  }

  ({String userId, AppRole role})? parseToken(String token) {
    try {
      final payload = JWT.verify(token, SecretKey(_jwtSecret)).payload;
      final map = payload is Map<String, dynamic>
          ? payload
          : Map<String, dynamic>.from(payload as Map);
      final userId = map['userId'] as String?;
      final roleValue = map['role'] as String?;
      if (userId == null || roleValue == null) {
        return null;
      }
      final role = AppRole.values.firstWhere((value) => value.name == roleValue);
      return (userId: userId, role: role);
    } on JWTException {
      return null;
    }
  }
}

Middleware requireRoles(Set<AppRole> allowedRoles, AuthService authService) {
  return (innerHandler) {
    return (request) async {
      final authHeader = request.headers['authorization'];
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return _unauthorized('Missing bearer token.');
      }
      final token = authHeader.substring('Bearer '.length);
      final auth = authService.parseToken(token);
      if (auth == null || !allowedRoles.contains(auth.role)) {
        return _unauthorized('Insufficient permissions.');
      }
      final scoped = request.change(context: {'userId': auth.userId, 'role': auth.role.name});
      return innerHandler(scoped);
    };
  };
}

Response _unauthorized(String message) {
  return Response.unauthorized(
    jsonEncode({'error': message}),
    headers: {'content-type': 'application/json'},
  );
}
