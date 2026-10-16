/// The photo_import domain: one photo of a page turned into cards the user
/// reviews and saves into a deck.
library;

export 'src/detail_level.dart' show DetailLevel, detailLevelStorageKeys;
export 'src/extraction_client.dart'
    show CandidateCard, ExtractionClient, extractCardsUrl, HttpExtractionClient;
export 'src/failure.dart'
    show
        CameraDenied,
        CameraUnavailable,
        DailyLimitReached,
        ExtractionOffline,
        ModelFailed,
        NoCardsFound,
        PhotoImportFailure,
        PhotoRefused,
        PhotoUnreadable,
        ServiceFailed,
        SignInRequired;
export 'src/photo.dart' show JpegPhoto;
export 'src/photo_import_screen.dart' show PhotoImportScreen;
export 'src/photo_source.dart'
    show CameraSession, DevicePhotoSource, PhotoSource;
export 'src/providers.dart' show photoImportProvider;
