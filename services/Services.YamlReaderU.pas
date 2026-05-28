{*******************************************************************************
  Unit Name: Services.YamlReaderU
  Purpose: Minimal strict YAML parser for the book seed dialect

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Parses the very small YAML subset used by data/books_seed.yaml. The
    accepted dialect is defined by the fixture in Tests.Services.YamlReaderU:

      - slug: <scalar>
        author: <scalar>
        titles:
          <lang>: <scalar>
          ...
        stats:
          - (inline mapping) name, kind, default, titles
              where titles is itself an inline mapping of lang to scalar
          ...

    Rules:
      * Indentation is exactly two spaces per level. Tabs and odd indents
        are rejected.
      * Comments starting with '#' run to end of line and are stripped
        from non-blank lines before parsing (defensive nicety; not used
        by the seed fixture but commonly expected).
      * Inline mappings nest at most one level deep.
      * Any deviation raises EYamlError with a line-number prefix
        formatted as 'YAML error at line <n>: <detail>'.

    Memory ownership:
      Each TYamlBook owns a TDictionary<string,string> in Titles, and
      every TYamlStat in Stats owns its own Titles dictionary. The same
      applies to each TYamlStartingItem.Titles in StartingInventory and
      each TYamlSpell.Names / TYamlSpell.Descriptions in Spells. Records
      cannot have destructors, so the CALLER is responsible for freeing
      these dictionaries (typically inside TBookCatalogService.LoadSeed
      after the upsert into SQLite).

  Dependencies:
    - System.Generics.Collections
    - System.SysUtils, System.Classes, System.IOUtils
*******************************************************************************}

unit Services.YamlReaderU;

interface

uses
  System.SysUtils, System.Generics.Collections;

type
  /// <summary>
  ///   Parsed stat definition. <c>Titles</c> is owned by the caller and
  ///   MUST be freed once the seed data has been consumed.
  /// </summary>
  TYamlStat = record
    Name, Kind, DefaultValue: string;
    Titles: TDictionary<string, string>;
  end;

  /// <summary>
  ///   Parsed starting inventory entry. <c>Titles</c> is owned by the
  ///   caller and MUST be freed once consumed. <c>Quantity</c> of 0
  ///   means the field was absent in the source; callers should treat
  ///   that as a default of 1.
  /// </summary>
  TYamlStartingItem = record
    Slug: string;
    Quantity: Integer;
    Titles: TDictionary<string, string>;
  end;

  /// <summary>
  ///   Parsed spell entry. Both <c>Names</c> and <c>Descriptions</c>
  ///   are owned by the caller and MUST be freed once consumed.
  /// </summary>
  TYamlSpell = record
    Slug: string;
    Names: TDictionary<string, string>;
    Descriptions: TDictionary<string, string>;
  end;

  /// <summary>
  ///   Parsed book entry. <c>Titles</c>, every <c>Stats[i].Titles</c>,
  ///   every <c>StartingInventory[i].Titles</c>, and every
  ///   <c>Spells[i].Names</c> / <c>Spells[i].Descriptions</c> are owned
  ///   by the caller and MUST be freed once consumed.
  /// </summary>
  TYamlBook = record
    Slug, Author: string;
    Titles: TDictionary<string, string>;
    Stats: TArray<TYamlStat>;
    StartingInventory: TArray<TYamlStartingItem>;
    Spells: TArray<TYamlSpell>;
  end;

  /// <summary>Raised on any deviation from the accepted YAML subset.</summary>
  EYamlError = class(Exception);

  /// <summary>
  ///   Static parser for the book seed YAML dialect. Callers own every
  ///   <c>TDictionary</c> returned inside the result records and must
  ///   free them; failing to do so leaks memory.
  /// </summary>
  TYamlReader = class
  public
    /// <summary>Parses an in-memory YAML string.</summary>
    class function ParseSeedString(const ASource: string): TArray<TYamlBook>;
    /// <summary>Reads and parses a UTF-8 YAML file from disk.</summary>
    class function ParseSeedFile(const APath: string): TArray<TYamlBook>;
  end;

implementation

uses
  System.Classes, System.IOUtils, System.StrUtils;

type
  TYamlLine = record
    LineNo: Integer;
    Indent: Integer;
    Content: string;
  end;

resourcestring
  RS_ERR_TAB_INDENT       = 'tabs are not allowed in indentation';
  RS_ERR_ODD_INDENT       = 'indentation must be a multiple of two spaces';
  RS_ERR_EXPECT_LIST      = 'expected top-level list item starting with "- "';
  RS_ERR_BAD_KV           = 'expected "key: value"';
  RS_ERR_UNEXPECTED_INDENT = 'unexpected indentation level';
  RS_ERR_UNKNOWN_FIELD    = 'unknown field "%s" in book mapping';
  RS_ERR_STATS_ITEM       = 'expected stats list item starting with "- { ... }"';
  RS_ERR_INLINE_BRACES    = 'inline mapping must be wrapped in "{ ... }"';
  RS_ERR_INLINE_NEST      = 'inline mapping may nest only one level deep';
  RS_ERR_UNKNOWN_STAT     = 'unknown field "%s" in stat mapping';
  RS_ERR_STARTING_ITEM_ITEM = 'expected starting_inventory list item starting with "- { ... }"';
  RS_ERR_SPELL_ITEM         = 'expected spells list item starting with "- { ... }"';
  RS_ERR_UNKNOWN_INV_FIELD  = 'unknown field "%s" in starting_inventory mapping';
  RS_ERR_UNKNOWN_SPELL_FIELD = 'unknown field "%s" in spells mapping';

procedure RaiseAt(ALineNo: Integer; const ADetail: string);
begin
  raise EYamlError.CreateFmt('YAML error at line %d: %s', [ALineNo, ADetail]);
end;

function IndentOf(const ALine: string; ALineNo: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(ALine) do
  begin
    if ALine[I] = #9 then
      RaiseAt(ALineNo, RS_ERR_TAB_INDENT);
    if ALine[I] <> ' ' then
      Break;
    Inc(Result);
  end;
  if (Result mod 2) <> 0 then
    RaiseAt(ALineNo, RS_ERR_ODD_INDENT);
end;

function StripComment(const ALine: string): string;
var
  P: Integer;
begin
  P := Pos('#', ALine);
  if P > 0 then
    Result := TrimRight(Copy(ALine, 1, P - 1))
  else
    Result := TrimRight(ALine);
end;

function Tokenize(const ASource: string): TArray<TYamlLine>;
var
  LRaw: TArray<string>;
  LList: TList<TYamlLine>;
  I: Integer;
  LStripped, LRest: string;
  LTok: TYamlLine;
begin
  LRaw := SplitString(ASource, #10);
  LList := TList<TYamlLine>.Create;
  try
    for I := 0 to High(LRaw) do
    begin
      LStripped := StringReplace(LRaw[I], #13, '', [rfReplaceAll]);
      LRest := StripComment(LStripped);
      if Trim(LRest) = '' then
        Continue;
      LTok.LineNo := I + 1;
      LTok.Indent := IndentOf(LRest, LTok.LineNo);
      LTok.Content := Copy(LRest, LTok.Indent + 1, MaxInt);
      LList.Add(LTok);
    end;
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

procedure SplitKV(const AContent: string; ALineNo: Integer;
  out AKey, AValue: string);
var
  P: Integer;
begin
  P := Pos(':', AContent);
  if P <= 0 then
    RaiseAt(ALineNo, RS_ERR_BAD_KV);
  AKey := Trim(Copy(AContent, 1, P - 1));
  AValue := Trim(Copy(AContent, P + 1, MaxInt));
  if AKey = '' then
    RaiseAt(ALineNo, RS_ERR_BAD_KV);
end;

/// <summary>
///   Splits an inline mapping body (without outer braces) on top-level
///   commas, ignoring those nested inside one level of '{ ... }'.
/// </summary>
function SplitTopLevelCommas(const ABody: string; ALineNo: Integer): TArray<string>;
var
  LList: TList<string>;
  I, LDepth, LStart: Integer;
  LCh: Char;
begin
  LList := TList<string>.Create;
  try
    LDepth := 0;
    LStart := 1;
    for I := 1 to Length(ABody) do
    begin
      LCh := ABody[I];
      case LCh of
        '{': Inc(LDepth);
        '}': Dec(LDepth);
        ',':
          if LDepth = 0 then
          begin
            LList.Add(Trim(Copy(ABody, LStart, I - LStart)));
            LStart := I + 1;
          end;
      end;
    end;
    if LDepth <> 0 then
      RaiseAt(ALineNo, RS_ERR_INLINE_BRACES);
    LList.Add(Trim(Copy(ABody, LStart, MaxInt)));
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

procedure ParseFlatInlineInto(const ABody: string; ALineNo: Integer;
  ADict: TDictionary<string, string>);
var
  LP, LK, LV: string;
begin
  for LP in SplitTopLevelCommas(ABody, ALineNo) do
  begin
    if LP = '' then
      Continue;
    SplitKV(LP, ALineNo, LK, LV);
    if (Pos('{', LV) > 0) or (Pos('}', LV) > 0) then
      RaiseAt(ALineNo, RS_ERR_INLINE_NEST);
    ADict.AddOrSetValue(LK, LV);
  end;
end;

/// <summary>
///   Strips a single pair of surrounding double quotes from <c>AValue</c>
///   if present. Used by the spell parser, where descriptions may be
///   quoted to allow punctuation such as commas. Existing stat values
///   are unquoted and never pass through this function.
/// </summary>
function StripSurroundingDoubleQuotes(const AValue: string): string;
begin
  if (Length(AValue) >= 2)
    and (AValue[1] = '"') and (AValue[Length(AValue)] = '"') then
    Result := Copy(AValue, 2, Length(AValue) - 2)
  else
    Result := AValue;
end;

procedure ParseFlatInlineIntoUnquoting(const ABody: string; ALineNo: Integer;
  ADict: TDictionary<string, string>);
var
  LP, LK, LV: string;
begin
  for LP in SplitTopLevelCommas(ABody, ALineNo) do
  begin
    if LP = '' then
      Continue;
    SplitKV(LP, ALineNo, LK, LV);
    if (Pos('{', LV) > 0) or (Pos('}', LV) > 0) then
      RaiseAt(ALineNo, RS_ERR_INLINE_NEST);
    ADict.AddOrSetValue(LK, StripSurroundingDoubleQuotes(LV));
  end;
end;

function ParseStatInline(const ALine: string; ALineNo: Integer): TYamlStat;
var
  LBody, LP, LK, LV, LInner: string;
begin
  // ALine starts with '- ' (already validated by caller)
  LBody := Trim(Copy(ALine, 3, MaxInt));
  if (LBody = '') or (LBody[1] <> '{') or (LBody[Length(LBody)] <> '}') then
    RaiseAt(ALineNo, RS_ERR_INLINE_BRACES);
  LBody := Trim(Copy(LBody, 2, Length(LBody) - 2));
  Result.Name := '';
  Result.Kind := '';
  Result.DefaultValue := '';
  Result.Titles := TDictionary<string, string>.Create;
  try
    for LP in SplitTopLevelCommas(LBody, ALineNo) do
    begin
      if LP = '' then Continue;
      SplitKV(LP, ALineNo, LK, LV);
      if LK = 'titles' then
      begin
        if (LV = '') or (LV[1] <> '{') or (LV[Length(LV)] <> '}') then
          RaiseAt(ALineNo, RS_ERR_INLINE_BRACES);
        LInner := Trim(Copy(LV, 2, Length(LV) - 2));
        ParseFlatInlineInto(LInner, ALineNo, Result.Titles);
      end
      else if LK = 'name' then
        Result.Name := LV
      else if LK = 'kind' then
        Result.Kind := LV
      else if LK = 'default' then
        Result.DefaultValue := LV
      else
        RaiseAt(ALineNo, Format(RS_ERR_UNKNOWN_STAT, [LK]));
    end;
  except
    Result.Titles.Free;
    raise;
  end;
end;

function ParseStartingItemInline(const ALine: string;
  ALineNo: Integer): TYamlStartingItem;
var
  LBody, LP, LK, LV, LInner: string;
begin
  LBody := Trim(Copy(ALine, 3, MaxInt));
  if (LBody = '') or (LBody[1] <> '{') or (LBody[Length(LBody)] <> '}') then
    RaiseAt(ALineNo, RS_ERR_INLINE_BRACES);
  LBody := Trim(Copy(LBody, 2, Length(LBody) - 2));
  Result.Slug := '';
  Result.Quantity := 0;
  Result.Titles := TDictionary<string, string>.Create;
  try
    for LP in SplitTopLevelCommas(LBody, ALineNo) do
    begin
      if LP = '' then Continue;
      SplitKV(LP, ALineNo, LK, LV);
      if LK = 'slug' then Result.Slug := LV
      else if LK = 'quantity' then Result.Quantity := StrToIntDef(LV, 0)
      else if LK = 'titles' then
      begin
        if (LV = '') or (LV[1] <> '{') or (LV[Length(LV)] <> '}') then
          RaiseAt(ALineNo, RS_ERR_INLINE_BRACES);
        LInner := Trim(Copy(LV, 2, Length(LV) - 2));
        ParseFlatInlineInto(LInner, ALineNo, Result.Titles);
      end
      else
        RaiseAt(ALineNo, Format(RS_ERR_UNKNOWN_INV_FIELD, [LK]));
    end;
  except
    Result.Titles.Free;
    raise;
  end;
end;

function ParseSpellInline(const ALine: string;
  ALineNo: Integer): TYamlSpell;
var
  LBody, LP, LK, LV, LInner: string;
begin
  LBody := Trim(Copy(ALine, 3, MaxInt));
  if (LBody = '') or (LBody[1] <> '{') or (LBody[Length(LBody)] <> '}') then
    RaiseAt(ALineNo, RS_ERR_INLINE_BRACES);
  LBody := Trim(Copy(LBody, 2, Length(LBody) - 2));
  Result.Slug := '';
  Result.Names := TDictionary<string, string>.Create;
  Result.Descriptions := TDictionary<string, string>.Create;
  try
    for LP in SplitTopLevelCommas(LBody, ALineNo) do
    begin
      if LP = '' then Continue;
      SplitKV(LP, ALineNo, LK, LV);
      if LK = 'slug' then Result.Slug := LV
      else if (LK = 'names') or (LK = 'descriptions') then
      begin
        if (LV = '') or (LV[1] <> '{') or (LV[Length(LV)] <> '}') then
          RaiseAt(ALineNo, RS_ERR_INLINE_BRACES);
        LInner := Trim(Copy(LV, 2, Length(LV) - 2));
        if LK = 'names' then
          ParseFlatInlineIntoUnquoting(LInner, ALineNo, Result.Names)
        else
          ParseFlatInlineIntoUnquoting(LInner, ALineNo, Result.Descriptions);
      end
      else
        RaiseAt(ALineNo, Format(RS_ERR_UNKNOWN_SPELL_FIELD, [LK]));
    end;
  except
    Result.Names.Free;
    Result.Descriptions.Free;
    raise;
  end;
end;

function ParseBook(const ALines: TArray<TYamlLine>; var AIdx: Integer): TYamlBook;
var
  LLine: TYamlLine;
  LKey, LValue: string;
  LStatList: TList<TYamlStat>;
  LInvList: TList<TYamlStartingItem>;
  LSpellList: TList<TYamlSpell>;
begin
  Result.Slug := '';
  Result.Author := '';
  Result.Titles := TDictionary<string, string>.Create;
  Result.StartingInventory := nil;
  Result.Spells := nil;
  LStatList := TList<TYamlStat>.Create;
  LInvList := TList<TYamlStartingItem>.Create;
  LSpellList := TList<TYamlSpell>.Create;
  try
    // First line: '- key: value' at indent 0
    LLine := ALines[AIdx];
    if (LLine.Indent <> 0) or not StartsText('- ', LLine.Content) then
      RaiseAt(LLine.LineNo, RS_ERR_EXPECT_LIST);
    SplitKV(Copy(LLine.Content, 3, MaxInt), LLine.LineNo, LKey, LValue);
    if LKey = 'slug' then Result.Slug := LValue
    else if LKey = 'author' then Result.Author := LValue
    else RaiseAt(LLine.LineNo, Format(RS_ERR_UNKNOWN_FIELD, [LKey]));
    Inc(AIdx);

    // Subsequent indent-2 fields until indent drops to 0 or EOF
    while (AIdx <= High(ALines)) and (ALines[AIdx].Indent = 2) do
    begin
      LLine := ALines[AIdx];
      SplitKV(LLine.Content, LLine.LineNo, LKey, LValue);
      Inc(AIdx);
      if LKey = 'slug' then Result.Slug := LValue
      else if LKey = 'author' then Result.Author := LValue
      else if LKey = 'titles' then
      begin
        if LValue <> '' then
          RaiseAt(LLine.LineNo, RS_ERR_BAD_KV);
        while (AIdx <= High(ALines)) and (ALines[AIdx].Indent = 4) do
        begin
          SplitKV(ALines[AIdx].Content, ALines[AIdx].LineNo, LKey, LValue);
          Result.Titles.AddOrSetValue(LKey, LValue);
          Inc(AIdx);
        end;
      end
      else if LKey = 'stats' then
      begin
        if LValue <> '' then
          RaiseAt(LLine.LineNo, RS_ERR_BAD_KV);
        while (AIdx <= High(ALines)) and (ALines[AIdx].Indent = 4) do
        begin
          if not StartsText('- ', ALines[AIdx].Content) then
            RaiseAt(ALines[AIdx].LineNo, RS_ERR_STATS_ITEM);
          LStatList.Add(ParseStatInline(ALines[AIdx].Content, ALines[AIdx].LineNo));
          Inc(AIdx);
        end;
      end
      else if LKey = 'starting_inventory' then
      begin
        if LValue <> '' then
          RaiseAt(LLine.LineNo, RS_ERR_BAD_KV);
        while (AIdx <= High(ALines)) and (ALines[AIdx].Indent = 4) do
        begin
          if not StartsText('- ', ALines[AIdx].Content) then
            RaiseAt(ALines[AIdx].LineNo, RS_ERR_STARTING_ITEM_ITEM);
          LInvList.Add(ParseStartingItemInline(
            ALines[AIdx].Content, ALines[AIdx].LineNo));
          Inc(AIdx);
        end;
      end
      else if LKey = 'spells' then
      begin
        if LValue <> '' then
          RaiseAt(LLine.LineNo, RS_ERR_BAD_KV);
        while (AIdx <= High(ALines)) and (ALines[AIdx].Indent = 4) do
        begin
          if not StartsText('- ', ALines[AIdx].Content) then
            RaiseAt(ALines[AIdx].LineNo, RS_ERR_SPELL_ITEM);
          LSpellList.Add(ParseSpellInline(
            ALines[AIdx].Content, ALines[AIdx].LineNo));
          Inc(AIdx);
        end;
      end
      else
        RaiseAt(LLine.LineNo, Format(RS_ERR_UNKNOWN_FIELD, [LKey]));
    end;

    if (AIdx <= High(ALines)) and (ALines[AIdx].Indent <> 0) then
      RaiseAt(ALines[AIdx].LineNo, RS_ERR_UNEXPECTED_INDENT);

    Result.Stats := LStatList.ToArray;
    Result.StartingInventory := LInvList.ToArray;
    Result.Spells := LSpellList.ToArray;
  finally
    LStatList.Free;
    LInvList.Free;
    LSpellList.Free;
  end;
end;

class function TYamlReader.ParseSeedString(const ASource: string): TArray<TYamlBook>;
var
  LLines: TArray<TYamlLine>;
  LBooks: TList<TYamlBook>;
  LIdx: Integer;
begin
  LLines := Tokenize(ASource);
  LBooks := TList<TYamlBook>.Create;
  try
    LIdx := 0;
    while LIdx <= High(LLines) do
      LBooks.Add(ParseBook(LLines, LIdx));
    Result := LBooks.ToArray;
  finally
    LBooks.Free;
  end;
end;

class function TYamlReader.ParseSeedFile(const APath: string): TArray<TYamlBook>;
begin
  Result := ParseSeedString(TFile.ReadAllText(APath, TEncoding.UTF8));
end;

end.
