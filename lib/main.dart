import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'credential_store.dart';
import 'back_translation_page.dart';
import 'practice_workbook.dart';
import 'translation.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ReMirrorApp());
}

const _ink = Color(0xFF1A2832);
const _muted = Color(0xFF647780);
const _accent = Color(0xFF187A82);
const _border = Color(0xFFDCE6E5);
const _background = Color(0xFFF5F8F7);

class ReMirrorApp extends StatelessWidget {
  const ReMirrorApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ReMirror',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'LiberationSerif',
          fontFamilyFallback: const ['AlibabaPuHuiTi'],
          scaffoldBackgroundColor: _background,
          colorScheme: ColorScheme.fromSeed(
            seedColor: _accent,
            surface: Colors.white,
          ),
          textTheme: const TextTheme(
            headlineLarge: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
            titleLarge: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
            bodyMedium: TextStyle(fontSize: 14, color: _ink, height: 1.6),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _accent, width: 1.5),
            ),
          ),
        ),
        home: const TranslationHome(),
      );
}

class TranslationHome extends StatefulWidget {
  const TranslationHome({super.key});

  @override
  State<TranslationHome> createState() => _TranslationHomeState();
}

class _TranslationHomeState extends State<TranslationHome> {
  final _original = TextEditingController();
  final _resultCardKey = GlobalKey();
  final _store = const CredentialStore();
  final _service = TranslationService();
  TranslationCredentials _credentials = const TranslationCredentials();
  TranslationSource _source = TranslationSource.google;
  List<TranslatedParagraph> _result = const [];
  bool _busy = false;
  bool _loadingSettings = true;
  bool _importing = false;
  int _completed = 0;
  int _total = 0;
  int _job = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _original.addListener(() => setState(() {}));
    _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    try {
      final value = await _store.load();
      if (mounted) setState(() => _credentials = value);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '无法读取本机保存的翻译凭据。');
      }
    } finally {
      if (mounted) setState(() => _loadingSettings = false);
    }
  }

  @override
  void dispose() {
    _job++;
    _original.dispose();
    _service.close();
    super.dispose();
  }

  Future<void> _openSettings() async {
    final result = await showDialog<TranslationCredentials>(
      context: context,
      builder: (context) =>
          SettingsDialog(initial: _credentials, store: _store),
    );
    if (result != null && mounted) {
      setState(() {
        _credentials = result;
        _error = null;
      });
    }
  }

  Future<void> _translate() async {
    if (_busy) return;
    if (_original.text.trim().isEmpty) {
      setState(() => _error = '请先粘贴英文原文。');
      return;
    }
    if (!_credentials.isConfigured(_source)) {
      await _openSettings();
      if (!mounted || !_credentials.isConfigured(_source)) return;
    }
    final job = ++_job;
    setState(() {
      _busy = true;
      _error = null;
      _result = const [];
      _completed = 0;
      _total = 0;
    });
    _focusResultOnSmallScreens();
    try {
      final result = await _service.translateArticle(
        english: _original.text,
        source: _source,
        credentials: _credentials,
        isCancelled: () => job != _job,
        onProgress: (completed, total) {
          if (mounted && job == _job) {
            setState(() {
              _completed = completed;
              _total = total;
            });
          }
        },
      );
      if (mounted && job == _job) setState(() => _result = result);
    } on TranslationException catch (error) {
      if (mounted && job == _job) setState(() => _error = error.message);
    } catch (_) {
      if (mounted && job == _job) {
        setState(() => _error = '翻译时出现意外错误，请重试。');
      }
    } finally {
      if (mounted && job == _job) setState(() => _busy = false);
    }
  }

  void _focusResultOnSmallScreens() {
    if (MediaQuery.sizeOf(context).width >= 880) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _resultCardKey.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: 0.04,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _cancel() {
    _job++;
    setState(() {
      _busy = false;
      _error = '已取消翻译。';
    });
  }

  void _chooseSource(TranslationSource source) {
    if (_busy) _cancel();
    setState(() {
      _source = source;
      _result = const [];
      _error = null;
    });
  }

  Future<void> _copyResult() async {
    await Clipboard.setData(
      ClipboardData(
        text: _result.map((paragraph) => paragraph.translated).join('\n\n'),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('译文已复制')));
    }
  }

  void _openPractice() {
    if (_result.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BackTranslationPage(paragraphs: List.of(_result)),
      ),
    );
  }

  Future<void> _importPractice() async {
    if (_busy || _importing) return;
    setState(() => _importing = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        dialogTitle: '导入上次的练习',
      );
      if (file == null) return;
      final workbook = PracticeWorkbook.import(await file.readAsBytes());
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BackTranslationPage(
            paragraphs: const [],
            importedPractice: workbook,
          ),
        ),
      );
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入失败，请确认文件可读取。')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 880;
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 20 : 36,
                  vertical: compact ? 20 : 30,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1240),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _header(compact),
                        SizedBox(height: compact ? 36 : 54),
                        _intro(compact),
                        const SizedBox(height: 28),
                        _steps(compact),
                        const SizedBox(height: 28),
                        if (compact) ...[
                          _sourceCard(),
                          const SizedBox(height: 18),
                          _resultCard(),
                        ] else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _sourceCard()),
                              const SizedBox(width: 20),
                              Expanded(child: _resultCard()),
                            ],
                          ),
                        const SizedBox(height: 24),
                        _footer(),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );

  Widget _header(bool compact) => Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(13),
            ),
            child:
                const Icon(Icons.compare_arrows_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Text(
            'ReMirror',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const Spacer(),
          if (!compact)
            const Text('用回译，重新看见英语',
                style: TextStyle(color: _muted, fontSize: 13)),
          if (!compact) const SizedBox(width: 22),
          IconButton.outlined(
            tooltip: '翻译源设置',
            onPressed: _openSettings,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      );

  Widget _intro(bool compact) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'STEP 01 / 理解原文',
            style: TextStyle(
              color: _accent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '从理解原文开始。',
            style: Theme.of(context)
                .textTheme
                .headlineLarge
                ?.copyWith(fontSize: compact ? 29 : 36),
          ),
          const SizedBox(height: 10),
          const Text(
            '粘贴一篇英文文章，选择翻译来源，得到按段对应的中文参考译文。',
            style: TextStyle(color: _muted, fontSize: 14, height: 1.6),
          ),
        ],
      );

  Widget _steps(bool compact) {
    final items = [
      ('01', '原文译解', _result.isEmpty),
      ('02', '逆向写作', _result.isNotEmpty),
      ('03', '逐句对照', false),
    ];
    return Wrap(
      spacing: compact ? 8 : 18,
      runSpacing: 10,
      children: items.map((item) {
        final active = item.$3;
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 11 : 16,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFE4F3F0) : Colors.white,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: active ? const Color(0xFFC8E6DF) : _border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.$1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: active ? _accent : _muted,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                item.$2,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? _ink : _muted,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _sourceCard() => _CardFrame(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeading(Icons.article_outlined, '英文原文', 'ORIGINAL TEXT'),
            const SizedBox(height: 20),
            if (_result.isNotEmpty)
              Container(
                height: 355,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFCFB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border),
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_off_outlined,
                          size: 42, color: Color(0xFF91B7B4)),
                      SizedBox(height: 14),
                      Text('原文已隐藏',
                          style: TextStyle(
                              color: _ink, fontWeight: FontWeight.w700)),
                      SizedBox(height: 6),
                      Text('完成回译后，在结果页查看原文',
                          style: TextStyle(color: _muted, fontSize: 13)),
                    ],
                  ),
                ),
              )
            else
              Container(
                height: 355,
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFCFB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border),
                ),
                child: TextField(
                  controller: _original,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  style:
                      const TextStyle(fontSize: 15, height: 1.65, color: _ink),
                  decoration: const InputDecoration(
                    hintText: '在这里粘贴英文文章…\n\n段落会被保留下来，方便后续回译练习。',
                    hintStyle: TextStyle(color: Color(0xFF9BAAAE)),
                    contentPadding: EdgeInsets.all(20),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  '${_original.text.runes.length} 字符 · '
                  '${splitParagraphs(_original.text).length} 段',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _busy || _result.isNotEmpty
                      ? null
                      : () => _original.text =
                          'Learning a language changes the way we notice the world. '
                              'A familiar street can suddenly offer new words on every sign.\n\n'
                              'Progress rarely happens in a straight line. Some days, '
                              'a single sentence takes time to understand. That effort '
                              'is part of learning.',
                  child: const Text('填入示例'),
                ),
                TextButton(
                  onPressed:
                      _busy || _result.isNotEmpty || _original.text.isEmpty
                          ? null
                          : () {
                              _original.clear();
                              setState(() => _result = const []);
                            },
                  child: const Text('清空'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: _result.isNotEmpty
                  ? OutlinedButton.icon(
                      onPressed: () => setState(() => _result = const []),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('重新编辑原文'),
                    )
                  : FilledButton.icon(
                      onPressed: _busy ? _cancel : _translate,
                      icon: Icon(
                          _busy ? Icons.close_rounded : Icons.auto_awesome),
                      label: Text(_busy ? '取消翻译' : '生成中文参考译文'),
                    ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy || _importing ? null : _importPractice,
                icon: const Icon(Icons.file_upload_outlined),
                label: Text(_importing ? '正在导入…' : '导入上次练习 XLSX'),
              ),
            ),
          ],
        ),
      );

  Widget _resultCard() => _CardFrame(
        key: _resultCardKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHeading(Icons.translate_rounded, '中文参考译文', 'REFERENCE'),
            const SizedBox(height: 20),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: TranslationSource.values.map((source) {
                  final selected = _source == source;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: selected,
                      label: Text(source.label),
                      avatar: selected
                          ? const Icon(Icons.check, size: 17, color: _accent)
                          : null,
                      onSelected: (_) => _chooseSource(source),
                      selectedColor: const Color(0xFFE4F3F0),
                      side: const BorderSide(color: _border),
                      labelStyle: TextStyle(
                        color: selected ? _accent : _muted,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 355,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.025),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: _busy
                    ? _progressView()
                    : _error != null
                        ? _errorView()
                        : _result.isNotEmpty
                            ? _translatedView()
                            : _emptyView(),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 15, color: _muted),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    '凭据保存在本机安全存储中',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ),
                IconButton.outlined(
                  tooltip: '复制译文',
                  onPressed: _result.isEmpty ? null : _copyResult,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                ),
              ],
            ),
            if (_result.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openPractice,
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('开始逐句回译'),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _cardHeading(IconData icon, String title, String eyebrow) => Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4F2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _accent, size: 19),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const Spacer(),
          Text(
            eyebrow,
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: _muted,
            ),
          ),
        ],
      );

  Widget _emptyView() => Container(
        key: const ValueKey('empty'),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFCFB),
          border: Border.all(color: _border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined,
                  size: 42, color: Color(0xFF91B7B4)),
              SizedBox(height: 16),
              Text(
                '译文将在这里出现',
                style: TextStyle(color: _ink, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 6),
              Text('选择来源，然后开始翻译',
                  style: TextStyle(color: _muted, fontSize: 13)),
            ],
          ),
        ),
      );

  Widget _progressView() => Container(
        key: const ValueKey('progress'),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFCFB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 38,
                height: 38,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 20),
              Text(
                '正在使用 ${_source.label} 翻译',
                style:
                    const TextStyle(color: _ink, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 7),
              Text(
                _total == 0 ? '准备分段…' : '已完成 $_completed / $_total 个片段',
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: 220,
                child: LinearProgressIndicator(
                  value: _total == 0 ? null : _completed / _total,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _errorView() => Container(
        key: const ValueKey('error'),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8F4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF3DFD2)),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 38,
                color: Color(0xFFBF7657),
              ),
              const SizedBox(height: 14),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('检查翻译源设置'),
              ),
            ],
          ),
        ),
      );

  Widget _translatedView() => Container(
        key: const ValueKey('translated'),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFCFB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: _result.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 32, color: _border),
          itemBuilder: (context, index) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3, right: 14),
                child: Text(
                  '${index + 1}'.padLeft(2, '0'),
                  style: const TextStyle(
                    color: _accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(
                  _result[index].translated,
                  style:
                      const TextStyle(color: _ink, fontSize: 15, height: 1.8),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _footer() => Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 4,
        children: [
          const Text(
            'ReMirror  ·  Read. Rebuild. Remember.',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
          if (!_loadingSettings && !_credentials.isConfigured(_source))
            const Text(
              '当前翻译源尚未配置',
              style: TextStyle(color: _muted, fontSize: 11),
            ),
        ],
      );
}

class _CardFrame extends StatelessWidget {
  const _CardFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x090B3D39),
              blurRadius: 26,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: child,
      );
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.initial, required this.store});

  final TranslationCredentials initial;
  final CredentialStore store;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _google;
  late final TextEditingController _baiduId;
  late final TextEditingController _baiduSecret;
  late final TextEditingController _aiEndpoint;
  late final TextEditingController _aiKey;
  late final TextEditingController _aiModel;
  bool _saving = false;
  bool _showSecrets = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final value = widget.initial;
    _google = TextEditingController(text: value.googleApiKey);
    _baiduId = TextEditingController(text: value.baiduAppId);
    _baiduSecret = TextEditingController(text: value.baiduSecret);
    _aiEndpoint = TextEditingController(text: value.aiEndpoint);
    _aiKey = TextEditingController(text: value.aiApiKey);
    _aiModel = TextEditingController(text: value.aiModel);
  }

  @override
  void dispose() {
    for (final controller in [
      _google,
      _baiduId,
      _baiduSecret,
      _aiEndpoint,
      _aiKey,
      _aiModel,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final value = TranslationCredentials(
      googleApiKey: _google.text.trim(),
      baiduAppId: _baiduId.text.trim(),
      baiduSecret: _baiduSecret.text.trim(),
      aiEndpoint: _aiEndpoint.text.trim(),
      aiApiKey: _aiKey.text.trim(),
      aiModel: _aiModel.text.trim(),
    );
    if (value.aiEndpoint.isNotEmpty &&
        (Uri.tryParse(value.aiEndpoint)?.scheme != 'https' ||
            Uri.tryParse(value.aiEndpoint)?.host.isEmpty == true)) {
      setState(() => _error = 'AI 接口地址需以 https:// 开头。');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.save(value);
      if (mounted) Navigator.of(context).pop(value);
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，请检查设备安全存储服务。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 570, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '翻译源设置',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Text(
                  '填写你自己的服务凭据；所有设置仅保存在本机。',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: ListView(
                    children: [
                      _section(
                        'Google Cloud Translation',
                        '使用 Cloud Translation Basic (v2) API Key。',
                      ),
                      _field(_google, 'API Key', secret: true),
                      const SizedBox(height: 22),
                      _section('百度翻译', '使用百度翻译开放平台通用翻译 API。'),
                      _field(_baiduId, 'APP ID'),
                      const SizedBox(height: 10),
                      _field(_baiduSecret, '密钥', secret: true),
                      const SizedBox(height: 22),
                      _section('AI 翻译', '使用 OpenAI Chat Completions 兼容接口。'),
                      _field(_aiEndpoint, '接口基础地址（含 /v1）'),
                      const SizedBox(height: 10),
                      _field(_aiKey, 'API Key', secret: true),
                      const SizedBox(height: 10),
                      _field(_aiModel, '模型名称'),
                      const SizedBox(height: 10),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title:
                            const Text('显示密钥', style: TextStyle(fontSize: 13)),
                        value: _showSecrets,
                        onChanged: (value) =>
                            setState(() => _showSecrets = value),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: const TextStyle(color: Color(0xFFB85843))),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '翻译请求会直接发送给所选服务。',
                        style: TextStyle(color: _muted, fontSize: 11),
                      ),
                    ),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? '保存中…' : '保存设置'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

  Widget _section(String title, String detail) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(detail, style: const TextStyle(fontSize: 12, color: _muted)),
          ],
        ),
      );

  Widget _field(
    TextEditingController controller,
    String label, {
    bool secret = false,
  }) =>
      TextField(
        controller: controller,
        obscureText: secret && !_showSecrets,
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(labelText: label, isDense: true),
      );
}
