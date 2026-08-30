import '../models/anime.dart';
import '../models/episode.dart';
import '../models/season.dart';
import '../models/video_quality.dart';

/// Données de démonstration locales.
///
/// Cette source sera remplacée par l'API backend (alimentée par Telegram)
/// dans une étape ultérieure ; la forme des modèles restera identique.
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
    languages: const ['VF', 'VOSTFR'],
    source: 'AnimeHD',
    popularity: 99,
    followers: 1520000,
    seasons: [
      Season(id: 'sl-s1', number: 1, episodes: [
        ..._rangeEpisodes('sl-s1', 1, 11, const [VideoQuality.fhd, VideoQuality.hd]),
        const Episode(id: 'sl-s1e12', number: 12, title: 'Arise', qualities: [VideoQuality.fhd, VideoQuality.hd, VideoQuality.sd]),
      ]),
      Season(id: 'sl-s2', number: 2, episodes: [
        ..._rangeEpisodes('sl-s2', 1, 7, const [VideoQuality.fhd, VideoQuality.hd, VideoQuality.sd]),
        const Episode(id: 'sl-s2e8', number: 8, title: 'La monarchie des ombres', qualities: [VideoQuality.fhd, VideoQuality.hd, VideoQuality.sd]),
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
    languages: const ['VOSTFR'],
    source: 'OtakuStream',
    popularity: 98,
    followers: 3200000,
    seasons: [
      Season(id: 'op-s1', number: 1, episodes: [
        ..._rangeEpisodes('op-s1', 1, 1119, const [VideoQuality.hd, VideoQuality.sd]),
        const Episode(id: 'op-s1e1120', number: 1120, title: 'La colère de Loki', qualities: [VideoQuality.hd, VideoQuality.sd]),
        const Episode(id: 'op-s1e1121', number: 1121, title: 'Le géant de fer', qualities: [VideoQuality.hd, VideoQuality.sd]),
        const Episode(id: 'op-s1e1122', number: 1122, title: 'Le royaume d\'Elbaf', qualities: [VideoQuality.hd, VideoQuality.sd]),
        const Episode(id: 'op-s1e1123', number: 1123, title: 'Le serment des géants', qualities: [VideoQuality.hd, VideoQuality.sd]),
        const Episode(id: 'op-s1e1124', number: 1124, title: 'L\'éveil du soleil', qualities: [VideoQuality.hd, VideoQuality.sd]),
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
    languages: const ['VF', 'VOSTFR'],
    source: 'AnimeHD',
    popularity: 95,
    followers: 980000,
    seasons: [
      Season(id: 'jjk-s1', number: 1, episodes: [
        ..._rangeEpisodes('jjk-s1', 1, 23, const [VideoQuality.hd, VideoQuality.sd]),
        const Episode(id: 'jjk-s1e24', number: 24, title: 'Accomplissement', qualities: [VideoQuality.hd, VideoQuality.sd]),
      ]),
      Season(id: 'jjk-s2', number: 2, episodes: [
        ..._rangeEpisodes('jjk-s2', 1, 22, const [VideoQuality.fhd, VideoQuality.hd, VideoQuality.sd]),
        const Episode(id: 'jjk-s2e23', number: 23, title: 'Shibuya — la fin du chaos', qualities: [VideoQuality.fhd, VideoQuality.hd, VideoQuality.sd]),
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
    languages: const ['VF', 'VOSTFR'],
    source: 'OtakuStream',
    popularity: 96,
    followers: 1100000,
    seasons: [
      Season(id: 'ds-s1', number: 1, episodes: _rangeEpisodes('ds-s1', 1, 26, const [VideoQuality.hd, VideoQuality.sd])),
      Season(id: 'ds-s2', number: 2, episodes: _rangeEpisodes('ds-s2', 1, 11, const [VideoQuality.fhd, VideoQuality.hd, VideoQuality.sd])),
      Season(id: 'ds-s3', number: 3, episodes: _rangeEpisodes('ds-s3', 1, 11, const [VideoQuality.fhd, VideoQuality.hd, VideoQuality.sd])),
      Season(id: 'ds-s4', number: 4, episodes: [
        ..._rangeEpisodes('ds-s4', 1, 10, const [VideoQuality.fhd, VideoQuality.hd, VideoQuality.sd]),
        const Episode(id: 'ds-s4e11', number: 11, title: 'La forteresse infinie', qualities: [VideoQuality.fhd, VideoQuality.hd, VideoQuality.sd]),
      ]),
    ],
  ),
];

/// Génère des épisodes consécutifs (de [from] à [to]) sans titre.
List<Episode> _rangeEpisodes(String seasonId, int from, int to, List<VideoQuality> qualities) => [
      for (int number = from; number <= to; number++)
        Episode(id: '$seasonId-e$number', number: number, qualities: qualities),
    ];
