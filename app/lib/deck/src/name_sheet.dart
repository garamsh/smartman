import 'package:flutter/material.dart';

import '../../shared/l10n/app_localizations.dart';
import '../../shared/ui/app_button.dart';
import '../../shared/ui/app_sheet.dart';
import '../../shared/ui/app_text_field.dart';

/// Asks for a deck name in a sheet titled [title], whose primary button reads
/// [action]; returns the name trimmed, or null when the sheet is dismissed.
Future<String?> showNameSheet(
  BuildContext context, {
  required String title,
  required String action,
  String initial = '',
}) => showAppSheet<String>(
  context,
  builder: (_) => _NameSheet(title: title, action: action, initial: initial),
);

class _NameSheet extends StatefulWidget {
  const _NameSheet({
    required this.title,
    required this.action,
    required this.initial,
  });

  final String title;
  final String action;
  final String initial;

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final _controller = TextEditingController(text: widget.initial);
  bool _showRequired = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _showRequired = true);
    } else {
      Navigator.of(context).pop(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppSheet(
      title: widget.title,
      content: AppTextField(
        label: l10n.deckName,
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        errorText: _showRequired ? l10n.deckNameRequired : null,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        AppButton(
          label: widget.action,
          size: AppButtonSize.cta,
          onPressed: _submit,
        ),
      ],
    );
  }
}
