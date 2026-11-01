import 'package:flutter/material.dart';
import '../../core/theme/wildscout_theme.dart';
import '../../domain/models/species_profile.dart';
import 'species_photo_avatar.dart';

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
  final Set<String> _expandedSpeciesIds = {'roe_deer'};

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.initialSelectedIds);
    if (_selectedIds.isNotEmpty) {
      _expandedSpeciesIds
        ..clear()
        ..add(_selectedIds.first);
    }
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

  @override
  Widget build(BuildContext context) {
    final onlyRoeDeer =
        _selectedIds.length == 1 && _selectedIds.contains('roe_deer');
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.84;

    return Container(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      decoration: BoxDecoration(
        color: WildScoutTheme.bgObsidian.withValues(alpha: 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(
          top: BorderSide(color: WildScoutTheme.borderSubtle, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: WildScoutTheme.emeraldBio.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.forest_outlined,
                  color: WildScoutTheme.emeraldBio,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Wildarten-Auswahl & Wildbiologie',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Lizenzfreie Unsplash-Fotos • Offene Wilddaten, Verhalten & Profi-Tipps',
                      style: TextStyle(
                        fontSize: 12,
                        color: WildScoutTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (!onlyRoeDeer)
                TextButton.icon(
                  onPressed: _resetToRoeDeerOnly,
                  icon: const Icon(
                    Icons.filter_center_focus,
                    size: 15,
                    color: WildScoutTheme.emeraldBio,
                  ),
                  label: const Text(
                    'Nur Rehwild',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: WildScoutTheme.emeraldBio,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.allSpecies.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final sp = widget.allSpecies[index];
                final isSelected = _selectedIds.contains(sp.id);
                final isExpanded = _expandedSpeciesIds.contains(sp.id);
                final isPrimaryFocus = sp.id == 'roe_deer';

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? sp.accentColor.withValues(alpha: 0.11)
                        : WildScoutTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isSelected
                          ? sp.accentColor.withValues(alpha: 0.78)
                          : WildScoutTheme.borderSubtle,
                      width: isSelected ? 1.6 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Obere Hauptzeile: Checkbox + Unsplash-Tierfoto + Name + Offene Eckdaten
                      InkWell(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(18),
                        ),
                        onTap: () => _toggleSpecies(sp.id),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: Checkbox(
                                    value: isSelected,
                                    activeColor: sp.accentColor,
                                    checkColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    onChanged: (_) => _toggleSpecies(sp.id),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  Navigator.of(context).pop();
                                  widget.onInspectSpecies(sp);
                                },
                                child: SpeciesPhotoAvatar(
                                  species: sp,
                                  width: 74,
                                  height: 74,
                                  borderRadius: 14,
                                  showLicenseBadge: true,
                                  borderWidth: 1.8,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            sp.name,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isPrimaryFocus
                                                ? WildScoutTheme.emeraldBio
                                                    .withValues(alpha: 0.22)
                                                : sp.accentColor.withValues(
                                                    alpha: 0.16,
                                                  ),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            isPrimaryFocus
                                                ? 'FOKUS-ART'
                                                : sp.category.label,
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w800,
                                              color: isPrimaryFocus
                                                  ? WildScoutTheme.emeraldBio
                                                  : sp.accentColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${sp.scientificName} • ${sp.openData.taxonomy}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                        color: WildScoutTheme.textMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      sp.shortDescription,
                                      maxLines: isExpanded ? 4 : 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: WildScoutTheme.textPrimary,
                                        height: 1.32,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Kompakte Offene-Daten-Chips direkt in der Auswahl
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 5,
                                      children: [
                                        _QuickFactPill(
                                          icon: Icons.air,
                                          label: sp.behavior
                                                      .scentSensitivityMeters >
                                                  0
                                              ? 'Witterung ${sp.behavior.scentSensitivityMeters.round()}m'
                                              : 'Sichtjäger (0m Witterung)',
                                          color: WildScoutTheme.crimsonScent,
                                        ),
                                        _QuickFactPill(
                                          icon: Icons.radar,
                                          label:
                                              'Flucht ${sp.behavior.flightDistanceMeters.round()}m',
                                          color: WildScoutTheme.amberGold,
                                        ),
                                        if (sp.openData.bodyWeight.isNotEmpty)
                                          _QuickFactPill(
                                            icon: Icons.monitor_weight_outlined,
                                            label: sp.openData.bodyWeight
                                                .split('(')
                                                .first
                                                .trim(),
                                            color: sp.accentColor,
                                          ),
                                        if (sp.openData.homeRange.isNotEmpty)
                                          _QuickFactPill(
                                            icon: Icons.map_outlined,
                                            label:
                                                'Revier ${sp.openData.homeRange.split('(').first.trim()}',
                                            color: WildScoutTheme.cyanWater,
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Aktionsleiste pro Tier: Aufklappen (Offene Daten, Verhalten & Tipps) + Vollbild-Steckbrief
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.24),
                          borderRadius: isExpanded
                              ? BorderRadius.zero
                              : const BorderRadius.vertical(
                                  bottom: Radius.circular(18),
                                ),
                          border: const Border(
                            top: BorderSide(
                              color: WildScoutTheme.borderSubtle,
                              width: 0.8,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => _toggleExpanded(sp.id),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isExpanded
                                            ? Icons.keyboard_arrow_up
                                            : Icons.keyboard_arrow_down,
                                        size: 17,
                                        color: sp.accentColor,
                                      ),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          isExpanded
                                              ? 'Offene Daten, Verhalten & Tipps einklappen'
                                              : 'Offene Daten, ${sp.behaviorTraits.length} Verhaltensweisen & ${sp.fieldTips.length} Tipps anzeigen',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: sp.accentColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                Navigator.of(context).pop();
                                widget.onInspectSpecies(sp);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: WildScoutTheme.borderSubtle,
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.open_in_full,
                                      size: 12,
                                      color: WildScoutTheme.textPrimary,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Voll-Steckbrief',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: WildScoutTheme.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Ausklappbarer Bereich direkt in der Tierauswahl:
                      // 1. Offene Wildbiologie-Daten
                      // 2. Typische Verhaltensweisen
                      // 3. Wertvolle Praxis- & Fotografie-Tipps
                      // 4. Lizenzfreier Bildnachweis (Unsplash License)
                      if (isExpanded)
                        Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.18),
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(18),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 1. Offene Daten (Open Data Steckbrief)
                              const Text(
                                'OFFENE WILDBIOLOGIE-DATEN (OPEN DATA)',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.7,
                                  color: WildScoutTheme.cyanWater,
                                ),
                              ),
                              const SizedBox(height: 7),
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
                                const SizedBox(height: 12),
                                const Text(
                                  'TYPISCHE VERHALTENSWEISEN',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.7,
                                    color: WildScoutTheme.emeraldBio,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                ...sp.behaviorTraits.map(
                                  (trait) => Container(
                                    margin: const EdgeInsets.only(bottom: 7),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: WildScoutTheme.surfaceCard,
                                      borderRadius: BorderRadius.circular(11),
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
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: sp.accentColor
                                                    .withValues(alpha: 0.18),
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                              ),
                                              child: Text(
                                                trait.tag,
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: sp.accentColor,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 7),
                                            Expanded(
                                              child: Text(
                                                trait.title,
                                                style: const TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w800,
                                                  color:
                                                      WildScoutTheme.textPrimary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          trait.description,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: WildScoutTheme.textMuted,
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 8),
                              const Text(
                                'WERTVOLLE PRAXIS- & FOTO-TIPPS FÜR DEN ANSITZ',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.7,
                                  color: WildScoutTheme.amberGold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ...sp.fieldTips.map(
                                (tip) => Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.only(top: 2),
                                        child: Icon(
                                          Icons.tips_and_updates_outlined,
                                          size: 13.5,
                                          color: WildScoutTheme.amberGold,
                                        ),
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          tip,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: WildScoutTheme.textPrimary,
                                            height: 1.34,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 8),
                              // Lizenz-Nachweis Box
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: WildScoutTheme.emeraldBio.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: WildScoutTheme.emeraldBio.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.verified_outlined,
                                      size: 14,
                                      color: WildScoutTheme.emeraldBio,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Tierfoto: ${sp.imageAuthor} • ${sp.imageLicense}',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          color: WildScoutTheme.textMuted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11.5, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: WildScoutTheme.textPrimary,
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
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 102,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: WildScoutTheme.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11.5,
                color: WildScoutTheme.textPrimary,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
