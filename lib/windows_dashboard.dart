import 'package:flutter/material.dart';

import 'dictionary_reader.dart';
import 'back_translation.dart';
import 'practice_history.dart';
import 'translation.dart';
import 'industrial_theme.dart';

const _navy = IndustrialPalette.ink;
const _blue = IndustrialPalette.accent;
const _muted = IndustrialPalette.muted;
const _line = IndustrialPalette.border;

enum _DashboardSection { home, article, reference, practice }

class WindowsDashboard extends StatefulWidget {
  const WindowsDashboard({
    super.key,
    this.hud,
    required this.original,
    required this.result,
    required this.source,
    required this.sessions,
    required this.activeSessionId,
    required this.busy,
    required this.importing,
    required this.loadingHistory,
    required this.readingPreview,
    required this.completed,
    required this.total,
    required this.error,
    required this.historyError,
    required this.onSettings,
    required this.onSourceChanged,
    required this.onTranslate,
    required this.onCancel,
    required this.onPractice,
    required this.onImport,
    required this.onImportArticle,
    required this.onOpenSession,
    required this.onDeleteSession,
    required this.onEditReference,
    required this.onReadingPreviewChanged,
    required this.onNewArticle,
    required this.onSample,
  });

  final Widget? hud;
  final TextEditingController original;
  final List<TranslatedParagraph> result;
  final TranslationSource source;
  final List<PracticeSession> sessions;
  final String? activeSessionId;
  final bool busy;
  final bool importing;
  final bool loadingHistory;
  final bool readingPreview;
  final int completed;
  final int total;
  final String? error;
  final String? historyError;
  final VoidCallback onSettings;
  final ValueChanged<TranslationSource> onSourceChanged;
  final VoidCallback onTranslate;
  final VoidCallback onCancel;
  final VoidCallback onPractice;
  final VoidCallback onImport;
  final VoidCallback onImportArticle;
  final ValueChanged<PracticeSession> onOpenSession;
  final ValueChanged<PracticeSession> onDeleteSession;
  final ValueChanged<int> onEditReference;
  final ValueChanged<bool> onReadingPreviewChanged;
  final VoidCallback onNewArticle;
  final VoidCallback onSample;

  @override
  State<WindowsDashboard> createState() => _WindowsDashboardState();
}

class _WindowsDashboardState extends State<WindowsDashboard> {
  bool _showAll = false;
  _DashboardSection _section = _DashboardSection.home;
  _DashboardSection? _hoveredStep;
  _DashboardSection? _focusedStep;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  Duration get _sectionDuration =>
      _reduceMotion ? Duration.zero : const Duration(milliseconds: 260);

  Duration get _feedbackDuration =>
      _reduceMotion ? Duration.zero : const Duration(milliseconds: 160);

  @override
  void initState() {
    super.initState();
    widget.original.addListener(_onOriginalChanged);
  }

  @override
  void didUpdateWidget(covariant WindowsDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.original != widget.original) {
      oldWidget.original.removeListener(_onOriginalChanged);
      widget.original.addListener(_onOriginalChanged);
    }
  }

  @override
  void dispose() {
    widget.original.removeListener(_onOriginalChanged);
    super.dispose();
  }

  void _onOriginalChanged() => setState(() {});

  void _openSection(_DashboardSection section) {
    if (section == _DashboardSection.practice) {
      if (widget.result.isNotEmpty) {
        widget.onPractice();
        return;
      }
      final session = _current;
      if (session != null) {
        widget.onOpenSession(session);
        return;
      }
    }
    setState(() {
      _hoveredStep = null;
      _focusedStep = null;
      _section = section;
    });
  }

  PracticeSession? get _latest =>
      widget.sessions.isEmpty ? null : widget.sessions.first;

  PracticeSession? get _current {
    if (widget.result.isEmpty) return _latest;
    for (final session in widget.sessions) {
      if (session.id == widget.activeSessionId) return session;
    }
    return null;
  }

  int get _currentSentenceCount =>
      _current?.sentenceCount ??
      buildPracticeSentences(widget.result)
          .where((sentence) => sentence.canAnswer)
          .length;

  List<TranslatedParagraph> get _reference {
    if (widget.result.isNotEmpty) return widget.result;
    if (_latest?.paragraphs.isNotEmpty == true) return _latest!.paragraphs;
    final imported = _latest?.importedPractice;
    if (imported == null) return const [];
    return [
      TranslatedParagraph(
        '',
        imported.sentences
            .map((sentence) => sentence.reference)
            .whereType<String>()
            .take(8)
            .join(' '),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 760;
                  final inset = compact ? 16.0 : 28.0;
                  return Padding(
                    padding: EdgeInsets.all(inset),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1380),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _header(),
                            const SizedBox(height: 22),
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: _sectionDuration,
                                reverseDuration: _feedbackDuration,
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: _reduceMotion
                                          ? Offset.zero
                                          : const Offset(0, 0.018),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                                child: KeyedSubtree(
                                  key: ValueKey(_section),
                                  child: _section == _DashboardSection.home
                                      ? _home(compact)
                                      : _detail(compact),
                                ),
                              ),
                            ),
                            if (widget.error != null ||
                                widget.historyError != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                widget.error ?? widget.historyError!,
                                style: const TextStyle(
                                  color: IndustrialPalette.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (widget.hud != null)
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: IgnorePointer(child: widget.hud!),
              ),
          ],
        ),
      );

  Widget _home(bool compact) {
    final tiles = compact
        ? Column(
            children: [
              _stepTile(_DashboardSection.article, height: 158),
              const SizedBox(height: 10),
              _stepTile(_DashboardSection.reference, height: 158),
              const SizedBox(height: 10),
              _stepTile(_DashboardSection.practice, height: 158),
            ],
          )
        : Row(
            children: [
              Expanded(child: _stepTile(_DashboardSection.article)),
              const SizedBox(width: 14),
              Expanded(child: _stepTile(_DashboardSection.reference)),
              const SizedBox(width: 14),
              Expanded(child: _stepTile(_DashboardSection.practice)),
            ],
          );
    if (compact) {
      return ListView(
        children: [
          _sectionHeading(),
          const SizedBox(height: 16),
          tiles,
          const SizedBox(height: 16),
          _progressStrip(),
          const SizedBox(height: 16),
          _history(false),
        ],
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeading(),
          const SizedBox(height: 16),
          Expanded(flex: 3, child: tiles),
          const SizedBox(height: 16),
          _progressStrip(),
          const SizedBox(height: 16),
          Expanded(flex: 2, child: _history(true, fill: true)),
        ],
      );
      if (constraints.maxHeight >= 520) return content;
      return SingleChildScrollView(
        child: SizedBox(height: 520, child: content),
      );
    });
  }

  Widget _sectionHeading() => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '从阅读到表达',
            style: TextStyle(
              color: _navy,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 3),
          Text(
            '选择一个步骤，文章、译文和进度会自动衔接。',
            style: TextStyle(color: _muted, fontSize: 13),
          ),
        ],
      );

  Widget _stepTile(_DashboardSection section, {double? height}) {
    final title = switch (section) {
      _DashboardSection.article => '输入文章',
      _DashboardSection.reference => '参考译文',
      _ => '逐句回译',
    };
    final subtitle = switch (section) {
      _DashboardSection.article => '粘贴或导入英文原文，随时编辑和查词',
      _DashboardSection.reference => '选择翻译来源，生成和修改中文参考',
      _ => '根据中文提示重写英文，查看进度',
    };
    final status = switch (section) {
      _DashboardSection.article => widget.original.text.trim().isEmpty
          ? '等待文章'
          : '${splitParagraphs(widget.original.text).length} 段原文',
      _DashboardSection.reference => widget.busy
          ? '生成中'
          : _reference.isEmpty
              ? '等待生成'
              : '${_reference.length} 段译文',
      _ => _currentSentenceCount == 0
          ? '等待练习'
          : '${_current?.answeredCount ?? 0} / $_currentSentenceCount 句',
    };
    final icon = switch (section) {
      _DashboardSection.article => Icons.article_outlined,
      _DashboardSection.reference => Icons.translate_rounded,
      _ => Icons.forum_rounded,
    };
    final highlighted = _hoveredStep == section || _focusedStep == section;
    return SizedBox(
      height: height,
      child: AnimatedContainer(
        duration: _feedbackDuration,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color:
              highlighted ? IndustrialPalette.reading : IndustrialPalette.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: highlighted ? _blue : _line),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('open-${section.name}'),
            borderRadius: BorderRadius.circular(16),
            onHover: (hovered) => setState(() {
              if (hovered) {
                _hoveredStep = section;
              } else if (_hoveredStep == section) {
                _hoveredStep = null;
              }
            }),
            onFocusChange: (focused) => setState(() {
              if (focused) {
                _focusedStep = section;
              } else if (_focusedStep == section) {
                _focusedStep = null;
              }
            }),
            onTap: () => _openSection(section),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: _blue, size: 25),
                      const Spacer(),
                      AnimatedSlide(
                        duration: _feedbackDuration,
                        curve: Curves.easeOutCubic,
                        offset: highlighted && !_reduceMotion
                            ? const Offset(0.16, -0.16)
                            : Offset.zero,
                        child: Icon(
                          Icons.arrow_outward_rounded,
                          color: highlighted ? _blue : _muted,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    title,
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    status,
                    style: const TextStyle(
                      color: _blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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

  Widget _detail(bool compact) => LayoutBuilder(
        builder: (context, constraints) {
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  switch (_section) {
                    _DashboardSection.article => '01 / 输入文章',
                    _DashboardSection.reference => '02 / 参考译文',
                    _ => '03 / 逐句回译',
                  },
                  style: const TextStyle(color: _muted, fontSize: 12)),
              const SizedBox(height: 12),
              Expanded(
                child: switch (_section) {
                  _DashboardSection.article => _articleCard(),
                  _DashboardSection.reference => _referenceCard(),
                  _ => _practiceCard(),
                },
              ),
              const SizedBox(height: 14),
              _detailActions(compact),
            ],
          );
          final minimumHeight = compact ? 550.0 : 480.0;
          if (constraints.maxHeight >= minimumHeight) return content;
          return SingleChildScrollView(
            child: SizedBox(height: minimumHeight, child: content),
          );
        },
      );

  Widget _detailActions(bool compact) {
    final action = switch (_section) {
      _DashboardSection.article => FilledButton.icon(
          onPressed: widget.original.text.trim().isEmpty
              ? null
              : () => setState(() => _section = _DashboardSection.reference),
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('查看参考译文'),
        ),
      _DashboardSection.reference => FilledButton.icon(
          onPressed: widget.busy
              ? widget.onCancel
              : widget.original.text.trim().isEmpty
                  ? null
                  : widget.onTranslate,
          icon: Icon(widget.busy ? Icons.close_rounded : Icons.auto_awesome),
          label: Text(widget.busy ? '取消翻译' : '生成参考译文'),
        ),
      _ => FilledButton.icon(
          onPressed: widget.result.isNotEmpty
              ? widget.onPractice
              : _current == null
                  ? null
                  : () => widget.onOpenSession(_current!),
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(
            _current?.submitted == true && widget.result.isEmpty
                ? '查看练习结果'
                : '进入逐句回译',
          ),
        ),
    };
    final secondary = switch (_section) {
      _DashboardSection.article => OutlinedButton.icon(
          onPressed: widget.busy || widget.importing ? null : widget.onImport,
          icon: const Icon(Icons.file_upload_outlined),
          label: Text(widget.importing ? '导入中…' : '导入 XLSX'),
        ),
      _DashboardSection.reference => OutlinedButton.icon(
          onPressed: widget.result.isEmpty
              ? null
              : () => _openSection(_DashboardSection.practice),
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('查看逐句回译'),
        ),
      _ => OutlinedButton.icon(
          onPressed: () =>
              setState(() => _section = _DashboardSection.reference),
          icon: const Icon(Icons.translate_rounded),
          label: const Text('查看参考译文'),
        ),
    };
    final articleImport = OutlinedButton.icon(
      onPressed:
          widget.busy || widget.importing ? null : widget.onImportArticle,
      icon: const Icon(Icons.article_outlined),
      label: Text(widget.importing ? '导入中…' : '导入文章'),
    );
    return compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              action,
              const SizedBox(height: 10),
              if (_section == _DashboardSection.article) ...[
                articleImport,
                const SizedBox(height: 10),
              ],
              secondary,
            ],
          )
        : Row(children: [
            action,
            const SizedBox(width: 12),
            if (_section == _DashboardSection.article) ...[
              articleImport,
              const SizedBox(width: 12),
            ],
            secondary,
          ]);
  }

  Widget _header() => Row(
        children: [
          if (_section != _DashboardSection.home) ...[
            IconButton(
              key: const ValueKey('back-to-dashboard'),
              tooltip: '返回工作台',
              onPressed: () =>
                  setState(() => _section = _DashboardSection.home),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: IndustrialPalette.accent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.compare_arrows_rounded,
              color: IndustrialPalette.accentInk,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'ReMirror',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _navy,
            ),
          ),
          const Spacer(),
          IconButton.filled(
            tooltip: '设置',
            onPressed: widget.onSettings,
            style:
                IconButton.styleFrom(backgroundColor: IndustrialPalette.panel),
            icon: const Icon(Icons.settings_rounded, color: _blue),
          ),
        ],
      );

  Widget _card({required Widget child, bool dark = false}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: dark ? IndustrialPalette.reading : IndustrialPalette.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: IndustrialPalette.border),
        ),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: _navy),
          child: child,
        ),
      );

  Widget _cardTitle(IconData icon, String title, String subtitle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: IndustrialPalette.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 28, color: _blue),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 12, color: _muted)),
        ],
      );

  Widget _articleCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cardTitle(Icons.article_outlined, '输入文章', '粘贴或导入英文原文'),
            const SizedBox(height: 14),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: IndustrialPalette.reading,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: widget.result.isNotEmpty
                    ? const Center(child: Text('原文已隐藏，完成回译后查看'))
                    : widget.readingPreview
                        ? SingleChildScrollView(
                            padding: const EdgeInsets.all(14),
                            child: DictionaryReader(text: widget.original.text),
                          )
                        : TextField(
                            controller: widget.original,
                            expands: true,
                            maxLines: null,
                            minLines: null,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: const InputDecoration(
                              hintText: '在这里粘贴英文文章…',
                              contentPadding: EdgeInsets.all(16),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                          ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '${widget.original.text.runes.length} 字符',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 16),
                Text(
                  '${splitParagraphs(widget.original.text).length} 段',
                  style: const TextStyle(fontSize: 12),
                ),
                const Spacer(),
                if (widget.result.isNotEmpty)
                  _smallAction('新文章', widget.onNewArticle)
                else if (widget.original.text.isEmpty)
                  _smallAction('示例', widget.onSample)
                else
                  _smallAction(
                    widget.readingPreview ? '编辑' : '查词',
                    () =>
                        widget.onReadingPreviewChanged(!widget.readingPreview),
                  ),
              ],
            ),
          ],
        ),
      );

  Widget _smallAction(String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Text(
            label,
            style: const TextStyle(
              color: _blue,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );

  Widget _referenceCard() {
    final paragraphs = _reference;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTitle(Icons.translate_rounded, '参考译文', '生成中文参考'),
          const SizedBox(height: 8),
          SizedBox(
            height: 32,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<TranslationSource>(
                value: widget.source,
                isDense: true,
                items: [
                  for (final source in TranslationSource.values)
                    DropdownMenuItem(value: source, child: Text(source.label)),
                ],
                onChanged: widget.busy
                    ? null
                    : (value) {
                        if (value != null) widget.onSourceChanged(value);
                      },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: IndustrialPalette.reading,
                borderRadius: BorderRadius.circular(14),
              ),
              child: AnimatedSwitcher(
                duration: _reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOutCubic,
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  fit: StackFit.expand,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                ),
                child: widget.busy
                    ? Column(
                        key: const ValueKey('reference-loading'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(
                            widget.total == 0
                                ? '正在准备…'
                                : '翻译中 ${widget.completed} / ${widget.total}',
                          ),
                        ],
                      )
                    : paragraphs.isEmpty
                        ? const Center(
                            key: ValueKey('reference-empty'),
                            child: Text('译文将在这里显示'),
                          )
                        : ListView.separated(
                            key: const ValueKey('reference-ready'),
                            itemCount: paragraphs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) => InkWell(
                              onTap: widget.result.isEmpty
                                  ? null
                                  : () => widget.onEditReference(index),
                              child: Text(
                                paragraphs[index].translated,
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    const TextStyle(fontSize: 13, height: 1.5),
                              ),
                            ),
                          ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                paragraphs.isEmpty ? Icons.info_outline : Icons.check_circle,
                size: 18,
                color: paragraphs.isEmpty ? _muted : _blue,
              ),
              const SizedBox(width: 8),
              Text(
                paragraphs.isEmpty ? '等待生成' : '已生成',
                style: const TextStyle(fontSize: 12),
              ),
              const Spacer(),
              if (widget.result.isNotEmpty)
                _smallAction('修改译文', () => widget.onEditReference(0)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _practiceCard() {
    final session = _current;
    final done = session?.answeredCount ?? 0;
    final total = _currentSentenceCount;
    final percent = total == 0 ? 0 : (done * 100 / total).round();
    return _card(
      dark: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTitle(Icons.forum_rounded, '逐句回译', '根据中文重写英文'),
          const SizedBox(height: 16),
          Container(
            height: 84,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: IndustrialPalette.panel,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '英文  →  中文  →  英文',
                  style: TextStyle(color: _navy, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                _animatedProgress(
                  value: total == 0 ? 0 : done / total,
                  height: 7,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const SizedBox(
            height: 48,
            child: CustomPaint(painter: _WavePainter()),
          ),
          const Spacer(),
          Row(
            children: [
              CircleAvatar(
                backgroundColor: IndustrialPalette.accent,
                child: Icon(
                  session?.submitted == true ? Icons.check : Icons.play_arrow,
                  color: IndustrialPalette.accentInk,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  session == null
                      ? total == 0
                          ? '尚无练习'
                          : '准备开始 · $total 句'
                      : session.submitted
                          ? '最近练习已完成'
                          : '练习进行中  $done / $total 句',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: IndustrialPalette.panel,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$percent%',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _progressStrip() {
    final session = _current;
    final total = _currentSentenceCount;
    final done = session?.answeredCount ?? 0;
    final ratio = total == 0 ? 0.0 : done / total;
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: IndustrialPalette.panel,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  total == 0 ? '暂无当前练习' : '当前练习 · $total 句',
                  style: const TextStyle(fontSize: 11, color: _muted),
                ),
              ),
              Text(
                '$done / $total',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 15),
              Text(
                '${(ratio * 100).round()}%',
                style: const TextStyle(
                  color: _blue,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          _animatedProgress(value: ratio, height: 6),
        ],
      ),
    );
  }

  Widget _animatedProgress({required double value, required double height}) =>
      TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0)),
        duration:
            _reduceMotion ? Duration.zero : const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
        builder: (context, progress, _) => LinearProgressIndicator(
          value: progress,
          minHeight: height,
          borderRadius: BorderRadius.circular(99),
          backgroundColor: _line,
          color: _blue,
        ),
      );

  Widget _history(bool wide, {bool fill = false}) {
    final sessions =
        _showAll ? widget.sessions : widget.sessions.take(4).toList();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: IndustrialPalette.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, color: _blue),
              const SizedBox(width: 9),
              const Text(
                '最近练习',
                style: TextStyle(
                  color: _navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (widget.sessions.length > 4)
                OutlinedButton(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  child: Text(_showAll ? '收起' : '查看全部'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (fill)
            Expanded(child: _historyContent(sessions, wide))
          else
            _historyContent(sessions, wide),
        ],
      ),
    );
  }

  Widget _historyContent(List<PracticeSession> sessions, bool wide) {
    if (widget.loadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }
    if (sessions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('还没有练习记录', style: TextStyle(color: _muted)),
        ),
      );
    }
    final rows = <Widget>[
      if (wide) _tableHeader(),
      for (final session in sessions) _historyRow(session, wide),
    ];
    return wide ? ListView(children: rows) : Column(children: rows);
  }

  Widget _tableHeader() => Container(
        color: IndustrialPalette.reading,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: const Row(
          children: [
            Expanded(flex: 4, child: Text('文章 / 练习')),
            Expanded(flex: 2, child: Text('时间')),
            Expanded(flex: 2, child: Text('翻译来源')),
            Expanded(child: Text('句数')),
            Expanded(flex: 2, child: Text('状态')),
            SizedBox(width: 32),
          ],
        ),
      );

  Widget _historyRow(PracticeSession session, bool wide) {
    final status = session.submitted
        ? '已完成'
        : session.answeredCount > 0
            ? '进行中'
            : '未开始';
    final statusColor = session.submitted
        ? _blue
        : session.answeredCount > 0
            ? _blue
            : _muted;
    final date = session.updatedAt;
    final dateLabel =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: () => widget.onOpenSession(session),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _line)),
        ),
        child: wide
            ? Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      session.title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(flex: 2, child: Text(dateLabel)),
                  Expanded(flex: 2, child: Text(session.source)),
                  Expanded(child: Text('${session.sentenceCount}')),
                  Expanded(
                    flex: 2,
                    child: Text(status, style: TextStyle(color: statusColor)),
                  ),
                  _rowMenu(session),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$dateLabel · ${session.source} · ${session.sentenceCount} 句',
                          style: const TextStyle(fontSize: 11, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  Text(status, style: TextStyle(color: statusColor)),
                  _rowMenu(session),
                ],
              ),
      ),
    );
  }

  Widget _rowMenu(PracticeSession session) => SizedBox(
        width: 32,
        child: PopupMenuButton<String>(
          tooltip: '练习操作',
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.more_horiz, size: 18, color: _muted),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'open', child: Text('打开')),
            PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
          onSelected: (value) => value == 'delete'
              ? widget.onDeleteSession(session)
              : widget.onOpenSession(session),
        ),
      );
}

class _WavePainter extends CustomPainter {
  const _WavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * .55)
      ..cubicTo(
        size.width * .08,
        -8,
        size.width * .17,
        size.height + 8,
        size.width * .26,
        size.height * .55,
      )
      ..cubicTo(
        size.width * .34,
        -8,
        size.width * .40,
        size.height + 8,
        size.width * .50,
        size.height * .55,
      )
      ..cubicTo(
        size.width * .59,
        size.height * .95,
        size.width * .63,
        -5,
        size.width * .72,
        size.height * .48,
      )
      ..cubicTo(
        size.width * .82,
        size.height + 5,
        size.width * .88,
        0,
        size.width,
        size.height * .65,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: .78)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
    canvas.drawCircle(
      Offset(size.width * .61, size.height * .45),
      4,
      Paint()..color = IndustrialPalette.accent,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
