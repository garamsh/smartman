/// The account domain: signing in with Google through Supabase Auth, and the
/// session that sign-in starts.
library;

export 'src/account_avatar.dart' show AccountAvatar;
export 'src/account_data.dart'
    show
        AccountData,
        AccountDataNotCleared,
        accountDataProvider,
        syncStatusProvider;
export 'src/account_gate.dart' show AccountGate, signedInHomeProvider;
export 'src/account_screen.dart' show AccountScreen;
export 'src/account_service.dart'
    show AccountConnection, AccountService, connectAccount;
export 'src/account_state.dart'
    show AccountState, AccountUnavailable, SignedIn, SignedOut, UserId;
export 'src/config.dart' show accountDefines;
export 'src/failure.dart'
    show AccountFailure, AccountMisconfigured, AccountOffline, AccountRejected;
export 'src/providers.dart' show accountServiceProvider, appVersionProvider;
