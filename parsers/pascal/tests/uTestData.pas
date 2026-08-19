(*
 ***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License.        *
 *                                                                         *
 ***************************************************************************
*)

{ Locates the test data and assembles the tables the suite runs against.

  Note what is NOT here: a generated-files directory, and any check that a
  shell script has been run first.  The tables are built straight out of
  data/dxcc by uDxccSource every time the suite starts, which is the same code
  path a real caller uses.  The table functions therefore return the table
  CONTENT, not a filename -- only MiniTableFile is a path, because the
  file-loading tests need one. }

unit uTestData;

{$mode objfpc}{$H+}

interface

{ tests/data -- the hand-written fixtures that belong to the suite. }
function DataDir: string;
{ data/dxcc -- the shipped OK1RR set, shared with every other parser. }
function DxccDataDir: string;

function MiniTableFile: string;
function ExceptionsFile: string;
function AmbiguousFile: string;

function PlainTable: string;
function ExpandedTable: string;
function DeletedTable: string;
function MiniTable: string;

{ The table the parser is specified against.

  CQRLOG builds country.tab in two places and they do not agree: dData.pas:1057
  concatenates the source files as they are, while fImportProgress.pas:344-351
  additionally expands every '%'-leading line into 26 copies, one per leading
  letter.  The expanded form is the richer of the two -- it resolves guest
  operator callsigns that the plain form cannot reach at all -- and it is what
  a user gets after running Import DXCC data.  So that is the reference. }
function CanonicalTable: string;

function HaveDxccData: Boolean;

implementation

uses
  Classes, SysUtils, uDxccSource;

var
  CachedDataDir: string = '';
  CachedDxccDir: string = '';
  CachedPlain: string = '';
  CachedExpanded: string = '';
  CachedDeleted: string = '';
  CachedMini: string = '';

{ Walks up from the executable so the runner works whether it is started from
  parsers/pascal, from tests/, or from the repository root. }
function FindUpwards(const Marker: string; out Found: string): Boolean;
var
  Dir: string;
  I: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for I := 0 to 5 do
  begin
    if FileExists(Dir + Marker) then
    begin
      Found := Dir;
      Exit(True);
    end;
    Dir := ExpandFileName(Dir + '..' + PathDelim);
  end;
  Found := '';
  Result := False;
end;

function DataDir: string;
var
  Base: string;
begin
  if CachedDataDir <> '' then
    Exit(CachedDataDir);
  if FindUpwards('data' + PathDelim + 'mini.tab', Base) then
    CachedDataDir := Base + 'data' + PathDelim
  else if FindUpwards('tests' + PathDelim + 'data' + PathDelim + 'mini.tab', Base) then
    CachedDataDir := Base + 'tests' + PathDelim + 'data' + PathDelim
  else
    raise Exception.Create('uTestData: cannot locate tests/data (mini.tab)');
  Result := CachedDataDir;
end;

function DxccDataDir: string;
var
  Base, Rel: string;
begin
  if CachedDxccDir <> '' then
    Exit(CachedDxccDir);
  Rel := 'data' + PathDelim + 'dxcc' + PathDelim + 'Country.tab';
  if not FindUpwards(Rel, Base) then
    raise Exception.Create('uTestData: cannot locate data/dxcc (Country.tab)');
  CachedDxccDir := Base + 'data' + PathDelim + 'dxcc' + PathDelim;
  Result := CachedDxccDir;
end;

function MiniTableFile: string;
begin
  Result := DataDir + 'mini.tab';
end;

function ExceptionsFile: string;
begin
  Result := DxccSourcePath(DxccDataDir, ExceptionsFileName);
end;

function AmbiguousFile: string;
begin
  Result := DxccSourcePath(DxccDataDir, AmbiguousFileName);
end;

function PlainTable: string;
begin
  if CachedPlain = '' then
    CachedPlain := BuildCountryTable(DxccDataDir, []);
  Result := CachedPlain;
end;

function ExpandedTable: string;
begin
  if CachedExpanded = '' then
    CachedExpanded := BuildCountryTable(DxccDataDir, [dsoExpandPercentLines]);
  Result := CachedExpanded;
end;

function DeletedTable: string;
begin
  if CachedDeleted = '' then
    CachedDeleted := BuildDeletedTable(DxccDataDir);
  Result := CachedDeleted;
end;

function MiniTable: string;
var
  L: TStringList;
begin
  if CachedMini = '' then
  begin
    L := TStringList.Create;
    try
      L.LoadFromFile(MiniTableFile);
      CachedMini := L.Text;
    finally
      L.Free;
    end;
  end;
  Result := CachedMini;
end;

function CanonicalTable: string;
begin
  Result := ExpandedTable;
end;

function HaveDxccData: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := Low(CountryFileNames) to High(CountryFileNames) do
    if not FileExists(DxccSourcePath(DxccDataDir, CountryFileNames[I])) then
      Exit;
  Result := FileExists(DxccSourcePath(DxccDataDir, DeletedFileName)) and
            FileExists(ExceptionsFile) and FileExists(AmbiguousFile);
end;

end.
