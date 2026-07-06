with Http_Client.Errors;
with Http_Client.Responses;
with Http_Client.Requests;
with Http_Client.Types;
with Http_Client.Headers;

package body Http_Client.Retry is
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.Types.Method_Name;
   use type Http_Client.Types.Status_Code;

   function Cap
     (Value : Delay_Milliseconds;
      Limit : Delay_Milliseconds) return Delay_Milliseconds
   is
   begin
      if Limit = 0 then
         return 0;
      elsif Value > Limit then
         return Limit;
      else
         return Value;
      end if;
   end Cap;

   function Is_Retryable_Method
     (Method  : Http_Client.Types.Method_Name;
      Options : Retry_Options := Default_Retry_Options) return Boolean
   is
   begin
      case Method is
         when Http_Client.Types.GET |
              Http_Client.Types.HEAD |
              Http_Client.Types.OPTIONS |
              Http_Client.Types.PUT |
              Http_Client.Types.DELETE =>
            return True;
         when Http_Client.Types.POST |
              Http_Client.Types.PATCH =>
            return Options.Allow_Non_Idempotent_Retry;
      end case;
   end Is_Retryable_Method;

   function Is_Request_Body_Replayable
     (Request : Http_Client.Requests.Request) return Boolean
   is
   begin
      return Http_Client.Requests.Is_Body_Replayable (Request);
   end Is_Request_Body_Replayable;

   function Is_Retryable_Status_Code
     (Status  : Http_Client.Types.Status_Code;
      Options : Retry_Options := Default_Retry_Options) return Boolean
   is
   begin
      if Options.Retry_408 and then Status = 408 then
         return True;
      elsif Options.Retry_429 and then Status = 429 then
         return True;
      elsif Options.Retry_425 and then Status = 425 then
         return True;
      elsif Options.Retry_5xx_Responses
        and then (Status = 500 or else Status = 502 or else Status = 503 or else Status = 504)
      then
         return True;
      else
         return False;
      end if;
   end Is_Retryable_Status_Code;

   function Is_Retryable_Response
     (Response : Http_Client.Responses.Response;
      Options  : Retry_Options := Default_Retry_Options) return Boolean
   is
   begin
      return Is_Retryable_Status_Code (Http_Client.Responses.Status_Code (Response), Options);
   end Is_Retryable_Response;

   function Is_Retryable_Failure
     (Status  : Http_Client.Errors.Result_Status;
      Options : Retry_Options := Default_Retry_Options) return Boolean
   is
   begin
      case Status is
         when Http_Client.Errors.Connection_Failed |
              Http_Client.Errors.DNS_Failed |
              Http_Client.Errors.Proxy_Connection_Failed |
              Http_Client.Errors.SOCKS_General_Server_Failure |
              Http_Client.Errors.SOCKS_Reply_Network_Unreachable |
              Http_Client.Errors.SOCKS_Reply_Host_Unreachable |
              Http_Client.Errors.SOCKS_Reply_Connection_Refused |
              Http_Client.Errors.SOCKS_TTL_Expired =>
            return Options.Retry_Connect_Failures;

         when Http_Client.Errors.Read_Failed |
              Http_Client.Errors.End_Of_Stream |
              Http_Client.Errors.Incomplete_Message |
              Http_Client.Errors.HTTP2_Stream_Refused =>
            return Options.Retry_Read_Failures;

         when Http_Client.Errors.Write_Failed =>
            return Options.Retry_Write_Failures;

         when Http_Client.Errors.Timeout =>
            return Options.Retry_Timeouts;

         when Http_Client.Errors.TLS_Failed |
              Http_Client.Errors.TLS_Handshake_Failed =>
            return Options.Retry_Transient_TLS_Failure;

         when others =>
            return False;
      end case;
   end Is_Retryable_Failure;

   function Delay_For_Attempt
     (Attempt : Positive;
      Options : Retry_Options := Default_Retry_Options) return Delay_Milliseconds
   is
      Pause : Delay_Milliseconds := Options.Base_Delay;
   begin
      if Options.Maximum_Delay = 0 or else Options.Base_Delay = 0 then
         return 0;
      end if;

      if Options.Backoff = Exponential_Delay then
         for I in 2 .. Attempt loop
            if Pause > Delay_Milliseconds'Last / 2 then
               Pause := Delay_Milliseconds'Last;
            else
               Pause := Pause * 2;
            end if;
         end loop;
      end if;

      return Cap (Pause, Options.Maximum_Delay);
   end Delay_For_Attempt;

   function Retry_After_Delay
     (Value   : String;
      Options : Retry_Options := Default_Retry_Options;
      Pause   : out Delay_Milliseconds) return Boolean
   is
      Seconds : Natural := 0;
   begin
      Pause := 0;

      if not Options.Respect_Retry_After or else Value'Length = 0 then
         return False;
      end if;

      for C of Value loop
         if C < '0' or else C > '9' then
            return False;
         end if;

         declare
            Digit : constant Natural := Character'Pos (C) - Character'Pos ('0');
         begin
            if Seconds > Natural'Last / 10
              or else (Seconds = Natural'Last / 10
                       and then Digit > Natural'Last mod 10)
            then
               Seconds := Natural'Last;
            else
               Seconds := Seconds * 10 + Digit;
            end if;
         end;
      end loop;

      if Seconds > Delay_Milliseconds'Last / 1000 then
         Pause := Delay_Milliseconds'Last;
      else
         Pause := Seconds * 1000;
      end if;

      if Options.Maximum_Retry_After > 0 and then Pause > Options.Maximum_Retry_After then
         Pause := Options.Maximum_Retry_After;
      end if;

      if Options.Maximum_Delay > 0 and then Pause > Options.Maximum_Delay then
         Pause := Options.Maximum_Delay;
      end if;

      return True;
   exception
      when others =>
         Pause := 0;
         return False;
   end Retry_After_Delay;

end Http_Client.Retry;
