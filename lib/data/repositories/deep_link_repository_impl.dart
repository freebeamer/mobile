import '../../domain/repositories/deep_link_repository.dart';
import '../datasources/deep_link_data_source.dart';

class DeepLinkRepositoryImpl implements IDeepLinkRepository {
  final IDeepLinkDataSource _dataSource;
  DeepLinkRepositoryImpl(this._dataSource);

  @override
  Future<Uri?> getInitialLink() => _dataSource.getInitialLink();

  @override
  Stream<Uri> get linkStream => _dataSource.linkStream;
}
