import 'package:flutter/material.dart';

import 'package:fladder/jt/jt_brand.dart';
import 'package:fladder/screens/shared/media/external_urls.dart';

/// Bronvermelding op het Over-scherm: JT-Streaming is gebaseerd op Fladder van DonutWare (GPL-3.0).
class JtAboutAttribution extends StatelessWidget {
  const JtAboutAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: Column(
        spacing: 8,
        children: [
          Text(
            '${JtBrand.appName} is gebaseerd op ${JtBrand.upstreamName} van ${JtBrand.upstreamAuthor} '
            '(${JtBrand.upstreamUrl.replaceFirst('https://', '')}, basis ${JtBrand.upstreamBase}), '
            'uitgebracht onder de GNU General Public License v3.0.',
            style: textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          Text(
            JtBrand.forkUrl.isEmpty
                ? 'De broncode van deze fork wordt beschikbaar gesteld op GitHub.'
                : 'Broncode van deze fork: ${JtBrand.forkUrl.replaceFirst('https://', '')}',
            style: textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: () => launchUrl(context, JtBrand.upstreamUrl),
                child: const Text(JtBrand.upstreamName),
              ),
              if (JtBrand.forkUrl.isNotEmpty)
                TextButton(
                  onPressed: () => launchUrl(context, JtBrand.forkUrl),
                  child: const Text(JtBrand.appName),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
