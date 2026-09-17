import '../../data/models/mhd_value.dart';

/// Connects to a vehicle's MHD/ENET WiFi adapter and reads live
/// monitor samples from it. One repository instance represents one
/// session's worth of connection state (connect, read repeatedly,
/// disconnect) — this app only ever drives one vehicle connection at
/// a time.
abstract class IVehicleRepository {
  /// Dials address:port, performs DoIP routing activation, and
  /// returns the discovered target (DME) address.
  Future<int> connect({
    required String address,
    required int port,
    int sourceAddress = 0x0E00,
    Duration dialTimeout = const Duration(seconds: 2),
    Duration activateTimeout = const Duration(seconds: 2),
  });

  /// Sends MG1.adx's monitor request and returns the decoded values.
  /// Must be called after connect() succeeds.
  Future<List<MhdValue>> readLive({Duration timeout = const Duration(seconds: 1)});

  Future<void> disconnect();
}
