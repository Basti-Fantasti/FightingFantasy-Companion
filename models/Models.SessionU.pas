{*******************************************************************************
  Unit Name: Models.SessionU
  Purpose: Session record matching the sessions table schema

  Author: Bastian Teufel
  Created: 2026-05-27

  Copyright (c) 1984-2026 GTR mbH

  Description:
    Plain-data record representing a row in the sessions table. The DMVC
    framework owns its own session storage for HTTP requests; this record is
    used by the lower-level repository when persisting tokens.
*******************************************************************************}

unit Models.SessionU;

interface

type
  /// <summary>
  ///   Snapshot of a session row.
  /// </summary>
  TSession = record
    /// <summary>Opaque session token (primary key).</summary>
    Token: string;
    /// <summary>Owning user id from users.id.</summary>
    UserId: Int64;
    /// <summary>Absolute expiry timestamp; rows past this should be purged.</summary>
    ExpiresAt: TDateTime;
  end;

implementation

end.
