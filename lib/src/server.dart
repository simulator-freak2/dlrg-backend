import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth.dart';
import 'models.dart';
import 'repository.dart';

Future<void> runServer() async {
  final repository = AppRepository();
  final authService = AuthService();
  final router = Router();

  router.get('/health', (Request request) {
    return _jsonResponse({'status': 'ok'});
  });

  router.post('/auth/login', (Request request) async {
    final body = await request.readAsString();
    final data = body.isEmpty ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>;
    final email = (data['email'] as String? ?? '').trim();
    User? user;
    for (final candidate in repository.users()) {
      if (candidate.email == email) {
        user = candidate;
        break;
      }
    }
    if (user == null) {
      return Response.forbidden(
        jsonEncode({'error': 'Unknown user.'}),
        headers: {'content-type': 'application/json'},
      );
    }
    final token = authService.issueToken(userId: user.id, role: user.role);
    return _jsonResponse({'token': token, 'user': user.toJson()});
  });

  final privilegedRoles = {
    AppRole.admin,
    AppRole.materialwart,
    AppRole.kassenwart,
    AppRole.vorsitz,
  };

  router.get('/users', (Request request) {
    return _jsonResponse({'data': repository.users().map((e) => e.toJson()).toList()});
  });

  router.get('/inventory', (Request request) {
    return _jsonResponse({'data': repository.inventory().map((e) => e.toJson()).toList()});
  });

  router.get('/clothing', (Request request) {
    return _jsonResponse({'data': repository.clothing().map((e) => e.toJson()).toList()});
  });

  router.get('/documents/templates', (Request request) {
    return _jsonResponse({'data': repository.documentTemplates().map((e) => e.toJson()).toList()});
  });

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addMiddleware(requireRoles(privilegedRoles, authService))
      .addHandler(router.call);

  final ip = InternetAddress.anyIPv4;
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await io.serve(handler, ip, port);
  print('Server running on http://${server.address.host}:${server.port}');
}

Response _jsonResponse(Map<String, dynamic> data, {int statusCode = 200}) {
  return Response(
    statusCode,
    body: jsonEncode(data),
    headers: {'content-type': 'application/json'},
  );
}
