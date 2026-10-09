import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/marge_theme.dart';

/// In-app Terms of Use. Content is Legal's draft, shipped verbatim as the
/// asset `assets/legal/terms-of-use.md` (copied from
/// marge-growth/terms-of-use-draft.md). Do not edit the wording here.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key, this.bundle});

  /// Test hook; defaults to [rootBundle].
  final AssetBundle? bundle;

  static const assetPath = 'assets/legal/terms-of-use.md';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms of Use')),
      body: FutureBuilder<String>(
        future: (bundle ?? rootBundle).loadString(assetPath),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('Terms could not be loaded.'));
          }
          final text = snap.data;
          if (text == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [for (final line in text.split('\n')) _line(line)],
          );
        },
      ),
    );
  }

  static Widget _line(String raw) {
    final line = raw.trimRight();
    if (line.isEmpty) return const SizedBox(height: 10);
    if (line.startsWith('# ')) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          line.substring(2),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: MargeColors.gold,
          ),
        ),
      );
    }
    if (line.startsWith('>')) {
      return Text(
        line.replaceFirst(RegExp(r'^>\s?'), ''),
        style: TextStyle(
          fontStyle: FontStyle.italic,
          fontSize: 12,
          color: MargeColors.cream.withValues(alpha: 0.7),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(TextSpan(children: boldSpans(line))),
    );
  }

  /// Split `**bold**` markers into spans; the words themselves are unchanged.
  static List<TextSpan> boldSpans(String line) {
    final spans = <TextSpan>[];
    final parts = line.split('**');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      spans.add(
        TextSpan(
          text: parts[i],
          style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w800) : null,
        ),
      );
    }
    return spans;
  }
}
