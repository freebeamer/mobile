import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freebeamer_mobile/core/error/exceptions.dart';
import 'package:freebeamer_mobile/data/datasources/device_auth_remote_data_source.dart';
import 'package:freebeamer_mobile/data/models/device_pairing.dart';
import 'package:freebeamer_mobile/data/models/provisioning_payload.dart';
import 'package:freebeamer_mobile/data/repositories/device_pairing_repository_impl.dart';
import 'package:freebeamer_mobile/domain/usecases/forget_device.dart';
import 'package:freebeamer_mobile/domain/usecases/list_device_pairings.dart';
import 'package:freebeamer_mobile/domain/usecases/pair_device.dart';
import 'package:freebeamer_mobile/domain/usecases/parse_provisioning_link.dart';
import 'package:freebeamer_mobile/presentation/cubits/tuners_cubit.dart';

import '../../support/fake_secure_storage.dart';
import '../../support/fakes.dart';

DevicePairing pairing(String clientId) => DevicePairing(
      clientId: clientId,
      displayName: 'Bay $clientId',
      relayUrl: 'https://relay.example',
      privateKey: Uint8List.fromList(List.filled(32, 1)),
      publicKey: Uint8List.fromList(List.filled(32, 2)),
      pairedAt: DateTime(2026, 9, 17),
    );

void main() {
  late FakeDeviceAuthRemoteDataSource remote;
  late DevicePairingRepositoryImpl repository;
  late TunersCubit cubit;

  setUp(() {
    remote = FakeDeviceAuthRemoteDataSource();
    repository = DevicePairingRepositoryImpl(FakeSecureStorage());
    cubit = TunersCubit(
      listDevicePairings: ListDevicePairings(repository),
      pairDevice: PairDevice(remote, repository),
      forgetDevice: ForgetDevice(repository),
      parseProvisioningLink: ParseProvisioningLink(),
    );
  });
  tearDown(() => cubit.close());

  test('load populates pairings from the repository', () async {
    await repository.save(pairing('client-1'));
    await cubit.load();
    expect(cubit.state.pairings.map((p) => p.clientId), ['client-1']);
    expect(cubit.state.loaded, isTrue);
  });

  test('consumeLink rejects an unrecognized string without calling pair',
      () async {
    final result = await cubit.consumeLink('not a link');
    expect(result, isNull);
    expect(cubit.state.qrError, isNotNull);
    expect(cubit.state.pairings, isEmpty);
  });

  test('consumeLink pairs, saves, and refreshes the list', () async {
    remote.pairResult =
        () => const PairResult(clientId: 'client-9', displayName: 'Bay 9');
    final link = const ProvisioningPayload(
            relayUrl: 'https://relay.example/v1/telemetry', pairingToken: 'tok')
        .toUri()
        .toString();

    final result = await cubit.consumeLink(link);

    expect(result?.clientId, 'client-9');
    expect(cubit.state.pairings.map((p) => p.clientId), ['client-9']);
    expect(cubit.state.busy, isFalse);
  });

  test('consumeLink surfaces a pairing failure without crashing', () async {
    remote.pairError = DeviceAuthException('gone');
    final link = const ProvisioningPayload(
            relayUrl: 'https://relay.example/v1/telemetry', pairingToken: 'tok')
        .toUri()
        .toString();

    final result = await cubit.consumeLink(link);

    expect(result, isNull);
    expect(cubit.state.error, isNotNull);
    expect(cubit.state.busy, isFalse);
    expect(cubit.state.pairings, isEmpty);
  });

  test('forget removes a pairing and refreshes the list', () async {
    await repository.save(pairing('client-1'));
    await cubit.load();

    await cubit.forget('client-1');

    expect(cubit.state.pairings, isEmpty);
    expect(await repository.list(), isEmpty);
  });
}
