import 'package:connectivity_plus/connectivity_plus.dart';

/// Whether the device has a network connection, kept current.
abstract interface class Reachability {
  /// Emits the current state first, then each change.
  Stream<bool> watchOnline();
}

/// The device's network interfaces as `connectivity_plus` reports them: online
/// while any of them is up. An interface that is up can still fail to reach
/// the server; that failure is the request's to report.
final class DeviceReachability implements Reachability {
  DeviceReachability([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Stream<bool> watchOnline() async* {
    yield _online(await _connectivity.checkConnectivity());
    yield* _connectivity.onConnectivityChanged.map(_online);
  }

  static bool _online(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
}
