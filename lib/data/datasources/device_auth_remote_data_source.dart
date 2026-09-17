import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/error/exceptions.dart';

/// POST /v1/pair's result: the client identity the relay created for
/// this device (see pkg/relayapi.PairResponse on the relay side).
class PairResult {
  final String clientId;
  final String displayName;
  const PairResult({required this.clientId, required this.displayName});
}

/// Talks to a FreeBeamer relay's device pairing/auth endpoints (POST
/// /v1/pair, /v1/auth/challenge, /v1/auth/session, /v1/auth/logout) —
/// the bootstrap and re-authentication half of the device identity
/// model. POST /v1/telemetry itself stays ITelemetryRemoteDataSource's
/// job; relayUrl here is always the relay's base URL with no
/// /v1/telemetry suffix (see DevicePairing's own doc comment).
abstract class IDeviceAuthRemoteDataSource {
  Future<PairResult> pair({
    required String relayUrl,
    required String pairingToken,
    required Uint8List publicKey,
    Duration timeout = const Duration(seconds: 5),
  });

  /// Returns the raw challenge nonce to sign — not yet base64, that's
  /// purely this data source's own wire encoding.
  Future<Uint8List> challenge({
    required String relayUrl,
    required String clientId,
    Duration timeout = const Duration(seconds: 5),
  });

  /// Returns a fresh session token, scoped to device-facing endpoints
  /// only (see the relay's requireDeviceSession).
  Future<String> createSession({
    required String relayUrl,
    required String clientId,
    required Uint8List signature,
    Duration timeout = const Duration(seconds: 5),
  });

  /// Revokes sessionToken server-side immediately. Deliberately
  /// tolerant of failure at the call site (see LogoutDevice) — ending a
  /// local session shouldn't be blocked on the relay being reachable.
  Future<void> logout({
    required String relayUrl,
    required String sessionToken,
    Duration timeout = const Duration(seconds: 5),
  });
}

class DeviceAuthRemoteDataSourceImpl implements IDeviceAuthRemoteDataSource {
  final http.Client _client;
  DeviceAuthRemoteDataSourceImpl({http.Client? client})
      : _client = client ?? http.Client();

  Uri _uri(String relayUrl, String path) {
    final base = relayUrl.endsWith('/')
        ? relayUrl.substring(0, relayUrl.length - 1)
        : relayUrl;
    return Uri.parse('$base$path');
  }

  Future<http.Response> _postJson(
    String relayUrl,
    String path,
    Map<String, dynamic> body, {
    String? bearer,
    required Duration timeout,
  }) async {
    final request = http.Request('POST', _uri(relayUrl, path))
      ..followRedirects = false
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);
    if (bearer != null) request.headers['Authorization'] = 'Bearer $bearer';
    final streamed = await _client.send(request).timeout(timeout);
    return http.Response.fromStream(streamed);
  }

  @override
  Future<PairResult> pair({
    required String relayUrl,
    required String pairingToken,
    required Uint8List publicKey,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final response = await _postJson(
      relayUrl,
      '/v1/pair',
      {'pairing_token': pairingToken, 'public_key': base64Encode(publicKey)},
      timeout: timeout,
    );
    if (response.statusCode == 410) {
      throw DeviceAuthException(
          'this pairing link was already used or has expired');
    }
    if (response.statusCode != 200) {
      throw DeviceAuthException('pair failed: status ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return PairResult(
      clientId: body['client_id'] as String,
      displayName: body['display_name'] as String? ?? '',
    );
  }

  @override
  Future<Uint8List> challenge({
    required String relayUrl,
    required String clientId,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final response = await _postJson(
      relayUrl,
      '/v1/auth/challenge',
      {'client_id': clientId},
      timeout: timeout,
    );
    if (response.statusCode != 200) {
      throw DeviceAuthException(
          'challenge failed: status ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return base64Decode(body['nonce'] as String);
  }

  @override
  Future<String> createSession({
    required String relayUrl,
    required String clientId,
    required Uint8List signature,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final response = await _postJson(
      relayUrl,
      '/v1/auth/session',
      {'client_id': clientId, 'signature': base64Encode(signature)},
      timeout: timeout,
    );
    if (response.statusCode != 200) {
      throw DeviceAuthException(
          'session failed: status ${response.statusCode}');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['session_token'] as String;
  }

  @override
  Future<void> logout({
    required String relayUrl,
    required String sessionToken,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      await _postJson(relayUrl, '/v1/auth/logout', const {},
          bearer: sessionToken, timeout: timeout);
    } catch (_) {
      // Best-effort: the local session ends regardless (see
      // LogoutDevice) — an unreachable relay shouldn't block that.
    }
  }
}
