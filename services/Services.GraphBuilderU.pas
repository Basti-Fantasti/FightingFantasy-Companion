{*******************************************************************************
  Unit Name: Services.GraphBuilderU
  Purpose: Builds the graph.json payload consumed by the Cytoscape graph tab

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    TGraphBuilder folds the non-undone step history of a single adventure into
    the JSON shape defined in design spec 9.4. Nodes are deduped by section
    number; each node carries a stable string id ("s<N>"), a visits counter
    and the lowest seq at which the section was first seen. Edges record the
    section transitions in step-sequence order. The "current" field is the
    to_section of the most recent non-undone step, mirroring the section the
    player is on after the latest move.

    Undone steps are excluded entirely. This means "current" is derived from
    the last surviving step's to_section and not from adventures.last_step_id,
    which may still point at a soft-undone row that has not yet been redone.

    Algorithm:
      1. Load ListByAdventureAsc(advId, IncludeUndone=False).
      2. For each step:
         - If FromSection > 0, ensure a node placeholder exists for it
           (without bumping visits — the from side is just a graph endpoint
           reference).
         - Touch ToSection: existing nodes get visits + 1, new nodes are
           added with visits = 1 and first_seq = step.seq.
         - When FromSection > 0, append an edge (from, to, seq).
      3. current = last step's ToSection, or 0 when the adventure has no
         non-undone steps.

    Visit-count semantics: a node's visits is the number of times the player
    arrives at that section (i.e. the count of non-undone steps with the
    section as their to_section). The from_section side of a step does not
    re-count the previous arrival.

    The very first step of an adventure has FromSection = 0 (NULL in DB) so
    it contributes a single node and no edge.

  Dependencies:
    - JsonDataObjects
    - System.Generics.Collections
    - Models.StepU
    - Repositories.StepsU
*******************************************************************************}

unit Services.GraphBuilderU;

interface

uses
  JsonDataObjects;

type
  /// <summary>
  ///   Builds the graph.json payload for a single adventure. The returned
  ///   TJsonObject is owned by the caller and must be freed (or handed off
  ///   to a renderer that takes ownership).
  /// </summary>
  TGraphBuilder = class
  private
    FConn: string;
  public
    /// <summary>Constructs the builder bound to a FireDAC connection def.</summary>
    constructor Create(const AConnectionName: string);

    /// <summary>
    ///   Builds the graph payload for the given adventure. Excludes undone
    ///   steps. Empty adventures yield current=0 with empty nodes / edges.
    /// </summary>
    /// <returns>A newly allocated JSON object; caller owns it.</returns>
    function Build(AAdventureId: Int64): TJsonObject;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Models.StepU,
  Repositories.StepsU;

constructor TGraphBuilder.Create(const AConnectionName: string);
begin
  inherited Create;
  FConn := AConnectionName;
end;

/// <summary>
///   Ensures a node entry exists in the array for the given section. New
///   nodes start with visits = 0 so the caller controls whether this touch
///   counts as an arrival (which AArrival = True does by incrementing the
///   visits counter). The from_section side of a step uses AArrival = False
///   so it only guarantees existence without re-counting an earlier visit.
/// </summary>
procedure TouchNode(ANodesArr: TJsonArray;
  ANodeIndex: TDictionary<Integer, Integer>;
  ASection, ASeq: Integer; AArrival: Boolean);
var
  LIndex: Integer;
  LObj: TJsonObject;
begin
  if ANodeIndex.TryGetValue(ASection, LIndex) then
  begin
    LObj := ANodesArr.O[LIndex];
    if AArrival then
      LObj.I['visits'] := LObj.I['visits'] + 1;
    Exit;
  end;
  LObj := ANodesArr.AddObject;
  LObj.S['id']        := 's' + IntToStr(ASection);
  LObj.I['section']   := ASection;
  if AArrival then
    LObj.I['visits'] := 1
  else
    LObj.I['visits'] := 0;
  LObj.I['first_seq'] := ASeq;
  ANodeIndex.Add(ASection, ANodesArr.Count - 1);
end;

function TGraphBuilder.Build(AAdventureId: Int64): TJsonObject;
var
  LStepsRepo: TStepsRepo;
  LSteps: TArray<TStep>;
  LStep: TStep;
  LNodeIndex: TDictionary<Integer, Integer>;
  LNodesArr, LEdgesArr: TJsonArray;
  LEdge: TJsonObject;
  LCurrent: Integer;
begin
  Result := TJsonObject.Create;
  LStepsRepo := TStepsRepo.Create(FConn);
  LNodeIndex := TDictionary<Integer, Integer>.Create;
  try
    LSteps := LStepsRepo.ListByAdventureAsc(AAdventureId, False);

    // Pre-create the two arrays inside Result so they share its lifetime.
    LNodesArr := Result.A['nodes'];
    LEdgesArr := Result.A['edges'];

    LCurrent := 0;
    for LStep in LSteps do
    begin
      // FromSection = 0 means the row's from_section column was NULL, i.e.
      // the very first step of the adventure. It contributes the start node
      // but no incoming edge.
      if LStep.FromSection > 0 then
      begin
        TouchNode(LNodesArr, LNodeIndex, LStep.FromSection, LStep.Seq, False);
        TouchNode(LNodesArr, LNodeIndex, LStep.ToSection, LStep.Seq, True);
        LEdge := LEdgesArr.AddObject;
        LEdge.S['from'] := 's' + IntToStr(LStep.FromSection);
        LEdge.S['to']   := 's' + IntToStr(LStep.ToSection);
        LEdge.I['seq']  := LStep.Seq;
      end
      else
      begin
        TouchNode(LNodesArr, LNodeIndex, LStep.ToSection, LStep.Seq, True);
      end;
      LCurrent := LStep.ToSection;
    end;

    Result.I['current'] := LCurrent;
  finally
    LNodeIndex.Free;
    LStepsRepo.Free;
  end;
end;

end.
