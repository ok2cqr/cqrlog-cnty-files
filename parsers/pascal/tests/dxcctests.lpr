(*
 ***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License.        *
 *                                                                         *
 ***************************************************************************
*)

{ Console test runner for the DXCC parser.

  Needs nothing but FPC -- no Lazarus, no LCL, no database.

  Usage:  ./dxcctests --format=plain --all  }

program dxcctests;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, consoletestrunner,
  uDxccTableIntf, uTestData, uModernTable,
  uDxccSuffixRules, uDxccResolver,
  tSmoke, tPattern, tRobustness, tDates, tFields, tLoading, tCollation,
  tArgentina, tSplitting;

type
  TDxccTestRunner = class(TTestRunner)
  end;

var
  App: TDxccTestRunner;

begin
  App := TDxccTestRunner.Create(nil);
  try
    App.Initialize;
    App.Title := 'CQRLOG DXCC parser tests';
    App.Run;
  finally
    App.Free;
  end;
end.
