import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeamer_mobile/core/error/exceptions.dart';
import 'package:freebeamer_mobile/data/models/device_pairing.dart';
import 'package:freebeamer_mobile/domain/usecases/authenticate_device.dart';

import '../../support/fakes.dart';

final testPairing = DevicePairing(
  clientId: 'client-1',
  displayName: 'Bay 3',
  relayUrl: 'https://relay.example',
  privateKey: Uint8List.fromList(List.filled(32, 1)),
  publicKey: Uint8List.fromList(List.filled(32, 2)),
  pairedAt: DateTime(2026, 9, 17),
);

void main() {
  test(
      'signs the exact challenge nonce with the pairing\'s own key and returns the session token',
      () async {
    // A real derived keypair (not an arbitrary filled array) so the
    // signature this produces can be genuinely verified below — the
    // whole point of this test.
    final keyPair = await Ed25519().newKeyPairFromSeed(List.filled(32, 1));
    final publicKey = await keyPair.extractPublicKey();
    final pairing = DevicePairing(
      clientId: 'client-1',
      displayName: 'Bay 3',
      relayUrl: 'https://relay.example',
      privateKey: Uint8List.fromList(List.filled(32, 1)),
      publicKey: Uint8List.fromList(publicKey.bytes),
      pairedAt: DateTime(2026, 9, 17),
    );

    final nonce = Uint8List.fromList(List.filled(32, 9));
    final remote = FakeDeviceAuthRemoteDataSource()
      ..challengeNonce = nonce
      ..sessionTokenFor = () => 'fresh-session-token';
    final authenticate = AuthenticateDevice(remote);

    final token = await authenticate(pairing);

    expect(token, 'fresh-session-token');
    expect(remote.lastSessionClientId, 'client-1');
    final validSignature = await Ed25519().verify(
      nonce,
      signature: Signature(remote.lastSignature!, publicKey: publicKey),
    );
    expect(validSignature, isTrue);
  });

  test('propagates a challenge failure (e.g. revoked client)', () async {
    final remote = FakeDeviceAuthRemoteDataSource()
      ..challengeError = DeviceAuthException('unknown or revoked client');
    final authenticate = AuthenticateDevice(remote);

    await expectLater(
        authenticate(testPairing), throwsA(isA<DeviceAuthException>()));
  });

  test('propagates a session-exchange failure', () async {
    final remote = FakeDeviceAuthRemoteDataSource()
      ..sessionError = DeviceAuthException('invalid signature');
    final authenticate = AuthenticateDevice(remote);

    await expectLater(
        authenticate(testPairing), throwsA(isA<DeviceAuthException>()));
  });
}
