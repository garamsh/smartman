import 'package:knowno/account/account.dart';

/// Stands in for the sync domain's [AccountData]. [push] reports
/// [pushSucceeds]; [clear] records that it ran, or throws [clearFailure].
class FakeAccountData implements AccountData {
  bool pushSucceeds = true;
  AccountDataNotCleared? clearFailure;
  var pushes = 0;
  var clears = 0;

  @override
  Future<bool> push() async {
    pushes++;
    return pushSucceeds;
  }

  @override
  Future<void> clear() async {
    if (clearFailure case final failure?) throw failure;
    clears++;
  }
}
