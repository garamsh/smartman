/// The deck domain: decks, the cards inside them, and the duplicate rule.
library;

export 'src/appearance_sheet.dart' show showDeckAppearanceSheet;
export 'src/add_cards.dart'
    show
        CardsAdded,
        DuplicateChoice,
        FromPhoto,
        FromCopy,
        IncomingCard,
        AddSource,
        AddToDeck,
        AddToNewDeck,
        AddTarget,
        mergeBack;
export 'src/card_editor_screen.dart' show CardEditorScreen;
export 'src/card_kind.dart' show deckStorageKeys, deckStorageProvider;
export 'src/card_key.dart' show CardKey;
export 'src/card_list.dart'
    show CardBackRow, CardSplitRow, describeContent, spokenContent;
export 'src/content.dart'
    show
        CardSense,
        ClozeContent,
        Content,
        OtherLabel,
        PartOfSpeech,
        PartOfSpeechLabel,
        SenseLabel,
        SensesContent,
        TableBlank,
        TableContent,
        TextContent,
        UnsupportedContent,
        clozeBlank,
        decodeContent,
        encodeContent,
        decodeSense,
        isWholeCard,
        plainText;
export 'src/content_view.dart' show ContentView, contentSpan, sensesSpan;
export 'src/deck_repository.dart'
    show CardSaved, DeckRepository, DuplicateFront, SaveCardResult;
export 'src/deck_row.dart' show DeckRow, DeckTile;
export 'src/failure.dart'
    show DeckDeleted, DeckFailure, StorageFailure, UnreadableCard;
export 'src/failure_message.dart'
    show describeFailure, describeProviderError, reportingFailure;
export 'src/name_sheet.dart' show showNameSheet;
export 'src/label_presets_screen.dart' show PartOfSpeechPresetsRow;
export 'src/model.dart'
    show
        Card,
        CardId,
        CardSource,
        Deck,
        DeckColor,
        DeckIcon,
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
