import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../data/datasources/device_auth_remote_data_source.dart';
import '../../data/models/device_pairing.dart';
import '../../data/models/provisioning_payload.dart';
import '../repositories/device_pairing_repository.dart';

const _telemetrySuffix = '/v1/telemetry';

/// A ProvisioningPayload's relayUrl is the full telemetry ingest
/// endpoint (see cmd/freebeamer-relay's provisioningLink); device-auth
/// calls and DevicePairing itself use the relay's base URL instead —
/// mirrors the exact suffix-stripping telemetry_remote_data_source.dart
/// already does to derive /v1/capabilities from the same endpoint.
String relayBaseUrl(String telemetryEndpoint) {
  return telemetryEndpoint.endsWith(_telemetrySuffix)
      ? telemetryEndpoint.substring(
          0, telemetryEndpoint.length - _telemetrySuffix.length)
      : telemetryEndpoint;
}

/// Redeems a single-use pairing link: generates a fresh Ed25519
/// keypair on-device (the private key never leaves it), exchanges the
/// public half for a client identity via POST /v1/pair, and persists
/// the result as a DevicePairing. The pairing link itself is disposed
/// of by the relay the instant this succeeds — a second device
/// presenting the same link always fails (see
/// IDeviceAuthRemoteDataSource.pair's 410 handling).
class PairDevice {
  final IDeviceAuthRemoteDataSource _remote;
  final IDevicePairingRepository _repository;
  final Ed25519 _algorithm;

  PairDevice(this._remote, this._repository, {Ed25519? algorithm})
      : _algorithm = algorithm ?? Ed25519();

  Future<DevicePairing> call(ProvisioningPayload payload) async {
    final relayUrl = relayBaseUrl(payload.relayUrl);
    final keyPair = await _algorithm.newKeyPair();
    final publicKey =
        Uint8List.fromList((await keyPair.extractPublicKey()).bytes);
    final privateKey =
        Uint8List.fromList(await keyPair.extractPrivateKeyBytes());

    final result = await _remote.pair(
      relayUrl: relayUrl,
      pairingToken: payload.pairingToken,
      publicKey: publicKey,
    );

    final pairing = DevicePairing(
      clientId: result.clientId,
      displayName:
          result.displayName.isNotEmpty ? result.displayName : payload.displayName,
      relayUrl: relayUrl,
      privateKey: privateKey,
      publicKey: publicKey,
      pairedAt: DateTime.now(),
    );
    await _repository.save(pairing);
    return pairing;
  }
}
