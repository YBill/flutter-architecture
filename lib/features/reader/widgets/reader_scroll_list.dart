import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart'
    show ItemPosition;

/// Explicit navigation may stop scrolling; moving the chapter window must not.
class ReaderItemScrollController {
  _ReaderScrollListState? _state;

  bool get isAttached => _state != null;

  void jumpTo({required int index, double alignment = 0}) {
    _state?._jumpTo(index, alignment);
  }
}

class ReaderItemPositionsListener {
  final itemPositions = ValueNotifier<Iterable<ItemPosition>>([]);

  void dispose() => itemPositions.dispose();
}

/// A lazy, bidirectional list anchored at a text block. The same ScrollPosition
/// survives index changes, preserving both the drag and ballistic activity.
class ReaderScrollList extends StatefulWidget {
  const ReaderScrollList({
    super.key,
    required this.itemCount,
    required this.itemKeys,
    required this.itemBuilder,
    required this.itemScrollController,
    required this.itemPositionsListener,
    required this.initialScrollIndex,
    required this.initialAlignment,
    required this.padding,
    this.onScrollingChanged,
  });

  final int itemCount;
  final List<Object> itemKeys;
  final IndexedWidgetBuilder itemBuilder;
  final ReaderItemScrollController itemScrollController;
  final ReaderItemPositionsListener itemPositionsListener;
  final int initialScrollIndex;
  final double initialAlignment;
  final EdgeInsets padding;
  final ValueChanged<bool>? onScrollingChanged;

  @override
  State<ReaderScrollList> createState() => _ReaderScrollListState();
}

class _ReaderScrollListState extends State<ReaderScrollList> {
  final _centerKey = UniqueKey();
  final _viewportKey = GlobalKey();
  final _items = <_ReaderListItemState>{};
  final _controller = _AnchorScrollController();
  late int _anchor;
  late Object _anchorKey;
  late Map<Object, int> _keyIndexes;
  bool _reportScheduled = false;
  double _reportedPixels = 0;

  @override
  void initState() {
    super.initState();
    _anchor = widget.initialScrollIndex;
    _anchorKey = widget.itemKeys[_anchor];
    _indexKeys();
    widget.itemScrollController._state = this;
    _controller.addListener(_scheduleReport);
    if (widget.initialAlignment != 0) {
      _reanchor(widget.initialAlignment);
    }
  }

  @override
  void didUpdateWidget(covariant ReaderScrollList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemScrollController != widget.itemScrollController) {
      oldWidget.itemScrollController._state = null;
      widget.itemScrollController._state = this;
    }
    if (!identical(widget.itemKeys, oldWidget.itemKeys)) {
      _indexKeys();
      final retained = _keyIndexes[_anchorKey];
      if (retained != null) {
        // Prepending/appending changes flat indexes, not the text at the
        // viewport's center. Keep its coordinates and cached render objects.
        _anchor = retained;
      } else {
        _anchor = widget.initialScrollIndex;
        _anchorKey = widget.itemKeys[_anchor];
        _reanchor(widget.initialAlignment, preserveMotion: true);
      }
    }
  }

  void _indexKeys() {
    _keyIndexes = {
      for (var i = 0; i < widget.itemKeys.length; i++) widget.itemKeys[i]: i,
    };
  }

  int? _leadingIndex(Key key) {
    final index = _keyIndexes[(key as ValueKey<Object>).value];
    return index != null && index < _anchor ? _anchor - index - 1 : null;
  }

  int? _trailingIndex(Key key) {
    final index = _keyIndexes[(key as ValueKey<Object>).value];
    return index != null && index > _anchor ? index - _anchor - 1 : null;
  }

  void _reanchor(double alignment, {bool preserveMotion = false}) =>
      _controller.reanchor(
        alignment,
        _anchor == 0 ? widget.padding.top : 0,
        referencePixels: preserveMotion ? _reportedPixels : null,
      );

  void _jumpTo(int index, double alignment) {
    // Only user-requested jumps (contents, settings, mode changes) cancel motion.
    if (_controller.hasClients) {
      _controller.jumpTo(_controller.offset);
    }
    setState(() {
      _anchor = index.clamp(0, widget.itemCount - 1);
      _anchorKey = widget.itemKeys[_anchor];
      _reanchor(alignment);
    });
  }

  @override
  void dispose() {
    if (widget.itemScrollController._state == this) {
      widget.itemScrollController._state = null;
    }
    _controller.dispose();
    super.dispose();
  }

  void _scheduleReport() {
    if (_reportScheduled) return;
    _reportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportScheduled = false;
      if (!mounted) return;
      final viewport = _viewportKey.currentContext?.findRenderObject();
      if (viewport is! RenderBox || !viewport.hasSize) return;
      final height = viewport.size.height;
      if (height <= 0) return;
      final positions = <ItemPosition>[];
      for (final item in _items) {
        final box = item.context.findRenderObject();
        if (box is! RenderBox || !box.attached || !box.hasSize) continue;
        final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
        final bottom = top + box.size.height;
        if (!top.isFinite || bottom <= 0 || top >= height) continue;
        positions.add(
          ItemPosition(
            index: item.widget.index,
            itemLeadingEdge: top / height,
            itemTrailingEdge: bottom / height,
          ),
        );
      }
      _reportedPixels = _controller.position.pixels;
      widget.itemPositionsListener.itemPositions.value = positions;
    });
  }

  Widget _item(int index) => _ReaderListItem(
    key: ValueKey(widget.itemKeys[index]),
    index: index,
    owner: this,
    child: widget.itemBuilder(context, index),
  );

  @override
  Widget build(BuildContext context) {
    _scheduleReport();
    return SizedBox.expand(
      key: _viewportKey,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) {
            if (notification is ScrollStartNotification) {
              widget.onScrollingChanged?.call(true);
            } else if (notification is ScrollEndNotification) {
              widget.onScrollingChanged?.call(false);
            }
          }
          return false;
        },
        child: CustomScrollView(
          controller: _controller,
          center: _centerKey,
          slivers: [
            if (_anchor > 0)
              SliverPadding(
                padding: EdgeInsets.only(top: widget.padding.top),
                sliver: SliverList.builder(
                  itemCount: _anchor,
                  findChildIndexCallback: _leadingIndex,
                  itemBuilder: (_, index) => _item(_anchor - index - 1),
                ),
              ),
            SliverPadding(
              key: _centerKey,
              padding: EdgeInsets.only(
                top: _anchor == 0 ? widget.padding.top : 0,
                bottom: _anchor == widget.itemCount - 1
                    ? widget.padding.bottom
                    : 0,
              ),
              sliver: SliverList.builder(
                itemCount: 1,
                itemBuilder: (_, _) => _item(_anchor),
              ),
            ),
            if (_anchor < widget.itemCount - 1)
              SliverPadding(
                padding: EdgeInsets.only(bottom: widget.padding.bottom),
                sliver: SliverList.builder(
                  itemCount: widget.itemCount - _anchor - 1,
                  findChildIndexCallback: _trailingIndex,
                  itemBuilder: (_, index) => _item(_anchor + index + 1),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReaderListItem extends StatefulWidget {
  const _ReaderListItem({
    super.key,
    required this.index,
    required this.owner,
    required this.child,
  });

  final int index;
  final _ReaderScrollListState owner;
  final Widget child;

  @override
  State<_ReaderListItem> createState() => _ReaderListItemState();
}

class _ReaderListItemState extends State<_ReaderListItem> {
  @override
  void initState() {
    super.initState();
    widget.owner._items.add(this);
  }

  @override
  void dispose() {
    widget.owner._items.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AnchorScrollController extends ScrollController {
  (double, double, double)? _pendingAnchor;

  void reanchor(
    double alignment,
    double leadingPadding, {
    double? referencePixels,
  }) {
    final anchor = (
      alignment,
      leadingPadding,
      referencePixels ?? (hasClients ? position.pixels : 0.0),
    );
    if (hasClients) {
      (position as _AnchorScrollPosition).pendingAnchor = anchor;
    } else {
      _pendingAnchor = anchor;
    }
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    final position = _AnchorScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
    )..pendingAnchor = _pendingAnchor;
    _pendingAnchor = null;
    return position;
  }
}

class _AnchorScrollPosition extends ScrollPositionWithSingleContext {
  _AnchorScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
  }) : super(keepScrollOffset: false);

  (double, double, double)? pendingAnchor;

  @override
  bool applyViewportDimension(double viewportDimension) {
    final accepted = super.applyViewportDimension(viewportDimension);
    final anchor = pendingAnchor;
    if (anchor != null) {
      pendingAnchor = null;
      // Layout correction preserves the ScrollActivity. jumpTo or replacing
      // the Scrollable here would cancel an in-progress drag or fling.
      // The activity may have advanced since the last painted anchor was
      // reported. Retain that distance as well, rather than losing one frame.
      final advance = pixels - anchor.$3;
      correctBy(anchor.$2 - anchor.$1 * viewportDimension + advance - pixels);
    }
    return accepted;
  }
}
