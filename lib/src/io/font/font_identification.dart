class FontIdentification {
  String? ttfVersion;
  String? ttfUniqueId;
  int? type1Xuid;
  String? panose;

  String? getTtfVersion() => ttfVersion;

  String? getTtfUniqueId() => ttfUniqueId;

  int? getType1Xuid() => type1Xuid;

  String? getPanose() => panose;

  void setTtfVersion(String ttfVersion) {
    this.ttfVersion = ttfVersion;
  }

  void setTtfUniqueId(String ttfUniqueId) {
    this.ttfUniqueId = ttfUniqueId;
  }

  void setType1Xuid(int? type1Xuid) {
    this.type1Xuid = type1Xuid;
  }

  void setPanose(dynamic panose) {
    if (panose is List<int>) {
      this.panose = String.fromCharCodes(panose);
    } else if (panose is String) {
      this.panose = panose;
    }
  }
}
