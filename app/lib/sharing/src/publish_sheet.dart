import 'package:flutter/material.dart';

import '../../deck/deck.dart';
import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import 'failure.dart';
import 'failure_message.dart';
import 'model.dart';
import 'sharing_service.dart';

/// Publishes [deck]: asks for the user's display name the first time, an
/// optional description, and the agreement not to publish inappropriate or
/// copyrighted content, which "공개" requires. Says in a snack bar once
/// published.
Future<void> showPublishSheet(
  BuildContext context, {
  required SharingService sharing,
  required Deck deck,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PublishSheet(sharing: sharing, deck: deck),
  );
  if (message != null) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PublishSheet extends StatefulWidget {
  const _PublishSheet({required this.sharing, required this.deck});

  final SharingService sharing;
  final Deck deck;

  @override
  State<_PublishSheet> createState() => _PublishSheetState();
}

class _PublishSheetState extends State<_PublishSheet> {
  late Future<DisplayName?> _name = widget.sharing.displayName();
  final _nameField = TextEditingController();
  late final _descriptionField = TextEditingController(
    text: widget.deck.description,
  );
  bool _agreed = false;
  bool _saving = false;
  bool _showErrors = false;
  String? _error;

  @override
  void dispose() {
    _nameField.dispose();
    _descriptionField.dispose();
    super.dispose();
  }

  String get _description => _descriptionField.text.trim();

  bool get _descriptionTooLong =>
      _description.runes.length > maxDescriptionLength;

  Future<void> _publish(AppLocalizations l10n, {required bool askName}) async {
    final name = askName ? DisplayName.tryParse(_nameField.text) : null;
    if ((askName && name == null) || _descriptionTooLong) {
      setState(() => _showErrors = true);
      return;
    }
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    String? done;
    final message = await describing(l10n, () async {
      await widget.sharing.makePublic(
        widget.deck.id,
        name: name,
        description: _description.isEmpty ? null : _description,
      );
      return done = l10n.published;
    });
    if (!mounted) return;
    if (done != null) {
      navigator.pop(done);
    } else {
      setState(() {
        _saving = false;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.publishTitle(widget.deck.name),
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FutureBuilder(
                future: _name,
                builder: (context, snapshot) => switch (snapshot) {
                  AsyncSnapshot(
                    connectionState: ConnectionState.done,
                    :final error?,
                    :final stackTrace,
                  ) =>
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 12,
                      children: [
                        Text(switch (error) {
                          SharingFailure() => describeSharingFailure(
                            l10n,
                            error,
                          ),
                          _ => Error.throwWithStackTrace(
                            error,
                            stackTrace ?? StackTrace.current,
                          ),
                        }),
                        OutlinedButton(
                          onPressed: () => setState(() {
                            _name = widget.sharing.displayName();
                          }),
                          child: Text(l10n.retry),
                        ),
                      ],
                    ),
                  AsyncSnapshot(
                    connectionState: ConnectionState.done,
                    :final data,
                  ) =>
                    _form(l10n, askName: data == null),
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
        ),
      ),
    );
  }

  Widget _form(AppLocalizations l10n, {required bool askName}) {
    final colors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final error = _error;
    final nameInvalid =
        _showErrors && DisplayName.tryParse(_nameField.text) == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        if (askName)
          TextField(
            controller: _nameField,
            enabled: !_saving,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.displayName,
              helperText: l10n.displayNameHelp,
              helperMaxLines: 2,
              errorText: nameInvalid ? l10n.displayNameLength : null,
            ),
          ),
        TextField(
          controller: _descriptionField,
          enabled: !_saving,
          minLines: 2,
          maxLines: 5,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: l10n.deckDescription,
            counterText: '${_description.runes.length}/$maxDescriptionLength',
            errorText: _descriptionTooLong
                ? l10n.deckDescriptionTooLong(maxDescriptionLength)
                : null,
          ),
        ),
        CheckboxListTile(
          value: _agreed,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: _saving
              ? null
              : (agreed) => setState(() => _agreed = agreed ?? false),
          title: Text(l10n.publishAgreement),
        ),
        if (error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              style: textTheme.bodyMedium?.copyWith(color: colors.dontKnowText),
            ),
          ),
        FilledButton(
          onPressed: _agreed && !_saving
              ? () => _publish(l10n, askName: askName)
              : null,
          child: Text(l10n.publishConfirm),
        ),
      ],
    );
  }
}
