class SkillParseException implements Exception {
  final String message;

  const SkillParseException({required this.message});

  @override
  String toString() {
    return 'SkillParseException: $message';
  }
}

class SkillValidateException implements Exception {
  final String message;

  const SkillValidateException({required this.message});

  @override
  String toString() {
    return 'SkillValidateException: $message';
  }
}
