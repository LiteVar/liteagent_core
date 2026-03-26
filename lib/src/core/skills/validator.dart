import 'exception.dart';
import 'model.dart';

class SkillValidator {
  static final RegExp _skillNameRegExp =
      RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$');

  const SkillValidator();

  void validate(SkillDefinition skill) {
    validateManifest(skill.manifest);
    validateInstructions(skill.instructions);
  }

  void validateManifest(SkillManifest manifest) {
    if (manifest.name.isEmpty) {
      throw const SkillValidateException(message: 'Skill name is required');
    }
    if (!_skillNameRegExp.hasMatch(manifest.name) ||
        manifest.name.contains('--')) {
      throw SkillValidateException(
        message: 'Invalid skill name: ${manifest.name}',
      );
    }
    if (manifest.description.trim().isEmpty) {
      throw const SkillValidateException(
        message: 'Skill description is required',
      );
    }
    if (manifest.description.length > 1024) {
      throw const SkillValidateException(
        message: 'Skill description is too long',
      );
    }
    if (manifest.compatibility != null &&
        manifest.compatibility!.length > 500) {
      throw const SkillValidateException(
        message: 'Skill compatibility is too long',
      );
    }
  }

  void validateInstructions(String instructions) {
    if (instructions.trim().isEmpty) {
      throw const SkillValidateException(
        message: 'Skill instructions are required',
      );
    }
  }
}
