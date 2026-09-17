import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// A device's durable identity at one relay, established once by
/// redeeming a single-use pairing link (see PairDevice) and reused
/// indefinitely afterward via challenge/response (see
/// AuthenticateDevice) — the on-device replacement for the old
/// permanent API key. [privateKey] never leaves the device; it's the
/// only thing that makes reconnecting without rescanning possible, so
/// losing it means the pairing itself is unrecoverable and the device
/// must be re-paired.
///
/// [relayUrl] is the relay's base URL (e.g. https://relay.example.com,
/// no path) — device-auth calls append /v1/pair, /v1/auth/challenge,
/// etc.; telemetry delivery appends /v1/telemetry separately (see
/// ConnectionCubit).
class DevicePairing extends Equatable {
  final String clientId;
  final String displayName;
  final String relayUrl;
  final Uint8List privateKey; // Ed25519 seed, 32 bytes
  final Uint8List publicKey; // 32 bytes
  final DateTime pairedAt;

  const DevicePairing({
    required this.clientId,
    required this.displayName,
    required this.relayUrl,
    required this.privateKey,
    required this.publicKey,
    required this.pairedAt,
  });

  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'display_name': displayName,
        'relay_url': relayUrl,
        'private_key': base64Encode(privateKey),
        'public_key': base64Encode(publicKey),
        'paired_at': pairedAt.toIso8601String(),
      };

  factory DevicePairing.fromJson(Map<String, dynamic> json) => DevicePairing(
        clientId: json['client_id'] as String,
        displayName: json['display_name'] as String,
        relayUrl: json['relay_url'] as String,
        privateKey: base64Decode(json['private_key'] as String),
        publicKey: base64Decode(json['public_key'] as String),
        pairedAt: DateTime.parse(json['paired_at'] as String),
      );

  @override
  List<Object?> get props =>
      [clientId, displayName, relayUrl, privateKey, publicKey, pairedAt];
}
