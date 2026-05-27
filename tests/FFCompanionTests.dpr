{*******************************************************************************
  Program: FFCompanionTests
  Purpose: DUnitX console runner for the FFCompanion test suite

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Boots DUnitX with the console logger, executes every fixture registered in
    the linked test units, and exits with code 1 on any failure. New test
    fixtures must be added to the uses clause to be discovered.
*******************************************************************************}

program FFCompanionTests;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.TestFramework,
  MVCFramework.SQLGenerators.Sqlite,
  Repositories.MigrationU in '..\repositories\Repositories.MigrationU.pas',
  TestHelpers.DbU in 'TestHelpers.DbU.pas',
  Tests.L10nU in 'Tests.L10nU.pas',
  Tests.MigrationU in 'Tests.MigrationU.pas';

var
  LRunner: ITestRunner;
  LResults: IRunResults;
  LLogger: ITestLogger;
begin
  try
    LRunner := TDUnitX.CreateRunner;
    LRunner.UseRTTI := True;
    LLogger := TDUnitXConsoleLogger.Create(True);
    LRunner.AddLogger(LLogger);
    LResults := LRunner.Execute;
    if not LResults.AllPassed then
      ExitCode := 1;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
