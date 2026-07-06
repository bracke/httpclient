with Http_Client.Errors;

package body Http_Client.HTTP2
  with SPARK_Mode => On
is
   use type Http_Client.Errors.Result_Status;

   function Validate
     (Options : HTTP2_Options) return Http_Client.Errors.Result_Status
   is
   begin
      if Options.Max_Frame_Size < 16_384
        or else Options.Max_Frame_Size > 16#00FF_FFFF#
      then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      if Options.Max_Header_List_Size = 0 then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      if Options.Max_Body_Size = 0 then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      if Options.Enable_Server_Push then
         return Http_Client.Errors.HTTP2_Unsupported_Feature;
      end if;

      if Options.Enable_Streaming_Decompression then
         return Http_Client.Errors.HTTP2_Unsupported_Feature;
      end if;

      if (Options.Enable_Multiplexing
          or else Options.Enable_Public_Streaming
          or else Options.Enable_Upload_Streaming)
        and then Options.Mode = HTTP2_Disabled
      then
         return Http_Client.Errors.HTTP2_Multiplexing_Unsupported;
      end if;

      if (Options.Enable_Public_Streaming
          or else Options.Enable_Upload_Streaming)
        and then not Options.Enable_Multiplexing
      then
         return Http_Client.Errors.HTTP2_Multiplexing_Unsupported;
      end if;

      if Options.Local_Max_Concurrent_Streams = 0
        or else Options.Local_Max_Concurrent_Streams > 32
      then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      if Options.Max_Per_Stream_Buffered_Bytes = 0
        or else Options.Max_Total_Queued_Body_Bytes = 0
        or else Options.Max_Active_Streamed_Responses = 0
        or else Options.Max_Active_Streamed_Responses > 32
        or else Options.Max_Active_Upload_Streams = 0
        or else Options.Max_Active_Upload_Streams > 32
      then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      if Options.Flow_Control_Update_Threshold = 0
        or else Options.Flow_Control_Update_Threshold > 16#7FFF_FFFF#
        or else Options.Upload_Flow_Control_Timeout_MS = 0
      then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      if Options.Initial_Stream_Window_Size > 16#7FFF_FFFF#
        or else Options.Initial_Connection_Window_Size > 16#7FFF_FFFF#
      then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      return Http_Client.Errors.Ok;
   end Validate;

   function ALPN_Advertisement
     (Options : HTTP2_Options) return String
   is
   begin
      case Options.Mode is
         when HTTP2_Disabled =>
            return "http/1.1";
         when HTTP2_Allowed =>
            return "h2,http/1.1";
         when HTTP2_Required =>
            return "h2";
      end case;
   end ALPN_Advertisement;

   function Normalize_ALPN_Selected
     (Protocol : String) return Selected_Protocol
   is
   begin
      if Protocol'Length = 0 then
         return Protocol_None;
      elsif Protocol = "h2" then
         return Protocol_HTTP_2;
      elsif Protocol = "http/1.1" then
         return Protocol_HTTP_1_1;
      else
         return Protocol_Unsupported;
      end if;
   end Normalize_ALPN_Selected;

   function Selected_Status
     (Options  : HTTP2_Options;
      Selected : Selected_Protocol) return Http_Client.Errors.Result_Status
   is
   begin
      if Validate (Options) /= Http_Client.Errors.Ok then
         return Validate (Options);
      end if;

      case Options.Mode is
         when HTTP2_Disabled =>
            if Selected = Protocol_HTTP_2 then
               return Http_Client.Errors.ALPN_Negotiation_Failed;
            elsif Selected = Protocol_Unsupported then
               return Http_Client.Errors.ALPN_Negotiation_Failed;
            else
               return Http_Client.Errors.Ok;
            end if;

         when HTTP2_Allowed =>
            if Selected = Protocol_Unsupported then
               return Http_Client.Errors.ALPN_Negotiation_Failed;
            else
               return Http_Client.Errors.Ok;
            end if;

         when HTTP2_Required =>
            if Selected = Protocol_HTTP_2 then
               return Http_Client.Errors.Ok;
            else
               return Http_Client.Errors.ALPN_Negotiation_Failed;
            end if;
      end case;
   end Selected_Status;

   function Execution_Status_For_Selected
     (Options  : HTTP2_Options;
      Selected : Selected_Protocol) return Http_Client.Errors.Result_Status
   is
      Status : constant Http_Client.Errors.Result_Status :=
        Selected_Status (Options, Selected);
   begin
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      return Http_Client.Errors.Ok;
   end Execution_Status_For_Selected;
end Http_Client.HTTP2;
