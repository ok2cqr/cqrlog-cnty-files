(*
 ***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License.        *
 *                                                                         *
 ***************************************************************************
*)

{ Assembles the parser's input out of the raw data/dxcc directory.

  The table files CQRLOG feeds to the engine are not the files OK1RR ships.
  CQRLOG concatenates three of them into one country.tab before the engine
  ever sees it, which used to mean a shell script had to run before the parser
  could start.  It does not any more: the whole of that preparation is these
  eighty lines, and every port of this parser is expected to reimplement them
  rather than depend on a generated file.

  The rules are specified in ../../../spec/ALGORITHM.md, section "Assembling
  the tables", and they are load-bearing:

    1. country.tab is Country.tab + CallResolution.tbl + AreaOK1RR.tbl, IN
       THAT ORDER.  The sort that indexes the table is stable and Find keeps
       the first of two equally good candidates, so the concatenation order
       decides which of two identical keys wins.
    2. Optionally every line beginning with '%' is appended again 26 times
       with that leading '%' replaced by 'A'..'Z'.  Lines produced this way
       are NOT themselves re-expanded.
    3. CountryDel.tab is a separate table, searched first.
    4. CR is dropped, so the CRLF files in the set load like the LF ones.

  Rule 2 is optional because CQRLOG has two builders that disagree, and both
  variants exist in the field: TdmData.PrepareDXCCData (dData.pas:1057, first
  run) concatenates plainly, while the manual "Import DXCC data"
  (fImportProgress.pas:344-351) expands.  The expanded form is the reference,
  and what the test suite runs against. }

unit uDxccSource;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TDxccSourceOption  = (dsoExpandPercentLines);
  TDxccSourceOptions = set of TDxccSourceOption;

const
  { The expanded form is what "Import DXCC data" produces, and the one the
    test suite runs against. }
  DefaultSourceOptions = [dsoExpandPercentLines];

  CountryFileNames: array[0..2] of string =
    ('Country.tab', 'CallResolution.tbl', 'AreaOK1RR.tbl');
  DeletedFileName    = 'CountryDel.tab';
  ExceptionsFileName = 'Exceptions.tab';
  AmbiguousFileName  = 'Ambiguous.tbl';

{ Joins Dir and FileName. Dir may or may not carry a trailing separator. }
function DxccSourcePath(const Dir, FileName: string): string;

{ The merged valid-entity table, ready for TDxccTable.LoadFromString. }
function BuildCountryTable(const Dir: string;
  Options: TDxccSourceOptions = DefaultSourceOptions): string;

{ The deleted-entity table. No merging, only CR removal. }
function BuildDeletedTable(const Dir: string): string;

implementation

function DxccSourcePath(const Dir, FileName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(Dir) + FileName;
end;

{ Reads a file verbatim, then normalises it to LF-terminated lines: CR is
  dropped and a final newline is added if the file lacks one, so that
  concatenating two files can never glue the last line of one onto the first
  line of the next. }
function ReadNormalised(const FileName: string): string;
var
  Stream: TFileStream;
  Raw: string;
  I, Kept: Integer;
begin
  Raw := '';
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Raw, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Raw[1], Stream.Size);
  finally
    Stream.Free;
  end;

  SetLength(Result, Length(Raw) + 1);
  Kept := 0;
  for I := 1 to Length(Raw) do
    if Raw[I] <> #13 then
    begin
      Inc(Kept);
      Result[Kept] := Raw[I];
    end;

  if (Kept > 0) and (Result[Kept] <> #10) then
  begin
    Inc(Kept);
    Result[Kept] := #10;
  end;
  SetLength(Result, Kept);
end;

{ Rule 2. Every '%'-leading line is appended again with the leading '%'
  replaced by each letter in turn -- and only the leading one; the rest of the
  pattern is copied verbatim, so '%%%%/B[A-LRSTYZ]0[A-F]%' yields
  'A%%%/B[A-LRSTYZ]0[A-F]%' and so on.

  The originals stay where they are and the generated lines all go after them,
  which is what the Pascal loop in fImportProgress does: it evaluates its
  upper bound once, so the lines it appends are never revisited. }
function ExpandPercentLines(const Text: string): string;
var
  Lines: TStringList;
  Tail: TMemoryStream;
  I: Integer;
  C: Char;
  Rest, Line: string;
begin
  Lines := TStringList.Create;
  Tail := TMemoryStream.Create;
  try
    Lines.Text := Text;
    for I := 0 to Lines.Count - 1 do
      if (Lines[I] <> '') and (Lines[I][1] = '%') then
      begin
        Rest := Copy(Lines[I], 2, Length(Lines[I]) - 1);
        for C := 'A' to 'Z' do
        begin
          Line := C + Rest + #10;
          Tail.WriteBuffer(Line[1], Length(Line));
        end;
      end;

    SetLength(Result, Length(Text) + Tail.Size);
    if Length(Text) > 0 then
      Move(Text[1], Result[1], Length(Text));
    if Tail.Size > 0 then
      Move(Tail.Memory^, Result[Length(Text) + 1], Tail.Size);
  finally
    Tail.Free;
    Lines.Free;
  end;
end;

function BuildCountryTable(const Dir: string;
  Options: TDxccSourceOptions): string;
var
  I: Integer;
  Path: string;
begin
  Result := '';
  for I := Low(CountryFileNames) to High(CountryFileNames) do
  begin
    Path := DxccSourcePath(Dir, CountryFileNames[I]);
    if not FileExists(Path) then
      raise EInOutError.CreateFmt('uDxccSource: missing %s', [Path]);
    Result := Result + ReadNormalised(Path);
  end;

  if dsoExpandPercentLines in Options then
    Result := ExpandPercentLines(Result);
end;

function BuildDeletedTable(const Dir: string): string;
var
  Path: string;
begin
  Path := DxccSourcePath(Dir, DeletedFileName);
  if not FileExists(Path) then
    raise EInOutError.CreateFmt('uDxccSource: missing %s', [Path]);
  Result := ReadNormalised(Path);
end;

end.
