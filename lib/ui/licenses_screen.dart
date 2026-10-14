import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:narrow_haul/game/services/audio_service.dart';
import 'package:narrow_haul/ui/space_ui.dart';

/// The game's own entries (registered in `main()`), listed before the
/// open-source packages.
const _gameAssets = ['RussoOne', 'Music'];

/// One package and every licence text registered for it.
class LicenseGroup {
  LicenseGroup(this.package);
  final String package;
  final List<List<LicenseParagraph>> texts = [];
}

/// Collects [entries] by package: the game's own assets first, then the
/// packages alphabetically.
List<LicenseGroup> groupLicenses(Iterable<LicenseEntry> entries) {
  final byPackage = <String, LicenseGroup>{};
  for (final entry in entries) {
    final paragraphs = entry.paragraphs.toList();
    for (final p in entry.packages) {
      byPackage.putIfAbsent(p, () => LicenseGroup(p)).texts.add(paragraphs);
    }
  }
  int rank(String p) {
    final i = _gameAssets.indexOf(p);
    return i < 0 ? _gameAssets.length : i;
  }

  return byPackage.values.toList()..sort((a, b) {
    final r = rank(a.package).compareTo(rank(b.package));
    return r != 0
        ? r
        : a.package.toLowerCase().compareTo(b.package.toLowerCase());
  });
}

/// Opens [LicensesScreen] over Settings.
Future<void> openLicenses(BuildContext context) => Navigator.of(context).push(
  PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => const LicensesScreen(),
    transitionsBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  ),
);

/// Open-source licences in the space UI: the packages on the left and the
/// selected text on the right. Narrow screens show one at a time.
class LicensesScreen extends StatefulWidget {
  const LicensesScreen({super.key, this.entries});

  /// Overrides [LicenseRegistry.licenses] (tests).
  final Stream<LicenseEntry>? entries;

  @override
  State<LicensesScreen> createState() => _LicensesScreenState();
}

class _LicensesScreenState extends State<LicensesScreen> {
  static const _wideFrom = 600.0;

  List<LicenseGroup>? _groups;
  int _selected = 0;

  /// A licence was tapped. Only the narrow layout shows it instead of the
  /// list (and steps back to the list first).
  bool _reading = false;

  /// The list and the text side by side (the 12 px side padding excluded).
  bool _wide(BuildContext context) =>
      MediaQuery.sizeOf(context).width - 24 >= _wideFrom;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await (widget.entries ?? LicenseRegistry.licenses).toList();
    if (!mounted) return;
    setState(() => _groups = groupLicenses(entries));
  }

  void _back() {
    if (_reading && !_wide(context)) {
      setState(() => _reading = false);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = _wide(context);
    final inText = _reading && !wide;
    return PopScope(
      canPop: !inText,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _reading = false);
      },
      child: Material(
        color: SpaceColors.bg,
        child: SpaceScreen(
          title: 'Open-source licenses',
          backLabel: inText ? 'Licenses' : 'Settings',
          onBack: _back,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: _body(wide),
          ),
        ),
      ),
    );
  }

  Widget _body(bool wide) {
    final groups = _groups;
    if (groups == null) {
      return Center(
        child: Text(
          'LOADING…',
          style: hudLabel(12, color: SpaceColors.textDim, spacing: 2.4),
        ),
      );
    }
    if (!wide) {
      return _reading
          ? _text(groups[_selected])
          : _list(groups, highlight: false);
    }
    return LayoutBuilder(
      builder: (context, box) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: (box.maxWidth * 0.32).clamp(220.0, 320.0),
            child: _list(groups, highlight: true),
          ),
          const SizedBox(width: 12),
          Expanded(child: _text(groups[_selected])),
        ],
      ),
    );
  }

  Widget _list(List<LicenseGroup> groups, {required bool highlight}) {
    return HoloPanel(
      title: '${groups.length} packages',
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 8),
      child: ListView.builder(
        itemCount: groups.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) return const _Intro();
          final g = groups[i - 1];
          return _PackageRow(
            group: g,
            selected: highlight && _selected == i - 1,
            onTap: () => setState(() {
              _selected = i - 1;
              _reading = true;
            }),
          );
        },
      ),
    );
  }

  Widget _text(LicenseGroup group) {
    final paragraphs = [
      for (final (i, text) in group.texts.indexed) ...[
        if (i > 0) null, // divider between licences of one package
        ...text,
      ],
    ];
    return HoloPanel(
      key: ValueKey(group.package),
      title: group.package,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      child: ListView.builder(
        padding: const EdgeInsets.only(right: 6, bottom: 8),
        itemCount: paragraphs.length,
        itemBuilder: (context, i) {
          final p = paragraphs[i];
          if (p == null) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Container(
                height: 1,
                color: SpaceColors.cyan.withValues(alpha: 0.25),
              ),
            );
          }
          final centred = p.indent == LicenseParagraph.centeredIndent;
          return Padding(
            padding: EdgeInsets.only(
              left: centred ? 0 : 14.0 * p.indent,
              bottom: 8,
            ),
            child: Text(
              p.text,
              textAlign: centred ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: centred ? SpaceColors.cyanBright : Colors.white70,
                fontWeight: centred ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 6, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('NARROW HAUL', style: hudLabel(13, spacing: 2.4)),
        const SizedBox(height: 2),
        const Text(
          '© 2026 zafrk. Built with open-source software. '
          'Thanks to everyone who made these.',
          style: TextStyle(fontSize: 11, height: 1.35, color: Colors.white54),
        ),
      ],
    ),
  );
}

class _PackageRow extends StatelessWidget {
  const _PackageRow({
    required this.group,
    required this.selected,
    required this.onTap,
  });

  final LicenseGroup group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = group.texts.length;
    final own = _gameAssets.contains(group.package);
    final accent = own ? SpaceColors.gold : SpaceColors.cyan;
    return InkWell(
      onTap: () {
        AudioService.playUi(UiSound.select);
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.14) : null,
          border: Border(
            left: BorderSide(
              color: selected ? accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                group.package,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? Colors.white : Colors.white70,
                ),
              ),
            ),
            if (n > 1)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  '$n',
                  style: hudLabel(10, color: SpaceColors.textFaint),
                ),
              ),
            if (own)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text('GAME', style: hudLabel(9, color: accent)),
              ),
          ],
        ),
      ),
    );
  }
}
