import 'package:flutter_test/flutter_test.dart';
import 'package:freebeamer_mobile/core/error/exceptions.dart';
import 'package:freebeamer_mobile/data/datasources/device_auth_remote_data_source.dart';
import 'package:freebeamer_mobile/data/models/provisioning_payload.dart';
import 'package:freebeamer_mobile/data/repositories/device_pairing_repository_impl.dart';
import 'package:freebeamer_mobile/domain/usecases/pair_device.dart';

import '../../support/fakes.dart';
import '../../support/fake_secure_storage.dart';

void main() {
  test('relayBaseUrl strips the /v1/telemetry suffix', () {
    expect(relayBaseUrl('https://relay.example/v1/telemetry'), 'https://relay.example');
    expect(relayBaseUrl('https://relay.example'), 'https://relay.example');
  });

  test('generates a keypair, redeems the link, and persists the pairing',
      () async {
    final remote = FakeDeviceAuthRemoteDataSource()
      ..pairResult = () =>
          const PairResult(clientId: 'client-42', displayName: 'Bay 3 - N55');
    final repository = DevicePairingRepositoryImpl(FakeSecureStorage());
    final pairDevice = PairDevice(remote, repository);

    const payload = ProvisioningPayload(
      relayUrl: 'https://relay.example/v1/telemetry',
      pairingToken: 'tok_abc',
      displayName: 'fallback name',
    );

    final pairing = await pairDevice(payload);

    expect(pairing.clientId, 'client-42');
    expect(pairing.displayName, 'Bay 3 - N55'); // server's name wins
    expect(pairing.relayUrl, 'https://relay.example'); // suffix stripped
    expect(pairing.publicKey, hasLength(32));
    expect(pairing.privateKey, hasLength(32));

    final saved = await repository.list();
    expect(saved, [pairing]);
  });

  test('falls back to the link\'s own display name when the server omits one',
      () async {
    final remote = FakeDeviceAuthRemoteDataSource()
      ..pairResult = () => const PairResult(clientId: 'client-1', displayName: '');
    final repository = DevicePairingRepositoryImpl(FakeSecureStorage());
    final pairDevice = PairDevice(remote, repository);

    const payload = ProvisioningPayload(
      relayUrl: 'https://relay.example/v1/telemetry',
      pairingToken: 'tok_abc',
      displayName: 'fallback name',
    );

    final pairing = await pairDevice(payload);
    expect(pairing.displayName, 'fallback name');
  });

  test('a consumed/expired pairing token surfaces DeviceAuthException',
      () async {
    final remote = FakeDeviceAuthRemoteDataSource()
      ..pairError = DeviceAuthException('gone');
    final repository = DevicePairingRepositoryImpl(FakeSecureStorage());
    final pairDevice = PairDevice(remote, repository);

    const payload = ProvisioningPayload(
      relayUrl: 'https://relay.example/v1/telemetry',
      pairingToken: 'tok_abc',
    );

    await expectLater(pairDevice(payload), throwsA(isA<DeviceAuthException>()));
    expect(await repository.list(), isEmpty);
  });
}
