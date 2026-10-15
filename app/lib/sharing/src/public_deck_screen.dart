import 'package:flutter/material.dart';

import '../../deck/deck.dart';
import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'import_sheet.dart';
import 'model.dart';
import 'sharing_service.dart';

/// A public deck's name, owner, description, counts and first cards, with
/// the action that copies it and a menu that reports it or blocks its owner.
/// Pops with true once the owner is blocked.
class PublicDeckScreen extends StatefulWidget {
  const PublicDeckScreen({
    super.key,
    required this.sharing,
    required this.deck,
  });

  final SharingService sharing;
  final PublicDeckSummary deck;

  @override
  State<PublicDeckScreen> createState() => _PublicDeckScreenState();
}

enum _Action { report, block }

class _PublicDeckScreenState extends State<PublicDeckScreen> {
  late Future<List<PublicCard>> _cards = widget.sharing.preview(widget.deck.id);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final deck = widget.deck;
    final description = deck.description;
    return Scaffold(
      appBar: AppBar(
        actions: [
          PopupMenuButton<_Action>(
            tooltip: l10n.deckActions,
            onSelected: (action) => switch (action) {
              _Action.report => _report(),
              _Action.block => _block(),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _Action.report,
                child: Text(l10n.reportDeck),
              ),
              PopupMenuItem(value: _Action.block, child: Text(l10n.blockUser)),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Semantics(
            header: true,
            child: Text(
              deck.name,
              style: textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.publicDeckLine(
              deck.ownerName.value,
              deck.cardCount,
              deck.importCount,
            ),
            style: textTheme.bodyMedium?.copyWith(color: colors.muted),
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(description, style: textTheme.bodyLarge),
          ],
          const SizedBox(height: 16),
          FutureBuilder(
            future: _cards,
            builder: (context, snapshot) => switch (snapshot) {
              AsyncSnapshot(hasData: true, :final data?) when data.isEmpty =>
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(l10n.noCards, textAlign: TextAlign.center),
                ),
              AsyncSnapshot(hasData: true, :final data?) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final card in data)
                    CardSplitRow(
                      front: describeContent(l10n, card.front),
                      back: describeContent(l10n, card.back),
                    ),
                  if (deck.cardCount > data.length)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        l10n.previewFirstCards(data.length, deck.cardCount),
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.muted,
                        ),
                      ),
                    ),
                ],
              ),
              AsyncSnapshot(:final error?, :final stackTrace) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  spacing: 12,
                  children: [
                    Text(switch (error) {
                      SharingFailure() => describeSharingFailure(l10n, error),
                      _ => Error.throwWithStackTrace(
                        error,
                        stackTrace ?? StackTrace.current,
                      ),
                    }, textAlign: TextAlign.center),
                    OutlinedButton(
                      onPressed: () => setState(() {
                        // Shown by the builder, which subscribes a frame later.
                        _cards = widget.sharing.preview(widget.deck.id)
                          ..ignore();
                      }),
                      child: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
              _ => Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: l10n.loading,
                  ),
                ),
              ),
            },
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            onPressed: _import,
            child: Text(l10n.importToMyDecks),
          ),
        ),
      ),
    );
  }

  Future<void> _import() async {
    final messenger = ScaffoldMessenger.of(context);
    final message = await showImportSheet(
      context,
      sharing: widget.sharing,
      deck: widget.deck,
    );
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _report() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final reason = await showDialog<ReportReason>(
      context: context,
      builder: (_) => const _ReportDialog(),
    );
    if (reason == null) return;
    final message = await describing(l10n, () async {
      return switch (await widget.sharing.report(widget.deck.id, reason)) {
        ReportOutcome.reported => l10n.reported,
        ReportOutcome.alreadyReported => l10n.alreadyReported,
      };
    });
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _block() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context);
    final name = widget.deck.ownerName.value;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.blockTitle(name)),
        content: Text(l10n.blockBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.block),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    var blocked = false;
    final message = await describing(l10n, () async {
      await widget.sharing.block(widget.deck.owner);
      blocked = true;
      return l10n.blocked(name);
    });
    messenger.showSnackBar(SnackBar(content: Text(message)));
    if (blocked) navigator.pop(true);
  }
}

/// Asks why the deck is reported; pops with the reason, or nothing when
/// cancelled.
class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  ReportReason? _reason;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reason = _reason;
    return AlertDialog(
      title: Text(l10n.reportTitle),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      content: RadioGroup<ReportReason>(
        groupValue: reason,
        onChanged: (value) => setState(() => _reason = value),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in ReportReason.values)
              RadioListTile<ReportReason>(
                value: option,
                title: Text(switch (option) {
                  ReportReason.inappropriate => l10n.reportInappropriate,
                  ReportReason.spam => l10n.reportSpam,
                  ReportReason.copyright => l10n.reportCopyright,
                  ReportReason.other => l10n.reportOther,
                }),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: reason == null
              ? null
              : () => Navigator.of(context).pop(reason),
          child: Text(l10n.reportDeck),
        ),
      ],
    );
  }
}
