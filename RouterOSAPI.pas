{*******************************************************************************

Author:        Pavel Skuratovich (aka Chupaka), Minsk, Belarus
Description:   Implementation of MikroTik RouterOS API Client
Version:       1.2
E-Mail:        chupaka@gmail.com
Support:       http://forum.mikrotik.com/viewtopic.php?t=31555
Dependencies:  Uses Ararat Synapse Library (http://synapse.ararat.cz/)
Legal issues:  Copyright © by Pavel Skuratovich

               This source code is provided 'as-is', without any express or
               implied warranty. In no event will the author be held liable
               for any damages arising from the use of this software.

               Permission is granted to anyone to use this software for any
               purpose, including commercial applications, and to alter it
               and redistribute it freely, subject to the following
               restrictions:

               1. The origin of this software must not be misrepresented,
                  you must not claim that you wrote the original software.
                  If you use this software in a product, an acknowledgment
                  in the product documentation would be appreciated but is
                  not required.

               2. Altered source versions must be plainly marked as such, and
                  must not be misrepresented as being the original software.

               3. This notice may not be removed or altered from any source
                  distribution.

********************************************************************************

  API over TLS notes:

    Added in RouterOS v6.1. Only TLS without certificate is currently supported.
    Add 'ssl_openssl' to your project uses
    (http://synapse.ararat.cz/doku.php/public:howto:sslplugin)
    and then call TRosApiClient.SSLConnect() instead of TRosApiClient.Connect()

********************************************************************************

Version history:
1.2     June 12, 2013
        Added basic support for API over TLS

1.1     November 5, 2009
        Delphi 2009 compatibility (thanks to Anton Ekermans for testing)
        Requires Synapse Release 39

1.0     May 1, 2009
        First public release

0.1     April 18, 2009
        Unit was rewritten to implement database-like interface

0.0     May 10, 2008
        The beginning

*******************************************************************************}

unit RouterOSAPI;

interface

uses
  SysUtils, Classes, StrUtils, blcksock, synautil, synsock, synacode;

type
  TRosApiWord = record
    Name,
    Value: AnsiString;
  end;

  TRosApiSentence = array of TROSAPIWord;

  TRosApiClient = class;

  TRosApiResult = class
  private
    Client: TROSAPIClient;
    Tag: AnsiString;
    Sentences: array of TRosApiSentence;
    FTrap: Boolean;
    FTrapMessage: AnsiString;
    FDone: Boolean;

    constructor Create;

    function GetValueByName(const Name: AnsiString): AnsiString;
    function GetValues: TRosApiSentence;
    function GetEof: Boolean;
    function GetRowsCount: Integer;
  public
    property ValueByName[const Name: AnsiString]: AnsiString read GetValueByName; default;
    property Values: TRosApiSentence read GetValues;
    function GetOne(const Wait: Boolean): Boolean;
    function GetAll: Boolean;

    property RowsCount: Integer read GetRowsCount;

    property Eof: Boolean read GetEof;
    property Trap: Boolean read FTrap;          
    property Done: Boolean read FDone;
    procedure Next;

    procedure Cancel;
  end;

  TRosApiClient = class
  private
    FNextTag: Cardinal;
    FSock: TTCPBlockSocket;
    FTimeout: Integer;

    FLastError: AnsiString;

    Sentences: array of TRosApiSentence;

    function SockRecvByte(out b: Byte; const Wait: Boolean = True): Boolean;
    function SockRecvBufferStr(Length: Cardinal): AnsiString;

    procedure SendWord(s: AnsiString);

    function RecvWord(const Wait: Boolean; out w: AnsiString): Boolean;
    function RecvSentence(const Wait: Boolean; out se: TROSAPISentence): Boolean;
    function GetSentenceWithTag(const Tag: AnsiString; const Wait: Boolean; out Sentence: TROSAPISentence): Boolean;
    procedure ClearSentenceTag(var Sentence: TRosApiSentence);
    function DoLogin(const Username, Password: AnsiString): Boolean;
  public
    function Connect(const Hostname, Username, Password: AnsiString; const Port: AnsiString = '8728'): Boolean;
    function SSLConnect(const Hostname, Username, Password: AnsiString; const Port: AnsiString = '8729'): Boolean;
    function Query(const Request: array of AnsiString;
      const GetAllAfterQuery: Boolean): TROSAPIResult;
    function Execute(const Request: array of AnsiString): Boolean;

    property Timeout: Integer read FTimeout write FTimeout;
    property LastError: AnsiString read FLastError;

    constructor Create;
    destructor Destroy; override;
    
    procedure Disconnect;

    function GetWordValueByName(Sentence: TROSAPISentence; Name: AnsiString;
      RaiseErrorIfNotFound: Boolean = False): AnsiString;
  end;

implementation

{******************************************************************************}

function HexToStr(hex: AnsiString): AnsiString;
const
  Convert: array['0'..'f'] of SmallInt =
    ( 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,-1,-1,-1,-1,-1,-1,
     -1,10,11,12,13,14,15,-1,-1,-1,-1,-1,-1,-1,-1,-1,
     -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
     -1,10,11,12,13,14,15);
var
  i: Integer;
begin
  Result := '';

  if Length(hex) mod 2 <> 0 then
    raise Exception.Create('Invalid hex value') at @HexToStr;

  SetLength(Result, Length(hex) div 2);

  for i := 1 to Length(hex) div 2 do
  begin
    if not (hex[i * 2 - 1] in ['0'..'9', 'a'..'f']) or not (hex[i * 2] in ['0'..'9', 'a'..'f']) then
      raise Exception.Create('Invalid hex value') at @HexToStr;
    Result[i] := AnsiChar((Convert[hex[i * 2 - 1]] shl 4) + Convert[hex[i * 2]]);
  end;
end;

{******************************************************************************}

constructor TRosApiResult.Create;
begin
  inherited Create;
  FTrap := False;
  FTrapMessage := '';
  FDone := False;
  SetLength(Sentences, 0);
end;

{******************************************************************************}

constructor TRosApiClient.Create;
begin
  inherited Create;
  FNextTag := 1;
  FTimeout := 30000;
  FLastError := '';
  FSock := TTCPBlockSocket.Create;
end;
          
{******************************************************************************}

destructor TRosApiClient.Destroy;
begin
  FSock.Free;
  inherited Destroy;
end;
         
{******************************************************************************}

function TRosApiClient.Connect(const Hostname, Username, Password: AnsiString; const Port: AnsiString = '8728'): Boolean;
begin
  FLastError := '';
  FSock.CloseSocket;
  FSock.LineBuffer := '';
  FSock.Connect(Hostname, Port);
  Result := FSock.LastError = 0;
  FLastError := FSock.LastErrorDesc;
  if not Result then Exit;

  Result := DoLogin(Username, Password);
end;
                       
{******************************************************************************}

function TRosApiClient.SSLConnect(const Hostname, Username, Password: AnsiString; const Port: AnsiString = '8729'): Boolean;
begin
  if FSock.SSL.LibName = 'ssl_none' then
  begin
    FLastError := 'No SSL/TLS support compiled';
    Result := False;
    Exit;
  end;

  FLastError := '';
  FSock.CloseSocket;
  FSock.LineBuffer := '';
  FSock.Connect(Hostname, Port);
  Result := FSock.LastError = 0;
  FLastError := FSock.LastErrorDesc;
  if not Result then Exit;

  FSock.SSL.Ciphers := 'ADH';
  FSock.SSL.SSLType := LT_TLSv1;
  FSock.SSLDoConnect;
  Result := FSock.LastError = 0;
  FLastError := FSock.LastErrorDesc;
  if not Result then Exit;

  Result := DoLogin(Username, Password);
end;

{******************************************************************************}

function TRosApiClient.DoLogin(const Username, Password: AnsiString): Boolean;
var
  Res, Res2: TRosApiResult;
begin
  Result := False;

  Res := Query(['/login'], True);
  if Res.Values[0].Name = '!done' then
  begin
    Res2 := Query(['/login', '=name=' + Username, '=response=00' +
      StrToHex(MD5(#0 + Password + HexToStr(Res['=ret'])))], True);
    if Res2.Trap then
      FSock.CloseSocket
    else
      Result := True;
    Res2.Free;
  end
  else
    raise Exception.Create('Invalid response: ''' + Res.Values[0].Name + ''', expected ''!done''');
  Res.Free;
end;

{******************************************************************************}

procedure TRosApiClient.Disconnect;
begin
  FSock.CloseSocket;      
  FSock.LineBuffer := '';
end;
      
{******************************************************************************}

function TRosApiClient.SockRecvByte(out b: Byte; const Wait: Boolean = True): Boolean;
begin
  Result := True;

  if Wait then
    b := FSock.RecvByte(FTimeout)
  else
    b := FSock.RecvByte(0);

  if (FSock.LastError = WSAETIMEDOUT) and (not Wait) then
    Result := False;
  if (FSock.LastError = WSAETIMEDOUT) and Wait then
    raise Exception.Create('Socket recv timeout in SockRecvByte');
end;
     
{******************************************************************************}

function TRosApiClient.SockRecvBufferStr(Length: Cardinal): AnsiString;
begin
  Result := FSock.RecvBufferStr(Length, FTimeout);

  if FSock.LastError = WSAETIMEDOUT then
  begin
    Result := '';
    raise Exception.Create('Socket recv timeout in SockRecvBufferStr');
  end;
end;
       
{******************************************************************************}

procedure TRosApiClient.SendWord(s: AnsiString);
var
  l: Cardinal;
begin
  l := Length(s);
  if l < $80 then
    FSock.SendByte(l) else
  if l < $4000 then begin
    l := l or $8000;
    FSock.SendByte((l shr 8) and $ff);
    FSock.SendByte(l and $ff); end else
  if l < $200000 then begin
    l := l or $c00000;
    FSock.SendByte((l shr 16) and $ff);
    FSock.SendByte((l shr 8) and $ff);
    FSock.SendByte(l and $ff); end else
  if l < $10000000 then begin          
    l := l or $e0000000;
    FSock.SendByte((l shr 24) and $ff);
    FSock.SendByte((l shr 16) and $ff);
    FSock.SendByte((l shr 8) and $ff);
    FSock.SendByte(l and $ff); end
  else begin
    FSock.SendByte($f0);
    FSock.SendByte((l shr 24) and $ff);
    FSock.SendByte((l shr 16) and $ff);
    FSock.SendByte((l shr 8) and $ff);
    FSock.SendByte(l and $ff);
  end;

  FSock.SendString(s);
end;

{******************************************************************************}

function TRosApiClient.Query(const Request: array of AnsiString;
  const GetAllAfterQuery: Boolean): TROSAPIResult;
var
  i: Integer;
begin
  FLastError := '';

  //Result := nil;
  // if not FSock.Connected then Exit;

  Result := TRosApiResult.Create;
  Result.Client := Self;
  Result.Tag := IntToHex(FNextTag, 4);
  Inc(FNextTag);

  for i := 0 to High(Request) do
    SendWord(Request[i]);
  SendWord('.tag=' + Result.Tag);
  SendWord('');

  if GetAllAfterQuery then
    if not Result.GetAll then
      raise Exception.Create('Cannot GetAll: ' + LastError);
end;

{******************************************************************************}

function TRosApiClient.RecvWord(const Wait: Boolean; out w: AnsiString): Boolean;
var
  l: Cardinal;
  b: Byte;
begin
  Result := False;
  if not SockRecvByte(b, Wait) then Exit;
  Result := True;

  l := b;

  if l >= $f8 then
    raise Exception.Create('Reserved control byte received, cannot proceed') else
  if (l and $80) = 0 then
    else
  if (l and $c0) = $80 then begin
    l := (l and not $c0) shl 8;
    SockRecvByte(b);
    l := l + b; end else
  if (l and $e0) = $c0 then begin
    l := (l and not $e0) shl 8;
    SockRecvByte(b);
    l := (l + b) shl 8;
    SockRecvByte(b);
    l := l + b; end else
  if (l and $f0) = $e0 then begin
    l := (l and not $f0) shl 8;
    SockRecvByte(b);
    l := (l + b) shl 8;
    SockRecvByte(b);
    l := (l + b) shl 8;
    SockRecvByte(b);
    l := l + b; end else
  if (l and $f8) = $f0 then begin
    SockRecvByte(b);
    l := b shl 8;
    SockRecvByte(b);
    l := (l + b) shl 8;
    SockRecvByte(b);
    l := (l + b) shl 8;
    SockRecvByte(b);
    l := l + b;
  end;

  w := SockRecvBufferStr(l);
end;
      
{******************************************************************************}

function TRosApiClient.RecvSentence(const Wait: Boolean; out se: TROSAPISentence): Boolean;
var
  p: Integer;
  w: AnsiString;
begin
  repeat
    if RecvWord(Wait, w) then
    begin                        
      SetLength(se, 1);
      se[0].Name := w;
    end
    else
    begin
      Result := False;
      Exit;
    end;
  until w <> '';

  repeat
    if RecvWord(True, w) then
    begin
      if w = '' then
      begin
        Result := True;
        Exit;
      end
      else
      begin
        SetLength(se, High(se) + 2);
        p := PosEx('=', w, 2);
        if p = 0 then
          se[High(se)].Name := w
        else
        begin
          se[High(se)].Name := Copy(w, 1, p - 1);
          se[High(se)].Value := Copy(w, p + 1, Length(w) - p);
        end;
      end;
    end
    else
    begin
      Result := False;
      Exit;
    end;
  until False;
end;
      
{******************************************************************************}

function TRosApiClient.GetSentenceWithTag(const Tag: AnsiString; const Wait: Boolean; out Sentence: TROSAPISentence): Boolean;
var
  i, j: Integer;
  se: TRosApiSentence;
begin
  Result := False;
  
  for i := 0 to High(Sentences) do
  begin
    if GetWordValueByName(Sentences[i], '.tag') = Tag then
    begin
      Sentence := Sentences[i];
      ClearSentenceTag(Sentence);
      for j := i to High(Sentences) - 1 do
        Sentences[j] := Sentences[j + 1];
      SetLength(Sentences, High(Sentences));
      Result := True;
      Exit;
    end;
  end;

  repeat
    if RecvSentence(Wait, se) then
    begin
      if GetWordValueByName(se, '.tag', True) = Tag then
      begin
        Sentence := se;
        ClearSentenceTag(Sentence);
        Result := True;
        Exit;
      end;

      SetLength(Sentences, High(Sentences) + 2);
      Sentences[High(Sentences)] := se;
    end
    else
      Exit;
  until False;
end;

{******************************************************************************}

procedure TRosApiClient.ClearSentenceTag(var Sentence: TRosApiSentence);
var
  i, j: Integer;
begin
  for i := High(Sentence) downto 0 do
    if Sentence[i].Name = '.tag' then
    begin
      for j := i to High(Sentence) - 1 do
        Sentence[j] := Sentence[j + 1];
      SetLength(Sentence, High(Sentence));
    end;
end;

{******************************************************************************}

function TRosApiClient.GetWordValueByName(Sentence: TROSAPISentence; Name: AnsiString;
  RaiseErrorIfNotFound: Boolean = False): AnsiString;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to High(Sentence) do         
    if (Sentence[i].Name = '=' + Name) or (Sentence[i].Name = Name) then
    begin
      Result := Sentence[i].Value;
      Exit;
    end;

  if RaiseErrorIfNotFound then
    raise Exception.Create('API Word ''' + Name + ''' not found in sentence');
end;
        
{******************************************************************************}

function TRosApiResult.GetValueByName(const Name: AnsiString): AnsiString;
begin
  if High(Sentences) = -1 then
    raise Exception.Create('No values - use Get* first?')
  else
    Result := Client.GetWordValueByName(Sentences[0], Name);
end;

{******************************************************************************}

function TRosApiResult.GetValues: TRosApiSentence;
begin
  if High(Sentences) = -1 then
    raise Exception.Create('No values - use Get* first?')
  else
    Result := Sentences[0];
end;

{******************************************************************************}

function TRosApiResult.GetOne(const Wait: Boolean): Boolean;
begin
  Client.FLastError := '';
  FTrap := False;

  SetLength(Sentences, 1);

  Result := Client.GetSentenceWithTag(Tag, Wait, Sentences[0]);
  if not Result then Exit;

  if Sentences[0][0].Name = '!trap' then
  begin
    FTrap := True;
    Client.FLastError := Self['=message'];
  end;

  FDone := Sentences[0][0].Name = '!done';
end;

{******************************************************************************}

function TRosApiResult.GetAll: Boolean;
var
  se: TRosApiSentence;
begin
  Client.FLastError := '';
  FTrap := False;

  repeat
    Result := Client.GetSentenceWithTag(Tag, True, se);
    if Result then
    begin
      if se[0].Name = '!trap' then
      begin
        FTrap := True;
        if Client.FLastError <> '' then
          Client.FLastError := Client.FLastError + '; ';
        Client.FLastError := Client.FLastError + Client.GetWordValueByName(se, '=message');
      end else
      if se[0].Name = '!done' then
      begin
        FDone := True;
        if High(se) > 0 then
        begin
          SetLength(Sentences, High(Sentences) + 2);
          Sentences[High(Sentences)] := se;
        end;

        Exit;
      end
      else
      begin
        SetLength(Sentences, High(Sentences) + 2);
        Sentences[High(Sentences)] := se;
      end;
    end;
  until False;
end;

{******************************************************************************}

function TRosApiResult.GetEof: Boolean;
begin
  Result := High(Sentences) = -1;
end;

{******************************************************************************}

function TRosApiResult.GetRowsCount: Integer;
begin
  Result := Length(Sentences);
end;

{******************************************************************************}

procedure TRosApiResult.Next;
var
  i: Integer;
begin
  Client.FLastError := '';

  for i := 0 to High(Sentences) - 1 do
    Sentences[i] := Sentences[i + 1];
  SetLength(Sentences, High(Sentences));
end;

{******************************************************************************}

procedure TRosApiResult.Cancel;
begin
  if not Client.Execute(['/cancel', '=tag=' + Tag]) then
    raise Exception.Create('Cannot cancel: ' + Client.LastError);
end;

{******************************************************************************}

function TRosApiClient.Execute(const Request: array of AnsiString): Boolean;
var
  Res: TRosApiResult;
begin
  Res := Query(Request, True);
  Result := not Res.Trap;
  Res.Free;
end;

{******************************************************************************}

end.
