{*******************************************************************************
  Unit Name: AppConfigU
  Purpose: Centralised application configuration sourced from environment vars

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Exposes TAppConfig with class functions that resolve runtime configuration
    values (HTTP port, default language, database path, seed YAML path,
    application directory) from environment variables, with sensible defaults
    when the variables are absent or invalid.

  Dependencies:
    - System.SysUtils
    - System.IOUtils
*******************************************************************************}

unit AppConfigU;

interface

type
  /// <summary>
  ///   Static accessor for FFCompanion runtime configuration values.
  ///   All methods are class functions; do not instantiate.
  /// </summary>
  TAppConfig = class
  public
    /// <summary>
    ///   Returns the default UI language code. Reads env var DEFAULT_LANGUAGE.
    /// </summary>
    /// <returns>Language code (e.g. 'de', 'en'); defaults to 'de' if unset.</returns>
    class function DefaultLanguage: string;

    /// <summary>
    ///   Returns the HTTP listener port. Reads env var HTTP_PORT.
    /// </summary>
    /// <returns>Port number; defaults to 8080 if unset or not a valid integer.</returns>
    class function HttpPort: Integer;

    /// <summary>
    ///   Returns the SQLite database file path. Reads env var DATABASE_PATH.
    /// </summary>
    /// <returns>
    ///   The env var value if set; otherwise &lt;AppPath&gt;/data/ffcompanion.db.
    /// </returns>
    class function DatabasePath: string;

    /// <summary>
    ///   Returns the path to the YAML seed file containing initial book data.
    /// </summary>
    /// <returns>&lt;AppPath&gt;/data/books_seed.yaml.</returns>
    class function SeedYamlPath: string;

    /// <summary>
    ///   Returns the directory containing the running executable.
    /// </summary>
    /// <returns>Absolute path to the application directory.</returns>
    class function AppPath: string;
  end;

implementation

uses
  System.SysUtils, System.IOUtils;

const
  DEFAULT_HTTP_PORT = 8080;
  DEFAULT_LANG      = 'de';

class function TAppConfig.AppPath: string;
begin
  Result := TPath.GetDirectoryName(ParamStr(0));
end;

class function TAppConfig.DefaultLanguage: string;
begin
  Result := GetEnvironmentVariable('DEFAULT_LANGUAGE');
  if Result.IsEmpty then
    Result := DEFAULT_LANG;
end;

class function TAppConfig.HttpPort: Integer;
var
  LRaw: string;
begin
  LRaw := GetEnvironmentVariable('HTTP_PORT');
  if LRaw.IsEmpty or not TryStrToInt(LRaw, Result) then
    Result := DEFAULT_HTTP_PORT;
end;

class function TAppConfig.DatabasePath: string;
var
  LRaw: string;
begin
  LRaw := GetEnvironmentVariable('DATABASE_PATH');
  if LRaw.IsEmpty then
    Result := TPath.Combine(TPath.Combine(AppPath, 'data'), 'ffcompanion.db')
  else
    Result := LRaw;
end;

class function TAppConfig.SeedYamlPath: string;
begin
  Result := TPath.Combine(TPath.Combine(AppPath, 'data'), 'books_seed.yaml');
end;

end.
