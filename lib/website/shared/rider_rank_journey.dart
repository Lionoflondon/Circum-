import 'package:flutter/material.dart';

/// An animated introduction to the Order, independent of account rank data.
class RiderRankJourney extends StatefulWidget {
  const RiderRankJourney({super.key});

  @override
  State<RiderRankJourney> createState() => _RiderRankJourneyState();
}

class _RiderRankJourneyState extends State<RiderRankJourney>
    with SingleTickerProviderStateMixin {
  static const _ranks = ['Agent', 'Sentinel', 'Warden', 'Knight', 'Veteran'];
  static const _blue = Color(0xff2455f5);
  static const _ink = Color(0xff102942);
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  bool _paused = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _updatePlayback();
  }

  void _updatePlayback() {
    if (_reduceMotion || _paused) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Pause briefly at each rank, then travel to the next. Hold at Veteran
  // before starting the introduction again; this never represents user status.
  double get _progress {
    if (_reduceMotion) return 4;
    final phase = _controller.value * 6;
    final step = phase.floor();
    if (step >= 4) return 4;
    final travel = ((phase - step - .4) / .6).clamp(0.0, 1.0);
    return step + Curves.easeInOutCubic.transform(travel);
  }

  Widget _rank(int index, double progress, bool vertical) {
    final reached = progress >= index;
    final active = !_reduceMotion && (progress - index).abs() < .08;
    final marker = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: reached ? _blue : Colors.white,
        border: Border.all(color: reached ? _blue : const Color(0xffa7c9df)),
        boxShadow: active
            ? [BoxShadow(color: _blue.withValues(alpha: .18), spreadRadius: 6)]
            : null,
      ),
      child: ExcludeSemantics(
        child: Text('0${index + 1}',
            style: TextStyle(
                color: reached ? Colors.white : _ink,
                fontSize: 13,
                fontWeight: FontWeight.w800)),
      ),
    );
    final label = Text(_ranks[index],
        style: const TextStyle(
            color: _ink, fontWeight: FontWeight.w700, fontSize: 16));
    return vertical
        ? Row(children: [marker, const SizedBox(width: 20), label])
        : Column(children: [marker, const SizedBox(height: 16), label]);
  }

  Widget _track(double progress, bool vertical) => ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            width: vertical ? 3 : double.infinity,
            height: vertical ? double.infinity : 3,
            child: ColoredBox(
              color: const Color(0xffa7c9df),
              child: Align(
                alignment: Alignment.topLeft,
                child: FractionallySizedBox(
                  widthFactor: vertical ? 1 : progress / 4,
                  heightFactor: vertical ? progress / 4 : 1,
                  child: const ColoredBox(color: _blue),
                ),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            final vertical = constraints.maxWidth <
                600 * MediaQuery.textScalerOf(context).scale(1);
            return AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final progress = _progress;
                  return Stack(children: [
                    if (vertical)
                      Positioned(
                          left: 20.5,
                          top: 22,
                          bottom: 22,
                          child: _track(progress, true))
                    else
                      Positioned(
                          left: constraints.maxWidth / 10,
                          right: constraints.maxWidth / 10,
                          top: 20.5,
                          child: _track(progress, false)),
                    if (vertical)
                      Column(children: [
                        for (var i = 0; i < _ranks.length; i++) ...[
                          if (i > 0) const SizedBox(height: 24),
                          _rank(i, progress, true),
                        ],
                      ])
                    else
                      Row(children: [
                        for (var i = 0; i < _ranks.length; i++)
                          Expanded(child: _rank(i, progress, false)),
                      ]),
                  ]);
                });
          }),
          if (!_reduceMotion) ...[
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: () => setState(() {
                _paused = !_paused;
                _updatePlayback();
              }),
              style: TextButton.styleFrom(foregroundColor: _ink),
              icon: Icon(_paused ? Icons.play_arrow : Icons.pause, size: 18),
              label: Text(
                  _paused ? 'Play rank animation' : 'Pause rank animation'),
            ),
          ],
        ],
      );
}
