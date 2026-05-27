{*******************************************************************************
  Unit Name: Models.UserU
  Purpose: User record matching the users table schema

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Plain-data record representing a row in the users table. Repositories
    populate this from FireDAC queries and services pass it around without
    additional behaviour. Kept as a record (not a class) so callers do not
    need to manage lifetime when reading or returning user data.
*******************************************************************************}

unit Models.UserU;

interface

type
  /// <summary>
  ///   Snapshot of a user row.
  /// </summary>
  TUser = record
    /// <summary>Primary key from users.id (autoincrement).</summary>
    Id: Int64;
    /// <summary>Unique username chosen by the user at signup.</summary>
    Username: string;
    /// <summary>Bcrypt-hashed password (never the plaintext).</summary>
    PasswordHash: string;
    /// <summary>ISO-8601 timestamp captured at signup, parsed to TDateTime.</summary>
    CreatedAt: TDateTime;
  end;

implementation

end.
