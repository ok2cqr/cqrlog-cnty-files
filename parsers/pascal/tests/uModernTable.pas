(*
 ***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License.        *
 *                                                                         *
 ***************************************************************************
*)

{ Wraps TDxccTable behind IDxccTable.

  The interface is a leftover from the differential era, when the same
  assertions had to run against two engines.  It is kept because the whole
  suite is written against it and because a second implementation -- a port in
  another language driven from here -- would slot straight in.

  The numeric Field(Index, N) accessor exists for that indirection; real
  callers use the named fields on TDxccEntry. }

unit uModernTable;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, uDxccTableIntf, uDxccTable, uDxccEntry;

type
  TModernTable = class(TInterfacedObject, IDxccTable)
  private
    FTable: TDxccTable;
  public
    { Text is the table content, as assembled by uDxccSource. }
    constructor Create(const Text: string);
    constructor CreateFromFile(const FileName: string);
    destructor Destroy; override;

    function Count: Integer;
    function Find(const Callsign, ADate: string; Mode: TMatchMode): Integer;
    function Pattern(Index: Integer): string;
    function Field(Index, FieldNo: Integer): string;
    function IsValidOn(Index: Integer; const ADate: string): Boolean;
  end;

implementation

uses
  uDxccLimits;

const
  ModeMap: array[TMatchMode] of TDxccMatchMode =
    (dmPrefix, dmExact, dmExactNoEquals);

constructor TModernTable.Create(const Text: string);
begin
  inherited Create;
  FTable := TDxccTable.Create;
  FTable.LoadFromString(Text);
end;

constructor TModernTable.CreateFromFile(const FileName: string);
begin
  inherited Create;
  FTable := TDxccTable.Create;
  FTable.LoadFromFile(FileName);
end;

destructor TModernTable.Destroy;
begin
  FTable.Free;
  inherited Destroy;
end;

function TModernTable.Count: Integer;
begin
  Result := FTable.Count;
end;

function TModernTable.Find(const Callsign, ADate: string; Mode: TMatchMode): Integer;
begin
  { The legacy entry point took a string[40] by reference, so an over-long
    callsign was cut before the search ever saw it.  Same here, explicitly. }
  Result := FTable.Find(Copy(Callsign, 1, MaxMarkLength), ADate, ModeMap[Mode]);
end;

function TModernTable.Pattern(Index: Integer): string;
begin
  Result := FTable.Pattern(Index);
end;

function TModernTable.Field(Index, FieldNo: Integer): string;
var
  E: TDxccEntry;
begin
  if (Index < 0) or (Index >= FTable.Count) then
    Exit(OutOfRangeMarker);
  E := FTable.Entry(Index);
  case FieldNo of
    fldCountry:   Result := E.Country;
    fldContinent: Result := E.Continent;
    fldUtcOffset: Result := E.UtcOffset;
    fldLatitude:  Result := E.Latitude;
    fldLongitude: Result := E.Longitude;
    fldItu:       Result := E.Itu;
    fldWaz:       Result := E.Waz;
    fldAdifCol:   Result := E.AdifColumn;
    fldFlag:      Result := E.Flag;
    fldValidFrom: Result := E.ValidFrom;
    fldValidTo:   Result := E.ValidTo;
    fldAdif:      Result := E.Adif;
  else
    Result := OutOfRangeMarker;
  end;
end;

function TModernTable.IsValidOn(Index: Integer; const ADate: string): Boolean;
begin
  Result := FTable.IsValidOn(Index, ADate);
end;

end.
