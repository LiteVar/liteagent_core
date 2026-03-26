class SkillManifest {
  final String name;
  final String description;
  final String? license;
  final String? compatibility;
  final List<String> allowedTools;
  final Map<String, dynamic> metadata;

  const SkillManifest({
    required this.name,
    required this.description,
    this.license,
    this.compatibility,
    this.allowedTools = const [],
    this.metadata = const {},
  });
}

class SkillDefinition {
  final SkillManifest manifest;
  final String instructions;
  final String raw;

  const SkillDefinition({
    required this.manifest,
    required this.instructions,
    required this.raw,
  });
}
