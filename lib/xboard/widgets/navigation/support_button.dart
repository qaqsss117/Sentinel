import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SupportButton extends StatelessWidget {
  const SupportButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: AppLocalizations.of(context).onlineSupport,
    icon: const Icon(Icons.support_agent_outlined),
    onPressed: () => context.push('/support'),
  );
}
