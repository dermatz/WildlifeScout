import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme/wildlifescout_theme.dart';
import '../../domain/models/secret_spot.dart';
import '../../domain/models/species_profile.dart';
import 'species_photo_avatar.dart';

class SpotVaultSheet extends StatefulWidget {
  final List<SecretSpot> spots;
  final List<SpeciesProfile> allSpecies;
  final LatLng currentMapPosition;
  final SpeciesProfile activeSpecies;
  final String currentWindCardinal;
  final ValueChanged<SecretSpot> onSelectSpot;
  final ValueChanged<SecretSpot> onAddSpot;
  final ValueChanged<String> onDeleteSpot;

  const SpotVaultSheet({
    super.key,
    required this.spots,
    required this.allSpecies,
    required this.currentMapPosition,
    required this.activeSpecies,
    required this.currentWindCardinal,
    required this.onSelectSpot,
    required this.onAddSpot,
    required this.onDeleteSpot,
  });

  @override
  State<SpotVaultSheet> createState() => _SpotVaultSheetState();
}

class _SpotVaultSheetState extends State<SpotVaultSheet> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  bool _isAdding = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _saveCurrentPositionAsSpot() {
    final title = _titleCtrl.text.trim().isEmpty
        ? '${widget.activeSpecies.name}-Ansitz (${DateTime.now().day}.${DateTime.now().month}.)'
        : _titleCtrl.text.trim();

    final newSpot = SecretSpot(
      id: 'spot_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      speciesId: widget.activeSpecies.id,
      latitude: widget.currentMapPosition.latitude,
      longitude: widget.currentMapPosition.longitude,
      notes: _notesCtrl.text.trim().isEmpty
          ? 'Gespeichert bei ${widget.currentWindCardinal}-Wind.'
          : _notesCtrl.text.trim(),
      idealWindCardinal: widget.currentWindCardinal,
      createdAt: DateTime.now(),
    );

    widget.onAddSpot(newSpot);
    setState(() {
      _isAdding = false;
      _titleCtrl.clear();
      _notesCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: WildlifeScoutTheme.bgObsidian.withValues(alpha: 0.97),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(
          top: BorderSide(color: WildlifeScoutTheme.borderSubtle, width: 1),
        ),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
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
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: WildlifeScoutTheme.emeraldBio,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Geheimer Spot-Tresor (Zero-Cloud)',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: WildlifeScoutTheme.textPrimary,
                      ),
                    ),
                    Text(
                      '100 % lokal auf deinem Gerät • Keine Weitergabe von Koordinaten',
                      style: TextStyle(
                        fontSize: 12,
                        color: WildlifeScoutTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => setState(() => _isAdding = !_isAdding),
                style: FilledButton.styleFrom(
                  backgroundColor: WildlifeScoutTheme.emeraldBio,
                  foregroundColor: Colors.black,
                ),
                icon: Icon(_isAdding ? Icons.close : Icons.add_location_alt, size: 18),
                label: Text(_isAdding ? 'Abbrechen' : 'Pin sichern'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isAdding) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: WildlifeScoutTheme.surfaceCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: WildlifeScoutTheme.emeraldBio.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aktuellen Tarnzelt-Pin speichern (${widget.activeSpecies.name})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: WildlifeScoutTheme.emeraldBio,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _titleCtrl,
                    decoration: InputDecoration(
                      hintText: 'Name (z.B. Waldwiese Nordkante)',
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Notiz (z.B. Wechsel aus SO, 400mm Brennweite optimal)',
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saveCurrentPositionAsSpot,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WildlifeScoutTheme.amberGold,
                        foregroundColor: Colors.black,
                      ),
                      icon: const Icon(Icons.lock_outline, size: 18),
                      label: const Text(
                        'Lokal im Tresor verschlüsseln & speichern',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 310),
            child: widget.spots.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        'Noch keine eigenen Standorte gespeichert.\nTippe oben auf „Pin sichern“, um deinen aktuellen Karten-Pin lokal zu speichern.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: WildlifeScoutTheme.textMuted,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: widget.spots.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final spot = widget.spots[index];
                final sp = widget.allSpecies.firstWhere(
                  (e) => e.id == spot.speciesId,
                  orElse: () => widget.activeSpecies,
                );
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    widget.onSelectSpot(spot);
                    Navigator.of(context).pop();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: WildlifeScoutTheme.surfaceCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: WildlifeScoutTheme.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        SpeciesPhotoAvatar(
                          species: sp,
                          width: 42,
                          height: 42,
                          borderRadius: 10,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      spot.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: sp.accentColor.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${sp.name} • Ideal: ${spot.idealWindCardinal}-Wind',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: sp.accentColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                spot.notes,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: WildlifeScoutTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 19,
                            color: Colors.white38,
                          ),
                          onPressed: () => widget.onDeleteSpot(spot.id),
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
}
