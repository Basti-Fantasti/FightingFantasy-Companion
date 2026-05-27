{*******************************************************************************
  Unit Name: Tests.Services.AuthU
  Purpose: DUnitX fixtures for TAuthService signup and login flows

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Covers the four core behaviours of TAuthService against a fresh per-test
    SQLite database: successful signup, duplicate-username rejection,
    successful login with the correct password, and login rejection with an
    incorrect password. Each test pairs NewMemoryDb with Drop in a finally
    block to keep fixtures fully isolated.
*******************************************************************************}

unit Tests.Services.AuthU;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>
  ///   DUnitX fixture exercising TAuthService end-to-end against SQLite.
  /// </summary>
  [TestFixture]
  TAuthServiceTests = class
  public
    [Test] procedure SignupCreatesUser;
    [Test] procedure DuplicateSignupFails;
    [Test] procedure LoginAcceptsCorrectPassword;
    [Test] procedure LoginRejectsWrongPassword;
  end;

implementation

uses
  System.SysUtils,
  Models.UserU,
  Services.AuthU,
  TestHelpers.DbU;

procedure TAuthServiceTests.SignupCreatesUser;
var
  LSvc: TAuthService;
  LUid: Int64;
  LErr: string;
  LDb: string;
begin
  LDb := TDbHelper.NewMemoryDb;
  LSvc := TAuthService.Create(LDb);
  try
    Assert.IsTrue(LSvc.Signup('alice', 'secret123', LUid, LErr));
    Assert.IsTrue(LUid > 0);
  finally
    LSvc.Free;
    TDbHelper.Drop(LDb);
  end;
end;

procedure TAuthServiceTests.DuplicateSignupFails;
var
  LSvc: TAuthService;
  LUid: Int64;
  LErr: string;
  LDb: string;
begin
  LDb := TDbHelper.NewMemoryDb;
  LSvc := TAuthService.Create(LDb);
  try
    LSvc.Signup('alice', 'secret123', LUid, LErr);
    Assert.IsFalse(LSvc.Signup('alice', 'other123', LUid, LErr));
    Assert.AreEqual('username_taken', LErr);
  finally
    LSvc.Free;
    TDbHelper.Drop(LDb);
  end;
end;

procedure TAuthServiceTests.LoginAcceptsCorrectPassword;
var
  LSvc: TAuthService;
  LUid: Int64;
  LErr: string;
  LUser: TUser;
  LDb: string;
begin
  LDb := TDbHelper.NewMemoryDb;
  LSvc := TAuthService.Create(LDb);
  try
    LSvc.Signup('alice', 'secret123', LUid, LErr);
    Assert.IsTrue(LSvc.Login('alice', 'secret123', LUser));
    Assert.AreEqual<Int64>(LUid, LUser.Id);
  finally
    LSvc.Free;
    TDbHelper.Drop(LDb);
  end;
end;

procedure TAuthServiceTests.LoginRejectsWrongPassword;
var
  LSvc: TAuthService;
  LUid: Int64;
  LErr: string;
  LUser: TUser;
  LDb: string;
begin
  LDb := TDbHelper.NewMemoryDb;
  LSvc := TAuthService.Create(LDb);
  try
    LSvc.Signup('alice', 'secret123', LUid, LErr);
    Assert.IsFalse(LSvc.Login('alice', 'wrong', LUser));
  finally
    LSvc.Free;
    TDbHelper.Drop(LDb);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAuthServiceTests);

end.
