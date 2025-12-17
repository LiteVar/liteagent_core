// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mcp_http.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

McpHttp _$McpHttpFromJson(Map<String, dynamic> json) => McpHttp(
      url: json['url'] as String,
      oAuthTokens: json['oAuthTokens'] == null
          ? null
          : OAuthTokens.fromJson(json['oAuthTokens'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$McpHttpToJson(McpHttp instance) {
  final val = <String, dynamic>{
    'url': instance.url,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('oAuthTokens', instance.oAuthTokens?.toJson());
  return val;
}

OAuthTokens _$OAuthTokensFromJson(Map<String, dynamic> json) => OAuthTokens(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String?,
    );

Map<String, dynamic> _$OAuthTokensToJson(OAuthTokens instance) {
  final val = <String, dynamic>{
    'accessToken': instance.accessToken,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('refreshToken', instance.refreshToken);
  return val;
}
