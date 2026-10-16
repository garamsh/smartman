import '../../l10n/app_localizations.dart';
import 'failure.dart';

/// The message a user reads for [failure].
String describeStudyFailure(AppLocalizations l10n, StudyFailure failure) =>
    switch (failure) {
      StudyStorageFailure() => l10n.storageFailure,
      AnswerNotSaved() => l10n.answerNotSaved,
      SchedulingFailure() => l10n.schedulingFailure,
    };
