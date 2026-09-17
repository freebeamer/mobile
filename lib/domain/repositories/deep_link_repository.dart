abstract class IDeepLinkRepository {
  Future<Uri?> getInitialLink();
  Stream<Uri> get linkStream;
}
