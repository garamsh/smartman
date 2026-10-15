/// The deck domain: decks, the cards inside them, and the duplicate rule.
library;

export 'src/card_import.dart'
    show
        CardsImported,
        DuplicateChoice,
        FromPhoto,
        FromPublicDeck,
        ImportedCard,
        ImportSource,
        ImportIntoDeck,
        ImportIntoNewDeck,
        ImportTarget,
        mergeBack;
export 'src/card_key.dart' show CardKey;
export 'src/card_list_screen.dart' show CardSplitRow, describeContent;
export 'src/content.dart'
    show Content, TextContent, UnsupportedContent, decodeContent, plainText;
export 'src/deck_list_screen.dart' show DeckListScreen;
export 'src/deck_repository.dart'
    show CardSaved, DeckRepository, DuplicateFront, SaveCardResult;
export 'src/failure.dart'
    show DeckDeleted, DeckFailure, StorageFailure, UnreadableCard;
export 'src/failure_message.dart' show describeFailure;
export 'src/name_dialog.dart' show showNameDialog;
export 'src/model.dart'
    show
        Card,
        CardId,
        CardSource,
        Deck,
        DeckId,
        DeckSelection,
        DeckVisibility,
        PrivateDeck,
        PublicDeck;
export 'src/providers.dart'
    show
        accountScreenProvider,
        DeckSharing,
        deckRepositoryProvider,
        deckSharingProvider,
        photoImportProvider,
        studyScreenProvider,
        TodayBuilder,
        TodayCount,
        TodayCounted,
        TodayPending,
        TodayUnavailable,
        todayProvider;
