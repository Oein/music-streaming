// Data models mirroring the server API responses.

class Album {
  final int id;
  final String name;
  final String? albumArtist;
  final int? year;
  final int? coverArtId;
  final int trackCount;

  Album({
    required this.id,
    required this.name,
    this.albumArtist,
    this.year,
    this.coverArtId,
    this.trackCount = 0,
  });

  factory Album.fromJson(Map<String, dynamic> j) => Album(
        id: j['id'] as int,
        name: j['name'] as String,
        albumArtist: j['albumArtist'] as String?,
        year: j['year'] as int?,
        coverArtId: j['coverArtId'] as int?,
        trackCount: (j['trackCount'] as int?) ?? 0,
      );
}

class Track {
  final int id;
  final String title;
  final String? artist;
  final int? albumId;
  final int? trackNo;
  final double? duration;
  final String format;
  final int? coverArtId;

  Track({
    required this.id,
    required this.title,
    this.artist,
    this.albumId,
    this.trackNo,
    this.duration,
    required this.format,
    this.coverArtId,
  });

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as int,
        title: j['title'] as String,
        artist: j['artist'] as String?,
        albumId: j['albumId'] as int?,
        trackNo: j['trackNo'] as int?,
        duration: (j['duration'] as num?)?.toDouble(),
        format: j['format'] as String,
        coverArtId: j['coverArtId'] as int?,
      );
}

class Playlist {
  final int id;
  final String name;
  final int trackCount;

  Playlist({required this.id, required this.name, this.trackCount = 0});

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'] as int,
        name: j['name'] as String,
        trackCount: (j['trackCount'] as int?) ?? 0,
      );
}

// --- Listening stats ---

// One day on the listening heatmap.
class ListenDay {
  final DateTime day; // local date (midnight)
  final double seconds;
  final int plays;
  ListenDay(this.day, this.seconds, this.plays);

  factory ListenDay.fromJson(Map<String, dynamic> j) => ListenDay(
        parseDay(j['day'] as String),
        (j['seconds'] as num).toDouble(),
        (j['plays'] as num).toInt(),
      );
}

// A track's listening total within a day or range. [track] is null when the
// file has since left the library; title/artist are kept from the listen.
class TrackListenStat {
  final Track? track;
  final String title;
  final String? artist;
  final String? albumName;
  final double seconds;
  final int plays;
  TrackListenStat(this.track, this.title, this.artist, this.albumName,
      this.seconds, this.plays);

  factory TrackListenStat.fromJson(Map<String, dynamic> j) => TrackListenStat(
        j['track'] == null
            ? null
            : Track.fromJson((j['track'] as Map).cast<String, dynamic>()),
        j['title'] as String,
        j['artist'] as String?,
        j['albumName'] as String?,
        (j['seconds'] as num).toDouble(),
        (j['plays'] as num).toInt(),
      );
}

class AlbumListenStat {
  final Album? album;
  final String name;
  final double seconds;
  final int plays;
  AlbumListenStat(this.album, this.name, this.seconds, this.plays);

  factory AlbumListenStat.fromJson(Map<String, dynamic> j) => AlbumListenStat(
        j['album'] == null
            ? null
            : Album.fromJson((j['album'] as Map).cast<String, dynamic>()),
        j['name'] as String,
        (j['seconds'] as num).toDouble(),
        (j['plays'] as num).toInt(),
      );
}

class ArtistListenStat {
  final String name;
  final double seconds;
  final int plays;
  ArtistListenStat(this.name, this.seconds, this.plays);

  factory ArtistListenStat.fromJson(Map<String, dynamic> j) => ArtistListenStat(
        j['name'] as String,
        (j['seconds'] as num).toDouble(),
        (j['plays'] as num).toInt(),
      );
}

class DayListenDetail {
  final DateTime day;
  final double seconds;
  final int plays;
  final List<TrackListenStat> tracks;
  DayListenDetail(this.day, this.seconds, this.plays, this.tracks);

  factory DayListenDetail.fromJson(Map<String, dynamic> j) => DayListenDetail(
        parseDay(j['day'] as String),
        (j['seconds'] as num).toDouble(),
        (j['plays'] as num).toInt(),
        (j['tracks'] as List)
            .map((e) => TrackListenStat.fromJson((e as Map).cast()))
            .toList(),
      );
}

class TopListens {
  final double seconds;
  final int plays;
  final int days;
  final List<TrackListenStat> tracks;
  final List<AlbumListenStat> albums;
  final List<ArtistListenStat> artists;
  TopListens(this.seconds, this.plays, this.days, this.tracks, this.albums,
      this.artists);

  factory TopListens.fromJson(Map<String, dynamic> j) => TopListens(
        (j['seconds'] as num).toDouble(),
        (j['plays'] as num).toInt(),
        (j['days'] as num).toInt(),
        (j['tracks'] as List)
            .map((e) => TrackListenStat.fromJson((e as Map).cast()))
            .toList(),
        (j['albums'] as List)
            .map((e) => AlbumListenStat.fromJson((e as Map).cast()))
            .toList(),
        (j['artists'] as List)
            .map((e) => ArtistListenStat.fromJson((e as Map).cast()))
            .toList(),
      );
}

// YYYY-MM-DD <-> local midnight DateTime.
DateTime parseDay(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

String formatDay(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}
