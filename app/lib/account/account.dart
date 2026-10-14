/// The account domain: signing in with Google through Supabase Auth, and the
/// session that sign-in starts.
library;

export 'src/account_screen.dart' show AccountScreen;
export 'src/account_service.dart' show AccountService, connectAccount;
export 'src/account_state.dart'
    show AccountState, AccountUnavailable, SignedIn, SignedOut;
export 'src/config.dart' show accountDefines;
export 'src/failure.dart'
    show AccountFailure, AccountMisconfigured, AccountOffline, AccountRejected;
export 'src/providers.dart' show accountServiceProvider;
