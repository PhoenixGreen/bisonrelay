import 'package:bruig/plugin_system/writing_tools/notes/note_target.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// note_targets.dart is how a page says what its note is about.
//
// The awkward shape of the problem is worth stating, because it is what
// decides the design. The notes panel is drawn at the foot of the *content
// area*, in overview.dart, which means it is an ANCESTOR of every page it
// shows notes for -- it wraps the navigator the pages live inside. An
// InheritedWidget is the obvious tool for "what is around me" and it is
// exactly the wrong one here: it carries information down, and this has to
// travel up.
//
// So it goes through a model above both of them instead. A page wraps itself
// in a NoteTargetScope naming its target; the scope pushes that into the
// model; the panel reads the model. One line per page, and pages that say
// nothing simply leave the last thing published to be withdrawn.
//
// The one subtlety is ownership. Flutter builds the incoming route before it
// disposes the outgoing one, so a naive "clear on dispose" would have the old
// page wipe the new page's target a frame after it was set. Each scope
// therefore withdraws only if it is still the one holding the floor.

/// NoteTargetModel is the page the notes panel is currently looking at, or
/// null on a page that has nothing of its own to take notes about.
class NoteTargetModel extends ChangeNotifier {
  NoteTarget? _target;
  Object? _owner;
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// target is what a local note would be about right now.
  NoteTarget? get target => _target;

  /// publish makes [target] the current one, on behalf of [owner].
  void publish(Object owner, NoteTarget target) {
    _owner = owner;
    if (_target == target) return;
    _target = target;
    _scheduleNotify();
  }

  /// withdraw clears the target, but only if [owner] is still the page that
  /// set it. A page being disposed after its replacement has already
  /// published is the normal case, not the exception, and it must not take
  /// the new page's target down with it.
  void withdraw(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    if (_target == null) return;
    _target = null;
    _scheduleNotify();
  }

  /// _scheduleNotify defers to the end of the frame.
  ///
  /// Every caller here is a page's initState or dispose, which run inside a
  /// build. Notifying from there would rebuild listeners mid-build, which
  /// Flutter rightly refuses. Coalesced, so a route change that withdraws one
  /// target and publishes another is one rebuild rather than two.
  void _scheduleNotify() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// NoteTargetScope declares what a page's note is about, for as long as the
/// page is on screen.
///
/// Put it around the page's body. It draws nothing and costs nothing beyond
/// the one model write, and it is safe on a page that may or may not have a
/// target -- pass null and it behaves as though it were not there.
class NoteTargetScope extends StatefulWidget {
  final NoteTarget? target;
  final Widget child;

  const NoteTargetScope({required this.target, required this.child, super.key});

  @override
  State<NoteTargetScope> createState() => _NoteTargetScopeState();
}

class _NoteTargetScopeState extends State<NoteTargetScope> {
  NoteTargetModel? _model;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read here rather than in initState: the provider is not reachable until
    // dependencies are resolved, and a page can be moved between subtrees.
    _model = context.read<NoteTargetModel?>();
    _publish();
  }

  @override
  void didUpdateWidget(covariant NoteTargetScope old) {
    super.didUpdateWidget(old);
    if (old.target != widget.target) _publish();
  }

  void _publish() {
    var target = widget.target;
    if (target == null) {
      _model?.withdraw(this);
    } else {
      _model?.publish(this, target);
    }
  }

  @override
  void dispose() {
    _model?.withdraw(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
