class DbVersion {
  final int version;
  final bool isPublished;

  DbVersion({
    required this.version,
    this.isPublished = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'version': version,
      'is_published': isPublished ? 1 : 0,
    };
  }

  factory DbVersion.fromMap(Map<String, dynamic> map) {
    return DbVersion(
      version: map['version'] as int,
      isPublished: (map['is_published'] as int? ?? 0) == 1,
    );
  }
}