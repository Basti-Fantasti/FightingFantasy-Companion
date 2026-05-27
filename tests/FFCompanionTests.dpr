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
  Models.UserU in '..\models\Models.UserU.pas',
  Models.SessionU in '..\models\Models.SessionU.pas',
  Repositories.UsersU in '..\repositories\Repositories.UsersU.pas',
  Repositories.SessionsU in '..\repositories\Repositories.SessionsU.pas',
  Services.AuthU in '..\services\Services.AuthU.pas',
  Models.BookU in '..\models\Models.BookU.pas',
  Models.StatDefU in '..\models\Models.StatDefU.pas',
  Repositories.BooksU in '..\repositories\Repositories.BooksU.pas',
  Services.LocalizedTitleU in '..\services\Services.LocalizedTitleU.pas',
  Services.YamlReaderU in '..\services\Services.YamlReaderU.pas',
  Services.BookCatalogU in '..\services\Services.BookCatalogU.pas',
  Models.AdventureU in '..\models\Models.AdventureU.pas',
  Repositories.AdventuresU in '..\repositories\Repositories.AdventuresU.pas',
  Models.StepU in '..\models\Models.StepU.pas',
  Repositories.StepsU in '..\repositories\Repositories.StepsU.pas',
  Models.StatChangeU in '..\models\Models.StatChangeU.pas',
  Repositories.StatChangesU in '..\repositories\Repositories.StatChangesU.pas',
  Models.InventoryEventU in '..\models\Models.InventoryEventU.pas',
  Repositories.InventoryEventsU in '..\repositories\Repositories.InventoryEventsU.pas',
  Services.AdventureStateU in '..\services\Services.AdventureStateU.pas',
  Services.GraphBuilderU in '..\services\Services.GraphBuilderU.pas',
  Tests.L10nU in 'Tests.L10nU.pas',
  Tests.MigrationU in 'Tests.MigrationU.pas',
  Tests.Services.AuthU in 'Tests.Services.AuthU.pas',
  Tests.Services.LocalizedTitleU in 'Tests.Services.LocalizedTitleU.pas',
  Tests.Services.YamlReaderU in 'Tests.Services.YamlReaderU.pas',
  Tests.Services.BookCatalogU in 'Tests.Services.BookCatalogU.pas',
  Tests.Repositories.AdventuresU in 'Tests.Repositories.AdventuresU.pas',
  Tests.Repositories.StepsU in 'Tests.Repositories.StepsU.pas',
  Tests.Services.AdventureStateU in 'Tests.Services.AdventureStateU.pas',
  Tests.Services.AdventureStateU.Inventory in 'Tests.Services.AdventureStateU.Inventory.pas',
  Tests.Services.GraphBuilderU in 'Tests.Services.GraphBuilderU.pas';

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
