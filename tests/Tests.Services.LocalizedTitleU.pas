{*******************************************************************************
  Unit Name: Tests.Services.LocalizedTitleU
  Purpose: DUnitX fixtures for the localised title fallback chain

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Verifies the four-step fallback chain implemented by
    TLocalizedTitleService.Pick:
      1. current language wins outright
      2. fallback to the application default language
      3. fallback to the first alphabetically-sorted available language
      4. fallback to the caller-supplied literal when the map is empty

  Dependencies:
    - DUnitX.TestFramework
    - Services.LocalizedTitleU
*******************************************************************************}

unit Tests.Services.LocalizedTitleU;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>
  ///   Fixture covering the localised title lookup precedence rules.
  /// </summary>
  [TestFixture]
  TLocalizedTitleTests = class
  public
    [Test] procedure CurrentLangWins;
    [Test] procedure FallsBackToDefault;
    [Test] procedure FallsBackToFirstAvailable;
    [Test] procedure FallsBackToLiteral;
  end;

implementation

uses
  System.Generics.Collections,
  Services.LocalizedTitleU;

procedure TLocalizedTitleTests.CurrentLangWins;
var
  LD: TDictionary<string, string>;
begin
  LD := TDictionary<string, string>.Create;
  try
    LD.Add('de', 'Die Zitadelle des Zauberers');
    LD.Add('en', 'The Citadel of Chaos');
    Assert.AreEqual('Die Zitadelle des Zauberers',
      TLocalizedTitleService.Pick(LD, 'de', 'en', 'fallback'));
  finally
    LD.Free;
  end;
end;

procedure TLocalizedTitleTests.FallsBackToDefault;
var
  LD: TDictionary<string, string>;
begin
  LD := TDictionary<string, string>.Create;
  try
    LD.Add('en', 'The Citadel of Chaos');
    Assert.AreEqual('The Citadel of Chaos',
      TLocalizedTitleService.Pick(LD, 'de', 'en', 'fallback'));
  finally
    LD.Free;
  end;
end;

procedure TLocalizedTitleTests.FallsBackToFirstAvailable;
var
  LD: TDictionary<string, string>;
begin
  LD := TDictionary<string, string>.Create;
  try
    LD.Add('fr', 'La Citadelle');
    Assert.AreEqual('La Citadelle',
      TLocalizedTitleService.Pick(LD, 'de', 'en', 'fallback'));
  finally
    LD.Free;
  end;
end;

procedure TLocalizedTitleTests.FallsBackToLiteral;
var
  LD: TDictionary<string, string>;
begin
  LD := TDictionary<string, string>.Create;
  try
    Assert.AreEqual('fallback',
      TLocalizedTitleService.Pick(LD, 'de', 'en', 'fallback'));
  finally
    LD.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLocalizedTitleTests);

end.
