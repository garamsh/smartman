import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/l10n/app_localizations.dart';
import '../../shared/theme.dart';
import '../../shared/ui/mascot.dart';
import 'config.dart';

/// Where the terms of service and the privacy policy are published; null
/// until the owner supplies one, when its link opens [ComingSoonScreen].
final class LegalLinks {
  const LegalLinks({this.terms, this.privacy});

  /// Reads [AccountConfigKey.termsUrl] and [AccountConfigKey.privacyUrl] from
  /// [values]: an empty or absent key is no link, and a value that is not an
  /// https URL throws [InvalidAccountConfig].
  factory LegalLinks.parse(Map<String, String> values) {
    final problems = <String>[];
    Uri? read(String key) {
      final value = values[key]?.trim() ?? '';
      if (value.isEmpty) return null;
      final uri = Uri.tryParse(value);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        problems.add('$key is malformed');
        return null;
      }
      return uri;
    }

    final terms = read(AccountConfigKey.termsUrl);
    final privacy = read(AccountConfigKey.privacyUrl);
    if (problems.isNotEmpty) throw InvalidAccountConfig(problems);
    return LegalLinks(terms: terms, privacy: privacy);
  }

  final Uri? terms;
  final Uri? privacy;
}

/// The legal links the build was given. The composition site overrides it
/// with the parsed configuration.
final legalLinksProvider = Provider<LegalLinks>(
  (ref) => throw UnimplementedError(
    'legalLinksProvider is overridden at the composition site',
  ),
);

/// Opens a URL outside the app, resolving to whether it opened.
typedef LinkOpener = Future<bool> Function(Uri uri);

/// How a link leaves the app: the platform's browser, unless a test
/// substitutes it.
final linkOpenerProvider = Provider<LinkOpener>(
  (ref) => (uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    }
  },
);

/// Opens [uri] outside the app, or, while there is none, the page titled
/// [title] that says it is coming. A link that does not open is said in a
/// snack bar.
Future<void> openLegalLink(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required Uri? uri,
}) async {
  if (uri == null) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ComingSoonScreen(title: title)),
    );
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  final opened = await ref.read(linkOpenerProvider)(uri);
  if (!opened) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.linkNotOpened)));
  }
}

/// A page whose document is not published yet: its [title], and a line that
/// says it is coming.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: AppSpace.s16,
            children: [
              Mascot(size: AppSize.mascotMedium, fill: colors.brandTint),
              Text(
                l10n.comingSoonBody,
                textAlign: TextAlign.center,
                style: AppType.body.copyWith(color: colors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The terms of service and the privacy policy as two quiet links, each
/// opening its document or, until there is one, the page that says it is
/// coming.
class LegalLinksRow extends ConsumerWidget {
  const LegalLinksRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final links = ref.watch(legalLinksProvider);
    final colors = AppColors.of(context);
    Widget link(String title, Uri? uri) => TextButton(
      style: TextButton.styleFrom(
        foregroundColor: colors.ink2,
        textStyle: AppType.caption.copyWith(
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
        ),
      ),
      onPressed: () => openLegalLink(context, ref, title: title, uri: uri),
      child: Text(title),
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpace.s8,
      children: [
        link(l10n.termsOfService, links.terms),
        link(l10n.privacyPolicy, links.privacy),
      ],
    );
  }
}
