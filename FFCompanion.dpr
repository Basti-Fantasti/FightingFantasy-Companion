program FFCompanion;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  MVCFramework.Logger,
  MVCFramework.Commons,
  MVCFramework.Signal,
  MVCFramework.SQLGenerators.Sqlite,
  IdHTTPWebBrokerBridge,
  Web.HTTPApp,
  Web.WebReq,
  Web.WebBroker,
  WebModuleU in 'webmodule\WebModuleU.pas' {FFWebModule: TWebModule},
  AppConfigU in 'config\AppConfigU.pas';

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
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
