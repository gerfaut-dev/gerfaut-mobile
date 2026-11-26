import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'focus_ring.dart';

/// One option of a [ChoiceGroup].
class ChoiceOption<T> {
  const ChoiceOption({
    required this.value,
    required this.label,
    this.icon,
    this.enabled = true,
  });

  final T value;
  final String label;

  /// A glyph before the label, decorative: the label carries the sense.
  final IconData? icon;

  /// An option that cannot apply here: quiet, and out of reach.
  final bool enabled;
}

/// The one way to pick between a handful of options in Gerfaut, in the
/// form the room allows.
///
/// Where every label fits its share of the width, the options sit side
/// by side on one sunken track, and the fill of the current one slides
/// to the option picked: a choice among two or three short words is
/// read at a glance, and does not cost the page a tall block per word.
///
/// Where one does not fit, a narrow phone or a large text size, each
/// option takes a full-width row of its own, stacked, with a real gap
/// between them: rows that touch read as one block of colour, and
/// adjacent touch targets need space of their own to be aimed at.
///
/// Either way an option answers the finger over a whole touch target,
/// and every choice in the app goes through here so none of them can
/// drift. The form is decided where the width is known, at layout, so
/// the group sits anywhere a box does: in a card, in a sheet, in a
/// form that sizes itself to its content.
class ChoiceGroup<T> extends StatefulWidget {
  const ChoiceGroup({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  /// What the group selects, announced around the options.
  final String label;
  final T value;
  final List<ChoiceOption<T>> options;

  /// Called with the option picked, even when it is the current one.
  final ValueChanged<T> onChanged;

  @override
  State<ChoiceGroup<T>> createState() => _ChoiceGroupState<T>();
}

class _ChoiceGroupState<T> extends State<ChoiceGroup<T>>
    with SingleTickerProviderStateMixin {
  /// Where the fill stands, in options: 1.5 is halfway between the
  /// second and the third.
  late final AnimationController _fill = AnimationController.unbounded(
    vsync: this,
    value: math.max(_current, 0).toDouble(),
  );

  /// The option the fill is at, or on its way to.
  int _target = -1;

  /// The option under the finger, if any.
  int? _pressed;

  /// The option under a pointer that hovers, if any.
  int? _hovered;

  /// The form the options took at their last layout: side by side.
  bool _inline = false;

  int get _current =>
      widget.options.indexWhere((option) => option.value == widget.value);

  @override
  void initState() {
    super.initState();
    _target = _current;
  }

  @override
  void didUpdateWidget(ChoiceGroup<T> old) {
    super.didUpdateWidget(old);
    // A press does not outlive its option: one that went away, or that
    // can no longer be picked, never reports the finger leaving.
    if (!_reachable(_pressed)) _pressed = null;
    if (!_reachable(_hovered)) _hovered = null;
    final current = _current;
    if (current == _target) return;
    final wasEmpty = _target < 0;
    _target = current;
    if (current < 0) return;
    // The fill travels to the option picked. It appears in place under
    // a first choice, for whoever asked for less motion, and between
    // stacked rows, where it would have to cross the gap.
    if (wasEmpty || !_inline || MediaQuery.disableAnimationsOf(context)) {
      _fill.value = current.toDouble();
    } else {
      _fill.animateTo(
        current.toDouble(),
        duration: GerfautMotion.base,
        curve: GerfautMotion.ease,
      );
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  void _pick(T picked) {
    // A tick under the finger for a choice that changes, as a detent
    // would give; none for a tap on what is already chosen.
    if (picked != widget.value) HapticFeedback.selectionClick();
    widget.onChanged(picked);
  }

  /// Whether [index] is still an option that can be picked.
  bool _reachable(int? index) =>
      index == null ||
      (index < widget.options.length && widget.options[index].enabled);

  void _press(int index, bool down) {
    final pressed = down ? index : (_pressed == index ? null : _pressed);
    if (pressed != _pressed) setState(() => _pressed = pressed);
  }

  void _hover(int index, bool over) {
    final hovered = over ? index : (_hovered == index ? null : _hovered);
    if (hovered != _hovered) setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final current = _current;
    return Semantics(
      container: true,
      label: widget.label,
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: _fill,
          builder: (context, _) => _ChoiceLayout(
            current: current,
            fillAt: current < 0 ? null : _fill.value,
            pressed: _pressed,
            hovered: _hovered,
            track: tokens.surfaceSunken,
            fill: tokens.primary,
            pressedTint: tokens.pressed,
            hoveredTint: tokens.hovered,
            textDirection: Directionality.of(context),
            onForm: (inline) => _inline = inline,
            children: [
              for (final (index, option) in widget.options.indexed)
                _Option<T>(
                  option: option,
                  selected: index == current,
                  // How much of the option the fill covers: its ink
                  // turns with the fill over it, never ahead of it.
                  covered: current < 0
                      ? 0
                      : (1 - (_fill.value - index).abs()).clamp(0, 1),
                  onTap: option.enabled ? () => _pick(option.value) : null,
                  onPress: (down) => _press(index, down),
                  onHover: (over) => _hover(index, over),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The glyph before a label.
const double _glyph = 16;

/// Inside an option, on each side of its label.
const double _padding = GerfautSpacing.gutter;

/// One option: its label, and a whole touch target to press. What is
/// under it, the track or a row of its own, the fill when it is the
/// current one, is drawn by the group, which knows the form.
class _Option<T> extends StatelessWidget {
  const _Option({
    required this.option,
    required this.selected,
    required this.covered,
    required this.onTap,
    required this.onPress,
    required this.onHover,
  });

  final ChoiceOption<T> option;
  final bool selected;

  /// How much of the option the fill covers, from 0 to 1.
  final double covered;
  final VoidCallback? onTap;

  /// A finger went down on the option, or left it.
  final ValueChanged<bool> onPress;

  /// A pointer came over the option, or left it.
  final ValueChanged<bool> onHover;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<GerfautTokens>()!;
    final ink = Color.lerp(
      option.enabled ? tokens.text : tokens.textMuted,
      tokens.onPrimary,
      covered,
    )!;
    final style = tokens.bodySmall.copyWith(
      fontWeight: FontWeight.w500,
      fontVariations: const [FontVariation('wght', 500)],
    );
    return Semantics(
      container: true,
      button: true,
      inMutuallyExclusiveGroup: true,
      enabled: option.enabled,
      selected: selected,
      label: option.label,
      onTap: onTap,
      excludeSemantics: true,
      // The ring just inside the option's edge: its neighbours touch
      // it, or a scroll view would cut a ring drawn outside.
      child: FocusRing(
        gap: 0,
        child: InkWell(
          // The group draws what a press looks like, under the label.
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          onHighlightChanged: onTap == null ? null : onPress,
          onHover: onTap == null ? null : onHover,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _padding),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (option.icon != null) ...[
                    Icon(option.icon, size: _glyph, color: ink),
                    const SizedBox(width: GerfautSpacing.sm),
                  ],
                  Flexible(
                    child: Text(
                      option.label,
                      style: style.copyWith(color: ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
}

/// Lays the options out side by side or stacked, and draws what they
/// stand on.
class _ChoiceLayout extends MultiChildRenderObjectWidget {
  const _ChoiceLayout({
    required this.current,
    required this.fillAt,
    required this.pressed,
    required this.hovered,
    required this.track,
    required this.fill,
    required this.pressedTint,
    required this.hoveredTint,
    required this.textDirection,
    required this.onForm,
    required super.children,
  });

  /// The option chosen, or -1.
  final int current;

  /// Where the fill is drawn, in options; null with nothing chosen.
  final double? fillAt;
  final int? pressed;
  final int? hovered;
  final Color track;
  final Color fill;
  final Color pressedTint;
  final Color hoveredTint;
  final TextDirection textDirection;

  /// Told at each layout which form the options took: side by side,
  /// or stacked.
  final ValueChanged<bool> onForm;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderChoiceLayout()
    ..current = current
    ..fillAt = fillAt
    ..pressed = pressed
    ..hovered = hovered
    ..track = track
    ..fill = fill
    ..pressedTint = pressedTint
    ..hoveredTint = hoveredTint
    ..textDirection = textDirection
    ..onForm = onForm;

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderChoiceLayout renderObject,
  ) {
    renderObject
      ..current = current
      ..fillAt = fillAt
      ..pressed = pressed
      ..hovered = hovered
      ..track = track
      ..fill = fill
      ..pressedTint = pressedTint
      ..hoveredTint = hoveredTint
      ..textDirection = textDirection
      ..onForm = onForm;
  }
}

class _ChoiceParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderChoiceLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ChoiceParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ChoiceParentData> {
  /// How tall an option answers the finger.
  static const double _row = GerfautTouch.target;

  /// What a row is taller than what is drawn in it, above and below.
  static const double _margin =
      (GerfautTouch.target - GerfautTouch.control) / 2;

  /// Between two stacked rows, on top of their margins: drawn 8 apart.
  static const double _gap = GerfautSpacing.xs;

  /// Between the edge of the track and the fill. With the fill's
  /// radius, the corners are concentric: 6 inside 8.
  static const double _inset = 2;

  int _current = -1;
  set current(int value) {
    if (value == _current) return;
    _current = value;
    markNeedsPaint();
  }

  double? _fillAt;
  set fillAt(double? value) {
    if (value == _fillAt) return;
    _fillAt = value;
    markNeedsPaint();
  }

  int? _pressed;
  set pressed(int? value) {
    if (value == _pressed) return;
    _pressed = value;
    markNeedsPaint();
  }

  Color _track = const Color(0x00000000);
  set track(Color value) {
    if (value == _track) return;
    _track = value;
    markNeedsPaint();
  }

  Color _fill = const Color(0x00000000);
  set fill(Color value) {
    if (value == _fill) return;
    _fill = value;
    markNeedsPaint();
  }

  Color _pressedTint = const Color(0x00000000);
  set pressedTint(Color value) {
    if (value == _pressedTint) return;
    _pressedTint = value;
    markNeedsPaint();
  }

  int? _hovered;
  set hovered(int? value) {
    if (value == _hovered) return;
    _hovered = value;
    markNeedsPaint();
  }

  Color _hoveredTint = const Color(0x00000000);
  set hoveredTint(Color value) {
    if (value == _hoveredTint) return;
    _hoveredTint = value;
    markNeedsPaint();
  }

  /// Side by side, the options follow the reading direction.
  TextDirection _textDirection = TextDirection.ltr;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  ValueChanged<bool>? onForm;

  /// Set at layout: the options share one line.
  bool _inline = false;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ChoiceParentData) {
      child.parentData = _ChoiceParentData();
    }
  }

  /// The widest an option wants to be, its padding included.
  double _widest() {
    var widest = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      widest = math.max(widest, child.getMaxIntrinsicWidth(double.infinity));
    }
    return widest;
  }

  /// Whether every option fits its share of [width] on one line. A
  /// pixel to spare: a label measured a hair short of its paint would
  /// lose its last glyph.
  bool _fits(double width) {
    if (!width.isFinite || childCount < 2) return false;
    // The width the group asks for itself must fit, to the rounding.
    return _widest() <=
        (width - _inset * 2) / childCount - 1 + precisionErrorTolerance;
  }

  double get _stackedHeight =>
      math.max(0, childCount * _row + (childCount - 1) * _gap);

  @override
  double computeMinIntrinsicWidth(double height) {
    var widest = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      widest = math.max(widest, child.getMinIntrinsicWidth(double.infinity));
    }
    return widest;
  }

  @override
  double computeMaxIntrinsicWidth(double height) =>
      childCount * (_widest() + 1) + _inset * 2;

  @override
  double computeMinIntrinsicHeight(double width) =>
      _fits(width) ? _row : _stackedHeight;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  double _widthFor(BoxConstraints constraints) => constraints.hasBoundedWidth
      ? constraints.maxWidth
      : constraints.constrainWidth(_widest());

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = _widthFor(constraints);
    return constraints.constrain(
      Size(width, _fits(width) ? _row : _stackedHeight),
    );
  }

  @override
  void performLayout() {
    final width = _widthFor(constraints);
    _inline = _fits(width);
    final share = _inline ? (width - _inset * 2) / childCount : width;
    var index = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      child.layout(BoxConstraints.tightFor(width: share, height: _row));
      (child.parentData! as _ChoiceParentData).offset = _inline
          ? Offset(_left(index.toDouble(), share, width), 0)
          : Offset(0, index * (_row + _gap));
      index++;
    }
    size = constraints.constrain(Size(width, _inline ? _row : _stackedHeight));
    onForm?.call(_inline);
  }

  /// Where the option at [at] starts on a track [width] wide, each
  /// option [share] wide: from the left, or from the right for a
  /// script read that way.
  double _left(double at, double share, double width) =>
      _textDirection == TextDirection.rtl
      ? width - _inset - (at + 1) * share
      : _inset + at * share;

  /// What is drawn of the option at [at], which may stand between two
  /// while the fill travels: the fill's own box on the track, the whole
  /// row when stacked.
  RRect _box(double at) {
    if (_inline) {
      final share = (size.width - _inset * 2) / childCount;
      final left = _left(at, share, size.width);
      return RRect.fromLTRBR(
        left,
        _margin + _inset,
        left + share,
        _row - _margin - _inset,
        const Radius.circular(GerfautRadius.md - _inset),
      );
    }
    final top = at * (_row + _gap);
    return RRect.fromLTRBR(
      0,
      top + _margin,
      size.width,
      top + _row - _margin,
      const Radius.circular(GerfautRadius.md),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final paint = Paint();
    if (_inline) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          0,
          _margin,
          size.width,
          _row - _margin,
          const Radius.circular(GerfautRadius.md),
        ).shift(offset),
        paint..color = _track,
      );
    } else {
      for (var index = 0; index < childCount; index++) {
        if (index == _current) continue;
        canvas.drawRRect(
          _box(index.toDouble()).shift(offset),
          paint..color = _track,
        );
      }
    }
    final pressed = _pressed;
    final hovered = _hovered;
    if (pressed != null && pressed != _current) {
      canvas.drawRRect(
        _box(pressed.toDouble()).shift(offset),
        paint..color = _pressedTint,
      );
    } else if (hovered != null && hovered != _current) {
      canvas.drawRRect(
        _box(hovered.toDouble()).shift(offset),
        paint..color = _hoveredTint,
      );
    }
    final fillAt = _fillAt;
    if (fillAt != null) {
      // Side by side the fill slides along the track. Stacked it would
      // have to cross the gap between two rows: it goes straight to
      // the row chosen.
      final at = _inline ? fillAt : _current.toDouble();
      canvas.drawRRect(_box(at).shift(offset), paint..color = _fill);
    }
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
