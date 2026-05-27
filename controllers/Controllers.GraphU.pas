{*******************************************************************************
  Unit Name: Controllers.GraphU
  Purpose: HTTP controller exposing the graph.json endpoint for the play view

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Defines TGraphController, mounted at /adventures/:adv_id/graph.json. The
    single GET action requires login + ownership, delegates to
    TGraphBuilder.Build, and writes the resulting payload back as raw
    application/json. The Cytoscape glue in static/js/app.js consumes the
    response when the Graph tab is active and after graph-changed HTMX
    events.

  Dependencies:
    - DMVCFramework (MVCFramework, MVCFramework.Commons)
    - Controllers.BaseU
    - Repositories.AdventuresU
    - Services.GraphBuilderU
*******************************************************************************}

unit Controllers.GraphU;

interface

uses
  MVCFramework, MVCFramework.Commons,
  Controllers.BaseU;

type
  /// <summary>
  ///   Controller exposing the read-only graph.json endpoint for a single
  ///   adventure. Used by the front-end graph tab to render the section
  ///   transition graph with Cytoscape.
  /// </summary>
  [MVCPath('/adventures/($AdvId)/graph.json')]
  TGraphController = class(TBaseController)
  public
    /// <summary>
    ///   Returns the graph payload (current section, nodes, edges) for the
    ///   adventure. Verifies login + ownership; foreign adventure ids return
    ///   404 to avoid leaking existence.
    /// </summary>
    [MVCPath('')]
    [MVCHTTPMethod([httpGET])]
    [MVCProduces(TMVCMediaType.APPLICATION_JSON)]
    procedure GetGraph(AdvId: Int64);
  end;

implementation

uses
  System.SysUtils,
  JsonDataObjects,
  Models.AdventureU,
  Repositories.AdventuresU,
  Services.GraphBuilderU;

const
  CMainConnection = 'FFMain';

resourcestring
  SAdventureGone = 'Adventure not found.';

{ TGraphController }

procedure TGraphController.GetGraph(AdvId: Int64);
var
  LAdvRepo: TAdventuresRepo;
  LBuilder: TGraphBuilder;
  LAdv: TAdventure;
  LPayload: TJsonObject;
begin
  RequireLogin;

  LAdvRepo := TAdventuresRepo.Create(CMainConnection);
  try
    if not LAdvRepo.TryGetById(AdvId, LAdv) then
    begin
      Context.Response.StatusCode := HTTP_STATUS.NotFound;
      Render(SAdventureGone);
      Exit;
    end;
    if LAdv.UserId <> CurrentUserId then
    begin
      Context.Response.StatusCode := HTTP_STATUS.NotFound;
      Render(SAdventureGone);
      Exit;
    end;
  finally
    LAdvRepo.Free;
  end;

  LBuilder := TGraphBuilder.Create(CMainConnection);
  try
    LPayload := LBuilder.Build(AdvId);
    try
      // Write the JSON payload directly as the response body so the client
      // receives the exact graph.json shape — not a wrapped envelope.
      Context.Response.ContentType := TMVCMediaType.APPLICATION_JSON;
      Render(LPayload.ToJSON);
    finally
      LPayload.Free;
    end;
  finally
    LBuilder.Free;
  end;
end;

end.
