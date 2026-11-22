class DbVersion {
  final int version;

  DbVersion({
    required this.version,
  });

  Map<String, dynamic> toMap() {
    return {
      'version': version,
    };
  }

  factory DbVersion.fromMap(Map<String, dynamic> map) {
    return DbVersion(
      version: map['version'] as int,
    );
  }
}