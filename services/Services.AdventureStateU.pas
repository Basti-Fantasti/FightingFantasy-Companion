{*******************************************************************************
  Unit Name: Services.AdventureStateU
  Purpose: Folds adventure event history into a current-state snapshot

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    TAdventureStateService projects the append-only event tables (steps,
    stat_changes, inventory_events) into the live state a player needs:
    the current section, the current stat values, and the current inventory.

    GetCurrentSection resolves adventures.last_step_id to steps.to_section.
    GetStatsHistory folds stat_changes for the adventure into one TStatSnapshot
    per stat_def: seeded from stat_defs.default_value, then overwritten in
    chronological order by every non-undone stat change. Display names are
    resolved through TLocalizedTitleService using the supplied language tags.
    GetCurrentInventory folds inventory_events per item: 'gain' adds, 'lose'
    subtracts, 'modify' sets an absolute quantity. Items whose final quantity
    is zero or negative are omitted from the returned snapshot (but the
    events stay in the database for audit). Item order in the result is
    first-seen across the non-undone event timeline.

    Callers must Free the returned lists.

  Dependencies:
    - System.Generics.Collections
    - Models.StatDefU, Models.StatChangeU, Models.InventoryEventU
    - Repositories.AdventuresU, Repositories.BooksU, Repositories.StatChangesU
    - Repositories.InventoryEventsU
    - Services.LocalizedTitleU
    - FireDAC.Comp.Client
*******************************************************************************}

unit Services.AdventureStateU;

interface

uses
  System.Generics.Collections,
  Models.AdventureSpellU;

type
  /// <summary>
  ///   Current value of a single tracked stat for an adventure.
  /// </summary>
  TStatSnapshot = record
    /// <summary>stat_defs.id this snapshot is for.</summary>
    StatDefId: Int64;
    /// <summary>Localised display name for the active language.</summary>
    DisplayName: string;
    /// <summary>Stat kind ('integer', 'string', 'boolean', ...).</summary>
    Kind: string;
    /// <summary>Current value as a string, ready for rendering.</summary>
    Value: string;
    /// <summary>Starting (default) value from the stat definition, unchanged
    ///   by replayed stat_changes. Useful for showing the player how far the
    ///   current value has drifted from character creation.</summary>
    StartValue: string;
  end;

  /// <summary>
  ///   Current quantity of a single inventory item for an adventure.
  /// </summary>
  TInventoryItem = record
    /// <summary>Item display name as recorded by the player.</summary>
    Name: string;
    /// <summary>Net quantity after folding gain/lose/modify events.</summary>
    Quantity: Integer;
    /// <summary>Optional free-form note carried with the item.</summary>
    Note: string;
  end;

  /// <summary>
  ///   Read-side service that folds adventure events into current state.
  /// </summary>
  TAdventureStateService = class
  private
    FConn: string;
  public
    /// <summary>Constructs the service bound to a FireDAC connection def.</summary>
    constructor Create(const AConnectionName: string);

    /// <summary>
    ///   Returns the section number the player is currently on. Reads the
    ///   adventure's last_step_id and resolves it to steps.to_section.
    ///   Returns 0 when last_step_id is NULL (no steps recorded yet).
    /// </summary>
    function GetCurrentSection(AAdventureId: Int64): Integer;

    /// <summary>
    ///   Returns the current value of every tracked stat for the adventure.
    ///   Seeds each stat from its default value, then replays every
    ///   non-undone stat change in step-sequence order, picking the localised
    ///   display name via the four-step fallback chain.
    ///   Callers must Free the returned list.
    /// </summary>
    function GetStatsHistory(AAdventureId: Int64;
      const ACurrentLang, ADefaultLang: string): TList<TStatSnapshot>;

    /// <summary>
    ///   Returns the current inventory for the adventure with quantities
    ///   folded across the non-undone inventory_events timeline. 'gain' adds
    ///   to the running quantity, 'lose' subtracts, and 'modify' sets an
    ///   absolute value. Items with a final quantity of zero or less are
    ///   omitted. Result order is first-seen across the event timeline.
    ///   The Note field carries the note from the most recent event for
    ///   that item.
    ///   Callers must Free the returned list.
    /// </summary>
    function GetCurrentInventory(AAdventureId: Int64): TList<TInventoryItem>;

    /// <summary>
    ///   Returns one TAdventureSpellGroup per distinct spell_def used in the
    ///   adventure, with available/consumed counts and a localised display
    ///   name resolved for ALang. Falls back to any other seeded language when
    ///   ALang has no entry, and to the spell's slug when no titles exist.
    ///   Result is ordered by spell_defs.ord ASC.
    /// </summary>
    function GetSpellSnapshot(AAdventureId: Int64;
      const ALang: string): TArray<TAdventureSpellGroup>;

    /// <summary>
    ///   Returns the display names of spells consumed at each step in the
    ///   adventure, keyed by step id. Only steps with at least one cast appear
    ///   in the dictionary. Display names are localised to ALang with fallback
    ///   to any other seeded language and finally to the spell slug.
    ///   Callers must Free the returned dictionary.
    /// </summary>
    function GetSpellCastsByStep(AAdventureId: Int64;
      const ALang: string): TDictionary<Int64, TArray<string>>;
  end;

implementation

uses
  System.SysUtils,
  Data.DB,
  FireDAC.Comp.Client,
  Models.AdventureU, Models.StatDefU, Models.StatChangeU,
  Models.InventoryEventU,
  Repositories.AdventuresU, Repositories.BooksU,
  Repositories.StatChangesU,
  Repositories.InventoryEventsU,
  Repositories.SpellDefsU, Repositories.AdventureSpellsU,
  Models.SpellDefU,
  Services.LocalizedTitleU;

constructor TAdventureStateService.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

function TAdventureStateService.GetCurrentSection(AAdventureId: Int64): Integer;
var
  LC: TFDConnection;
  LQ: TFDQuery;
  LLastStepField: TField;
  LLastStepId: Int64;
begin
  Result := 0;
  LC := TFDConnection.Create(nil);
  LQ := TFDQuery.Create(nil);
  try
    LC.ConnectionDefName := FConn;
    LC.Open;
    LQ.Connection := LC;
    LQ.Open('SELECT last_step_id FROM adventures WHERE id=:i',
      [AAdventureId]);
    if LQ.Eof then
      Exit;
    LLastStepField := LQ.FieldByName('last_step_id');
    if LLastStepField.IsNull then
      Exit;
    LLastStepId := LLastStepField.AsLargeInt;
    LQ.Close;
    LQ.Open('SELECT to_section FROM steps WHERE id=:i', [LLastStepId]);
    if not LQ.Eof then
      Result := LQ.FieldByName('to_section').AsInteger;
  finally
    LQ.Free;
    LC.Free;
  end;
end;

function TAdventureStateService.GetStatsHistory(AAdventureId: Int64;
  const ACurrentLang, ADefaultLang: string): TList<TStatSnapshot>;
var
  LAdvRepo: TAdventuresRepo;
  LBooksRepo: TBooksRepo;
  LChangesRepo: TStatChangesRepo;
  LAdv: TAdventure;
  LDefs: TArray<TStatDef>;
  LDef: TStatDef;
  LTitles: TArray<TStatDefTitle>;
  LTitle: TStatDefTitle;
  LTitleDict: TDictionary<string, string>;
  LChanges: TArray<TStatChange>;
  LChange: TStatChange;
  LSnapshot: TStatSnapshot;
  LValues: TDictionary<Int64, string>;
  LStartValues: TDictionary<Int64, string>;
begin
  Result := TList<TStatSnapshot>.Create;
  LAdvRepo := TAdventuresRepo.Create(FConn);
  try
    if not LAdvRepo.TryGetById(AAdventureId, LAdv) then
      Exit;
  finally
    LAdvRepo.Free;
  end;

  LBooksRepo := TBooksRepo.Create(FConn);
  LChangesRepo := TStatChangesRepo.Create(FConn);
  LValues := TDictionary<Int64, string>.Create;
  LStartValues := TDictionary<Int64, string>.Create;
  try
    LDefs := LBooksRepo.GetStatDefs(LAdv.BookId);
    for LDef in LDefs do
      LValues.AddOrSetValue(LDef.Id, LDef.DefaultValue);

    // Replay every non-undone change in chronological (seq, id) order so the
    // last write wins per stat_def_id. The first change seen per stat is the
    // adventure's starting value (entered on the setup step); FF stat_defs
    // seed default_value=0 because real starting values are rolled per run.
    LChanges := LChangesRepo.ListByAdventure(AAdventureId, False);
    for LChange in LChanges do
      if LValues.ContainsKey(LChange.StatDefId) then
      begin
        if not LStartValues.ContainsKey(LChange.StatDefId) then
          LStartValues.Add(LChange.StatDefId, LChange.NewValue);
        LValues[LChange.StatDefId] := LChange.NewValue;
      end;

    // Build snapshots in stat-def order with localised display names.
    for LDef in LDefs do
    begin
      LTitleDict := TDictionary<string, string>.Create;
      try
        LTitles := LBooksRepo.GetStatDefTitles(LDef.Id);
        for LTitle in LTitles do
          LTitleDict.AddOrSetValue(LTitle.Lang, LTitle.DisplayName);
        LSnapshot.StatDefId   := LDef.Id;
        LSnapshot.DisplayName := TLocalizedTitleService.Pick(LTitleDict,
          ACurrentLang, ADefaultLang, LDef.Name);
      finally
        LTitleDict.Free;
      end;
      LSnapshot.Kind  := LDef.Kind;
      LSnapshot.Value := LValues[LDef.Id];
      if not LStartValues.TryGetValue(LDef.Id, LSnapshot.StartValue) then
        LSnapshot.StartValue := LDef.DefaultValue;
      Result.Add(LSnapshot);
    end;
  finally
    LStartValues.Free;
    LValues.Free;
    LChangesRepo.Free;
    LBooksRepo.Free;
  end;
end;

function TAdventureStateService.GetCurrentInventory(
  AAdventureId: Int64): TList<TInventoryItem>;
var
  LRepo: TInventoryEventsRepo;
  LEvents: TArray<TInventoryEvent>;
  LEvent: TInventoryEvent;
  LOrder: TList<string>;
  LQuantities: TDictionary<string, Integer>;
  LNotes: TDictionary<string, string>;
  LName: string;
  LQty: Integer;
  LItem: TInventoryItem;
begin
  Result := TList<TInventoryItem>.Create;
  LRepo := TInventoryEventsRepo.Create(FConn);
  LOrder := TList<string>.Create;
  LQuantities := TDictionary<string, Integer>.Create;
  LNotes := TDictionary<string, string>.Create;
  try
    // Read events in chronological order with undone steps excluded.
    LEvents := LRepo.ListByAdventure(AAdventureId, False);

    // Fold per item, remembering insertion order for stable output.
    for LEvent in LEvents do
    begin
      if not LQuantities.ContainsKey(LEvent.ItemName) then
      begin
        LOrder.Add(LEvent.ItemName);
        LQuantities.Add(LEvent.ItemName, 0);
      end;
      if SameText(LEvent.Kind, 'gain') then
        LQuantities[LEvent.ItemName] := LQuantities[LEvent.ItemName] +
          LEvent.Quantity
      else if SameText(LEvent.Kind, 'lose') then
        LQuantities[LEvent.ItemName] := LQuantities[LEvent.ItemName] -
          LEvent.Quantity
      else if SameText(LEvent.Kind, 'modify') then
        LQuantities[LEvent.ItemName] := LEvent.Quantity;
      // Note from the most recent event for that item wins.
      LNotes.AddOrSetValue(LEvent.ItemName, LEvent.Note);
    end;

    // Emit only items with a positive remaining quantity.
    for LName in LOrder do
    begin
      LQty := LQuantities[LName];
      if LQty <= 0 then
        Continue;
      LItem.Name     := LName;
      LItem.Quantity := LQty;
      if not LNotes.TryGetValue(LName, LItem.Note) then
        LItem.Note := '';
      Result.Add(LItem);
    end;
  finally
    LNotes.Free;
    LQuantities.Free;
    LOrder.Free;
    LRepo.Free;
  end;
end;

function TAdventureStateService.GetSpellSnapshot(AAdventureId: Int64;
  const ALang: string): TArray<TAdventureSpellGroup>;
var
  LC: TFDConnection;
  LQ: TFDQuery;
  LGroup: TAdventureSpellGroup;
begin
  Result := nil;
  LC := TFDConnection.Create(nil);
  LQ := TFDQuery.Create(nil);
  try
    LC.ConnectionDefName := FConn;
    LC.Open;
    LQ.Connection := LC;
    LQ.Open(
      'SELECT sd.id, sd.slug, sd.ord, ' +
      '       COALESCE(t1.display_name, t2.display_name, sd.slug) AS name, ' +
      '       COALESCE(t1.description,  t2.description,  '''')     AS descr, ' +
      '       SUM(CASE WHEN a.consumed_at IS NULL THEN 1 ELSE 0 END) AS avail, ' +
      '       SUM(CASE WHEN a.consumed_at IS NULL THEN 0 ELSE 1 END) AS cons ' +
      'FROM adventure_spells a ' +
      'JOIN spell_defs sd ON sd.id = a.spell_def_id ' +
      'LEFT JOIN spell_def_titles t1 ' +
      '  ON t1.spell_def_id = sd.id AND t1.lang = :lang ' +
      'LEFT JOIN spell_def_titles t2 ' +
      '  ON t2.spell_def_id = sd.id ' +
      '  AND t2.lang = (SELECT lang FROM spell_def_titles ' +
      '                 WHERE spell_def_id = sd.id ORDER BY lang LIMIT 1) ' +
      'WHERE a.adventure_id = :a ' +
      'GROUP BY sd.id, sd.slug, sd.ord, name, descr ' +
      'ORDER BY sd.ord ASC',
      [ALang, AAdventureId]);
    while not LQ.Eof do
    begin
      LGroup.SpellDefId  := LQ.FieldByName('id').AsLargeInt;
      LGroup.Slug        := LQ.FieldByName('slug').AsString;
      LGroup.DisplayName := LQ.FieldByName('name').AsString;
      LGroup.Description := LQ.FieldByName('descr').AsString;
      LGroup.Available   := LQ.FieldByName('avail').AsInteger;
      LGroup.Consumed    := LQ.FieldByName('cons').AsInteger;
      Result := Result + [LGroup];
      LQ.Next;
    end;
  finally
    LQ.Free;
    LC.Free;
  end;
end;

function TAdventureStateService.GetSpellCastsByStep(AAdventureId: Int64;
  const ALang: string): TDictionary<Int64, TArray<string>>;
var
  LC: TFDConnection;
  LQ: TFDQuery;
  LStepId: Int64;
  LName: string;
  LExisting: TArray<string>;
begin
  Result := TDictionary<Int64, TArray<string>>.Create;
  LC := TFDConnection.Create(nil);
  LQ := TFDQuery.Create(nil);
  try
    LC.ConnectionDefName := FConn;
    LC.Open;
    LQ.Connection := LC;
    LQ.Open(
      'SELECT a.consumed_step_id AS step_id, ' +
      '       COALESCE(t1.display_name, t2.display_name, sd.slug) AS name ' +
      'FROM adventure_spells a ' +
      'JOIN spell_defs sd ON sd.id = a.spell_def_id ' +
      'LEFT JOIN spell_def_titles t1 ' +
      '  ON t1.spell_def_id = sd.id AND t1.lang = :lang ' +
      'LEFT JOIN spell_def_titles t2 ' +
      '  ON t2.spell_def_id = sd.id ' +
      '  AND t2.lang = (SELECT lang FROM spell_def_titles ' +
      '                 WHERE spell_def_id = sd.id ORDER BY lang LIMIT 1) ' +
      'WHERE a.adventure_id = :a ' +
      '  AND a.consumed_step_id IS NOT NULL ' +
      'ORDER BY a.consumed_step_id, a.ord',
      [ALang, AAdventureId]);
    while not LQ.Eof do
    begin
      LStepId := LQ.FieldByName('step_id').AsLargeInt;
      LName   := LQ.FieldByName('name').AsString;
      if Result.TryGetValue(LStepId, LExisting) then
        Result[LStepId] := LExisting + [LName]
      else
        Result.Add(LStepId, TArray<string>.Create(LName));
      LQ.Next;
    end;
  finally
    LQ.Free;
    LC.Free;
  end;
end;

end.
