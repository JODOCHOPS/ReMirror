import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'ai_review.dart';
import 'back_translation.dart';
import 'practice_workbook.dart';
import 'translation.dart';

const _ink = Color(0xFF1A2832);
const _muted = Color(0xFF647780);
const _accent = Color(0xFF187A82);
const _border = Color(0xFFDCE6E5);

class BackTranslationPage extends StatefulWidget {
  const BackTranslationPage({
    super.key,
    required this.paragraphs,
    this.importedPractice,
    this.aiCredentials,
    this.reviewService,
  });

  final List<TranslatedParagraph> paragraphs;
  final PracticeWorkbook? importedPractice;
  final TranslationCredentials? aiCredentials;
  final AiReviewService? reviewService;

  @override
  State<BackTranslationPage> createState() => _BackTranslationPageState();
}

class _BackTranslationPageState extends State<BackTranslationPage> {
  late final List<PracticeSentence> _sentences =
      widget.importedPractice?.sentences ??
          buildPracticeSentences(widget.paragraphs);
  late final PracticeWorkbook _workbook =
      widget.importedPractice ?? PracticeWorkbook.fromParagraphs(_sentences);
  final Map<int, String> _answers = {};
  final Map<int, AiReviewResult> _reviews = {};
  late final AiReviewService _reviewService =
      widget.reviewService ?? AiReviewService();
  bool _submitted = false;
  bool _exporting = false;
  bool _reviewing = false;
  String? _reviewError;
  int _reviewDone = 0;
  int _reviewTotal = 0;
  int _reviewJob = 0;

  bool get _canReview =>
      widget.aiCredentials?.isConfigured(TranslationSource.ai) ?? false;

  @override
  void dispose() {
    _reviewJob++;
    if (widget.reviewService == null) _reviewService.close();
    super.dispose();
  }

  int get _exerciseCount =>
      _sentences.where((sentence) => sentence.canAnswer).length;
  int get _answeredCount =>
      _answers.values.where((answer) => answer.trim().isNotEmpty).length;
  bool get _hasUnmatched => _sentences.any(
        (sentence) => sentence.original == null || sentence.reference == null,
      );

  Future<void> _editSentence(int index) async {
    var draft = _answers[index] ?? '';
    final answer = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            '第 ${_sentences[index].paragraphNumber} 段 · 第 ${_sentences[index].sentenceNumber} 句'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _sentences[index].reference!,
                style: const TextStyle(fontSize: 16, height: 1.6, color: _ink),
              ),
              const SizedBox(height: 18),
              TextFormField(
                initialValue: draft,
                onChanged: (value) => draft = value,
                autofocus: true,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '你的英文回译',
                  hintText: '根据中文写出英文句子',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft),
            child: const Text('保存句子'),
          ),
        ],
      ),
    );
    if (answer != null && mounted) {
      setState(() {
        if (answer.trim().isEmpty) {
          _answers.remove(index);
        } else {
          _answers[index] = answer.trim();
        }
      });
    }
  }

  void _restart() => setState(() {
        _reviewJob++;
        _answers.clear();
        _reviews.clear();
        _reviewError = null;
        _reviewing = false;
        _reviewDone = 0;
        _reviewTotal = 0;
        _submitted = false;
      });

  void _submit() {
    setState(() => _submitted = true);
    if (_canReview) _runReview();
  }

  Future<void> _runReview() async {
    if (_reviewing || !_canReview) return;
    final pending = <AiReviewInput>[
      for (var index = 0; index < _sentences.length; index++)
        if (_sentences[index].reference != null &&
            (_answers[index]?.isNotEmpty ?? false) &&
            !_reviews.containsKey(index))
          AiReviewInput(
            index: index,
            reference: _sentences[index].reference!,
            original: _sentences[index].original,
            answer: _answers[index]!,
          ),
    ];
    if (pending.isEmpty) return;
    final job = ++_reviewJob;
    setState(() {
      _reviewing = true;
      _reviewError = null;
      _reviewDone = 0;
      _reviewTotal = pending.length;
    });
    try {
      for (var start = 0; start < pending.length; start += 8) {
        final end = start + 8 < pending.length ? start + 8 : pending.length;
        final batch = pending.sublist(start, end);
        final results = await _reviewService.reviewSentences(
          batch,
          widget.aiCredentials!,
        );
        if (!mounted || job != _reviewJob) return;
        setState(() {
          _reviews.addAll(results);
          _reviewDone += batch.length;
        });
      }
    } on AiReviewException catch (error) {
      if (mounted && job == _reviewJob) {
        setState(() => _reviewError = error.message);
      }
    } catch (_) {
      if (mounted && job == _reviewJob) {
        setState(() => _reviewError = 'AI 点评出现意外错误，请重试。');
      }
    } finally {
      if (mounted && job == _reviewJob) {
        setState(() => _reviewing = false);
      }
    }
  }

  Future<void> _export() async {
    if (!_submitted || _exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = _workbook.export(_answers);
      final saved = await FilePicker.saveFile(
        fileName: 'ReMirror-${_workbook.nextRoundSheetName}.xlsx',
        bytes: bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        dialogTitle: '导出本轮练习结果',
      );
      if (mounted && saved != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('练习结果已导出')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F8F7),
        title: Text(_submitted ? '回译结果' : '逐句回译'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                compact ? 20 : 36,
                22,
                compact ? 20 : 36,
                48,
              ),
              children: [
                Text(
                  _submitted ? 'STEP 02 / 回译结果' : 'STEP 02 / 逆向写作',
                  style: const TextStyle(
                    color: _accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _submitted ? '对照原文，发现差异。' : '从中文，重新写出英文。',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontSize: compact ? 28 : 36,
                      ),
                ),
                const SizedBox(height: 9),
                Text(
                  _submitted
                      ? '标色部分是文本差异；用词不同也可能表达相同意思。'
                      : '点击中文句子填写回译。完成整篇后，原文和差异会一起显示。',
                  style:
                      const TextStyle(color: _muted, fontSize: 14, height: 1.6),
                ),
                const SizedBox(height: 22),
                _progressCard(),
                if (_submitted && _canReview) ...[
                  const SizedBox(height: 12),
                  _reviewStatus(),
                ],
                if (_hasUnmatched) ...[
                  const SizedBox(height: 12),
                  const Text(
                    '部分段落的中英文句数不同，结果按各段句序尽量对应；多出的句子会单独显示。',
                    style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
                  ),
                ],
                const SizedBox(height: 20),
                for (var index = 0; index < _sentences.length; index++)
                  if (_submitted || _sentences[index].canAnswer) ...[
                    _submitted
                        ? _resultCard(index, compact)
                        : _exerciseCard(index),
                    const SizedBox(height: 12),
                  ],
                const SizedBox(height: 12),
                if (_submitted) ...[
                  FilledButton.icon(
                    onPressed: _exporting ? null : _export,
                    icon: const Icon(Icons.file_download_outlined),
                    label: Text(_exporting ? '正在导出…' : '导出本轮结果 XLSX'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _restart,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('重新练习'),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: _exerciseCount == 0 ? null : _submit,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('结束并查看结果'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _progressCard() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: _decoration(),
        child: Row(
          children: [
            Icon(
              _submitted ? Icons.task_alt_rounded : Icons.edit_note_rounded,
              color: _accent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _submitted
                    ? '已作答 $_answeredCount / $_exerciseCount 句'
                    : '已完成 $_answeredCount / $_exerciseCount 句',
                style:
                    const TextStyle(color: _ink, fontWeight: FontWeight.w700),
              ),
            ),
            if (!_submitted)
              Text(
                '${_exerciseCount == 0 ? 0 : (_answeredCount * 100 / _exerciseCount).round()}%',
                style: const TextStyle(
                    color: _accent, fontWeight: FontWeight.w700),
              ),
          ],
        ),
      );

  Widget _reviewStatus() {
    final message = _reviewing
        ? 'AI 正在点评：$_reviewDone / $_reviewTotal 句'
        : _reviewError != null
            ? _reviewError!
            : _reviews.isEmpty
                ? '未作答，已跳过 AI 点评。'
                : 'AI 已点评 ${_reviews.length} 句';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: _decoration(),
      child: Row(
        children: [
          Icon(
            _reviewError == null ? Icons.auto_awesome : Icons.error_outline,
            color: _accent,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: _ink))),
          if (_reviewing)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (_reviewError != null)
            TextButton(onPressed: _runReview, child: const Text('重试点评')),
        ],
      ),
    );
  }

  Widget _exerciseCard(int index) {
    final sentence = _sentences[index];
    final answer = _answers[index];
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _border),
      ),
      child: InkWell(
        onTap: () => _editSentence(index),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label(sentence),
              const SizedBox(height: 10),
              Text(
                sentence.reference!,
                style: const TextStyle(color: _ink, fontSize: 16, height: 1.65),
              ),
              const SizedBox(height: 14),
              Text(
                answer == null ? '点击填写英文回译' : '你的回译：$answer',
                style: TextStyle(
                  color: answer == null ? _accent : _muted,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultCard(int index, bool compact) {
    final sentence = _sentences[index];
    final answer = _answers[index];
    final original = sentence.original;
    final diff = original == null || answer == null
        ? null
        : compareSentence(original, answer);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _decoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(sentence),
          if (sentence.reference != null) ...[
            const SizedBox(height: 8),
            Text(
              sentence.reference!,
              style: const TextStyle(color: _muted, fontSize: 14, height: 1.6),
            ),
          ],
          const SizedBox(height: 16),
          Flex(
            direction: compact ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _comparisonPanel(
                compact: compact,
                title: '英文原文',
                text: original ?? '无对应原文句子',
                words: diff?.original,
                highlight: const Color(0xFFFFE1DB),
              ),
              SizedBox(width: compact ? 0 : 12, height: compact ? 12 : 0),
              _comparisonPanel(
                compact: compact,
                title: '你的回译',
                text: sentence.reference == null ? '无对应中文句子' : answer ?? '未作答',
                words: diff?.answer,
                highlight: const Color(0xFFFFE9B8),
              ),
            ],
          ),
          if (diff?.exactMatch == true) ...[
            const SizedBox(height: 12),
            const Text(
              '词语完全一致',
              style: TextStyle(color: _accent, fontSize: 12),
            ),
          ],
          if (_canReview && sentence.reference != null) ...[
            const SizedBox(height: 16),
            _reviewPanel(index, answer),
          ],
          if (widget.importedPractice != null) ...[
            const SizedBox(height: 16),
            const Text(
              '上轮回译',
              style: TextStyle(
                color: _muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              widget.importedPractice!.previousAnswers[index] ?? '未作答',
              style: const TextStyle(color: _ink, height: 1.6),
            ),
          ],
        ],
      ),
    );
  }

  Widget _reviewPanel(int index, String? answer) {
    final review = _reviews[index];
    final verdict = review == null
        ? null
        : switch (review.verdict) {
            AiReviewVerdict.accurate => '准确',
            AiReviewVerdict.mostlyAccurate => '基本准确',
            AiReviewVerdict.needsWork => '需改进',
          };
    final color = switch (review?.verdict) {
      AiReviewVerdict.accurate => _accent,
      AiReviewVerdict.mostlyAccurate => const Color(0xFF966A15),
      AiReviewVerdict.needsWork => const Color(0xFFB44A3E),
      null => _muted,
    };
    final detail = answer == null
        ? '未作答，已跳过点评。'
        : review?.reason ?? (_reviewing ? '正在生成点评…' : '暂未获得点评，可在上方重试。');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F9F8),
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            verdict == null ? 'AI 点评' : 'AI 点评 · $verdict',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(detail, style: const TextStyle(color: _ink, height: 1.5)),
        ],
      ),
    );
  }

  Widget _comparisonPanel({
    required bool compact,
    required String title,
    required String text,
    required Color highlight,
    List<WordDiff>? words,
  }) {
    final panel = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFCFB),
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          if (words == null)
            Text(text, style: const TextStyle(color: _ink, height: 1.6))
          else
            SelectableText.rich(
              TextSpan(
                children: [
                  for (var index = 0; index < words.length; index++) ...[
                    TextSpan(
                      text: words[index].text,
                      style: TextStyle(
                        color: _ink,
                        backgroundColor:
                            words[index].matches ? null : highlight,
                      ),
                    ),
                    if (index < words.length - 1) const TextSpan(text: ' '),
                  ],
                ],
              ),
              style: const TextStyle(color: _ink, height: 1.6),
            ),
        ],
      ),
    );
    return compact ? panel : Expanded(child: panel);
  }

  Widget _label(PracticeSentence sentence) => Text(
        '第 ${sentence.paragraphNumber} 段 · 第 ${sentence.sentenceNumber} 句',
        style: const TextStyle(
          color: _accent,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      );

  BoxDecoration _decoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      );
}
