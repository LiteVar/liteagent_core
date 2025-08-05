import 'package:json_annotation/json_annotation.dart';
part 'mcp_http.g.dart';

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class McpHttp {
  String url;
  OAuthTokens? oAuthTokens;

  McpHttp({required this.url, this.oAuthTokens});

  factory McpHttp.fromJson(Map<String, dynamic> json) => _$McpHttpFromJson(json);
  Map<String, dynamic> toJson() => _$McpHttpToJson(this);
}

@JsonSerializable(explicitToJson: true, includeIfNull: false)
class OAuthTokens {
  String accessToken;
  String? refreshToken;

  OAuthTokens({required this.accessToken, this.refreshToken});

  factory OAuthTokens.fromJson(Map<String, dynamic> json) => _$OAuthTokensFromJson(json);
  Map<String, dynamic> toJson() => _$OAuthTokensToJson(this);
}