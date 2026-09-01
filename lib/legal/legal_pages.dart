import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'legal_consent_store.dart';
import 'legal_documents.dart';

Future<void> ensureLegalConsent() async {
  if (await LegalConsentStore.isAccepted()) {
    return;
  }

  final accepted = Completer<void>();
  runApp(_LegalBootstrapApp(onAccepted: accepted.complete));
  await accepted.future;
}

Future<void> showLegalDocument(
  BuildContext context,
  LegalDocumentType type,
) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => LegalDocumentPage(type: type),
    ),
  );
}

class LegalDocumentPage extends StatefulWidget {
  const LegalDocumentPage({
    required this.type,
    super.key,
  });

  final LegalDocumentType type;

  @override
  State<LegalDocumentPage> createState() => _LegalDocumentPageState();
}

class _LegalDocumentPageState extends State<LegalDocumentPage> {
  bool _english = false;

  @override
  Widget build(BuildContext context) {
    final document = legalDocumentFor(widget.type, english: _english);
    return Scaffold(
      appBar: AppBar(
        title: Text(document.title),
      ),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('中文')),
                        ButtonSegment(value: true, label: Text('English')),
                      ],
                      selected: {_english},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) {
                        setState(() => _english = selection.first);
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    document.effectiveDate,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 16),
                  Text(document.introduction),
                  for (final section in document.sections) ...[
                    const SizedBox(height: 24),
                    Text(
                      section.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(section.body),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LegalLinks extends StatelessWidget {
  const LegalLinks({
    this.checked,
    this.onChecked,
    this.prefix,
    super.key,
  });

  final bool? checked;
  final ValueChanged<bool?>? onChecked;
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final links = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.center,
      children: [
        Text(prefix ?? '我已阅读并同意 / I have read and agree to'),
        TextButton(
          onPressed: () => showLegalDocument(context, LegalDocumentType.terms),
          child: const Text('《用户协议》/ Terms'),
        ),
        const Text('与 / and'),
        TextButton(
          onPressed: () => showLegalDocument(context, LegalDocumentType.privacy),
          child: const Text('《隐私政策》/ Privacy'),
        ),
      ],
    );

    if (onChecked == null) {
      return links;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Checkbox(value: checked ?? false, onChanged: onChecked),
        Expanded(child: links),
      ],
    );
  }
}

class _LegalBootstrapApp extends StatelessWidget {
  const _LegalBootstrapApp({required this.onAccepted});

  final VoidCallback onAccepted;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '哨兵加速器 / SentinelVPN',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF176B5B)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF43A68F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: LegalConsentPage(onAccepted: onAccepted),
    );
  }
}

class LegalConsentPage extends StatefulWidget {
  const LegalConsentPage({required this.onAccepted, super.key});

  final VoidCallback onAccepted;

  @override
  State<LegalConsentPage> createState() => _LegalConsentPageState();
}

class _LegalConsentPageState extends State<LegalConsentPage> {
  bool _checked = false;
  bool _saving = false;

  Future<void> _accept() async {
    setState(() => _saving = true);
    final saved = await LegalConsentStore.accept();
    if (!mounted) return;
    if (!saved) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法保存同意状态，请重试 / Unable to save consent. Please retry.'),
        ),
      );
      return;
    }
    widget.onAccepted();
  }

  void _decline() {
    if (Platform.isAndroid) {
      SystemNavigator.pop();
      return;
    }
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.shield_outlined, size: 56),
                  const SizedBox(height: 20),
                  Text(
                    '用户协议与隐私政策',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Terms of Service & Privacy Policy',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '使用哨兵加速器前，请阅读并同意下列文件。我们会处理账户、设备、订阅、交易、网络连接和诊断信息以提供及保护服务。协议内容存储在客户端内，可离线查看。\n\nBefore using SentinelVPN, please review and accept the documents below. We process account, device, subscription, transaction, network connection, and diagnostic data to provide and secure the service. The documents are built into the client and can be viewed offline.',
                  ),
                  const SizedBox(height: 16),
                  LegalLinks(
                    key: const Key('legal-consent-links'),
                    checked: _checked,
                    onChecked: _saving
                        ? null
                        : (value) => setState(() => _checked = value ?? false),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('legal-consent-accept'),
                    onPressed: _checked && !_saving ? _accept : null,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('同意并继续 / Agree and Continue'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _saving ? null : _decline,
                    child: const Text('不同意并退出 / Decline and Exit'),
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