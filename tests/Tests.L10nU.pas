{*******************************************************************************
  Unit Name: Tests.L10nU
  Purpose: Parity check between l10n catalogues (de.json vs. en.json)

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Loads both translation catalogues from l10n/ and asserts that they expose
    the exact same set of keys. Catches drift the moment a new key is added
    to one file without the other.

    Path resolution: the test executable lives at
      tests\bin\Win64\Debug\FFCompanionTests.exe
    so the l10n directory is four levels above ExtractFileDir(ParamStr(0)).

  Dependencies:
    - DUnitX
    - JsonDataObjects
*******************************************************************************}

unit Tests.L10nU;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Localisation catalogue invariants.</summary>
  [TestFixture]
  TL10nTests = class
  public
    /// <summary>de.json and en.json must declare the same key set.</summary>
    [Test]
    procedure DeAndEnHaveIdenticalKeys;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.Classes, System.Generics.Collections,
  JsonDataObjects;

function LoadKeys(const APath: string): TList<string>;
var
  LObj: TJsonObject;
  I: Integer;
begin
  Result := TList<string>.Create;
  LObj := TJsonObject(TJsonObject.ParseFromFile(APath));
  try
    for I := 0 to LObj.Count - 1 do
      Result.Add(LObj.Names[I]);
    Result.Sort;
  finally
    LObj.Free;
  end;
end;

procedure TL10nTests.DeAndEnHaveIdenticalKeys;
var
  LEn, LDe: TList<string>;
  LBase: string;
begin
  // Test exe path: <root>\tests\bin\Win64\Debug\FFCompanionTests.exe
  // -> four directories up reaches <root>, then into l10n.
  LBase := TPath.GetFullPath(
    TPath.Combine(ExtractFileDir(ParamStr(0)), '..\..\..\..\l10n'));
  Assert.IsTrue(TDirectory.Exists(LBase),
    'l10n directory not found at: ' + LBase);
  LEn := LoadKeys(TPath.Combine(LBase, 'en.json'));
  LDe := LoadKeys(TPath.Combine(LBase, 'de.json'));
  try
    Assert.AreEqual(string.Join(',', LEn.ToArray), string.Join(',', LDe.ToArray),
      'l10n key sets must be identical between de.json and en.json');
  finally
    LEn.Free;
    LDe.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TL10nTests);

end.
