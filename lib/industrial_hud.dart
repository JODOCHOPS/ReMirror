import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'industrial_theme.dart';

/// ReMirror's inline, three-state HUD motion, inspired by the MIT-licensed
/// zmd-charge project: https://github.com/QinAnze/zmd-charge.
class IndustrialHud extends StatefulWidget {
  const IndustrialHud({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.detail,
    this.persistent = false,
  });

  final String eyebrow;
  final String title;
  final String detail;
  final bool persistent;

  @override
  State<IndustrialHud> createState() => _IndustrialHudState();
}

class _IndustrialHudState extends State<IndustrialHud>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..addStatusListener(_onStatus);
  Timer? _dismissTimer;
  bool _started = false;
  bool _playing = true;
  bool _visible = true;
  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reducedMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reducedMotion) {
      _playing = false;
      if (!widget.persistent) {
        _dismissTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _visible = false);
        });
      }
    } else {
      _controller.forward(from: 0);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    setState(() {
      _playing = false;
      _visible = widget.persistent;
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = !_visible
        ? const SizedBox.shrink()
        : SizedBox(
            height: _playing ? 100 : 56,
            width: double.infinity,
            child: Semantics(
              liveRegion: true,
              label: '${widget.title}，${widget.detail}',
              excludeSemantics: true,
              child: _playing
                  ? AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) => _stage(_controller.value),
                    )
                  : Center(
                      child: IndustrialStatusPill(
                        label: widget.detail,
                        active: widget.persistent,
                      ),
                    ),
            ),
          );
    if (_reducedMotion) return content;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: content,
    );
  }

  Widget _stage(double time) => LayoutBuilder(
        builder: (context, constraints) {
          final width =
              math.max(0.0, math.min(constraints.maxWidth - 24, 560.0));
          final pop = Curves.easeOutBack.transform(_cue(time, .02, .18));
          final appear = _cue(time, .07, .17);
          final expand = Curves.easeInOutCubic.transform(_cue(time, .16, .32));
          final contract =
              Curves.easeInOutCubic.transform(_cue(time, .61, .76));
          final height = 56 + 30 * (expand - contract);
          final radius = 28 - 12 * (expand - contract);
          final move = Curves.easeInOutCubic.transform(_cue(time, .29, .48));
          final moveAgain =
              Curves.easeInOutCubic.transform(_cue(time, .61, .76));
          final iconCenter = width * (.5 - .31 * move - .115 * moveAgain);
          final titleOpacity =
              _cue(time, .45, .55) * (1 - _cue(time, .62, .72));
          final detailOpacity = _cue(time, .76, .86);
          final exit = widget.persistent ? 1.0 : 1 - _cue(time, .9, 1);
          final stageScale = (.62 + .38 * pop) * exit;

          return Center(
            child: Transform.scale(
              scale: stageScale,
              child: SizedBox(
                width: width,
                height: 100,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: Opacity(
                        opacity: appear,
                        child: Container(
                          width: width,
                          height: height,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: const Color(0xFF312F30),
                            borderRadius: BorderRadius.circular(radius),
                            border: Border.all(color: IndustrialPalette.border),
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _HudRipples(
                                    time: time,
                                    centerX: iconCenter,
                                    height: height,
                                  ),
                                ),
                              ),
                              Center(
                                child: Opacity(
                                  opacity: titleOpacity,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(widget.eyebrow,
                                          style: const TextStyle(
                                            color: IndustrialPalette.muted,
                                            fontSize: 10,
                                            letterSpacing: 2,
                                            fontWeight: FontWeight.w700,
                                          )),
                                      const SizedBox(height: 3),
                                      Text(widget.title,
                                          style: const TextStyle(
                                            color: IndustrialPalette.ink,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700,
                                          )),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 58,
                                right: 24,
                                top: 0,
                                bottom: 0,
                                child: Opacity(
                                  opacity: detailOpacity,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      widget.detail,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: IndustrialPalette.ink,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: iconCenter - 17,
                      top: 33,
                      child: Opacity(
                        opacity: _cue(time, .03, .14),
                        child: Transform.scale(
                          scale: pop,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE9E7E4),
                              borderRadius:
                                  BorderRadius.circular(17 - 10 * contract),
                            ),
                            child: const Icon(Icons.bolt_rounded,
                                size: 23, color: Color(0xFF141313)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}

double _cue(double time, double start, double end) =>
    ((time - start) / (end - start)).clamp(0.0, 1.0);

class _HudRipples extends CustomPainter {
  const _HudRipples(
      {required this.time, required this.centerX, required this.height});

  final double time;
  final double centerX;
  final double height;

  @override
  void paint(Canvas canvas, Size size) {
    for (var index = 0; index < 3; index++) {
      final progress = Curves.easeOutCubic.transform(
        _cue(time, .29 + index * .035, .60 + index * .035),
      );
      final fade = 1 - _cue(time, .61, .75);
      final opacity =
          (math.sin(progress * math.pi) * fade * .35).clamp(0.0, 1.0);
      if (opacity <= 0) continue;
      canvas.drawCircle(
        Offset(centerX, height / 2),
        16 + (70 + 28 * index) * progress,
        Paint()
          ..color = const Color(0xFF8A8886).withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 - index * .5,
      );
    }
  }

  @override
  bool shouldRepaint(_HudRipples oldDelegate) =>
      time != oldDelegate.time ||
      centerX != oldDelegate.centerX ||
      height != oldDelegate.height;
}
