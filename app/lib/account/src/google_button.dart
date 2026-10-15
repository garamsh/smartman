import 'package:flutter/material.dart';

import '../../shared/theme.dart';

/// Google's "Sign in with Google" button, full width: the "G" mark and
/// [label] on the light button in the light theme and the dark one in the
/// dark theme, as Google's branding guidelines draw them.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final style = GoogleButtonStyle.of(context);
    final spacing = GoogleButtonStyle.spacing(Theme.of(context).platform);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.button),
      side: BorderSide(color: style.stroke),
    );
    return Semantics(
      button: true,
      child: SizedBox(
        height: AppSize.cta,
        child: Material(
          color: style.fill,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onPressed,
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: spacing.start,
                end: spacing.end,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: spacing.gap,
                children: [
                  Image.asset(
                    style.mark,
                    width: GoogleButtonStyle.markSize,
                    height: GoogleButtonStyle.markSize,
                    excludeFromSemantics: true,
                  ),
                  Flexible(
                    child: Text(
                      label,
                      style: GoogleButtonStyle.labelStyle.copyWith(
                        color: style.label,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
