import 'package:flutter/material.dart';
import '../../core/theme/wildscout_theme.dart';
import '../../domain/models/species_profile.dart';

/// Zeigt das lizenzfreie Unsplash-Tierfoto (lokal eingebettet unter `assets/species/images/`
/// mit automatischem Fallback auf die freie Unsplash-CDN-URL `images.unsplash.com`).
class SpeciesPhotoAvatar extends StatelessWidget {
  final SpeciesProfile species;
  final double width;
  final double height;
  final double borderRadius;
  final bool showLicenseBadge;
  final double borderWidth;

  const SpeciesPhotoAvatar({
    super.key,
    required this.species,
    this.width = 56,
    this.height = 56,
    this.borderRadius = 14,
    this.showLicenseBadge = false,
    this.borderWidth = 1.5,
  });

  IconData _fallbackIcon(String id) {
    switch (id) {
      case 'roe_deer':
        return Icons.forest_outlined;
      case 'red_deer':
        return Icons.terrain;
      case 'wild_boar':
        return Icons.grass;
      case 'red_fox':
        return Icons.pets;
      case 'badger':
        return Icons.nights_stay_outlined;
      case 'kingfisher':
        return Icons.water;
      default:
        return Icons.explore;
    }
  }

  Widget _buildFallbackContainer() {
    return Container(
      width: width,
      height: height,
      color: species.accentColor.withValues(alpha: 0.2),
      child: Icon(
        _fallbackIcon(species.id),
        color: species.accentColor,
        size: (width * 0.42).clamp(14.0, 32.0),
      ),
    );
  }

  Widget _buildImage() {
    if (species.imageAssetPath.isNotEmpty) {
      return Image.asset(
        species.imageAssetPath,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) {
          if (species.imageUrl.isNotEmpty) {
            return Image.network(
              species.imageUrl,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _buildFallbackContainer(),
            );
          }
          return _buildFallbackContainer();
        },
      );
    }
    if (species.imageUrl.isNotEmpty) {
      return Image.network(
        species.imageUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildFallbackContainer(),
      );
    }
    return _buildFallbackContainer();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: species.accentColor.withValues(alpha: 0.65),
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          (borderRadius - borderWidth).clamp(2.0, 40.0),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildImage(),
            if (showLicenseBadge)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.85),
                        Colors.black.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                  child: const Text(
                    'Unsplash • Frei',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      color: WildScoutTheme.emeraldBio,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
