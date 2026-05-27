unit AppConfigU;

interface

type
  TAppConfig = class
  public
    class function DefaultLanguage: string;
    class function HttpPort: Integer;
    class function DatabasePath: string;
    class function SeedYamlPath: string;
    class function AppPath: string;
  end;

implementation

uses
  System.SysUtils, System.IOUtils;

class function TAppConfig.AppPath: string;
begin
  Result := TPath.GetDirectoryName(ParamStr(0));
end;

class function TAppConfig.DefaultLanguage: string;
begin
  Result := GetEnvironmentVariable('DEFAULT_LANGUAGE');
  if Result.IsEmpty then
    Result := 'de';
end;

class function TAppConfig.HttpPort: Integer;
var
  LRaw: string;
begin
  LRaw := GetEnvironmentVariable('HTTP_PORT');
  if LRaw.IsEmpty or not TryStrToInt(LRaw, Result) then
    Result := 8080;
end;

class function TAppConfig.DatabasePath: string;
var
  LRaw: string;
begin
  LRaw := GetEnvironmentVariable('DATABASE_PATH');
  if LRaw.IsEmpty then
    Result := TPath.Combine(AppPath, 'data' + PathDelim + 'ffcompanion.db')
  else
    Result := LRaw;
end;

class function TAppConfig.SeedYamlPath: string;
begin
  Result := TPath.Combine(AppPath, 'data' + PathDelim + 'books_seed.yaml');
end;

end.
