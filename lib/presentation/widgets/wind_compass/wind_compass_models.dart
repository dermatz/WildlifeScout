enum ScentStatus {
  scentContaminated,
  safeHeadwind,
  crosswind,
}

class TargetBearingInfo {
  final String title;
  final String category;
  final double bearingDeg;
  final double distanceMeters;
  final ScentStatus status;
  final bool isPrimary;

  const TargetBearingInfo({
    required this.title,
    required this.category,
    required this.bearingDeg,
    required this.distanceMeters,
    required this.status,
    required this.isPrimary,
  });
}
