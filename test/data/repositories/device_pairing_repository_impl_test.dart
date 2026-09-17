import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freebeamer_mobile/data/models/device_pairing.dart';
import 'package:freebeamer_mobile/data/repositories/device_pairing_repository_impl.dart';

import '../../support/fake_secure_storage.dart';

DevicePairing pairing(String clientId, {String displayName = 'Bay'}) =>
    DevicePairing(
      clientId: clientId,
      displayName: displayName,
      relayUrl: 'https://relay.example',
      privateKey: Uint8List.fromList(List.filled(32, 1)),
      publicKey: Uint8List.fromList(List.filled(32, 2)),
      pairedAt: DateTime(2026, 9, 17, 12, 0, 0),
    );

void main() {
  test('save then list round trips exactly, including key bytes', () async {
    final repository = DevicePairingRepositoryImpl(FakeSecureStorage());
    final p = pairing('client-1');

    await repository.save(p);

    final loaded = await repository.list();
    expect(loaded, [p]);
  });

  test('list is empty before anything is saved', () async {
    final repository = DevicePairingRepositoryImpl(FakeSecureStorage());
    expect(await repository.list(), isEmpty);
  });

  test('saving twice for the same clientId replaces, not duplicates', () async {
    final repository = DevicePairingRepositoryImpl(FakeSecureStorage());
    await repository.save(pairing('client-1', displayName: 'Old name'));
    await repository.save(pairing('client-1', displayName: 'New name'));

    final loaded = await repository.list();
    expect(loaded, hasLength(1));
    expect(loaded.single.displayName, 'New name');
  });

  test('multiple distinct pairings coexist', () async {
    final repository = DevicePairingRepositoryImpl(FakeSecureStorage());
    await repository.save(pairing('client-1'));
    await repository.save(pairing('client-2'));

    final loaded = await repository.list();
    expect(loaded.map((p) => p.clientId).toSet(), {'client-1', 'client-2'});
  });

  test('remove deletes only the named pairing', () async {
    final repository = DevicePairingRepositoryImpl(FakeSecureStorage());
    await repository.save(pairing('client-1'));
    await repository.save(pairing('client-2'));

    await repository.remove('client-1');

    final loaded = await repository.list();
    expect(loaded.map((p) => p.clientId), ['client-2']);
  });

  test('removing the last pairing clears storage rather than leaving []',
      () async {
    final storage = FakeSecureStorage();
    final repository = DevicePairingRepositoryImpl(storage);
    await repository.save(pairing('client-1'));

    await repository.remove('client-1');

    expect(await repository.list(), isEmpty);
    expect(storage.values, isEmpty);
  });
}
