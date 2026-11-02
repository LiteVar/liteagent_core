class LLMProviderType {
  static const String openai = "openai";
  static const String liteOneApi = "lite_oneapi";

  static String normalize(String? provider) {
    if (provider == null || provider.trim().isEmpty) {
      return openai;
    }

    final normalized = provider.trim().toLowerCase();
    switch (normalized) {
      case "openai":
        return openai;
      case "lite_oneapi":
      case "liteoneapi":
      case "oneapi":
        return liteOneApi;
      default:
        return normalized;
    }
  }

  static bool isSupported(String? provider) {
    final normalized = normalize(provider);
    return normalized == openai || normalized == liteOneApi;
  }
}
