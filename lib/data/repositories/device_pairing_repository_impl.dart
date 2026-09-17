import 'dart:convert';

import '../../domain/repositories/device_pairing_repository.dart';
import '../datasources/secure_storage_data_source.dart';
import '../models/device_pairing.dart';

/// Stores every DevicePairing as one JSON array under a single secure-
/// storage key — the list is small (one entry per tuning session a
/// phone has ever paired with) and always read/written as a whole, so
/// there's no need for the one-key-per-pairing scheme a larger dataset
/// might warrant.
class DevicePairingRepositoryImpl implements IDevicePairingRepository {
  static const _key = 'device_pairings';

  final ISecureStorageDataSource _storage;
  DevicePairingRepositoryImpl(this._storage);

  @override
  Future<void> save(DevicePairing pairing) async {
    final pairings = await list();
    final next = [
      ...pairings.where((existing) => existing.clientId != pairing.clientId),
      pairing,
    ];
    await _write(next);
  }

  @override
  Future<List<DevicePairing>> list() async {
    final raw = await _storage.read(_key);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((entry) => DevicePairing.fromJson(entry as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> remove(String clientId) async {
    final pairings = await list();
    await _write(
        pairings.where((existing) => existing.clientId != clientId).toList());
  }

  Future<void> _write(List<DevicePairing> pairings) async {
    if (pairings.isEmpty) {
      await _storage.delete(_key);
      return;
    }
    await _storage.write(
        _key, jsonEncode(pairings.map((p) => p.toJson()).toList()));
  }
}
