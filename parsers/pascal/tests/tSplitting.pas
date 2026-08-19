(*
 ***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License.        *
 *                                                                         *
 ***************************************************************************
*)

{ The callsign-splitting layer: TDxccResolver.

  These tests were originally written differentially, against a verbatim copy
  of the original CoVyhodnocovat, to show that exactly one behavioural change
  was intended -- the Argentine province suffixes -- and that nothing else
  moved.  The legacy engine is not carried into this repository, so the values
  the original produced are recorded here as literals, captured from it while
  it was still on hand.  Where a line says "the original produced X", X is
  measured, not remembered.

  The wholesale sweeps that compared the two engines callsign by callsign are
  gone with it; what they established is recorded in docs/EQUIVALENCE.md. }

unit tSplitting;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  uDxccTableIntf, uDxccTable, uDxccResolver, uDxccSuffixRules;

type
  TSplittingTests = class(TTestCase)
  private
    FValid, FDeleted: TDxccTable;
    FRules: TDxccSuffixRules;
    FResolver: TDxccResolver;

    function NewKey(const Callsign: string; const ADate: string = '2020/01/01'): string;
    function CountryFor(const Callsign: string): string;
    function AdifFor(const Callsign: string): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { --- the fix -------------------------------------------------------- }
    procedure ArgentineRegionSuffixRewritesCharacterFour;
    procedure ArgentineLettersTheOriginalMissed;
    procedure ArgentineLettersAlreadyPatchedInTheTable;
    procedure ArgentineMobileAndPortableKeepTheirRegion;
    procedure CompanionPrefixesBehaveLikeLu;
    procedure ArgentineSuffixResolvesToTheRightProvince;
    procedure TheFixChangesTheProvinceNotTheEntity;

    { --- everything else must be unchanged ------------------------------ }
    procedure NonArgentineSlashFormsAreUnchanged;

    { --- ported behaviour worth stating outright ------------------------ }
    procedure MaritimeAndAeronauticalMobileHaveNoCountry;
    procedure IgnoredSuffixesFallBackToTheOperatorCall;
    procedure DigitSuffixRenumbersTheCallArea;
    procedure UsCallsMoveToTheWDistrict;
    procedure VerbatimSlashEntriesNeedNoSplitting;
    procedure ShortCallsignsDoNotCorruptMemory;
  end;

implementation

uses
  uTestData, uDxccEntry;

const
  ArgentinePrefixList: array[0..10] of string =
    ('LU', 'LW', 'AY', 'AZ', 'LO', 'LP', 'LQ', 'LR', 'LS', 'LT', 'LV');

  { The letters the original leaves out of its suffix-letter set AND that the
    country files do not patch up with an explicit slash pattern.

    The original omits F, G, I, K and W because each is a major DXCC prefix.
    For W the data authors added L[O-W][1-9]%%%/W -> Chubut, and for X they
    added /X[A-O] and /X[P-Z], so those two resolve correctly through the
    table before the splitting rules ever run.  F, G, I and K got no such
    entry, so they are the four that actually break. }
  MissedLetters = 'FGIK';

  { The key the original produced for LU1AAA/<missed letter>: its generic
    branch set the key to the bare suffix, then probed prefix[1..2]+'/'+suffix
    in prefix mode.  Measured from the legacy engine. }
  OldKeyForMissedLetter = 'LU/';

procedure TSplittingTests.SetUp;
begin
  inherited SetUp;
  FValid := TDxccTable.Create;
  FValid.LoadFromString(CanonicalTable);
  FDeleted := TDxccTable.Create;
  FDeleted.LoadFromString(DeletedTable);

  FRules := TDxccSuffixRules.Create;
  FRules.LoadExceptions(ExceptionsFile);
  FRules.LoadAmbiguous(AmbiguousFile);

  FResolver := TDxccResolver.Create(FValid, FDeleted, FRules);
end;

procedure TSplittingTests.TearDown;
begin
  FResolver.Free;
  FRules.Free;
  FDeleted.Free;
  FValid.Free;
  inherited TearDown;
end;

function TSplittingTests.NewKey(const Callsign: string; const ADate: string): string;
var
  Resolved: Boolean;
  Adif: Integer;
begin
  Result := FResolver.EffectiveCallsign(Callsign, ADate, Resolved, Adif);
end;

function TSplittingTests.CountryFor(const Callsign: string): string;
var
  Found: TDxccLookup;
begin
  Found := FResolver.Lookup(NewKey(Callsign), '2020/01/01');
  if Found.Found then
    Result := Found.Entry.Country
  else
    Result := '<no match>';
end;

function TSplittingTests.AdifFor(const Callsign: string): Integer;
var
  Found: TDxccLookup;
begin
  Found := FResolver.Lookup(NewKey(Callsign), '2020/01/01');
  if Found.Found then
    Result := Found.Adif
  else
    Result := 0;
end;

{ --- the fix ---------------------------------------------------------- }

procedure TSplittingTests.ArgentineRegionSuffixRewritesCharacterFour;
begin
  AssertEquals('LU1ZAA', NewKey('LU1AAA/Z'));
  AssertEquals('LU1MAA', NewKey('LU1AAA/M'));
  AssertEquals('LU1HAA', NewKey('LU1AAA/H'));
end;

procedure TSplittingTests.ArgentineLettersTheOriginalMissed;
var
  I: Integer;
  C: AnsiChar;
begin
  { F G I K W were absent from the original's suffix-letter set because they
    are foreign DXCC prefixes; for Argentine calls they are provinces. }
  for I := 1 to Length(MissedLetters) do
  begin
    C := MissedLetters[I];
    AssertEquals('LU1AAA/' + C + ' should rewrite character 4',
      'LU1' + C + 'AA', NewKey('LU1AAA/' + C));
    { The original fell through to its generic branch and probed 'LU/<letter>'
      instead -- measured, before the legacy engine was retired.  Asserting it
      here is what makes this a test of the fix rather than of the fixture:
      if the new key ever equalled the old one, the province would be lost
      again and this would fail. }
    AssertTrue('the fix must differ from the original key LU/' + C,
      OldKeyForMissedLetter + C <> NewKey('LU1AAA/' + C));
  end;
end;

procedure TSplittingTests.ArgentineLettersAlreadyPatchedInTheTable;
begin
  { /W and /X are carried by explicit slash patterns in AreaOK1RR.tbl, so the
    exact-match attempt at the top of the splitter answers them before any
    rewriting happens.  Both implementations must leave these alone -- the
    fix must not "helpfully" take them over. }
  { The original produced 'LU1AAA/W' here too -- the fix must not take it over. }
  AssertEquals('LU1AAA/W', NewKey('LU1AAA/W'));
  AssertEquals('Argentina, Chubut (CH)', CountryFor('LU1AAA/W'));

  AssertEquals('LU1AAA/XA', NewKey('LU1AAA/XA'));
  AssertEquals('Argentina, Santa Cruz (SC)', CountryFor('LU1AAA/XA'));
  AssertEquals('Argentina, Tierra del Fuego (TF)', CountryFor('LU1AAA/XZ'));
end;

procedure TSplittingTests.ArgentineMobileAndPortableKeepTheirRegion;
begin
  { /M and /P are mobile and portable for everyone else, but Mendoza and San
    Juan for Argentina.  The original special-cased this for LU only. }
  AssertEquals('LU1MAA', NewKey('LU1AAA/M'));
  AssertEquals('LU1PAA', NewKey('LU1AAA/P'));
  AssertEquals('LW1MAA', NewKey('LW1AAA/M'));
  AssertEquals('LW1PAA', NewKey('LW1AAA/P'));

  { ...and stay mobile/portable for everyone else. }
  AssertEquals('OK1ABC', NewKey('OK1ABC/M'));
  AssertEquals('OK1ABC', NewKey('OK1ABC/P'));
  AssertEquals('DL1ABC', NewKey('DL1ABC/M'));
end;

procedure TSplittingTests.CompanionPrefixesBehaveLikeLu;
var
  I: Integer;
  Prefix: string;
begin
  for I := Low(ArgentinePrefixList) to High(ArgentinePrefixList) do
  begin
    Prefix := ArgentinePrefixList[I];
    AssertEquals(Prefix + '1AAA/Z should become ' + Prefix + '1ZAA',
      Prefix + '1ZAA', NewKey(Prefix + '1AAA/Z'));
  end;
end;

procedure TSplittingTests.ArgentineSuffixResolvesToTheRightProvince;
begin
  { End to end: the key the splitter produces, resolved through the table. }
  AssertEquals('Argentina, Buenos Aires (CF)', CountryFor('LU1AAA'));
  AssertEquals('Antarctica',                   CountryFor('LU1AAA/Z'));
  AssertEquals('Argentina, Santa Fe (SF)',     CountryFor('LU1AAA/F'));
  AssertEquals('Argentina, Cordoba (CD)',      CountryFor('LU1AAA/H'));
  AssertEquals('Argentina, Misiones (MN)',     CountryFor('LU1AAA/I'));
  AssertEquals('Argentina, Tucuman (TM)',      CountryFor('LU1AAA/K'));
  AssertEquals('Argentina, Mendoza (MZ)',      CountryFor('LU1AAA/M'));
  AssertEquals('Argentina, San Juan (SJ)',     CountryFor('LU1AAA/P'));
  { Chubut arrives via the table's own /W pattern rather than a rewrite. }
  AssertEquals('Argentina, Chubut (CH)',       CountryFor('LU1AAA/W'));
end;

procedure TSplittingTests.TheFixChangesTheProvinceNotTheEntity;
const
  { The six forms the fix actually touches. }
  Affected: array[0..5] of string = (
    'LU1AAA/F', 'LU1AAA/G', 'LU1AAA/I', 'LU1AAA/K', 'LW1AAA/M', 'LW1AAA/P');
  { What the original resolved each of them to, measured. All ADIF 100. }
  OldCountry: array[0..5] of string = (
    'Argentina', 'Argentina', 'Argentina', 'Argentina',
    'Argentina, Buenos Aires (CF)', 'Argentina, Buenos Aires (CF)');
var
  I: Integer;
begin
  { It is tempting to read the original as "F is France, so LU1AAA/F resolved
    as France".  It did not.  The branch sets the key to the bare suffix, but
    the statement right after it probes Copy(prefix,1,2) + '/' + suffix in
    PREFIX mode, where the callsign may be longer than the pattern -- and 'LU'
    is itself a mark.  So the probe hit, and the old answer was plain
    Argentina: measured key 'LU/F', measured country 'Argentina'. }
  AssertEquals('Argentina, Santa Fe (SF)', CountryFor('LU1AAA/F'));

  { The same mechanism for a non-Argentine call, where both engines agree:
    DL1ABC/F resolves through 'DL/F' as Germany, not France. }
  AssertEquals('DL/F', NewKey('DL1ABC/F'));
  AssertEquals('Federal Republic of Germany', CountryFor('DL1ABC/F'));

  { Which is why the fix moves no DXCC entity: every Argentine province shares
    ADIF 100.  It sharpens the province, and the province is what the log
    shows.  Confirmed over a 58 184-QSO log -- zero ADIF differences; see
    docs/EQUIVALENCE.md. }
  for I := Low(Affected) to High(Affected) do
  begin
    AssertEquals(Affected[I] + ' should still be ADIF 100',
      100, AdifFor(Affected[I]));
    AssertTrue(Affected[I] + ' should change province, but still reads ' +
      OldCountry[I], OldCountry[I] <> CountryFor(Affected[I]));
  end;
end;

{ --- everything else must be unchanged -------------------------------- }

procedure TSplittingTests.NonArgentineSlashFormsAreUnchanged;
const
  Cases: array[0..17] of string = (
    'OK1ABC/P', 'OK1ABC/M', 'OK1ABC/QRP', 'OK1ABC/1', 'OK1ABC/OK2',
    'DL1ABC/LH', 'DL1ABC/F', 'DL1ABC/A', 'KL7AA/1', 'W1AW/4',
    'SP2AD/1', 'ZL1AMO/C', 'RA1AAA/2/M', 'VP2E/G4XYZ', 'G4XYZ/VP2E',
    'F/OK1ABC', 'OK1ABC/MM', 'OK1ABC/AM');
  { The key the original produced for each, measured before it was retired.
    '?' is the splitter's "maritime or aeronautical mobile, no country". }
  Expected: array[0..17] of string = (
    'OK1ABC', 'OK1ABC', 'OK1ABC', 'OK1ABC', 'OK1ABC',
    'DL1ABC', 'DL/F', 'DL/A', 'W1', 'W4',
    'SP1AD', 'ZL/C', 'RA2AAA', 'VP2E', 'VP2E',
    'F', '?', '?');
var
  I: Integer;
begin
  for I := Low(Cases) to High(Cases) do
    AssertEquals('splitting ' + Cases[I], Expected[I], NewKey(Cases[I]));
end;

{ --- ported behaviour worth stating outright -------------------------- }

procedure TSplittingTests.MaritimeAndAeronauticalMobileHaveNoCountry;
begin
  AssertEquals('?', NewKey('OK1ABC/MM'));
  AssertEquals('?', NewKey('OK1ABC/AM'));
  AssertEquals('?', NewKey('OK1ABC/MM1'));
  AssertEquals('?', NewKey('OK1ABC/1/MM'));
end;

procedure TSplittingTests.IgnoredSuffixesFallBackToTheOperatorCall;
begin
  { /LH is a lighthouse, not the LH prefix. }
  AssertEquals('DL1ABC', NewKey('DL1ABC/LH'));
  AssertEquals('OK1ABC', NewKey('OK1ABC/QRP'));
  AssertEquals('OK1ABC', NewKey('OK1ABC/QRPP'));
  { A long all-letter suffix is free text. }
  AssertEquals('OK1ABC', NewKey('OK1ABC/PORTABLE'));
end;

procedure TSplittingTests.DigitSuffixRenumbersTheCallArea;
begin
  { SP2AD/1 -> SP1AD: the digit replaces character 3. }
  AssertEquals('SP1AD', NewKey('SP2AD/1'));
  { A multi-digit suffix is a serial, not an area. }
  AssertEquals('OK1ABC', NewKey('OK1ABC/12'));
end;

procedure TSplittingTests.UsCallsMoveToTheWDistrict;
begin
  AssertEquals('W1', NewKey('KL7AA/1'));
  AssertEquals('W4', NewKey('W1AW/4'));
end;

procedure TSplittingTests.VerbatimSlashEntriesNeedNoSplitting;
var
  Resolved: Boolean;
  Adif: Integer;
begin
  { Listed with the slash in CallResolution.tbl, so the first exact-match
    attempt wins and nothing is rewritten. }
  AssertEquals('LU2ERA/Z',
    FResolver.EffectiveCallsign('LU2ERA/Z', '2020/01/01', Resolved, Adif));
  AssertTrue('an exact hit should report the answer as already resolved',
    Resolved);
end;

procedure TSplittingTests.ShortCallsignsDoNotCorruptMemory;
const
  Shorts: array[0..8] of string = (
    'LU/Z', 'LU1/Z', 'L/Z', '/Z', 'LU/', 'A/1', 'LU/1', 'X/', '//');
var
  I: Integer;
begin
  { The original wrote pred_lomitkem[3] and [4] without checking the length,
    which is undefined behaviour on anything shorter.  These must simply
    return something. }
  for I := Low(Shorts) to High(Shorts) do
    AssertTrue('splitting ' + Shorts[I] + ' should not raise',
      NewKey(Shorts[I]) <> #1);
end;

initialization
  RegisterTest(TSplittingTests);

end.
