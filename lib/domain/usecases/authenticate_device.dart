import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../data/datasources/device_auth_remote_data_source.dart';
import '../../data/models/device_pairing.dart';

/// The "second factor" that turns a paired device's stored private key
/// into a short-lived session token: request a challenge nonce, sign
/// it, exchange the signature for a session. Safe to call repeatedly —
/// every call gets a fresh nonce and a fresh token, whether it's the
/// first authentication right after pairing or a reconnect the next
/// day (see the tuners panel's tap-to-reconnect) — no new pairing link
/// is ever needed for this.
class AuthenticateDevice {
  final IDeviceAuthRemoteDataSource _remote;
  final Ed25519 _algorithm;

  AuthenticateDevice(this._remote, {Ed25519? algorithm})
      : _algorithm = algorithm ?? Ed25519();

  Future<String> call(DevicePairing pairing) async {
    final nonce = await _remote.challenge(
      relayUrl: pairing.relayUrl,
      clientId: pairing.clientId,
    );
    final keyPair = await _algorithm.newKeyPairFromSeed(pairing.privateKey);
    final signature = await _algorithm.sign(nonce, keyPair: keyPair);
    return _remote.createSession(
      relayUrl: pairing.relayUrl,
      clientId: pairing.clientId,
      signature: Uint8List.fromList(signature.bytes),
    );
  }
}
