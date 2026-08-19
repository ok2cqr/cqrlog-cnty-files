(*
 ***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License.        *
 *                                                                         *
 ***************************************************************************
*)

{ Resolves callsigns to DXCC entities from the command line.

  It follows the same path CQRLOG's id_country does: split the callsign into
  the key a table can be probed with, look that key up in the deleted table
  first and then the valid one, and read the fields off the entry that won.

  Usage:
    dxcclookup --call OK1AYY [--date YYYY-MM-DD] [--explain]
    dxcclookup --csv <file>            columns: date,callsign (header ignored)
    dxcclookup --dump-tables <dir>     write the merged tables and stop

    --data <dir>       where the OK1RR files live (default: ../../data/dxcc)
    --variant plain    use the unexpanded country.tab (default: expanded)

  --dump-tables exists so the in-memory merge can be checked against
  tools/build-tables.sh: the two must agree byte for byte. }

program dxcclookup;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils,
  uDxccTable, uDxccEntry, uDxccResolver, uDxccSuffixRules, uDxccSource;

var
  DataDir: string = '';
  CallArg: string = '';
  DateArg: string = '';
  CsvArg: string = '';
  DumpDir: string = '';
  Explain: Boolean = False;
  Expanded: Boolean = True;

  Valid, Deleted: TDxccTable;
  Rules: TDxccSuffixRules;
  Resolver: TDxccResolver;

{ RFC 4180 quoting -- country names contain commas ("Czech Republic, Bohemia"),
  so unquoted output would not be readable as CSV. }
function Csv(const S: string): string;
begin
  if (Pos(',', S) > 0) or (Pos('"', S) > 0) then
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"'
  else
    Result := S;
end;

procedure Fail(const Msg: string);
begin
  Writeln(StdErr, 'dxcclookup: ', Msg);
  Halt(2);
end;

procedure Usage;
begin
  Writeln('usage:');
  Writeln('  dxcclookup --call SIGN [--date YYYY-MM-DD] [--explain]');
  Writeln('  dxcclookup --csv FILE');
  Writeln('  dxcclookup --dump-tables DIR');
  Writeln('options:');
  Writeln('  --data DIR        directory holding the OK1RR files');
  Writeln('  --variant plain|expanded   which country.tab to build');
  Halt(0);
end;

{ The data directory is found relative to the binary so the tool works from a
  checkout without arguments. }
function FindDataDir: string;
var
  Dir, Rel: string;
  I: Integer;
begin
  Rel := 'data' + PathDelim + 'dxcc' + PathDelim;
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for I := 0 to 5 do
  begin
    if FileExists(Dir + Rel + 'Country.tab') then
      Exit(Dir + Rel);
    Dir := ExpandFileName(Dir + '..' + PathDelim);
  end;
  Fail('cannot find data/dxcc -- pass --data <dir>');
  Result := '';
end;

{ CQRLOG stores dates as YYYY/MM/DD; accept the ISO form people actually
  type and convert. }
function NormaliseDate(const S: string): string;
begin
  Result := StringReplace(S, '-', '/', [rfReplaceAll]);
  if (Length(Result) <> 10) or (Result[5] <> '/') or (Result[8] <> '/') then
    Fail('date must be YYYY-MM-DD, got: ' + S);
end;

procedure ParseArgs;
var
  I: Integer;
  Arg, V: string;
begin
  I := 1;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);
    if Arg = '--call' then begin Inc(I); CallArg := ParamStr(I); end
    else if Arg = '--date' then begin Inc(I); DateArg := NormaliseDate(ParamStr(I)); end
    else if Arg = '--csv' then begin Inc(I); CsvArg := ParamStr(I); end
    else if Arg = '--data' then begin Inc(I); DataDir := ParamStr(I); end
    else if Arg = '--dump-tables' then begin Inc(I); DumpDir := ParamStr(I); end
    else if Arg = '--explain' then Explain := True
    else if Arg = '--variant' then
    begin
      Inc(I);
      V := ParamStr(I);
      if V = 'plain' then Expanded := False
      else if V = 'expanded' then Expanded := True
      else Fail('--variant must be plain or expanded');
    end
    else if (Arg = '--help') or (Arg = '-h') then Usage
    else Fail('unknown argument: ' + Arg);
    Inc(I);
  end;

  if (CallArg = '') and (CsvArg = '') and (DumpDir = '') then
    Usage;
  if (CallArg <> '') and (CsvArg <> '') then
    Fail('--call and --csv are mutually exclusive');
  if DateArg = '' then
    DateArg := FormatDateTime('yyyy"/"mm"/"dd', Now);
  if DataDir = '' then
    DataDir := FindDataDir
  else
    DataDir := IncludeTrailingPathDelimiter(DataDir);
end;

procedure DumpTables;
var
  Target: string;

  { Writes the bytes we assembled, not a TStringList round-trip: the point of
    this dump is that it is comparable byte for byte. }
  procedure Put(const Name, Text: string);
  begin
    with TFileStream.Create(Target + Name, fmCreate) do
    try
      if Length(Text) > 0 then
        WriteBuffer(Text[1], Length(Text));
    finally
      Free;
    end;
    Writeln(Format('%-24s %10d bytes', [Name, Length(Text)]));
  end;

begin
  Target := IncludeTrailingPathDelimiter(DumpDir);
  if not DirectoryExists(Target) then
    ForceDirectories(Target);
  Put('country-plain.tab', BuildCountryTable(DataDir, []));
  Put('country-expanded.tab', BuildCountryTable(DataDir, [dsoExpandPercentLines]));
  Put('country_del.tab', BuildDeletedTable(DataDir));
end;

procedure LoadEngine;
var
  Options: TDxccSourceOptions;
begin
  if Expanded then
    Options := [dsoExpandPercentLines]
  else
    Options := [];

  Valid := TDxccTable.Create;
  Valid.LoadFromString(BuildCountryTable(DataDir, Options));
  Deleted := TDxccTable.Create;
  Deleted.LoadFromString(BuildDeletedTable(DataDir));

  Rules := TDxccSuffixRules.Create;
  Rules.LoadExceptions(DxccSourcePath(DataDir, ExceptionsFileName));
  Rules.LoadAmbiguous(DxccSourcePath(DataDir, AmbiguousFileName));

  Resolver := TDxccResolver.Create(Valid, Deleted, Rules);
end;

procedure FreeEngine;
begin
  Resolver.Free;
  Rules.Free;
  Deleted.Free;
  Valid.Free;
end;

type
  TAnswer = record
    Key: string;
    Found, Deleted: Boolean;
    Pattern: string;
    Entry: TDxccEntry;
  end;

function Resolve(const Callsign, ADate: string): TAnswer;
var
  Resolved: Boolean;
  Adif, Idx: Integer;
begin
  Resolved := False;
  Adif := 0;
  Result.Key := Resolver.EffectiveCallsign(Callsign, ADate, Resolved, Adif);
  Result.Found := False;
  Result.Deleted := False;
  Result.Pattern := '';
  ClearEntry(Result.Entry);

  { Deleted entities are consulted first: that is what makes OK1AYY in 1992
    Czechoslovakia rather than the Czech Republic. }
  Idx := Deleted.Find(Result.Key, ADate, dmPrefix);
  if Idx <> -1 then
  begin
    Result.Found := True;
    Result.Deleted := True;
    Result.Pattern := Deleted.Pattern(Idx);
    Result.Entry := Deleted.Entry(Idx);
    Exit;
  end;

  Idx := Valid.Find(Result.Key, ADate, dmPrefix);
  if Idx <> -1 then
  begin
    Result.Found := True;
    Result.Pattern := Valid.Pattern(Idx);
    Result.Entry := Valid.Entry(Idx);
  end;
end;

procedure ReportOne(const Callsign, ADate: string);
var
  A: TAnswer;
begin
  A := Resolve(Callsign, ADate);
  Writeln('callsign : ', Callsign);
  Writeln('date     : ', ADate);
  if not A.Found then
  begin
    Writeln('country  : <no match>   (lookup key ', A.Key, ')');
    Exit;
  end;
  Writeln('country  : ', A.Entry.Country);
  Writeln('adif     : ', A.Entry.Adif);
  if A.Deleted then
    Writeln('status   : deleted entity');
  if Explain then
  begin
    Writeln('key      : ', A.Key);
    Writeln('pattern  : ', A.Pattern);
    Writeln('continent: ', A.Entry.Continent);
    Writeln('cq/itu   : ', A.Entry.Waz, ' / ', A.Entry.Itu);
    Writeln('lat/lon  : ', A.Entry.Latitude, ' ', A.Entry.Longitude);
    Writeln('valid    : ', A.Entry.ValidFrom, ' - ', A.Entry.ValidTo);
    Writeln('table    : ', BoolToStr(A.Deleted, 'country_del.tab', 'country.tab'));
  end;
end;

{ Reads date,callsign rows. Quotes are stripped; a row that does not have two
  usable columns is counted rather than quietly skipped. }
procedure ReportCsv(const FileName: string);
var
  Raw, F: TStringList;
  I, Comma, Bad, Total, NoCountry: Integer;
  Line, D, C: string;
  A: TAnswer;
begin
  if not FileExists(FileName) then
    Fail('no such file: ' + FileName);
  Raw := TStringList.Create;
  F := TStringList.Create;
  try
    Raw.LoadFromFile(FileName);
    Bad := 0;
    Total := 0;
    NoCountry := 0;
    Writeln('date,callsign,key,adif,country');
    for I := 0 to Raw.Count - 1 do
    begin
      Line := Trim(Raw[I]);
      if Line = '' then
        Continue;
      Comma := Pos(',', Line);
      if Comma = 0 then
      begin
        Inc(Bad);
        Continue;
      end;
      D := StringReplace(Trim(Copy(Line, 1, Comma - 1)), '"', '', [rfReplaceAll]);
      C := StringReplace(Trim(Copy(Line, Comma + 1, MaxInt)), '"', '', [rfReplaceAll]);
      if (D = '') or (C = '') then
      begin
        Inc(Bad);
        Continue;
      end;
      { Skip a header row rather than reporting it as unparseable. }
      if (I = 0) and (Pos('-', D) = 0) and (Pos('/', D) = 0) then
        Continue;
      D := StringReplace(D, '-', '/', [rfReplaceAll]);
      A := Resolve(UpperCase(C), D);
      Inc(Total);
      if not A.Found then
        Inc(NoCountry);
      Writeln(Format('%s,%s,%s,%s,%s',
        [D, Csv(C), Csv(A.Key), Csv(A.Entry.Adif), Csv(A.Entry.Country)]));
    end;
    Writeln(StdErr, Format('SUMMARY rows=%d nocountry=%d unparseable=%d',
      [Total, NoCountry, Bad]));
  finally
    F.Free;
    Raw.Free;
  end;
end;

begin
  ParseArgs;

  if DumpDir <> '' then
  begin
    DumpTables;
    Halt(0);
  end;

  LoadEngine;
  try
    if CallArg <> '' then
      ReportOne(UpperCase(CallArg), DateArg)
    else
      ReportCsv(CsvArg);
  finally
    FreeEngine;
  end;
end.
