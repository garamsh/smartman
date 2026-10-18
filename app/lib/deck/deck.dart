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
export 'src/card_editor_screen.dart' show CardEditorScreen;
export 'src/card_key.dart' show CardKey;
export 'src/card_list.dart'
    show CardAnswerRow, CardSplitRow, describeContent, spokenContent;
export 'src/content.dart'
    show
        ClozeContent,
        Content,
        TableBlank,
        TableContent,
        TextContent,
        UnsupportedContent,
        clozeBlank,
        decodeContent,
        isWholeCard,
        plainText;
export 'src/content_view.dart' show ContentView;
export 'src/deck_repository.dart'
    show CardSaved, DeckRepository, DuplicateFront, SaveCardResult;
export 'src/deck_row.dart' show DeckRow, DeckTile;
export 'src/failure.dart'
    show DeckDeleted, DeckFailure, StorageFailure, UnreadableCard;
export 'src/failure_message.dart'
    show describeFailure, describeProviderError, reportingFailure;
export 'src/name_sheet.dart' show showNameSheet;
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
        cardCountsProvider,
        cardsProvider,
        deckProvider,
        deckRepositoryProvider,
        decksProvider;
export 'src/split_card.dart' show SideBuilder, SplitCard;
export 'src/whole_card_view.dart' show WholeCardView;
