(*
 ***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License.        *
 *                                                                         *
 ***************************************************************************
*)

{ Phase 0: proves the shipped data is present, that uDxccSource assembles it
  and that the engine loads the result.  If this fails, nothing else in the
  suite is meaningful. }

unit tSmoke;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry;

type
  TSmokeTest = class(TTestCase)
  published
    procedure DxccDataIsPresent;
    procedure MiniTableLoads;
    procedure PlainTableLoads;
    procedure ExpandedTableIsLarger;
    procedure DeletedTableLoads;
    procedure MissingFileDoesNotCrash;
    procedure MergeOrderIsCountryCallResolutionArea;
  end;

implementation

uses
  uDxccTableIntf, uModernTable, uTestData, uDxccSource;

procedure TSmokeTest.DxccDataIsPresent;
begin
  AssertTrue('data/dxcc is incomplete -- expected the OK1RR files in ' +
    DxccDataDir, HaveDxccData);
end;

procedure TSmokeTest.MiniTableLoads;
var
  T: IDxccTable;
begin
  T := TModernTable.Create(MiniTable);
  { 30 lines, but several carry more than one mark. }
  AssertTrue('mini.tab should yield more than 30 marks, got ' + IntToStr(T.Count),
    T.Count > 30);
end;

procedure TSmokeTest.PlainTableLoads;
var
  T: IDxccTable;
begin
  T := TModernTable.Create(PlainTable);
  { Pinned so that a data refresh which silently loses half the file is caught
    here, rather than as a puzzling resolution change somewhere else. }
  AssertEquals('mark count of the plain country.tab', 21560, T.Count);
end;

procedure TSmokeTest.ExpandedTableIsLarger;
var
  Plain, Expanded: IDxccTable;
begin
  Plain    := TModernTable.Create(PlainTable);
  Expanded := TModernTable.Create(ExpandedTable);
  AssertTrue('the %-expanded table must hold more marks',
    Expanded.Count > Plain.Count);
end;

procedure TSmokeTest.DeletedTableLoads;
var
  T: IDxccTable;
begin
  T := TModernTable.Create(DeletedTable);
  AssertTrue('country_del.tab should hold marks, got ' + IntToStr(T.Count),
    T.Count > 0);
end;

procedure TSmokeTest.MissingFileDoesNotCrash;
var
  T: IDxccTable;
begin
  { LoadFromFile reports the problem and marks the table unloaded; it does
    not raise. }
  T := TModernTable.CreateFromFile(DataDir + 'no-such-file.tab');
  AssertEquals('a table that failed to load reports no marks', 0, T.Count);
end;

{ The concatenation order is load-bearing: the sort is stable and Find keeps
  the first of two equally good candidates, so whichever file contributed a
  mark first wins a tie.  Assert the order rather than trusting the constant. }
procedure TSmokeTest.MergeOrderIsCountryCallResolutionArea;
begin
  AssertEquals(3, Length(CountryFileNames));
  AssertEquals('Country.tab',        CountryFileNames[0]);
  AssertEquals('CallResolution.tbl', CountryFileNames[1]);
  AssertEquals('AreaOK1RR.tbl',      CountryFileNames[2]);
end;

initialization
  RegisterTest(TSmokeTest);

end.
