import 'package:get_it/get_it.dart';

import '../../data/datasources/deep_link_data_source.dart';
import '../../data/datasources/device_auth_remote_data_source.dart';
import '../../data/datasources/doip_data_source.dart';
import '../../data/datasources/mhd_data_source.dart';
import '../../data/datasources/secure_storage_data_source.dart';
import '../../data/datasources/telemetry_local_data_source.dart';
import '../../data/datasources/telemetry_remote_data_source.dart';
import '../../data/repositories/deep_link_repository_impl.dart';
import '../../data/repositories/device_pairing_repository_impl.dart';
import '../../data/repositories/telemetry_repository_impl.dart';
import '../../data/repositories/vehicle_repository_impl.dart';
import '../../domain/repositories/deep_link_repository.dart';
import '../../domain/repositories/device_pairing_repository.dart';
import '../../domain/repositories/telemetry_repository.dart';
import '../../domain/repositories/vehicle_repository.dart';
import '../../domain/usecases/authenticate_device.dart';
import '../../domain/usecases/connect_to_vehicle.dart';
import '../../domain/usecases/disconnect_from_vehicle.dart';
import '../../domain/usecases/forget_device.dart';
import '../../domain/usecases/list_device_pairings.dart';
import '../../domain/usecases/listen_for_deep_links.dart';
import '../../domain/usecases/logout_device.dart';
import '../../domain/usecases/pair_device.dart';
import '../../domain/usecases/parse_provisioning_link.dart';
import '../../domain/usecases/read_live_sample.dart';
import '../../domain/usecases/negotiate_telemetry.dart';
import '../../presentation/cubits/connection_cubit.dart';
import '../../presentation/cubits/tuners_cubit.dart';
import '../logging/connection_log.dart';
import '../telemetry/telemetry_upload_service.dart';

final GetIt sl = GetIt.instance;

/// Wires every interface this app defines to its concrete
/// implementation, and every use case/Cubit to its dependencies. This
/// is the only place an `Impl` class is referenced outside its own
/// file and its own tests — everywhere else resolves dependencies as
/// `sl<ISomething>()`.
void setupServiceLocator() {
  // Diagnostic connection log, shared app-wide.
  sl.registerLazySingleton<IConnectionLog>(() => ConnectionLogImpl());

  // Data sources.
  sl.registerLazySingleton<ISecureStorageDataSource>(
      () => SecureStorageDataSourceImpl());
  sl.registerLazySingleton<IDoipDataSource>(() => DoipDataSourceImpl(log: sl()));
  sl.registerLazySingleton<IMhdDataSource>(() => MhdDataSourceImpl(sl()));
  sl.registerLazySingleton<ITelemetryRemoteDataSource>(
      () => TelemetryRemoteDataSourceImpl());
  sl.registerLazySingleton<ITelemetryLocalDataSource>(
      () => TelemetryLocalDataSourceImpl());
  sl.registerLazySingleton<IDeepLinkDataSource>(() => DeepLinkDataSourceImpl());
  sl.registerLazySingleton<IDeviceAuthRemoteDataSource>(
      () => DeviceAuthRemoteDataSourceImpl());

  // Repositories. IVehicleRepository/ITelemetryRepository are
  // singletons since this app only ever drives one vehicle connection
  // and relays through one uploader configuration at a time.
  sl.registerLazySingleton<IVehicleRepository>(
      () => VehicleRepositoryImpl(sl(), sl()));
  sl.registerLazySingleton<ITelemetryRepository>(
      () => TelemetryRepositoryImpl(sl(), sl()));
  sl.registerLazySingleton<IDevicePairingRepository>(
      () => DevicePairingRepositoryImpl(sl()));
  sl.registerLazySingleton<IDeepLinkRepository>(
      () => DeepLinkRepositoryImpl(sl()));

  // TelemetryUploadService: same app-lifetime-singleton reasoning as
  // ITelemetryRepository above — it drains one destination's spool at a
  // time. Talks to the remote/local data sources directly (not through
  // ITelemetryRepository, whose send/flushBuffer stay as unused-but-tested
  // low-level primitives — see that class's doc comment).
  sl.registerLazySingleton<ITelemetryUploadService>(
      () => TelemetryUploadServiceImpl(sl(), sl()));

  // Use cases.
  sl.registerFactory(() => ConnectToVehicle(sl()));
  sl.registerFactory(() => DisconnectFromVehicle(sl()));
  sl.registerFactory(() => ReadLiveSample(sl()));
  sl.registerFactory(() => NegotiateTelemetry(sl()));
  sl.registerFactory(() => ParseProvisioningLink());
  sl.registerFactory(() => ListenForDeepLinks(sl()));
  sl.registerFactory(() => PairDevice(sl(), sl()));
  sl.registerFactory(() => AuthenticateDevice(sl()));
  sl.registerFactory(() => LogoutDevice(sl()));
  sl.registerFactory(() => ForgetDevice(sl()));
  sl.registerFactory(() => ListDevicePairings(sl()));

  // Cubits: factories, since each screen that owns one creates and
  // disposes its own instance.
  sl.registerFactory(
    () => ConnectionCubit(
      connectToVehicle: sl(),
      disconnectFromVehicle: sl(),
      readLiveSample: sl(),
      telemetryUploadService: sl(),
      negotiateTelemetry: sl(),
      authenticateDevice: sl(),
      log: sl(),
    ),
  );
  sl.registerFactory(
    () => TunersCubit(
      listDevicePairings: sl(),
      pairDevice: sl(),
      forgetDevice: sl(),
      parseProvisioningLink: sl(),
    ),
  );
}
