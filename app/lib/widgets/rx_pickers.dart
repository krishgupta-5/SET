import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:startup_expense_tracker/widgets/rx_ui.dart';

/// Themed replacements for dropdowns and date pickers.
///
/// Both open as bottom sheets (thumb-reachable, consistent on Android and
/// iOS) instead of popovers or dialogs. Selecting an option or a day closes
/// the sheet immediately, so each pick is a single tap.

// ---------------------------------------------------------------------------
// Sheet chrome
// ---------------------------------------------------------------------------

Future<T?> _showRxSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scrollControlled = false,
}) {
  final rx = context.rx;
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: scrollControlled,
    backgroundColor: rx.sheet,
    barrierColor: rx.barrier,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: builder,
  );
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Column(
      children: [
        const SizedBox(height: 10),
        Container(
          width: 36,
          height: 5,
          decoration: BoxDecoration(
            color: rx.textPrimary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(100),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: RxText.navTitle(context).copyWith(fontSize: 19),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Select (dropdown replacement)
// ---------------------------------------------------------------------------

/// One choice in a select sheet.
class RxOption<T> {
  const RxOption(this.value, this.label, {this.icon, this.subtitle});

  final T value;
  final String label;
  final List<List<dynamic>>? icon;
  final String? subtitle;
}

/// Opens a themed option sheet and returns the picked value (null if
/// dismissed). A search field appears automatically for long lists.
Future<T?> showRxSelectSheet<T>(
  BuildContext context, {
  required String title,
  required List<RxOption<T>> options,
  T? selected,
  bool? searchable,
}) {
  return _showRxSheet<T>(
    context,
    scrollControlled: true,
    builder: (_) => _SelectSheet<T>(
      title: title,
      options: options,
      selected: selected,
      searchable: searchable ?? options.length > 8,
    ),
  );
}

class _SelectSheet<T> extends StatefulWidget {
  const _SelectSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.searchable,
  });

  final String title;
  final List<RxOption<T>> options;
  final T? selected;
  final bool searchable;

  @override
  State<_SelectSheet<T>> createState() => _SelectSheetState<T>();
}

class _SelectSheetState<T> extends State<_SelectSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? widget.options
        : widget.options
              .where((o) => o.label.toLowerCase().contains(q))
              .toList();
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetHeader(title: widget.title),
            if (widget.searchable)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: RxSearchField(
                  hint: 'Search',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            Flexible(
              child: visible.isEmpty
                  ? const RxEmptyState(
                      icon: HugeIcons.strokeRoundedSearch01,
                      title: 'No matches',
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.fromLTRB(
                        12,
                        0,
                        12,
                        16 + MediaQuery.paddingOf(context).bottom,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final o = visible[i];
                        final isSel = o.value == widget.selected;
                        return Semantics(
                          selected: isSel,
                          button: true,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              splashFactory: NoSplash.splashFactory,
                              highlightColor: rx.surfaceMuted,
                              onTap: () => Navigator.pop(context, o.value),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isSel ? rx.surface : null,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: isSel ? rx.cardShadow : null,
                                ),
                                child: Row(
                                  children: [
                                    if (o.icon != null) ...[
                                      RxIconTile(
                                        icon: o.icon!,
                                        size: 34,
                                        iconSize: 17,
                                      ),
                                      const SizedBox(width: 12),
                                    ],
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            o.label,
                                            style: RxText.body(context)
                                                .copyWith(
                                                  fontWeight: isSel
                                                      ? FontWeight.w600
                                                      : FontWeight.w500,
                                                ),
                                          ),
                                          if (o.subtitle != null)
                                            Text(
                                              o.subtitle!,
                                              style: RxText.caption(context),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (isSel)
                                      HugeIcon(
                                        icon: HugeIcons.strokeRoundedTick02,
                                        color: rx.textPrimary,
                                        size: 20,
                                        strokeWidth: 2.2,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Field that looks like an input and opens [showRxSelectSheet].
class RxSelectField<T> extends StatelessWidget {
  const RxSelectField({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.icon,
    this.sheetTitle,
  });

  final String? label;
  final List<RxOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String? placeholder;
  final List<List<dynamic>>? icon;
  final String? sheetTitle;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    RxOption<T>? current;
    for (final o in options) {
      if (o.value == value) current = o;
    }

    return _FieldShell(
      label: label,
      icon: icon ?? current?.icon,
      text: current?.label,
      placeholder: placeholder ?? 'Select',
      trailing: HugeIcon(
        icon: HugeIcons.strokeRoundedArrowDown01,
        color: rx.textSecondary,
        size: 18,
        strokeWidth: 1.9,
      ),
      onTap: () async {
        FocusScope.of(context).unfocus();
        final picked = await showRxSelectSheet<T>(
          context,
          title: sheetTitle ?? label ?? 'Select',
          options: options,
          selected: value,
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Date picker
// ---------------------------------------------------------------------------

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _monthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "24 Oct 2026".
String rxFormatDate(DateTime d) =>
    '${d.day} ${_monthShort[d.month - 1]} ${d.year}';

/// Opens a themed calendar sheet. Returns the picked day, or null if
/// dismissed. Pass [onClear] to show a "Clear" action (closes and calls it).
Future<DateTime?> showRxDatePicker(
  BuildContext context, {
  DateTime? initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  String title = 'Select date',
  VoidCallback? onClear,
}) {
  final now = DateTime.now();
  return _showRxSheet<DateTime>(
    context,
    scrollControlled: true,
    builder: (_) => _DateSheet(
      title: title,
      initial: initialDate,
      first: firstDate ?? DateTime(now.year - 5),
      last: lastDate ?? DateTime(now.year + 5, 12, 31),
      onClear: onClear,
    ),
  );
}

class _DateSheet extends StatefulWidget {
  const _DateSheet({
    required this.title,
    required this.initial,
    required this.first,
    required this.last,
    required this.onClear,
  });

  final String title;
  final DateTime? initial;
  final DateTime first;
  final DateTime last;
  final VoidCallback? onClear;

  @override
  State<_DateSheet> createState() => _DateSheetState();
}

class _DateSheetState extends State<_DateSheet> {
  late DateTime _month;
  bool _pickingYear = false;

  @override
  void initState() {
    super.initState();
    final base = widget.initial ?? DateTime.now();
    _month = DateTime(base.year, base.month);
  }

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _inRange(DateTime d) =>
      !_day(d).isBefore(_day(widget.first)) &&
      !_day(d).isAfter(_day(widget.last));

  bool get _canPrev => DateTime(
    _month.year,
    _month.month,
  ).isAfter(DateTime(widget.first.year, widget.first.month));
  bool get _canNext => DateTime(
    _month.year,
    _month.month,
  ).isBefore(DateTime(widget.last.year, widget.last.month));

  void _shift(int months) {
    setState(() => _month = DateTime(_month.year, _month.month + months));
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final today = _day(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));

    return Padding(
      padding: EdgeInsets.only(
        bottom: 16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetHeader(
            title: widget.title,
            trailing: widget.onClear == null
                ? null
                : TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onClear!();
                    },
                    child: Text(
                      'Clear',
                      style: RxText.body(
                        context,
                        color: rx.negative,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
          ),
          // Quick picks for the two most common answers.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                for (final (label, d) in [
                  ('Today', today),
                  ('Yesterday', yesterday),
                ])
                  if (_inRange(d))
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _Chip(
                        label: label,
                        selected:
                            widget.initial != null &&
                            _day(widget.initial!) == d,
                        onTap: () => Navigator.pop(context, d),
                      ),
                    ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: RxCard(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () =>
                                setState(() => _pickingYear = !_pickingYear),
                            style: TextButton.styleFrom(
                              foregroundColor: rx.textPrimary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${_monthNames[_month.month - 1]} ${_month.year}',
                                  style: RxText.heading(context),
                                ),
                                const SizedBox(width: 4),
                                HugeIcon(
                                  icon: _pickingYear
                                      ? HugeIcons.strokeRoundedArrowUp01
                                      : HugeIcons.strokeRoundedArrowDown01,
                                  color: rx.textSecondary,
                                  size: 16,
                                  strokeWidth: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (!_pickingYear) ...[
                        _NavButton(
                          icon: HugeIcons.strokeRoundedArrowLeft01,
                          label: 'Previous month',
                          onTap: _canPrev ? () => _shift(-1) : null,
                        ),
                        _NavButton(
                          icon: HugeIcons.strokeRoundedArrowRight01,
                          label: 'Next month',
                          onTap: _canNext ? () => _shift(1) : null,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 6 * 44 + 22,
                    child: _pickingYear ? _buildYears() : _buildGrid(today),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYears() {
    final rx = context.rx;
    final years = [
      for (var y = widget.first.year; y <= widget.last.year; y++) y,
    ];
    return GridView.count(
      crossAxisCount: 4,
      childAspectRatio: 2,
      padding: const EdgeInsets.only(top: 4),
      children: [
        for (final y in years)
          Padding(
            padding: const EdgeInsets.all(4),
            child: Material(
              color: y == _month.year ? rx.inverse : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() {
                  _month = DateTime(y, _month.month);
                  _pickingYear = false;
                }),
                child: Center(
                  child: Text(
                    '$y',
                    style: RxText.body(
                      context,
                      color: y == _month.year ? rx.onInverse : rx.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGrid(DateTime today) {
    final rx = context.rx;
    final firstOfMonth = DateTime(_month.year, _month.month, 1);
    // Monday-first week.
    final lead = (firstOfMonth.weekday + 6) % 7;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final selected = widget.initial == null ? null : _day(widget.initial!);

    return Column(
      children: [
        SizedBox(
          height: 22,
          child: Row(
            children: [
              for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(
                  child: Center(child: Text(d, style: RxText.micro(context))),
                ),
            ],
          ),
        ),
        for (var week = 0; week < 6; week++)
          SizedBox(
            height: 44,
            child: Row(
              children: [
                for (var wd = 0; wd < 7; wd++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final dayNum = week * 7 + wd - lead + 1;
                        if (dayNum < 1 || dayNum > daysInMonth) {
                          return const SizedBox.shrink();
                        }
                        final date = DateTime(
                          _month.year,
                          _month.month,
                          dayNum,
                        );
                        final enabled = _inRange(date);
                        final isSel = selected == date;
                        final isToday = today == date;
                        return Semantics(
                          button: enabled,
                          selected: isSel,
                          label: rxFormatDate(date),
                          excludeSemantics: true,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: enabled
                                ? () => Navigator.pop(context, date)
                                : null,
                            child: Center(
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSel ? rx.inverse : null,
                                  border: isToday && !isSel
                                      ? Border.all(
                                          color: rx.textPrimary.withValues(
                                            alpha: 0.35,
                                          ),
                                        )
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '$dayNum',
                                  style:
                                      RxText.body(
                                        context,
                                        color: isSel
                                            ? rx.onInverse
                                            : enabled
                                            ? rx.textPrimary
                                            : rx.textTertiary.withValues(
                                                alpha: 0.5,
                                              ),
                                      ).copyWith(
                                        fontWeight: isSel || isToday
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.label, this.onTap});

  final List<List<dynamic>> icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return IconButton(
      onPressed: onTap,
      tooltip: label,
      icon: HugeIcon(
        icon: icon,
        color: onTap == null
            ? rx.textTertiary.withValues(alpha: 0.4)
            : rx.textPrimary,
        size: 20,
        strokeWidth: 1.9,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return RxPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? rx.inverse : rx.surface,
          borderRadius: BorderRadius.circular(100),
          boxShadow: selected ? null : rx.cardShadow,
        ),
        child: Text(
          label,
          style: RxText.label(
            context,
            color: selected ? rx.onInverse : rx.textPrimary,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Field that looks like an input and opens [showRxDatePicker].
class RxDateField extends StatelessWidget {
  const RxDateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.placeholder = 'Select date',
    this.firstDate,
    this.lastDate,
  });

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final String? label;
  final String placeholder;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return _FieldShell(
      label: label,
      icon: HugeIcons.strokeRoundedCalendar03,
      text: value == null ? null : rxFormatDate(value!),
      placeholder: placeholder,
      trailing: HugeIcon(
        icon: HugeIcons.strokeRoundedArrowDown01,
        color: rx.textSecondary,
        size: 18,
        strokeWidth: 1.9,
      ),
      onTap: () async {
        FocusScope.of(context).unfocus();
        final picked = await showRxDatePicker(
          context,
          initialDate: value,
          firstDate: firstDate,
          lastDate: lastDate,
          title: label ?? 'Select date',
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Shared field look
// ---------------------------------------------------------------------------

class _FieldShell extends StatelessWidget {
  const _FieldShell({
    required this.label,
    required this.icon,
    required this.text,
    required this.placeholder,
    required this.trailing,
    required this.onTap,
  });

  final String? label;
  final List<List<dynamic>>? icon;
  final String? text;
  final String placeholder;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final field = RxPressable(
      onTap: onTap,
      scale: 0.99,
      semanticLabel: '${label ?? placeholder}: ${text ?? 'not set'}',
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: rx.surface,
          borderRadius: BorderRadius.circular(14),
          // Inputs keep a visible boundary (3:1 non-text contrast).
          border: Border.all(color: rx.textPrimary.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              HugeIcon(
                icon: icon!,
                color: rx.textSecondary,
                size: 19,
                strokeWidth: 1.7,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                text ?? placeholder,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RxText.body(
                  context,
                  color: text == null ? rx.textTertiary : rx.textPrimary,
                ).copyWith(fontWeight: text == null ? FontWeight.w400 : null),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );

    if (label == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label!,
            style: RxText.label(context).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        field,
      ],
    );
  }
}

/// Rounded search input used in sheets and the search screen.
class RxSearchField extends StatelessWidget {
  const RxSearchField({
    super.key,
    required this.onChanged,
    this.hint = 'Search',
    this.controller,
    this.autofocus = false,
  });

  final ValueChanged<String> onChanged;
  final String hint;
  final TextEditingController? controller;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: rx.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedSearch01,
            color: rx.textSecondary,
            size: 18,
            strokeWidth: 1.8,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              onChanged: onChanged,
              cursorColor: rx.textPrimary,
              style: RxText.body(context).copyWith(fontWeight: FontWeight.w400),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: RxText.body(
                  context,
                  color: rx.textTertiary,
                ).copyWith(fontWeight: FontWeight.w400),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action sheet
// ---------------------------------------------------------------------------

/// One row in [showRxActionSheet].
class RxSheetAction {
  const RxSheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
  });

  final List<List<dynamic>> icon;
  final String label;
  final String? subtitle;
  final bool destructive;

  /// Runs after the sheet has closed.
  final VoidCallback onTap;
}

/// Compact list of actions in a themed bottom sheet, sized to its content.
Future<void> showRxActionSheet(
  BuildContext context, {
  required String title,
  required List<RxSheetAction> actions,
}) async {
  RxSheetAction? picked;
  await _showRxSheet<void>(
    context,
    builder: (sheetContext) {
      final rx = sheetContext.rx;
      return Padding(
        padding: EdgeInsets.only(
          bottom: 12 + MediaQuery.paddingOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetHeader(title: title),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: RxCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const RxDivider(indent: 64),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          splashFactory: NoSplash.splashFactory,
                          highlightColor: rx.surfaceMuted,
                          onTap: () {
                            picked = actions[i];
                            Navigator.pop(sheetContext);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                RxIconTile(
                                  icon: actions[i].icon,
                                  size: 38,
                                  iconSize: 19,
                                  background: actions[i].destructive
                                      ? rx.negativeSoft
                                      : rx.surfaceMuted,
                                  foreground: actions[i].destructive
                                      ? rx.negative
                                      : rx.textPrimary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        actions[i].label,
                                        style: RxText.body(
                                          sheetContext,
                                          color: actions[i].destructive
                                              ? rx.negative
                                              : rx.textPrimary,
                                        ),
                                      ),
                                      if (actions[i].subtitle != null)
                                        Text(
                                          actions[i].subtitle!,
                                          style: RxText.caption(sheetContext),
                                        ),
                                    ],
                                  ),
                                ),
                                HugeIcon(
                                  icon: HugeIcons.strokeRoundedArrowRight01,
                                  color: rx.textTertiary,
                                  size: 18,
                                  strokeWidth: 1.8,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  picked?.onTap();
}
