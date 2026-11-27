import 'package:material_ui/material_ui.dart';

import 'package:nhasixapp/presentation/widgets/kuron_fx.dart';
import 'package:nhasixapp/presentation/widgets/kuron_squash.dart';

/// Checkbox with the [KuronFxKind.checkboxTick] burst on check.
///
/// Wraps the Material [Checkbox] in a [KuronSquash] for press feel. The FX is
/// anchored on the box itself through an internal [GlobalKey] (overridable
/// via [checkboxKey] so a [KuronCheckboxListTile] can share the anchor).
/// Checking fires the burst; unchecking mounts nothing — the state change is
/// the message. Quiet mode / reduced motion suppress the burst through the
/// shared [KuronFx.triggerOn] gate; the value still toggles.
class KuronCheckbox extends StatefulWidget {
  const KuronCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.tristate = false,
    this.isReader = false,
    this.activeColor,
    this.checkColor,
    this.side,
    this.shape,
    this.checkboxKey,
  });

  final bool? value;
  final ValueChanged<bool?> onChanged;

  /// Mirrors [Checkbox.tristate].
  final bool tristate;

  /// Reader surfaces stay hard-off even when the stored mode is not quiet.
  final bool isReader;

  final Color? activeColor;
  final Color? checkColor;
  final BorderSide? side;
  final OutlinedBorder? shape;

  /// External anchor for the FX rect. When null the state owns its own key.
  final GlobalKey? checkboxKey;

  @override
  State<KuronCheckbox> createState() => _KuronCheckboxState();
}

class _KuronCheckboxState extends State<KuronCheckbox> {
  final GlobalKey _ownKey = GlobalKey();

  GlobalKey get _key => widget.checkboxKey ?? _ownKey;

  void _handleChanged(bool? next) {
    if (next == true) {
      final boxContext = _key.currentContext;
      final rect = boxContext == null
          ? KuronFx.targetRectOf(context)
          : KuronFx.targetRectOf(boxContext);
      if (rect != null) {
        KuronFx.triggerOn(
          context,
          rect: rect,
          kind: KuronFxKind.checkboxTick,
          isReader: widget.isReader,
        );
      }
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) => KuronSquash(
    child: Checkbox(
      key: _key,
      value: widget.value,
      tristate: widget.tristate,
      onChanged: _handleChanged,
      activeColor: widget.activeColor,
      checkColor: widget.checkColor,
      side: widget.side,
      shape: widget.shape,
    ),
  );
}

/// [ListTile] with a [KuronCheckbox] in the trailing (or leading) slot.
///
/// Tapping the tile toggles the value and fires the same checkbox-anchored
/// burst as tapping the box itself; unchecking mounts nothing.
class KuronCheckboxListTile extends StatefulWidget {
  const KuronCheckboxListTile({
    super.key,
    this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.controlAffinity = ListTileControlAffinity.platform,
    this.isReader = false,
    this.activeColor,
    this.checkColor,
  });

  final Widget? title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Defaults to [ListTileControlAffinity.platform] (trailing on Android).
  final ListTileControlAffinity controlAffinity;

  /// Reader surfaces stay hard-off even when the stored mode is not quiet.
  final bool isReader;

  final Color? activeColor;
  final Color? checkColor;

  @override
  State<KuronCheckboxListTile> createState() => _KuronCheckboxListTileState();
}

class _KuronCheckboxListTileState extends State<KuronCheckboxListTile> {
  final GlobalKey _checkKey = GlobalKey();

  void _fireTick() {
    final boxContext = _checkKey.currentContext;
    final rect = boxContext == null ? null : KuronFx.targetRectOf(boxContext);
    if (rect != null) {
      KuronFx.triggerOn(
        context,
        rect: rect,
        kind: KuronFxKind.checkboxTick,
        isReader: widget.isReader,
      );
    }
  }

  void _toggle() {
    final next = !widget.value;
    if (next) _fireTick();
    widget.onChanged(next);
  }

  void _handleBoxChanged(bool? next) {
    // The box already fired its own anchored burst when checking; the tile
    // only forwards the value so a direct box tap never double-fires.
    widget.onChanged(next ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final checkbox = KuronCheckbox(
      checkboxKey: _checkKey,
      value: widget.value,
      onChanged: _handleBoxChanged,
      isReader: widget.isReader,
      activeColor: widget.activeColor,
      checkColor: widget.checkColor,
    );
    return ListTile(
      title: widget.title,
      subtitle: widget.subtitle,
      leading: widget.controlAffinity == ListTileControlAffinity.leading
          ? checkbox
          : null,
      trailing: widget.controlAffinity == ListTileControlAffinity.leading
          ? null
          : checkbox,
      onTap: _toggle,
    );
  }
}
