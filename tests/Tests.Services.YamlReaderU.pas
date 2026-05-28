unit Tests.Services.YamlReaderU;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TYamlReaderTests = class
  public
    [Test] procedure ParsesSeedFixture;
    [Test] procedure ParsesStartingInventoryAndSpells;
  end;

implementation

uses System.SysUtils, Services.YamlReaderU;

const
  FIXTURE =
    '- slug: citadel-of-chaos'#10 +
    '  author: Steve Jackson'#10 +
    '  titles:'#10 +
    '    en: The Citadel of Chaos'#10 +
    '    de: Die Zitadelle des Zauberers'#10 +
    '  stats:'#10 +
    '    - { name: skill, kind: integer, default: 0, titles: { en: Skill, de: Geschicklichkeit } }'#10 +
    '    - { name: magic, kind: integer, default: 0, titles: { en: Magic, de: Magie } }'#10;

/// <summary>
///   Frees every caller-owned dictionary inside <c>ABooks</c>: each
///   book's <c>Titles</c>, every stat's <c>Titles</c>, every starting
///   inventory item's <c>Titles</c>, and every spell's <c>Names</c> and
///   <c>Descriptions</c>.
/// </summary>
procedure FreeBookOwned(const ABooks: TArray<TYamlBook>);
var
  LBook: TYamlBook;
  LStat: TYamlStat;
  LItem: TYamlStartingItem;
  LSpell: TYamlSpell;
begin
  for LBook in ABooks do
  begin
    LBook.Titles.Free;
    for LStat in LBook.Stats do
      LStat.Titles.Free;
    for LItem in LBook.StartingInventory do
      LItem.Titles.Free;
    for LSpell in LBook.Spells do
    begin
      LSpell.Names.Free;
      LSpell.Descriptions.Free;
    end;
  end;
end;

procedure TYamlReaderTests.ParsesSeedFixture;
var
  LBooks: TArray<TYamlBook>;
begin
  LBooks := TYamlReader.ParseSeedString(FIXTURE);
  try
    Assert.AreEqual(NativeInt(1), Length(LBooks));
    Assert.AreEqual('citadel-of-chaos', LBooks[0].Slug);
    Assert.AreEqual('Steve Jackson', LBooks[0].Author);
    Assert.AreEqual('Die Zitadelle des Zauberers', LBooks[0].Titles['de']);
    Assert.AreEqual('The Citadel of Chaos', LBooks[0].Titles['en']);
    Assert.AreEqual(NativeInt(2), Length(LBooks[0].Stats));
    Assert.AreEqual('skill', LBooks[0].Stats[0].Name);
    Assert.AreEqual('integer', LBooks[0].Stats[0].Kind);
    Assert.AreEqual('Geschicklichkeit', LBooks[0].Stats[0].Titles['de']);
    Assert.AreEqual('Magie', LBooks[0].Stats[1].Titles['de']);
  finally
    FreeBookOwned(LBooks);
  end;
end;

procedure TYamlReaderTests.ParsesStartingInventoryAndSpells;
const
  CYaml =
    '- slug: citadel'#10 +
    '  author: SJ'#10 +
    '  titles:'#10 +
    '    en: Citadel'#10 +
    '  stats:'#10 +
    '    - { name: magic, kind: integer, default: 0, titles: { en: Magic } }'#10 +
    '  starting_inventory:'#10 +
    '    - { slug: sword, quantity: 1, titles: { de: Schwert, en: Sword } }'#10 +
    '    - { slug: torch, titles: { de: Fackel, en: Torch } }'#10 +
    '  spells:'#10 +
    '    - { slug: strength, names: { de: Stärke, en: Strength }, descriptions: { de: "Erhöht Skill.", en: "Raises Skill." } }'#10 +
    '    - { slug: weakness, names: { de: Schwäche, en: Weakness }, descriptions: { de: "Senkt Skill.", en: "Lowers Skill." } }'#10;
var
  LBooks: TArray<TYamlBook>;
begin
  LBooks := TYamlReader.ParseSeedString(CYaml);
  try
    Assert.AreEqual(NativeInt(1), Length(LBooks));
    Assert.AreEqual(NativeInt(2), Length(LBooks[0].StartingInventory));
    Assert.AreEqual('sword', LBooks[0].StartingInventory[0].Slug);
    Assert.AreEqual(1, LBooks[0].StartingInventory[0].Quantity);
    Assert.AreEqual('Schwert', LBooks[0].StartingInventory[0].Titles['de']);
    Assert.AreEqual(0, LBooks[0].StartingInventory[1].Quantity,
      'absent quantity stays 0; caller defaults to 1');

    Assert.AreEqual(NativeInt(2), Length(LBooks[0].Spells));
    Assert.AreEqual('strength', LBooks[0].Spells[0].Slug);
    Assert.AreEqual('Stärke', LBooks[0].Spells[0].Names['de']);
    Assert.AreEqual('Senkt Skill.', LBooks[0].Spells[1].Descriptions['de']);
  finally
    FreeBookOwned(LBooks);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TYamlReaderTests);

end.
