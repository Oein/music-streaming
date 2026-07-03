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
