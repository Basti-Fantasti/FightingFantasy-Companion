program FFCompanion;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Web.HTTPApp,
  Web.WebReq,
  Web.WebBroker,
  MVCFramework.Logger,
  MVCFramework.Commons,
  MVCFramework.Signal,
  MVCFramework.SQLGenerators.Sqlite,
  IdHTTPWebBrokerBridge,
  WebModuleU in 'webmodule\WebModuleU.pas' {FFWebModule: TWebModule},
  AppConfigU in 'config\AppConfigU.pas',
  Controllers.BaseU in 'controllers\Controllers.BaseU.pas';

procedure RunServer(APort: Integer);
var
  LServer: TIdHTTPWebBrokerBridge;
begin
  Writeln('Starting FFCompanion on port ', APort);
  LServer := TIdHTTPWebBrokerBridge.Create(nil);
  try
    LServer.DefaultPort := APort;
    LServer.Active := True;
    WaitForTerminationSignal;
    LServer.Active := False;
  finally
    LServer.Free;
  end;
end;

begin
  if not WebRequestHandler.WebModuleClass.InheritsFrom(TWebModule) then
    WebRequestHandler.WebModuleClass := WebModuleClass;
  try
    RunServer(TAppConfig.HttpPort);
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
