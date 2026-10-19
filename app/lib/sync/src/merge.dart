import '../../database/database.dart';

/// Which copy of a row a merge keeps: the device's, or the server's.
enum Kept { local, remote }

/// Whether the local edit is the later one. On a tie an unsynced local edit
/// is, since the server has not seen it; otherwise the server's is.
bool _localIsLater({
  required DateTime localUpdatedAt,
  required bool localDirty,
  required DateTime remoteUpdatedAt,
}) =>
    localUpdatedAt.isAfter(remoteUpdatedAt) ||
    (localDirty && localUpdatedAt.isAtSameMomentAs(remoteUpdatedAt));

/// Decks and cards: a tombstone wins over a live row, whenever either was
/// written; between two live rows, or two tombstones, the later edit wins.
Kept mergeEdit({
  required DateTime localUpdatedAt,
  required DateTime? localDeletedAt,
  required bool localDirty,
  required DateTime remoteUpdatedAt,
  required DateTime? remoteDeletedAt,
}) {
  final localDeleted = localDeletedAt != null;
  final remoteDeleted = remoteDeletedAt != null;
  if (localDeleted != remoteDeleted) {
    return localDeleted ? Kept.local : Kept.remote;
  }
  return _localIsLater(
        localUpdatedAt: localUpdatedAt,
        localDirty: localDirty,
        remoteUpdatedAt: remoteUpdatedAt,
      )
      ? Kept.local
      : Kept.remote;
}

Kept mergeDeck(DeckRow? local, DeckRow remote) => local == null
    ? Kept.remote
    : mergeEdit(
        localUpdatedAt: local.updatedAt,
        localDeletedAt: local.deletedAt,
        localDirty: local.dirty,
        remoteUpdatedAt: remote.updatedAt,
        remoteDeletedAt: remote.deletedAt,
      );

Kept mergeCard(CardRow? local, CardRow remote) => local == null
    ? Kept.remote
    : mergeEdit(
        localUpdatedAt: local.updatedAt,
        localDeletedAt: local.deletedAt,
        localDirty: local.dirty,
        remoteUpdatedAt: remote.updatedAt,
        remoteDeletedAt: remote.deletedAt,
      );

/// Reviews are a union by id. A review on both sides keeps the rating of the
/// later edit.
Kept mergeReview(ReviewRow? local, ReviewRow remote) =>
    local != null &&
        _localIsLater(
          localUpdatedAt: local.updatedAt,
          localDirty: local.dirty,
          remoteUpdatedAt: remote.updatedAt,
        )
    ? Kept.local
    : Kept.remote;

/// Card states are never merged. An unsynced local state is kept, to be
/// pushed; otherwise the server's is taken. Either is recomputed after a pull
/// brings a review of its card.
Kept mergeCardState(CardStateRow? local, CardStateRow remote) =>
    local != null && local.dirty ? Kept.local : Kept.remote;

/// Study settings: the later edit wins, with the same tie rule.
Kept mergeStudySettings(StudySettingsRow? local, StudySettingsRow remote) =>
    local != null &&
        _localIsLater(
          localUpdatedAt: local.updatedAt,
          localDirty: local.dirty,
          remoteUpdatedAt: remote.updatedAt,
        )
    ? Kept.local
    : Kept.remote;
