import 'package:flutter/material.dart';
import '../../core/theme/wildlifescout_theme.dart';
import '../../domain/models/species_profile.dart';

class SpeciesMultiSelectSheet extends StatefulWidget {
  final List<SpeciesProfile> allSpecies;
  final Set<String> initialSelectedIds;
  final ValueChanged<Set<String>> onSelectionChanged;
  final ValueChanged<SpeciesProfile> onInspectSpecies;

  const SpeciesMultiSelectSheet({
    super.key,
    required this.allSpecies,
    required this.initialSelectedIds,
    required this.onSelectionChanged,
    required this.onInspectSpecies,
  });

  @override
  State<SpeciesMultiSelectSheet> createState() =>
      _SpeciesMultiSelectSheetState();
}

class _SpeciesMultiSelectSheetState extends State<SpeciesMultiSelectSheet> {
  late Set<String> _selectedIds;
  final Set<String> _expandedSpeciesIds = <String>{};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.initialSelectedIds);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSpecies(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        // Mindestens 1 Art bleibt aktiv (Rehwild als Fallback)
        if (_selectedIds.length > 1) {
          _selectedIds.remove(id);
        }
      } else {
        _selectedIds.add(id);
      }
    });
    widget.onSelectionChanged(Set<String>.from(_selectedIds));
  }

  void _toggleExpanded(String id) {
    setState(() {
      if (_expandedSpeciesIds.contains(id)) {
        _expandedSpeciesIds.remove(id);
      } else {
        _expandedSpeciesIds.add(id);
      }
    });
  }

  void _resetToRoeDeerOnly() {
    setState(() {
      _selectedIds = {'roe_deer'};
    });
    widget.onSelectionChanged({'roe_deer'});
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
    });
  }

  List<SpeciesProfile> get _filteredSpecies {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return widget.allSpecies;

    final results = widget.allSpecies.where((sp) {
      final nameMatches = sp.name.toLowerCase().contains(query);
      final categoryMatches = sp.category.label.toLowerCase().contains(query);
      final scientificMatches =
          sp.scientificName.toLowerCase().contains(query);

      // Bei kurzen Eingaben (1-2 Zeichen) nur Name, Kategorie & wissenschaftl. Bezeichnung
      if (query.length < 3) {
        return nameMatches || categoryMatches || scientificMatches;
      }

      final descMatches = sp.shortDescription.toLowerCase().contains(query);
      final taxonomyMatches =
          sp.openData.taxonomy.toLowerCase().contains(query);
      final dietMatches = sp.openData.diet.toLowerCase().contains(query);
      return nameMatches ||
          categoryMatches ||
          scientificMatches ||
          descMatches ||
          taxonomyMatches ||
          dietMatches;
    }).toList();

    // Treffer, die im deutschen Namen mit dem Suchbegriff beginnen, nach oben priorisieren
    results.sort((a, b) {
      final aStarts = a.name.toLowerCase().startsWith(query);
      final bStarts = b.name.toLowerCase().startsWith(query);
      if (aStarts && !bStarts) return -1;
      if (!aStarts && bStarts) return 1;
      return 0;
    });

    return results;
  }

  @override
  Widget build(BuildContext context) {
    final onlyRoeDeer =
        _selectedIds.length == 1 && _selectedIds.contains('roe_deer');
    final viewInsets = MediaQuery.of(context).viewInsets;
    final screenHeight = MediaQuery.of(context).size.height;
    final maxSheetHeight = screenHeight * 0.88;
    final minSheetHeight = (screenHeight * 0.52).clamp(380.0, maxSheetHeight);
    final filtered = _filteredSpecies;

    return Container(
      constraints: BoxConstraints(
        minHeight: minSheetHeight,
        maxHeight: maxSheetHeight,
      ),
      decoration: BoxDecoration(
        color: WildlifeScoutTheme.bgObsidian.withValues(alpha: 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(
          top: BorderSide(color: WildlifeScoutTheme.borderSubtle, width: 1),
        ),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Kopfzeile: Icon, Titel, Subtitel & "Nur Rehwild"-Button
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.forest_outlined,
                  color: WildlifeScoutTheme.emeraldBio,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Wildarten-Auswahl & Wildbiologie',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Wilddaten & Tipps',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: WildlifeScoutTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (!onlyRoeDeer)
                TextButton.icon(
                  onPressed: _resetToRoeDeerOnly,
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(
                    Icons.filter_center_focus,
                    size: 14,
                    color: WildlifeScoutTheme.emeraldBio,
                  ),
                  label: const Text(
                    'Nur Rehwild',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: WildlifeScoutTheme.emeraldBio,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Suchfeld für Wildarten
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: WildlifeScoutTheme.surfaceCard,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: _searchQuery.isNotEmpty
                    ? WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.5)
                    : WildlifeScoutTheme.borderSubtle,
                width: 1,
              ),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              style: const TextStyle(
                fontSize: 13,
                color: WildlifeScoutTheme.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                hintText: 'Wildart suchen (z. B. Reh, Hirsch, Schalenwild)...',
                hintStyle: const TextStyle(
                  fontSize: 12,
                  color: WildlifeScoutTheme.textMuted,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 18,
                  color: WildlifeScoutTheme.emeraldBio,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        color: WildlifeScoutTheme.textMuted,
                        onPressed: _clearSearch,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Suche leeren',
                      )
                    : null,
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Leiste: Treffer-Zähler & Aktive Auswahl
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _searchQuery.isNotEmpty
                    ? '${filtered.length} von ${widget.allSpecies.length} Wildarten gefunden'
                    : '${widget.allSpecies.length} Wildarten im Revier',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: WildlifeScoutTheme.textMuted,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '${_selectedIds.length} aktiv',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: WildlifeScoutTheme.emeraldBio,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Arten-Liste oder Leerer Zustand
          Flexible(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 28,
                        horizontal: 16,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.search_off_rounded,
                            size: 40,
                            color: WildlifeScoutTheme.textMuted,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Keine Wildart für "$_searchQuery" gefunden',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: WildlifeScoutTheme.textPrimary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Probiere einen anderen Begriff, Kategorie oder wissenschaftlichen Namen.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: WildlifeScoutTheme.textMuted,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          TextButton.icon(
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.clear, size: 14),
                            label: const Text('Suche zurücksetzen'),
                            style: TextButton.styleFrom(
                              foregroundColor: WildlifeScoutTheme.emeraldBio,
                              textStyle: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final sp = filtered[index];
                      final isSelected = _selectedIds.contains(sp.id);
                      final isExpanded = _expandedSpeciesIds.contains(sp.id);

                      final cardBg = isSelected
                          ? const Color(0xFF133827)
                          : const Color(0xFF0F261C);

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        constraints: const BoxConstraints(
                          minHeight: 76,
                        ),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? sp.accentColor.withValues(alpha: 0.85)
                                : WildlifeScoutTheme.borderSubtle,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Kompakte Hauptzeile mit Tierfoto-Verlauf im Hintergrund
                              Stack(
                                children: [
                                  // Hintergrund-Tierfoto von links nach rechts mit weichem Verlauf
                                  Positioned.fill(
                                    child: _buildBackgroundPhoto(sp, cardBg),
                                  ),

                                  // Interaktive Hauptzeile
                                  InkWell(
                                    onTap: () => _toggleSpecies(sp.id),
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        minHeight: 76,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          // Checkbox mit dezentem Schatten für optimale Erkennbarkeit auf jedem Foto
                                          Container(
                                            decoration: BoxDecoration(
                                              color: Colors.black.withValues(alpha: 0.35),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: SizedBox(
                                              width: 26,
                                              height: 26,
                                              child: Checkbox(
                                                value: isSelected,
                                                activeColor: sp.accentColor,
                                                checkColor: Colors.black,
                                                visualDensity:
                                                    VisualDensity.compact,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                onChanged: (_) =>
                                                    _toggleSpecies(sp.id),
                                              ),
                                            ),
                                          ),
                                          // Abstand/Padding, damit das Tierbild links frei sichtbar ist
                                          const SizedBox(width: 52),

                                          // Text- & Kennzahlen-Spalte (weiter rechts platziert, ohne Latein & ohne Kategorie-Badge)
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  sp.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 15.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: WildlifeScoutTheme
                                                        .textPrimary,
                                                  ),
                                                ),
                                                if (sp.shortDescription
                                                    .isNotEmpty) ...[
                                                  const SizedBox(height: 1.5),
                                                  Text(
                                                    sp.shortDescription,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: WildlifeScoutTheme
                                                          .textMuted,
                                                    ),
                                                  ),
                                                ],
                                                const SizedBox(height: 4),
                                                // Einzeilige Kennzahlen-Chips
                                                SingleChildScrollView(
                                                  scrollDirection:
                                                      Axis.horizontal,
                                                  physics:
                                                      const BouncingScrollPhysics(),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      _QuickFactPill(
                                                        icon: Icons.air,
                                                        label: sp.behavior
                                                                    .scentSensitivityMeters >
                                                                0
                                                            ? 'Witterung ${sp.behavior.scentSensitivityMeters.round()}m'
                                                            : 'Sichtjäger',
                                                        color: WildlifeScoutTheme
                                                            .crimsonScent,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      _QuickFactPill(
                                                        icon: Icons.radar,
                                                        label:
                                                            'Flucht ${sp.behavior.flightDistanceMeters.round()}m',
                                                        color: WildlifeScoutTheme
                                                            .amberGold,
                                                      ),
                                                      if (sp.openData.bodyWeight
                                                          .isNotEmpty) ...[
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        _QuickFactPill(
                                                          icon: Icons
                                                              .monitor_weight_outlined,
                                                          label: sp
                                                              .openData
                                                              .bodyWeight
                                                              .split('(')
                                                              .first
                                                              .trim(),
                                                          color: sp.accentColor,
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 4),

                                          // Aktionen rechts: Steckbrief & Details einklappen/ausklappen
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: Icon(
                                                  Icons.info_outline,
                                                  size: 19,
                                                  color: sp.accentColor,
                                                ),
                                                tooltip:
                                                    'Voll-Steckbrief für ${sp.name}',
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(
                                                  minWidth: 30,
                                                  minHeight: 36,
                                                ),
                                                onPressed: () {
                                                  Navigator.of(context).pop();
                                                  widget.onInspectSpecies(sp);
                                                },
                                              ),
                                              IconButton(
                                                icon: Icon(
                                                  isExpanded
                                                      ? Icons.keyboard_arrow_up
                                                      : Icons
                                                          .keyboard_arrow_down,
                                                  size: 19,
                                                  color:
                                                      WildlifeScoutTheme.textMuted,
                                                ),
                                                tooltip: isExpanded
                                                    ? 'Details verbergen'
                                                    : 'Biologie & Tipps anzeigen',
                                                visualDensity:
                                                    VisualDensity.compact,
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(
                                                  minWidth: 26,
                                                  minHeight: 36,
                                                ),
                                                onPressed: () =>
                                                    _toggleExpanded(sp.id),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                            // Ausklappbarer Bereich: Biologie, Tipps & Lizenz
                            if (isExpanded)
                              Container(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 10, 12, 12),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.22),
                                  borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(14),
                                  ),
                                  border: const Border(
                                    top: BorderSide(
                                      color: WildlifeScoutTheme.borderSubtle,
                                      width: 0.8,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 1. Offene Daten (Open Data)
                                    const Text(
                                      'OFFENE WILDBIOLOGIE-DATEN (OPEN DATA)',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.6,
                                        color: WildlifeScoutTheme.cyanWater,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    _OpenDataRow(
                                      label: 'Schutzstatus',
                                      value: sp.openData.conservationStatus,
                                    ),
                                    _OpenDataRow(
                                      label: 'Körpermaße',
                                      value:
                                          '${sp.openData.bodyWeight} • ${sp.openData.bodySize}',
                                    ),
                                    _OpenDataRow(
                                      label: 'Hochphase',
                                      value: sp.openData.peakSeason,
                                    ),
                                    _OpenDataRow(
                                      label: 'Nahrung',
                                      value: sp.openData.diet,
                                    ),
                                    _OpenDataRow(
                                      label: 'Spuren & Losung',
                                      value: sp.openData.tracksAndSigns,
                                    ),
                                    _OpenDataRow(
                                      label: 'Lautäußerung',
                                      value: sp.openData.vocalizations,
                                    ),
                                    _OpenDataRow(
                                      label: 'Sinnesleistung',
                                      value: sp.openData.sensoryStrengths,
                                    ),
                                    _OpenDataRow(
                                      label: 'Foto-Optik',
                                      value: sp.openData.recommendedLens,
                                    ),

                                    if (sp.behaviorTraits.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      const Text(
                                        'TYPISCHE VERHALTENSWEISEN',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.6,
                                          color: WildlifeScoutTheme.emeraldBio,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      ...sp.behaviorTraits.map(
                                        (trait) => Container(
                                          margin:
                                              const EdgeInsets.only(bottom: 6),
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: WildlifeScoutTheme.surfaceCard,
                                            borderRadius:
                                                BorderRadius.circular(9),
                                            border: Border.all(
                                              color: sp.accentColor.withValues(
                                                alpha: 0.28,
                                              ),
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 5,
                                                      vertical: 1.5,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: sp.accentColor
                                                          .withValues(
                                                        alpha: 0.18,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        4,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      trait.tag,
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: sp.accentColor,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      trait.title,
                                                      style: const TextStyle(
                                                        fontSize: 11.5,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: WildlifeScoutTheme
                                                            .textPrimary,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                trait.description,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      WildlifeScoutTheme.textMuted,
                                                  height: 1.3,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],

                                    if (sp.fieldTips.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      const Text(
                                        'WERTVOLLE PRAXIS- & FOTO-TIPPS FÜR DEN ANSITZ',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.6,
                                          color: WildlifeScoutTheme.amberGold,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      ...sp.fieldTips.map(
                                        (tip) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 4),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Padding(
                                                padding:
                                                    EdgeInsets.only(top: 2),
                                                child: Icon(
                                                  Icons
                                                      .tips_and_updates_outlined,
                                                  size: 13,
                                                  color:
                                                      WildlifeScoutTheme.amberGold,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  tip,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: WildlifeScoutTheme
                                                        .textPrimary,
                                                    height: 1.3,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],

                                    const SizedBox(height: 8),
                                    // Lizenz-Nachweis Box
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: WildlifeScoutTheme.emeraldBio
                                            .withValues(
                                          alpha: 0.08,
                                        ),
                                        borderRadius: BorderRadius.circular(7),
                                        border: Border.all(
                                          color: WildlifeScoutTheme.emeraldBio
                                              .withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.verified_outlined,
                                            size: 13,
                                            color: WildlifeScoutTheme.emeraldBio,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Tierfoto: ${sp.imageAuthor} • ${sp.imageLicense}',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: WildlifeScoutTheme.textMuted,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 10),
                                    // Voll-Steckbrief Button
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          widget.onInspectSpecies(sp);
                                        },
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              WildlifeScoutTheme.textPrimary,
                                          side: const BorderSide(
                                            color: WildlifeScoutTheme.borderSubtle,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 7,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.open_in_full,
                                          size: 13,
                                        ),
                                        label: Text(
                                          'Ausführlichen Steckbrief für ${sp.name} öffnen',
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundPhoto(SpeciesProfile species, Color cardBg) {
    Widget imageWidget;
    if (species.imageAssetPath.isNotEmpty) {
      imageWidget = Image.asset(
        species.imageAssetPath,
        fit: BoxFit.cover,
        alignment: Alignment.centerLeft,
        errorBuilder: (_, _, _) {
          if (species.imageUrl.isNotEmpty) {
            return Image.network(
              species.imageUrl,
              fit: BoxFit.cover,
              alignment: Alignment.centerLeft,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            );
          }
          return const SizedBox.shrink();
        },
      );
    } else if (species.imageUrl.isNotEmpty) {
      imageWidget = Image.network(
        species.imageUrl,
        fit: BoxFit.cover,
        alignment: Alignment.centerLeft,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    } else {
      imageWidget = const SizedBox.shrink();
    }

    // Bild so breit wie hoch (~82px x 76px) mit weichem Verlauf nach rechts in die Kachelfarbe
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 86,
        height: 76,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Tierfoto links im quadratischen Zuschnitt
            imageWidget,

            // Verlauf nach rechts zu transparent / Kachelhintergrund
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0.0, 0.42, 0.78, 1.0],
                  colors: [
                    Colors.black.withValues(alpha: 0.15),
                    Colors.transparent,
                    cardBg.withValues(alpha: 0.70),
                    cardBg,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickFactPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _QuickFactPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3.5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: WildlifeScoutTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenDataRow extends StatelessWidget {
  final String label;
  final String value;

  const _OpenDataRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 98,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: WildlifeScoutTheme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                color: WildlifeScoutTheme.textPrimary,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
