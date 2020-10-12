# Delphi RouterOS API
Another RouterOS API Delphi Client. Supports API over TLS and RouterOS 6.43+ API login method.

# Links
Official API documentation: https://wiki.mikrotik.com/wiki/Manual:API

MikroTik Forum topic: https://forum.mikrotik.com/viewtopic.php?f=9&t=31555

# Documentation
This is an implementation of MikroTik RouterOS API Client for Delphi. It supports execution of parallel requests to a router and has database-like interface for ease of use.

## Classes

**RouterOSAPI** unit contains definition of two classes which you need to work with API protocol from your Delphi programs.

### TRosApiClient

This class encapsulates properties and methods to make a connection to a router via RouterOS API protocol.

* function **Connect**(*Hostname*, *Username*, *Password*: String; *Port*: String = '8728'): Boolean;

This function connects to the router and performs login procedure. It returns **True** if login was successful, **False** otherwise.

* function **Query**(*Request*: array of String; *GetAllAfterQuery*: Boolean): TROSAPIResult;

Makes a query to the router. **Request** is an array of strings, first one being the command and others are parameters. If **GetAllAfterQuery** is **True**, then **TROSAPIResult.GetAll** is executed after sending a query.

* function **Execute**(*Request*: array of String): Boolean;

If you do not need to receive any output from your query, use this method. It simply calls **Query** function and frees returned object.

* property **Timeout**: Integer;

With this property you can set timeout value for network operations (in milliseconds).

* property **LastError**: String;

This read-only property contains textual description of the last error occured.

* procedure **Disconnect**;

Disconnects from the router.

### TRosApiResult

This class gives you an ability to work with data returned from queries. Each command execution is "isolated" in its **TRosApiResult** object, so you can do parallel requests by calling **TRosApiClient.Query** and receiving several **TRosApiResult** objects.

* property **ValueByName**[*Name*: String]: String; default;

Returns the value of **Name** parameter (*word* in terms of API) in current sentence. The preferred way of getting the result is the following: **ApiResult['ParmName']** instead of **ApiResult.ValueByName('ParmName')**. You can use param name both with and without leading '=' character (*ApiResult['address']* and *ApiResult['=address']* return the same result).

* property **Values**: TRosApiSentence;

Returns current sentence of query result (type is TRosApiSentence).

* function **GetOne**(*Wait*: Boolean): Boolean;

Receives one sentence from the router. If **Wait** parameter is **True**, function will wait until sentence is received. If **Wait** is **False** and no sentences were received for now, function returns **False**. This is helpful when executing infinite commands (like 'listen') in GUI, when you need to process other user's actions: you should periodically call **GetOne** with **Wait = False**, and in case of negative result just do something else for a time.

* function **GetAll**: Boolean;

Receives all sentences upto '!done', then returns **True** (or **False** in case of a timeout).

* property **RowsCount**: Integer;

Returns number of received sentences after calling **GetAll**.

* property **Eof**: Boolean;

Returns **True** if there's more sentence(s) in query result.

* property **Trap**: Boolean;

Returns **True** if there were trap(s) during **GetAll**

* property **Done**: Boolean;

Returns **True** if '!done' sentence was received in **GetOne**

* procedure **Next**;

Shifts to the next sentence received in **GetAll**

* procedure **Cancel**;

Cancels current command execution.

## Examples

Sample **APITest** application can be downloaded in Releases section: https://github.com/Chupaka/Delphi-RouterOS-API/releases

### Creating a connection to a router

At first, we should declare a variable and create an instance of *TRosApiClient*:

```delphi
var
  RouterOS: TRosApiClient;

RouterOS := TRosApiClient.Create;
```

Now we connect to the router and perform login procedure:

```delphi
if RouterOS.Connect('192.168.0.1', 'admin', 'password') then
begin
  //we are connected successfully
end
else
begin
  //an error occured; text error message is in LastError property
end;
```

### Executing queries

All queries are done by calling **Query** function of **TRosApiClient**. It returns an instance of **TRosApiResult** from which all data is fetched.

```delphi
var
  Res: TRosApiResult;

Res := RouterOS.Query(['/system/resource/print'], True);
```

### Obtaining the result with GetAll

```delphi
Res := ROS.Query(['/ip/arp/print', '?interface=ether2'], True);

while not Res.Eof do
begin
  SomeProcessingFunction(Res['.id'], Res['address']);
  Res.Next;
end;

Res.Free;
```

### Obtaining the result with GetOne

First, place a Timer on form and name it **tmrListen**, set **Enabled** to *False*. Then we make a query and enable timer:

```delphi
ResListen := ROS.Query(['/log/listen'], False);
tmrListen.Enabled := True;
```

Then we check for a new data on timer event:

```delphi
procedure TForm1.tmrListenTimer(Sender: TObject);
begin
  repeat
    if not ResListen.GetOne(False) then Break;
    
    if ResListen.Trap then
    begin
      ShowMessage('Trap: ' + ROS.LastError);
      Break;
    end;
    
    if ResListen.Done then
    begin
      ShowMessage('Done');
      ResListen.Free;
      tmrListen.Enabled := False;
      Break;
    end;

    Memo1.Lines.Add(ResListen['time'] + ': ' + ResListen['message']);
  until False;
end;
```

## Downloads and suggestions

For discussions and suggestions you may check MikroTik Forum thread [RouterOS API Delphi Client](https://forum.mikrotik.com/viewtopic.php?f=9&t=31555&start=0)
