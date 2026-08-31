import '../models/anime.dart';
import '../models/episode.dart';
import '../models/episode_quality.dart';
import '../models/season.dart';
import '../models/video_quality.dart';

/// Données de démonstration locales (étape 2 : épisodes, qualités, lecture).
///
/// Cette source sera remplacée par l'API backend (alimentée par Telegram)
/// dans une étape ultérieure ; la forme des modèles restera identique.

const int _gb = 1024 * 1024 * 1024;
const int _mb = 1024 * 1024;

// ---------------------------------------------------------------------------
// Vignettes (générées localement, dans assets/img/)
// ---------------------------------------------------------------------------

const List<String> _soloThumbs = [
  'assets/img/solo_t1.png',
  'assets/img/solo_t2.png',
];
const List<String> _opThumbs = [
  'assets/img/op_t1.png',
  'assets/img/op_t2.png',
];
const List<String> _jjkThumbs = [
  'assets/img/jjk_t1.png',
  'assets/img/jjk_t2.png',
];
const List<String> _dsThumbs = [
  'assets/img/ds_t1.png',
  'assets/img/ds_t2.png',
];

String _thumb(List<String> thumbs, int number) => thumbs[(number - 1) % thumbs.length];

// ---------------------------------------------------------------------------
// Générateurs d'épisodes et de qualités
// ---------------------------------------------------------------------------

/// Génère une plage d'épisodes consécutifs.
List<Episode> _rangeEpisodes({
  required String seasonId,
  required int from,
  required int to,
  required DateTime firstDate,
  required List<String> thumbs,
  Map<int, String> titles = const {},
  Set<int> newEpisodes = const {},
  required List<EpisodeQuality> Function(String episodeId, int number) qualities,
}) {
  return [
    for (int number = from; number <= to; number++)
      Episode(
        id: '${seasonId}e$number',
        number: number,
        title: titles[number],
        thumbnail: _thumb(thumbs, number),
        date: firstDate.add(Duration(days: 7 * (number - from))),
        isNew: newEpisodes.contains(number),
        qualities: qualities('$seasonId-e$number', number),
      ),
  ];
}

/// Construit la liste des qualités d'un épisode (tailles fictives mockées).
List<EpisodeQuality> _qualities(
  String episodeId, {
  int? fhdBytes,
  int? hdBytes,
  int? sdBytes,
  int? lowBytes,
  String fhdLang = 'VF',
  String hdLang = 'VOSTFR',
  String sdLang = 'VF',
  String lowLang = 'VF',
  String subtitles = 'FR',
}) {
  return [
    if (fhdBytes != null)
      EpisodeQuality(
        id: '$episodeId-q1080',
        quality: VideoQuality.fhd,
        resolution: 'FHD',
        size: fhdBytes,
        language: fhdLang,
        subtitles: subtitles,
      ),
    if (hdBytes != null)
      EpisodeQuality(
        id: '$episodeId-q720',
        quality: VideoQuality.hd,
        resolution: 'HD',
        size: hdBytes,
        language: hdLang,
        subtitles: subtitles,
      ),
    if (sdBytes != null)
      EpisodeQuality(
        id: '$episodeId-q480',
        quality: VideoQuality.sd,
        resolution: 'SD',
        size: sdBytes,
        language: sdLang,
        subtitles: subtitles,
      ),
    if (lowBytes != null)
      EpisodeQuality(
        id: '$episodeId-q360',
        quality: VideoQuality.low,
        resolution: 'SD',
        size: lowBytes,
        language: lowLang,
        subtitles: subtitles,
      ),
  ];
}

// ---------------------------------------------------------------------------
// Qualités par animé
// ---------------------------------------------------------------------------

List<EpisodeQuality> _soloQualities(String episodeId, int number) => _qualities(
      episodeId,
      fhdBytes: (1.2 * _gb).round(),
      hdBytes: (650 * _mb).round(),
      sdBytes: (350 * _mb).round(),
      lowBytes: number == 9 ? (270 * _mb).round() : null,
    );

List<EpisodeQuality> _opQualities(String episodeId, int number) => number >= 1120
    ? _qualities(
        episodeId,
        fhdBytes: (900 * _mb).round(),
        hdBytes: (600 * _mb).round(),
        sdBytes: (350 * _mb).round(),
        fhdLang: 'VOSTFR',
        hdLang: 'VOSTFR',
        sdLang: 'VOSTFR',
      )
    : _qualities(
        episodeId,
        hdBytes: (600 * _mb).round(),
        sdBytes: (350 * _mb).round(),
        hdLang: 'VOSTFR',
        sdLang: 'VOSTFR',
      );

List<EpisodeQuality> _jjkQualities(String episodeId, _) => _qualities(
      episodeId,
      fhdBytes: (1.1 * _gb).round(),
      hdBytes: (650 * _mb).round(),
      sdBytes: (350 * _mb).round(),
    );

List<EpisodeQuality> _dsQualities(String episodeId, _) => _qualities(
      episodeId,
      fhdBytes: (1.2 * _gb).round(),
      hdBytes: (650 * _mb).round(),
      sdBytes: (350 * _mb).round(),
    );

// ---------------------------------------------------------------------------
// Catalogue
// ---------------------------------------------------------------------------

final List<Anime> kMockAnime = [
  Anime(
    id: 'solo-leveling',
    title: 'Solo Leveling',
    posterAsset: 'assets/img/poster_solo_leveling.png',
    backdropAsset: 'assets/img/backdrop_solo_leveling.png',
    description: "Dix ans après l'apparition des mystérieux « Portails » qui relient notre monde à celui des "
        "monstres, certains humains ont développé des pouvoirs et sont devenus des chasseurs. Sung Jinwoo, "
        "surnommé « le chasseur le plus faible de l'humanité », survit miraculeusement à un double donjon et "
        "se découvre la capacité unique d'augmenter de niveau sans limite. Son ascension ne fait que commencer…",
    genres: const ['Action', 'Aventure', 'Fantastique'],
    year: 2024,
    rating: 9.2,
    status: AnimeStatus.ongoing,
    languages: const ['VF', 'VOSTFR'],
    source: 'AnimeHD',
    popularity: 99,
    followers: 1520000,
    seasons: [
      Season(id: 'sl-s1', number: 1, episodes: [
        ..._rangeEpisodes(
          seasonId: 'sl-s1',
          from: 1,
          to: 11,
          firstDate: DateTime(2024, 1, 7),
          thumbs: _soloThumbs,
          titles: const {},
          qualities: (String id, int number) => _qualities(
            id,
            fhdBytes: (1.1 * _gb).round(),
            hdBytes: (600 * _mb).round(),
            sdBytes: (320 * _mb).round(),
          ),
        ),
        Episode(
          id: 'sl-s1e12',
          number: 12,
          title: 'Arise',
          thumbnail: _thumb(_soloThumbs, 12),
          date: DateTime(2024, 3, 24),
          qualities: _qualities('sl-s1e12', fhdBytes: (1.2 * _gb).round(), hdBytes: (650 * _mb).round(), sdBytes: (350 * _mb).round(), lowBytes: (270 * _mb).round()),
        ),
      ]),
      Season(id: 'sl-s2', number: 2, episodes: [
        ..._rangeEpisodes(
          seasonId: 'sl-s2',
          from: 1,
          to: 7,
          firstDate: DateTime(2024, 3, 24),
          thumbs: _soloThumbs,
          titles: const {
            1: 'Retour à la chasse',
            2: 'Le banquet des ombres',
            3: 'L\'ombre du monarque',
            4: 'Les dix rois',
            5: 'L\'armée des ombres',
            6: 'La marque du roi',
            7: 'Le véritable pouvoir',
          },
          qualities: _soloQualities,
        ),
        Episode(
          id: 'sl-s2e8',
          number: 8,
          title: 'Le roi des ombres',
          thumbnail: _thumb(_soloThumbs, 8),
          date: DateTime(2024, 5, 12),
          qualities: _soloQualities('sl-s2e8', 8),
        ),
        Episode(
          id: 'sl-s2e9',
          number: 9,
          title: 'Le combat commence',
          thumbnail: _thumb(_soloThumbs, 9),
          date: DateTime(2024, 5, 19),
          isNew: true,
          qualities: _soloQualities('sl-s2e9', 9),
        ),
      ], specials: [
        Episode(
          id: 'sl-sp1',
          number: 1,
          title: 'Récapitulatif de la saison 1',
          thumbnail: _thumb(_soloThumbs, 1),
          date: DateTime(2024, 3, 17),
          qualities: _qualities('sl-sp1', hdBytes: (600 * _mb).round(), sdBytes: (320 * _mb).round()),
        ),
        Episode(
          id: 'sl-sp2',
          number: 2,
          title: 'Aperçu de la saison 2',
          thumbnail: _thumb(_soloThumbs, 2),
          date: DateTime(2024, 3, 31),
          qualities: _qualities('sl-sp2', hdBytes: (600 * _mb).round(), sdBytes: (320 * _mb).round()),
        ),
      ]),
    ],
  ),
  Anime(
    id: 'one-piece',
    title: 'One Piece',
    posterAsset: 'assets/img/poster_one_piece.png',
    backdropAsset: 'assets/img/poster_one_piece.png',
    description: "Monkey D. Luffy, un jeune garçon au corps élastique, rêve de devenir le roi des pirates. "
        "Avec son équipage du chapeau de paille, il parcourt Grand Line à la recherche du One Piece, le trésor "
        "légendaire laissé par Gol D. Roger. Une aventure épique de plus de mille épisodes.",
    genres: const ['Action', 'Aventure', 'Comédie', 'Fantastique'],
    year: 1999,
    rating: 9.1,
    status: AnimeStatus.ongoing,
    languages: const ['VOSTFR'],
    source: 'OtakuStream',
    popularity: 98,
    followers: 3200000,
    seasons: [
      Season(id: 'op-s1', number: 1, episodes: [
        ..._rangeEpisodes(
          seasonId: 'op-s1',
          from: 1,
          to: 1119,
          firstDate: DateTime(1999, 10, 20),
          thumbs: _opThumbs,
          qualities: _opQualities,
        ),
        ..._rangeEpisodes(
          seasonId: 'op-s1',
          from: 1120,
          to: 1125,
          firstDate: DateTime(2024, 4, 21),
          thumbs: _opThumbs,
          titles: const {
            1120: 'La colère de Loki',
            1121: 'Le géant de fer',
            1122: 'Le royaume d\'Elbaf',
            1123: 'Le serment des géants',
            1124: 'L\'éveil du soleil',
            1125: 'Le souffle du dragon',
          },
          newEpisodes: const {1125},
          qualities: _opQualities,
        ),
      ], specials: [
        for (final (int number, String title) in const [
          (1, 'Épisode de Luffy'),
          (2, '3D2Y — Surmonter la mort d\'Ace'),
          (3, 'Heart of Gold'),
          (4, 'Épisode de Sabo'),
        ])
          Episode(
            id: 'op-sp$number',
            number: number,
            title: title,
            thumbnail: _thumb(_opThumbs, number),
            date: DateTime(2014 + number, 8, 30),
            qualities: _qualities('op-sp$number', hdBytes: (600 * _mb).round(), sdBytes: (350 * _mb).round(), hdLang: 'VOSTFR', sdLang: 'VOSTFR'),
          ),
      ]),
    ],
  ),
  Anime(
    id: 'jujutsu-kaisen',
    title: 'Jujutsu Kaisen',
    posterAsset: 'assets/img/poster_jujutsu_kaisen.png',
    backdropAsset: 'assets/img/poster_jujutsu_kaisen.png',
    description: "Yuji Itadori, lycéen à la force hors du commun, avale un doigt maudit pour sauver ses amis et "
        "devient l'hôte de Sukuna, le roi des fléaux. Recruté par l'école d'exorcisme de Tokyo, il apprend à "
        "combattre les fléaux aux côtés de Megumi Fushiguro et Nobara Kugisaki.",
    genres: const ['Action', 'Fantastique', 'Surnaturel'],
    year: 2020,
    rating: 8.9,
    status: AnimeStatus.ongoing,
    languages: const ['VF', 'VOSTFR'],
    source: 'AnimeHD',
    popularity: 95,
    followers: 980000,
    seasons: [
      Season(id: 'jjk-s1', number: 1, episodes: [
        ..._rangeEpisodes(
          seasonId: 'jjk-s1',
          from: 1,
          to: 23,
          firstDate: DateTime(2020, 10, 3),
          thumbs: _jjkThumbs,
          qualities: (String id, _) => _qualities(id, hdBytes: (650 * _mb).round(), sdBytes: (350 * _mb).round()),
        ),
        Episode(
          id: 'jjk-s1e24',
          number: 24,
          title: 'Accomplissement',
          thumbnail: _thumb(_jjkThumbs, 24),
          date: DateTime(2021, 3, 27),
          qualities: _qualities('jjk-s1e24', hdBytes: (650 * _mb).round(), sdBytes: (350 * _mb).round()),
        ),
      ]),
      Season(id: 'jjk-s2', number: 2, episodes: [
        ..._rangeEpisodes(
          seasonId: 'jjk-s2',
          from: 1,
          to: 22,
          firstDate: DateTime(2023, 7, 6),
          thumbs: _jjkThumbs,
          qualities: _jjkQualities,
        ),
        Episode(
          id: 'jjk-s2e23',
          number: 23,
          title: 'Shibuya — la fin du chaos',
          thumbnail: _thumb(_jjkThumbs, 23),
          date: DateTime(2023, 12, 28),
          qualities: _jjkQualities('jjk-s2e23', 23),
        ),
      ]),
    ],
  ),
  Anime(
    id: 'demon-slayer',
    title: 'Demon Slayer',
    posterAsset: 'assets/img/poster_demon_slayer.png',
    backdropAsset: 'assets/img/poster_demon_slayer.png',
    description: "Après le massacre de sa famille par un démon, Tanjiro Kamado rejoint les pourfendeurs de démons "
        "pour trouver un remède à la malédiction de sa sœur Nezuko. Armé de sa lame et d'une volonté inébranlable, "
        "il affronte les douze lunes démoniaques aux côtés de Zenitsu et Inosuke.",
    genres: const ['Action', 'Aventure', 'Fantastique', 'Historique'],
    year: 2019,
    rating: 9.0,
    status: AnimeStatus.ongoing,
    languages: const ['VF', 'VOSTFR'],
    source: 'OtakuStream',
    popularity: 96,
    followers: 1100000,
    seasons: [
      Season(id: 'ds-s1', number: 1, episodes: _rangeEpisodes(
        seasonId: 'ds-s1',
        from: 1,
        to: 26,
        firstDate: DateTime(2019, 4, 6),
        thumbs: _dsThumbs,
        qualities: (String id, _) => _qualities(id, hdBytes: (600 * _mb).round(), sdBytes: (350 * _mb).round()),
      )),
      Season(id: 'ds-s2', number: 2, episodes: [
        ..._rangeEpisodes(
          seasonId: 'ds-s2',
          from: 1,
          to: 10,
          firstDate: DateTime(2021, 12, 5),
          thumbs: _dsThumbs,
          qualities: _dsQualities,
        ),
        Episode(
          id: 'ds-s2e11',
          number: 11,
          title: 'Le quartier des plaisirs',
          thumbnail: _thumb(_dsThumbs, 11),
          date: DateTime(2022, 2, 13),
          qualities: _dsQualities('ds-s2e11', 11),
        ),
      ]),
      Season(id: 'ds-s3', number: 3, episodes: [
        ..._rangeEpisodes(
          seasonId: 'ds-s3',
          from: 1,
          to: 10,
          firstDate: DateTime(2023, 4, 9),
          thumbs: _dsThumbs,
          qualities: _dsQualities,
        ),
        Episode(
          id: 'ds-s3e11',
          number: 11,
          title: 'L\'union des pourfendeurs',
          thumbnail: _thumb(_dsThumbs, 11),
          date: DateTime(2023, 6, 18),
          qualities: _dsQualities('ds-s3e11', 11),
        ),
      ]),
      Season(id: 'ds-s4', number: 4, episodes: [
        ..._rangeEpisodes(
          seasonId: 'ds-s4',
          from: 1,
          to: 10,
          firstDate: DateTime(2024, 5, 12),
          thumbs: _dsThumbs,
          qualities: _dsQualities,
        ),
        Episode(
          id: 'ds-s4e11',
          number: 11,
          title: 'La forteresse infinie',
          thumbnail: _thumb(_dsThumbs, 11),
          date: DateTime(2024, 7, 21),
          qualities: _dsQualities('ds-s4e11', 11),
        ),
      ]),
    ],
  ),
];
