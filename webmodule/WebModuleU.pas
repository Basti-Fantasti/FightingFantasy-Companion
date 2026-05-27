{*******************************************************************************
  Unit Name: WebModuleU
  Purpose: WebBroker module hosting the DMVCFramework engine for FFCompanion

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Defines TFFWebModule, the WebBroker TWebModule descendant that creates and
    configures the central TMVCEngine instance: TemplatePro view engine, static
    file middleware, and in-memory session middleware. Controllers are
    registered here in subsequent phases.

    Project naming convention: this project uses the U-SUFFIX style for unit
    names (e.g. WebModuleU, AppConfigU, Controllers.AuthU) to match the
    DMVCFramework sample convention. New units should follow the same pattern.

  Dependencies:
    - DMVCFramework (MVCFramework, MVCFramework.Commons, ...)
    - Web.HTTPApp (WebBroker)
    - AppConfigU
*******************************************************************************}

unit WebModuleU;

interface

uses
  System.SysUtils, System.Classes, Web.HTTPApp,
  MVCFramework;

type
  /// <summary>
  ///   WebBroker module that owns and configures the DMVCFramework engine
  ///   (views, middlewares, controllers) for the FFCompanion application.
  /// </summary>
  TFFWebModule = class(TWebModule)
    procedure WebModuleCreate(Sender: TObject);
    procedure WebModuleDestroy(Sender: TObject);
  private
    FMVC: TMVCEngine;
  end;

var
  /// WebBroker discovery hook: assigned to WebRequestHandler.WebModuleClass on startup.
  WebModuleClass: TComponentClass = TFFWebModule;

implementation

{$R *.dfm}

uses
  System.IOUtils,
  MVCFramework.Commons,
  MVCFramework.View.Renderers.TemplatePro,
  MVCFramework.Middleware.StaticFiles,
  MVCFramework.Middleware.Session,
  AppConfigU,
  Repositories.MigrationU;

procedure TFFWebModule.WebModuleCreate(Sender: TObject);
var
  LConnName: string;
begin
  // Ensure the SQLite database exists and is migrated before any controller
  // can touch it. Runs once per WebModule (one per worker on Indy).
  LConnName := TMigrationRunner.CreateFileConnection(TAppConfig.DatabasePath);
  TMigrationRunner.RunOnConnection(LConnName);

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
