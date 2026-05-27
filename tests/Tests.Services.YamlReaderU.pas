unit Tests.Services.YamlReaderU;

interface

uses DUnitX.TestFramework;

type
  [TestFixture]
  TYamlReaderTests = class
  public
    [Test] procedure ParsesSeedFixture;
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

procedure TYamlReaderTests.ParsesSeedFixture;
var LBooks: TArray<TYamlBook>;
begin
  LBooks := TYamlReader.ParseSeedString(FIXTURE);
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
end;

initialization
  TDUnitX.RegisterTestFixture(TYamlReaderTests);

end.
