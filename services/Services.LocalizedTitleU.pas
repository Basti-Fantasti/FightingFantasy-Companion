{*******************************************************************************
  Unit Name: Services.LocalizedTitleU
  Purpose: Four-step language fallback chain for localised titles

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Implements the lookup order from spec section 6 for picking a display
    title from a dictionary of language -> string entries:
      1. exact match on the current UI language
      2. match on the application default language
      3. first non-empty entry in alphabetical key order (deterministic)
      4. caller-supplied literal fallback (e.g. the book slug)

    The service is stateless and reusable across requests; callers own the
    lifetime of the input dictionary.

  Dependencies:
    - System.Generics.Collections
*******************************************************************************}

unit Services.LocalizedTitleU;

interface

uses
  System.Generics.Collections;

type
  /// <summary>
  ///   Stateless helper that selects a localised title using the four-step
  ///   fallback chain.
  /// </summary>
  TLocalizedTitleService = class
  public
    /// <summary>
    ///   Picks the best title for the given UI language.
    /// </summary>
    /// <param name="ATitles">Map of language tag to title text.</param>
    /// <param name="ACurrentLang">Preferred UI language.</param>
    /// <param name="ADefaultLang">Application default language.</param>
    /// <param name="AFallback">Literal returned when nothing else matches.</param>
    class function Pick(const ATitles: TDictionary<string, string>;
      const ACurrentLang, ADefaultLang, AFallback: string): string;
  end;

implementation

uses
  System.Generics.Defaults, System.SysUtils;

class function TLocalizedTitleService.Pick(
  const ATitles: TDictionary<string, string>;
  const ACurrentLang, ADefaultLang, AFallback: string): string;
var
  LKeys: TArray<string>;
  LK: string;
begin
  if ATitles.TryGetValue(ACurrentLang, Result) and (Result <> '') then
    Exit;
  if ATitles.TryGetValue(ADefaultLang, Result) and (Result <> '') then
    Exit;
  LKeys := ATitles.Keys.ToArray;
  TArray.Sort<string>(LKeys);
  for LK in LKeys do
    if ATitles[LK] <> '' then
      Exit(ATitles[LK]);
  Result := AFallback;
end;

end.
