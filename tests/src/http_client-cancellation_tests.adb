with AUnit.Assertions;

with Http_Client.Cancellation;
with Http_Client.Clients;
with Http_Client.Errors; use Http_Client.Errors;
with Http_Client.Requests;
with Http_Client.Responses; use Http_Client.Responses;
with Http_Client.Response_Streams;
with Http_Client.Retry;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Cancellation_Tests is
   use AUnit.Assertions;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Cancellation.Cancellation_Token_Access;

   procedure Build_Request (Request : out Http_Client.Requests.Request) is
      URI    : Http_Client.URI.URI_Reference;
      Status : Http_Client.Errors.Result_Status;
   begin
      Status := Http_Client.URI.Parse ("http://127.0.0.1:1/cancel", URI);
      Assert (Status = Http_Client.Errors.Ok, "cancellation test URI should parse");

      Status := Http_Client.Requests.Create
        (Method => Http_Client.Types.GET,
         URI    => URI,
         Item   => Request);
      Assert (Status = Http_Client.Errors.Ok, "cancellation test request should build");
   end Build_Request;

   procedure Test_Token_State

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Token : Http_Client.Cancellation.Cancellation_Token;
   begin
      Assert
        (not Http_Client.Cancellation.Is_Cancelled (Token),
         "new cancellation token should not start cancelled");

      Http_Client.Cancellation.Cancel (Token);
      Assert
        (Http_Client.Cancellation.Is_Cancelled (Token),
         "Cancel should set cancellation state");

      Http_Client.Cancellation.Reset (Token);
      Assert
        (not Http_Client.Cancellation.Is_Cancelled (Token),
         "Reset should clear cancellation state for later reuse");
   end Test_Token_State;

   procedure Test_Cancelled_Status_Category

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
   begin
      Assert
        (Http_Client.Errors.Category (Http_Client.Errors.Cancelled) =
         Http_Client.Errors.Transport_Category,
         "Cancelled should be a transport-category ordinary outcome");
   end Test_Cancelled_Status_Category;

   procedure Test_Cancellation_Is_Not_Retryable

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Options : Http_Client.Retry.Retry_Options :=
        Http_Client.Retry.Default_Retry_Options;
   begin
      Options.Enable_Retries := True;
      Options.Maximum_Attempts := 3;

      Assert
        (not Http_Client.Retry.Is_Retryable_Failure
           (Status  => Http_Client.Errors.Cancelled,
            Options => Options),
         "Cancelled must not be classified as retryable even when retries are enabled");
   end Test_Cancellation_Is_Not_Retryable;

   procedure Test_Default_Cancellation_Fields_Are_Null

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Execution : constant Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
      Streaming : constant Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
   begin
      Assert
        (Execution.Cancellation = null,
         "default buffered execution cancellation token should be null");
      Assert
        (Streaming.Cancellation = null,
         "default streaming cancellation token should be null");
   end Test_Default_Cancellation_Fields_Are_Null;

   procedure Test_Buffered_Pre_Cancelled_Execute

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Client   : constant Http_Client.Clients.Client := Http_Client.Clients.Create;
      Token    : aliased Http_Client.Cancellation.Cancellation_Token;
      Options  : Http_Client.Clients.Execution_Options :=
        Http_Client.Clients.Default_Execution_Options;
      Request  : Http_Client.Requests.Request;
      Response : Http_Client.Responses.Response;
      Status   : Http_Client.Errors.Result_Status;
   begin
      Build_Request (Request);
      Http_Client.Cancellation.Cancel (Token);
      Options.Cancellation := Token'Unchecked_Access;

      Status := Http_Client.Clients.Execute
        (Item     => Client,
         Request  => Request,
         Response => Response,
         Options  => Options);

      Assert
        (Status = Http_Client.Errors.Cancelled,
         "pre-cancelled buffered execution should return Cancelled before network I/O");
   end Test_Buffered_Pre_Cancelled_Execute;

   procedure Test_Streaming_Pre_Cancelled_Open

     (Case_Context : in out AUnit.Test_Cases.Test_Case'Class)

   is

      pragma Unreferenced (Case_Context);
      Token   : aliased Http_Client.Cancellation.Cancellation_Token;
      Options : Http_Client.Response_Streams.Streaming_Options :=
        Http_Client.Response_Streams.Default_Streaming_Options;
      Request : Http_Client.Requests.Request;
      Stream  : Http_Client.Response_Streams.Streaming_Response;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Build_Request (Request);
      Http_Client.Cancellation.Cancel (Token);
      Options.Cancellation := Token'Unchecked_Access;

      Status := Http_Client.Response_Streams.Open
        (Request => Request,
         Stream  => Stream,
         Options => Options);

      Assert
        (Status = Http_Client.Errors.Cancelled,
         "pre-cancelled streaming open should return Cancelled before network I/O");
      Assert
        (Http_Client.Response_Streams.Last_Status (Stream) = Http_Client.Errors.Cancelled,
         "stream Last_Status should preserve Cancelled after cancelled Open");
   end Test_Streaming_Pre_Cancelled_Open;

   overriding function Name
     (T : Section_Test_Case) return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Http_Client.Cancellation_Tests");
   end Name;

   overriding procedure Register_Tests
     (T : in out Section_Test_Case)
   is
      use AUnit.Test_Cases.Registration;
   begin
      Register_Routine (T, Test_Token_State'Access, "Test_Token_State");
      Register_Routine
        (T,
         Test_Cancelled_Status_Category'Access,
         "Test_Cancelled_Status_Category");
      Register_Routine
        (T,
         Test_Cancellation_Is_Not_Retryable'Access,
         "Test_Cancellation_Is_Not_Retryable");
      Register_Routine
        (T,
         Test_Default_Cancellation_Fields_Are_Null'Access,
         "Test_Default_Cancellation_Fields_Are_Null");
      Register_Routine
        (T,
         Test_Buffered_Pre_Cancelled_Execute'Access,
         "Test_Buffered_Pre_Cancelled_Execute");
      Register_Routine
        (T,
         Test_Streaming_Pre_Cancelled_Open'Access,
         "Test_Streaming_Pre_Cancelled_Open");
   end Register_Tests;
end Http_Client.Cancellation_Tests;
