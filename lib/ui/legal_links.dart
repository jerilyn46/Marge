import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Public legal / support links. Values already published in this repo
/// (gh-pages privacy policy and Legal's Terms draft) — nothing invented.
class LegalLinks {
  LegalLinks._();

  static const privacyPolicyUrl =
      'https://jerilyn46.github.io/Marge/privacy-policy/';

  /// Contact listed on the published privacy policy (gh-pages
  /// privacy-policy.md) and in the Terms of Use draft.
  static const supportEmail = 'jerilyn46@gmail.com';

  static Uri get privacyPolicyUri => Uri.parse(privacyPolicyUrl);

  static Uri get supportMailUri => Uri(
    scheme: 'mailto',
    path: supportEmail,
    queryParameters: {'subject': 'Marge support'},
  );

  /// Open [uri] outside the app. If no app can handle it, copy [fallback]
  /// to the clipboard and say so — never a dead tap.
  static Future<void> open(
    BuildContext context,
    Uri uri, {
    required String fallback,
  }) async {
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (ok || !context.mounted) return;
    await Clipboard.setData(ClipboardData(text: fallback));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied $fallback')),
    );
  }
}
