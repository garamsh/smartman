import 'dart:async';

import 'package:smartman/account/account.dart';

/// Stands in for the account service at the auth boundary. [signIn] signs in
/// as [email], or throws [failure] when one is set; [cancelSignIn] makes it
/// return as a cancelled picker does.
class FakeAccountService implements AccountService {
  FakeAccountService([this._state = const SignedOut()]);

  AccountState _state;
  final _changes = StreamController<AccountState>.broadcast();

  UserId userId = const UserId('00000000-0000-4000-8000-00000000000a');
  String email = 'ada@example.com';
  AccountFailure? failure;
  bool cancelSignIn = false;

  @override
  AccountState get state => _state;

  @override
  Stream<AccountState> get stateChanges => _changes.stream;

  void _set(AccountState next) {
    _state = next;
    _changes.add(next);
  }

  @override
  Future<void> signIn() async {
    if (failure case final failure?) throw failure;
    if (cancelSignIn) return;
    _set(SignedIn(userId: userId, email: email));
  }

  @override
  Future<void> signOut() async {
    _set(const SignedOut());
    if (failure case final failure?) throw failure;
  }
}
