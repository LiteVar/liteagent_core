import 'package:front_matter_ml/front_matter_ml.dart' as fm;

import 'exception.dart';
import 'model.dart';

abstract class SkillParser {
  SkillDefinition parse(String raw);
}

class MarkdownSkillParser implements SkillParser {
  @override
  SkillDefinition parse(String raw) {
    try {
      final document = fm.parse(raw);
      final data = _normalizeData(document.data);
      final instructions = (document.content ?? '').trim();

      final name = _readRequiredString(data, 'name');
      final description = _readRequiredString(data, 'description');
      final license = _readOptionalString(data, 'license');
      final compatibility = _readOptionalString(data, 'compatibility');
      final allowedTools = _readStringList(data, 'allowed-tools');

      final metadata = Map<String, dynamic>.from(data)
        ..remove('name')
        ..remove('description')
        ..remove('license')
        ..remove('compatibility')
        ..remove('allowed-tools');

      return SkillDefinition(
        manifest: SkillManifest(
          name: name,
          description: description,
          license: license,
          compatibility: compatibility,
          allowedTools: allowedTools,
          metadata: metadata,
        ),
        instructions: instructions,
        raw: raw,
      );
    } catch (e) {
      if (e is SkillParseException) rethrow;
      throw SkillParseException(message: e.toString());
    }
  }

  Map<String, dynamic> _normalizeData(dynamic data) {
    if (data is Map) {
      return Map<String, dynamic>.fromEntries(
        data.entries.map(
          (entry) => MapEntry(entry.key.toString(), entry.value),
        ),
      );
    }
    throw const SkillParseException(
      message: 'Invalid front matter metadata',
    );
  }

  String _readRequiredString(Map<String, dynamic> data, String key) {
    final value = _readOptionalString(data, key);
    if (value == null || value.isEmpty) {
      throw SkillParseException(message: 'Missing required field: $key');
    }
    return value;
  }

  String? _readOptionalString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return null;
    if (value is! String) {
      throw SkillParseException(message: 'Field must be a string: $key');
    }
    return value.trim();
  }

  List<String> _readStringList(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return const [];
    if (value is! List) {
      throw SkillParseException(message: 'Field must be a list: $key');
    }
    return value.map((item) {
      if (item is! String) {
        throw SkillParseException(
          message: 'Field list items must be strings: $key',
        );
      }
      return item.trim();
    }).toList(growable: false);
  }
}
