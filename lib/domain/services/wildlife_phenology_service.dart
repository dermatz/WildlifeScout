class WildlifePhenologyPhase {
  final String phaseName;
  final String emoji;
  final double activityBonus;
  final String description;
  final bool relaxesMiddayDip;
  final bool boostEdgesAndMeadows;

  const WildlifePhenologyPhase({
    required this.phaseName,
    required this.emoji,
    required this.activityBonus,
    required this.description,
    this.relaxesMiddayDip = false,
    this.boostEdgesAndMeadows = false,
  });
}

/// Wildbiologischer Phänologie- & Jahreszeiten-Kalender.
///
/// Berechnet biologische Brunft-, Fege-, Setz- und Rauschzeiten der heimischen
/// Wildarten und deren Einfluss auf Aktivität und räumliche Habitatnutzung.
class WildlifePhenologyService {
  const WildlifePhenologyService._();

  static WildlifePhenologyPhase evaluate({
    required String speciesId,
    required DateTime dateTime,
  }) {
    final month = dateTime.month;
    final day = dateTime.day;

    switch (speciesId) {
      case 'roe_deer':
        // 1. Blattzeit (Rehwild-Brunft): 15. Juli bis 15. August
        if ((month == 7 && day >= 15) || (month == 8 && day <= 15)) {
          return const WildlifePhenologyPhase(
            phaseName: 'Blattzeit (Rehwild-Brunft)',
            emoji: '🌾',
            activityBonus: 14.0,
            description:
                'Höhepunkt der Paarungszeit: Böcke treiben Ricken intensiv über Wiesen und Kanten – auch bei sommerlicher Mittagshitze aktiv!',
            relaxesMiddayDip: true,
            boostEdgesAndMeadows: true,
          );
        }
        // 2. Fegezeit & Territorialphase: 15. April bis 31. Mai
        if ((month == 4 && day >= 15) || month == 5) {
          return const WildlifePhenologyPhase(
            phaseName: 'Fegezeit & Reviermarkierung',
            emoji: '🌿',
            activityBonus: 8.0,
            description:
                'Böcke fegen das Bastgeweih an jungen Sträuchern ab und markieren Wald- und Feldkanten mit Plätzstellen.',
            boostEdgesAndMeadows: true,
          );
        }
        // 3. Setzzeit & Kitzführung: 15. Mai bis 25. Juni
        if ((month == 5 && day >= 15) || (month == 6 && day <= 25)) {
          return const WildlifePhenologyPhase(
            phaseName: 'Setzzeit & Kitzablage',
            emoji: '🌱',
            activityBonus: 3.0,
            description:
                'Ricken legen Kitze im hohen Gras ab. Äsungsaufnahme erfolgt vorsichtig an ruhigen, geschützten Waldrändern.',
            boostEdgesAndMeadows: true,
          );
        }
        // 4. Herbst-Feistzeit & Sprungbildung: 1. Oktober bis 15. November
        if (month == 10 || (month == 11 && day <= 15)) {
          return const WildlifePhenologyPhase(
            phaseName: 'Herbst-Äsung & Sprungbildung',
            emoji: '🍂',
            activityBonus: 5.0,
            description:
                'Rehwild schließt sich zu kleineren Sprüngen zusammen und sucht eiweißreiche Herbstsaaten und Wiesen auf.',
            boostEdgesAndMeadows: true,
          );
        }
        // 5. Winterruhe: 1. Dezember bis 28. Februar
        if (month == 12 || month == 1 || month == 2) {
          return const WildlifePhenologyPhase(
            phaseName: 'Winterruhe & Energiesparmodus',
            emoji: '❄️',
            activityBonus: -8.0,
            description:
                'Stoffwechsel stark gedrosselt. Wild verharrt kraftsparend im Einstand und äst nur kurz in günstigsten Sonnenstunden.',
          );
        }
        return const WildlifePhenologyPhase(
          phaseName: 'Reguläre Äsungsperiode',
          emoji: '🌲',
          activityBonus: 0.0,
          description:
              'Ausgewogener Rhythmus zwischen morgendlicher und abendlicher Äsungsaufnahme.',
        );

      case 'red_deer':
        // 1. Brunftzeit: 10. September bis 10. Oktober
        if ((month == 9 && day >= 10) || (month == 10 && day <= 10)) {
          return const WildlifePhenologyPhase(
            phaseName: 'Rotwild-Brunft',
            emoji: '🦌',
            activityBonus: 18.0,
            description:
                'Platzhirsche melden lautstark und treiben Kahlwildrudel auf Lichtungen und großen Waldwiesen.',
            relaxesMiddayDip: true,
            boostEdgesAndMeadows: true,
          );
        }
        // 2. Feistzeit der Hirsche: 15. Juli bis 31. August
        if ((month == 7 && day >= 15) || month == 8) {
          return const WildlifePhenologyPhase(
            phaseName: 'Feistzeit der Hirsche',
            emoji: '🌾',
            activityBonus: 5.0,
            description:
                'Hirsche äsen ungestört in ruhigen Revierteilen, um Feist für die anstrengende Brunft aufzubauen.',
          );
        }
        // 3. Winterruhe: 1. Dezember bis Ende Februar
        if (month == 12 || month == 1 || month == 2) {
          return const WildlifePhenologyPhase(
            phaseName: 'Winterruhe',
            emoji: '❄️',
            activityBonus: -10.0,
            description:
                'Energiesparmodus im Kernwald; strikte Vermeidung von Störungen.',
          );
        }
        return const WildlifePhenologyPhase(
          phaseName: 'Kahlwild- & Rudelperiode',
          emoji: '🌲',
          activityBonus: 0.0,
          description:
              'Vertrauter Tagesrhythmus mit Schwerpunkt auf morgendlichem und abendlichem Ausziehen.',
        );

      case 'wild_boar':
        // 1. Milchreife im Getreide: 20. Juni bis 15. August
        if ((month == 6 && day >= 20) || month == 7 || (month == 8 && day <= 15)) {
          return const WildlifePhenologyPhase(
            phaseName: 'Milchreife (Getreidemagnet)',
            emoji: '🌽',
            activityBonus: 14.0,
            description:
                'Milchreifes Getreide zieht Rotten magisch aus dem Wald an Feldkanten und Maisschläge.',
            boostEdgesAndMeadows: true,
          );
        }
        // 2. Rauschzeit (Brunft): 15. November bis 15. Januar
        if ((month == 11 && day >= 15) || month == 12 || (month == 1 && day <= 15)) {
          return const WildlifePhenologyPhase(
            phaseName: 'Rauschzeit (Schwarzwild-Brunft)',
            emoji: '🐗',
            activityBonus: 12.0,
            description:
                'Keiler schließen sich den Rotten an; hohe Bewegungsaktivität und Kämpfe durch die ganze Nacht.',
          );
        }
        return const WildlifePhenologyPhase(
          phaseName: 'Rottenaktivität & Suhlenzeit',
          emoji: '🌲',
          activityBonus: 0.0,
          description:
              'Dämmerungs- und nachtaktive Futtersuche an Suhlen, Mastbäumen und Waldrändern.',
        );

      case 'red_fox':
        // 1. Ranzzeit: 10. Januar bis 20. Februar
        if ((month == 1 && day >= 10) || (month == 2 && day <= 20)) {
          return const WildlifePhenologyPhase(
            phaseName: 'Ranzzeit (Fuchs-Paarung)',
            emoji: '🦊',
            activityBonus: 10.0,
            description:
                'Rüden schnüren aktiv auch am helllichten Tag und bellen vernehmlich auf Freiflächen.',
            relaxesMiddayDip: true,
            boostEdgesAndMeadows: true,
          );
        }
        // 2. Welpenaufzucht: 15. April bis 30. Juni
        if ((month == 4 && day >= 15) || month == 5 || month == 6) {
          return const WildlifePhenologyPhase(
            phaseName: 'Welpenaufzucht am Bau',
            emoji: '🐾',
            activityBonus: 6.0,
            description:
                'Hoher Beutebedarf zwingt Altfüchse zu ausgedehnten Jagdzügen auch in den Nachmittagsstunden.',
          );
        }
        return const WildlifePhenologyPhase(
          phaseName: 'Mäusejagd & Patrouille',
          emoji: '🌾',
          activityBonus: 0.0,
          description:
              'Klassische Pirsch entlang von Gräben, Hecken und Wiesenrändern.',
        );

      case 'badger':
        // 1. Winterruhe: 1. Dezember bis 15. Februar
        if (month == 12 || month == 1 || (month == 2 && day <= 15)) {
          return const WildlifePhenologyPhase(
            phaseName: 'Winterruhe im Erdbau',
            emoji: '❄️',
            activityBonus: -18.0,
            description:
                'Dachse halten Winterruhe im tiefen Bau und verlassen die Röhre nur bei mildem Tauwetter.',
          );
        }
        // 2. Herbstfettung: 1. September bis 31. Oktober
        if (month == 9 || month == 10) {
          return const WildlifePhenologyPhase(
            phaseName: 'Herbstmast & Fettpolsteraufbau',
            emoji: '🦡',
            activityBonus: 8.0,
            description:
                'Intensive Nahrungssuche nach Fallobst, Eicheln und Engerlingen vor dem Kälteeinbruch.',
            boostEdgesAndMeadows: true,
          );
        }
        return const WildlifePhenologyPhase(
          phaseName: 'Bau-Ausfahrt & Nahrungssuche',
          emoji: '🌲',
          activityBonus: 0.0,
          description:
              'Ausfahrt aus dem Bau in der späten Dämmerung zur nächtlichen Futtersuche.',
        );

      case 'kingfisher':
        // 1. Balz & Brutrevier: 15. März bis 15. Mai
        if ((month == 3 && day >= 15) || month == 4 || (month == 5 && day <= 15)) {
          return const WildlifePhenologyPhase(
            phaseName: 'Balz & Brutzeit',
            emoji: '💎',
            activityBonus: 10.0,
            description:
                'Rufend patrouillierende Eisvögel, Partnerfütterung und Graben der Brutröhren an Steilufern.',
          );
        }
        return const WildlifePhenologyPhase(
          phaseName: 'Ansitzjagd am Gewässer',
          emoji: '🌊',
          activityBonus: 0.0,
          description:
              'Fokussierte Tauchjagd von überhängenden Ästen auf Kleinfische.',
        );

      default:
        return const WildlifePhenologyPhase(
          phaseName: 'Jahreszeitliche Normalphase',
          emoji: '🌲',
          activityBonus: 0.0,
          description: 'Reguläre tageszeitliche Aktivität.',
        );
    }
  }
}
