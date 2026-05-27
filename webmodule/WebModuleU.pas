unit WebModuleU;

interface

uses
  System.SysUtils, System.Classes, Web.HTTPApp,
  MVCFramework;

type
  TFFWebModule = class(TWebModule)
    procedure WebModuleCreate(Sender: TObject);
    procedure WebModuleDestroy(Sender: TObject);
  private
    FMVC: TMVCEngine;
  end;

var
  WebModuleClass: TComponentClass = TFFWebModule;

implementation

{$R *.dfm}

uses
  System.IOUtils,
  MVCFramework.Commons,
  MVCFramework.View.Renderers.TemplatePro,
  MVCFramework.Middleware.StaticFiles,
  MVCFramework.Middleware.Session,
  AppConfigU;

procedure TFFWebModule.WebModuleCreate(Sender: TObject);
begin
  FMVC := TMVCEngine.Create(Self,
    procedure(Config: TMVCConfig)
    begin
      Config[TMVCConfigKey.ViewPath] := 'templates';
      Config[TMVCConfigKey.DefaultViewFileExtension] := 'html';
      Config[TMVCConfigKey.DefaultContentType] := TMVCMediaType.TEXT_HTML;
    end);
  FMVC.SetViewEngine(TMVCTemplateProViewEngine);
  FMVC.AddMiddleware(TMVCStaticFilesMiddleware.Create('/static',
    TPath.Combine(TAppConfig.AppPath, 'static')));
  FMVC.AddMiddleware(UseMemorySessionMiddleware(0));
  // Controllers added in later phases:
  // FMVC.AddController(TAuthController);
  // FMVC.AddController(TAdventuresController);
  // ...
end;

procedure TFFWebModule.WebModuleDestroy(Sender: TObject);
begin
  FMVC.Free;
end;

end.
