(*
 ***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License.        *
 *                                                                         *
 ***************************************************************************
*)

{ Base class for the table tests: fixture building and match assertions.

  NewTable is still a virtual, even though only one engine remains.  It is the
  seam a second implementation would be driven through -- a port in another
  language, wrapped behind IDxccTable, inherits every published test here by
  overriding this one method. }

unit uDxccTestBase;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, uDxccTableIntf;

type
  TDxccTableTestCase = class(TTestCase)
  protected
    { The seam. Text is the table content, not a filename. }
    function NewTable(const Text: string): IDxccTable; virtual;
    { For the handful of tests that are specifically about loading a FILE. }
    function NewTableFromFile(const FileName: string): IDxccTable; virtual;

    { Builds a throwaway table from literal lines.

      A sentinel entry is appended -- see SentinelMark below. }
    function BuildTable(const Lines: array of string): IDxccTable;

    { Convenience: a table holding exactly one entry with the given mark(s).
      The description is fixed so tests only have to think about the pattern. }
    function SinglePattern(const Marks: string): IDxccTable;

    { True when Callsign resolves to something in a single-pattern table. }
    function Matches(const Marks, Callsign: string): Boolean;
    function MatchesMode(const Marks, Callsign: string; Mode: TMatchMode): Boolean;

    procedure AssertMatches(const Marks, Callsign: string);
    procedure AssertNoMatch(const Marks, Callsign: string);
  end;

const
  { A complete, valid description line -- everything after the marks. }
  StockDescription = '|Test Land|EU|-1|50.00N|14.00E|28|15||R|=100';

  { Every table built here gets this extra entry appended.

    Tseznam.znacka_najdikam_s (znacmech.pas:529) can leave its search index one
    past the last entry when the probe key sorts above everything in the table;
    znacky is a zero-filled fixed array, so the next dereference hits nil and
    the process dies.  najdis_s2 probes with first-char + '[', and '[' outranks
    every alphanumeric in odbec's collation, so ANY table whose marks are all
    alphanumeric triggers this -- which is every hand-written fixture.

    The real tables escape it only because they contain '%'-leading marks that
    sort above the probe key (see tRobustness).  '~' outranks every
    alphanumeric too, so this sentinel reproduces that protection.  It is a
    plain literal, so it never matches a test callsign.

    TDxccTable does not need this crutch -- tRobustness asserts that
    directly -- but the fixtures keep it so their contents stay exactly what
    the characterisation tests were written against. }
  SentinelMark = '~~~~';

implementation

uses
  uModernTable;

function TDxccTableTestCase.NewTable(const Text: string): IDxccTable;
begin
  Result := TModernTable.Create(Text);
end;

function TDxccTableTestCase.NewTableFromFile(const FileName: string): IDxccTable;
begin
  Result := TModernTable.CreateFromFile(FileName);
end;

function TDxccTableTestCase.BuildTable(const Lines: array of string): IDxccTable;
var
  L: TStringList;
  I: Integer;
begin
  L := TStringList.Create;
  try
    for I := Low(Lines) to High(Lines) do
      L.Add(Lines[I]);
    L.Add(SentinelMark + StockDescription);
    Result := NewTable(L.Text);
  finally
    L.Free;
  end;
end;

function TDxccTableTestCase.SinglePattern(const Marks: string): IDxccTable;
begin
  Result := BuildTable([Marks + StockDescription]);
end;

function TDxccTableTestCase.MatchesMode(const Marks, Callsign: string;
  Mode: TMatchMode): Boolean;
begin
  Result := SinglePattern(Marks).Find(Callsign, '*', Mode) >= 0;
end;

function TDxccTableTestCase.Matches(const Marks, Callsign: string): Boolean;
begin
  Result := MatchesMode(Marks, Callsign, mmPrefix);
end;

procedure TDxccTableTestCase.AssertMatches(const Marks, Callsign: string);
begin
  AssertTrue(Format('pattern %s should match %s', [Marks, Callsign]),
    Matches(Marks, Callsign));
end;

procedure TDxccTableTestCase.AssertNoMatch(const Marks, Callsign: string);
begin
  AssertFalse(Format('pattern %s should not match %s', [Marks, Callsign]),
    Matches(Marks, Callsign));
end;

end.
