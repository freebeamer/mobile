import 'package:app_links/app_links.dart';

/// Wraps package:app_links — the app's incoming freebeamer://connect
/// links, whether the app was cold-started by one or it arrived while
/// already running.
abstract class IDeepLinkDataSource {
  /// The link that launched the app, if it was launched by one and
  /// hasn't been consumed by a prior call. Null on an ordinary launch.
  Future<Uri?> getInitialLink();

  /// Links received while the app is already running.
  Stream<Uri> get linkStream;
}

class DeepLinkDataSourceImpl implements IDeepLinkDataSource {
  final AppLinks _appLinks = AppLinks();

  @override
  Future<Uri?> getInitialLink() => _appLinks.getInitialLink();

  @override
  Stream<Uri> get linkStream => _appLinks.uriLinkStream;
}
