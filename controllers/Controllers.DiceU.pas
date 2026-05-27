{*******************************************************************************
  Unit Name: Controllers.DiceU
  Purpose: HTTP controller backing the dice roller panel

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Defines TDiceController, mounted under /adventures/:adv_id/roll. Accepts a
    single POST that rolls the requested dice expression ('2d6' or '1d6') and
    re-renders the dice panel fragment with the latest result and a short
    history of recent rolls. Each roll persists a row in dice_rolls; rolls
    made before any step is logged are attached with step_id NULL.

    Ownership is verified before any read/write. Foreign adventure ids return
    404 to avoid leaking existence. Unsupported expressions are rejected with
    400 and a small Bulma error fragment so HTMX can swap it into the panel.

  Dependencies:
    - DMVCFramework (MVCFramework, MVCFramework.Commons)
    - Controllers.BaseU
    - Repositories.AdventuresU, Repositories.DiceRollsU
*******************************************************************************}

unit Controllers.DiceU;

interface

uses
  MVCFramework, MVCFramework.Commons,
  Controllers.BaseU;

type
  /// <summary>
  ///   Controller exposing the single POST endpoint that rolls dice for an
  ///   adventure and returns the refreshed dice panel fragment.
  /// </summary>
  [MVCPath('/adventures/($AdvId)/roll')]
  TDiceController = class(TBaseController)
  public
    /// <summary>
    ///   Rolls the submitted dice expression ('2d6' or '1d6'), persists the
    ///   result against the adventure (attached to the current step if any),
    ///   and returns the refreshed _dice_panel.html fragment.
    /// </summary>
    [MVCPath('')]
    [MVCHTTPMethod([httpPOST])]
    [MVCConsumes(TMVCMediaType.APPLICATION_FORM_URLENCODED)]
    [MVCProduces(TMVCMediaType.TEXT_HTML)]
    procedure Roll(AdvId: Int64;
      [MVCFromContentField('expression', '2d6')] AExpression: string);
  end;

implementation

uses
  System.SysUtils,
  JsonDataObjects,
  Models.AdventureU, Models.DiceRollU,
  Repositories.AdventuresU, Repositories.DiceRollsU;

const
  CMainConnection = 'FFMain';
  CExpr2d6 = '2d6';
  CExpr1d6 = '1d6';
  CHistoryLimit = 3;

resourcestring
  SAdventureGone = 'Adventure not found.';
  SInvalidExpr   = 'Unsupported dice expression.';

/// <summary>
///   Rolls the given expression. Supports the two whitelisted forms only.
///   Caller must validate the expression before invoking.
/// </summary>
function RollExpression(const AExpression: string): Integer;
var
  LCount, LFaces, I: Integer;
begin
  if AExpression = CExpr1d6 then
  begin
    LCount := 1;
    LFaces := 6;
  end
  else // CExpr2d6
  begin
    LCount := 2;
    LFaces := 6;
  end;
  Result := 0;
  for I := 1 to LCount do
    Result := Result + Random(LFaces) + 1;
end;

{ TDiceController }

procedure TDiceController.Roll(AdvId: Int64; AExpression: string);
var
  LAdvRepo: TAdventuresRepo;
  LDiceRepo: TDiceRollsRepo;
  LAdv: TAdventure;
  LResult: Integer;
  LRecent: TArray<TDiceRoll>;
  LRoll: TDiceRoll;
  LLastRoll: TJsonObject;
  LRecentArr: TJsonArray;
  LObj, LAdvObj: TJsonObject;
begin
  RequireLogin;

  AExpression := Trim(LowerCase(AExpression));
  if (AExpression <> CExpr2d6) and (AExpression <> CExpr1d6) then
  begin
    Context.Response.StatusCode := HTTP_STATUS.BadRequest;
    Render(Format('<div class="notification is-danger">%s</div>',
      [SInvalidExpr]));
    Exit;
  end;

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

  LResult := RollExpression(AExpression);

  LDiceRepo := TDiceRollsRepo.Create(CMainConnection);
  try
    // LastStepId is 0 when no step has been logged yet — repo writes NULL.
    LDiceRepo.Insert(LAdv.Id, LAdv.LastStepId, AExpression, LResult);
    LRecent := LDiceRepo.LastN(LAdv.Id, CHistoryLimit);
  finally
    LDiceRepo.Free;
  end;

  // last_roll is just the freshly committed roll — surfaced separately so the
  // template can highlight it without depending on list order.
  LLastRoll := TJsonObject.Create;
  LLastRoll.S['expression'] := AExpression;
  LLastRoll.I['result']     := LResult;

  LRecentArr := TJsonArray.Create;
  for LRoll in LRecent do
  begin
    LObj := LRecentArr.AddObject;
    LObj.S['expression'] := LRoll.Expression;
    LObj.I['result']     := LRoll.Rolled;
  end;

  LAdvObj := TJsonObject.Create;
  LAdvObj.L['id']           := LAdv.Id;
  LAdvObj.S['title']        := LAdv.Title;
  LAdvObj.S['status']       := LAdv.Status;
  LAdvObj.L['book_id']      := LAdv.BookId;
  LAdvObj.L['last_step_id'] := LAdv.LastStepId;

  ViewData['adventure']    := LAdvObj;
  ViewData['last_roll']    := LLastRoll;
  ViewData['recent_rolls'] := LRecentArr;

  Render(RenderView('partials/_dice_panel'));
end;

end.
