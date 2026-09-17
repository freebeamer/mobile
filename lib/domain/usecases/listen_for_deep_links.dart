import '../repositories/deep_link_repository.dart';

class ListenForDeepLinks {
  final IDeepLinkRepository _repository;
  ListenForDeepLinks(this._repository);

  Future<Uri?> initialLink() => _repository.getInitialLink();
  Stream<Uri> stream() => _repository.linkStream;
}
