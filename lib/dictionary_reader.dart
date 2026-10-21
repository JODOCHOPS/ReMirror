import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'offline_resources.dart';
import 'back_translation.dart';

/// English text with tap-to-look-up words and a selection menu for phrases.
class DictionaryReader extends StatefulWidget {
  const DictionaryReader(
      {super.key, required this.text, this.style, this.differences});

  final String text;
  final TextStyle? style;
  final List<WordDiff>? differences;

  @override
  State<DictionaryReader> createState() => _DictionaryReaderState();
}

class _DictionaryReaderState extends State<DictionaryReader> {
  final List<TapGestureRecognizer> _recognizers = [];
  String _selection = '';

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  Future<void> _showEntry(String query) async {
    final term = query.trim();
    if (term.isEmpty) return;
    final result = await showDialog<void>(
      context: context,
      builder: (context) => _LookupDialog(term: term),
    );
    if (!mounted) return;
    return result;
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    final spans = <InlineSpan>[];
    final pattern = RegExp(r"[A-Za-z]+(?:['’-][A-Za-z]+)*");
    final tokens = RegExp(r'\S+').allMatches(widget.text).toList();
    var tokenIndex = 0;
    var position = 0;
    for (final match in pattern.allMatches(widget.text)) {
      if (match.start > position) {
        spans.add(TextSpan(text: widget.text.substring(position, match.start)));
      }
      final word = match.group(0)!;
      while (tokenIndex + 1 < tokens.length &&
          tokens[tokenIndex].end <= match.start) {
        tokenIndex++;
      }
      final highlighted = widget.differences != null &&
          tokenIndex < widget.differences!.length &&
          !widget.differences![tokenIndex].matches;
      final recognizer = TapGestureRecognizer()..onTap = () => _showEntry(word);
      _recognizers.add(recognizer);
      spans.add(TextSpan(
        text: word,
        recognizer: recognizer,
        style: const TextStyle(
                decoration: TextDecoration.underline,
                decorationStyle: TextDecorationStyle.dotted)
            .copyWith(
          backgroundColor: highlighted ? const Color(0xFF563834) : null,
        ),
      ));
      position = match.end;
    }
    if (position < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(position)));
    }
    return SelectionArea(
      onSelectionChanged: (content) => _selection = content?.plainText ?? '',
      contextMenuBuilder: (context, region) =>
          AdaptiveTextSelectionToolbar.buttonItems(
        anchors: region.contextMenuAnchors,
        buttonItems: [
          ...region.contextMenuButtonItems,
          if (_selection.trim().isNotEmpty)
            ContextMenuButtonItem(
              label: '查词 / 短语',
              onPressed: () {
                final selected = _selection;
                region.hideToolbar();
                _showEntry(selected);
              },
            ),
        ],
      ),
      child: Text.rich(TextSpan(children: spans),
          style: widget.style ?? const TextStyle(fontSize: 15, height: 1.65)),
    );
  }
}

class _LookupDialog extends StatefulWidget {
  const _LookupDialog({required this.term});
  final String term;

  @override
  State<_LookupDialog> createState() => _LookupDialogState();
}

class _LookupDialogState extends State<_LookupDialog> {
  late final Future<(DictionaryEntry?, String?)> _lookup = _load();

  Future<(DictionaryEntry?, String?)> _load() async {
    final entry = await bundledDictionary.lookup(widget.term);
    if (entry != null) return (entry, null);
    if (widget.term.trim().contains(' ')) {
      return (null, await bundledTranslator.translate(widget.term));
    }
    return (null, null);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.term),
        content: SizedBox(
          width: 440,
          child: FutureBuilder<(DictionaryEntry?, String?)>(
            future: _lookup,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text('词典或离线模型暂时无法读取。');
              }
              if (!snapshot.hasData) {
                return const Row(children: [
                  SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  Text('正在查找…'),
                ]);
              }
              final (entry, machineTranslation) = snapshot.data!;
              if (entry == null) {
                if (machineTranslation == null) return const Text('内置词典未收录该词。');
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('机器译文',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(machineTranslation),
                  ],
                );
              }
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (entry.word != entry.queried.toLowerCase()) ...[
                      Text('原形：${entry.word}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                    ],
                    if (entry.phonetic.isNotEmpty) ...[
                      Text('[${entry.phonetic}]',
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.primary)),
                      const SizedBox(height: 12),
                    ],
                    Text(entry.translation,
                        style: const TextStyle(height: 1.6)),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      );
}
