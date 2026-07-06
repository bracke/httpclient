package body Http_Client.HTTP2.Streams
  with SPARK_Mode => On
is
   function Is_Client_Initiated_Stream_ID (Stream : Natural) return Boolean is
   begin
      return Stream /= 0 and then Stream mod 2 = 1 and then Stream <= 16#7FFF_FFFF#;
   end Is_Client_Initiated_Stream_ID;

   function Apply
     (State : in out Stream_State;
      Event : Stream_Event) return Http_Client.Errors.Result_Status
      with SPARK_Mode => Off
   is
   begin
      case State is
         when Idle =>
            case Event is
               when Send_Headers =>
                  State := Open;
               when Send_Headers_End_Stream =>
                  State := Half_Closed_Local;
               when others =>
                  return Http_Client.Errors.HTTP2_Protocol_Error;
            end case;

         when Open =>
            case Event is
               when Send_Data | Receive_Data | Send_Headers | Receive_Headers =>
                  null;
               when Send_Data_End_Stream | Send_Headers_End_Stream =>
                  State := Half_Closed_Local;
               when Receive_Data_End_Stream | Receive_Headers_End_Stream =>
                  State := Half_Closed_Remote;
               when Receive_RST_Stream | Send_RST_Stream =>
                  State := Reset;
            end case;

         when Half_Closed_Local =>
            case Event is
               when Receive_Data | Receive_Headers =>
                  null;
               when Receive_Data_End_Stream | Receive_Headers_End_Stream =>
                  State := Closed;
               when Receive_RST_Stream | Send_RST_Stream =>
                  State := Reset;
               when others =>
                  return Http_Client.Errors.HTTP2_Protocol_Error;
            end case;

         when Half_Closed_Remote =>
            case Event is
               when Send_Data | Send_Headers =>
                  null;
               when Send_Data_End_Stream | Send_Headers_End_Stream =>
                  State := Closed;
               when Receive_RST_Stream | Send_RST_Stream =>
                  State := Reset;
               when others =>
                  return Http_Client.Errors.HTTP2_Protocol_Error;
            end case;

         when Closed | Reset =>
            return Http_Client.Errors.HTTP2_Protocol_Error;
      end case;

      return Http_Client.Errors.Ok;
   end Apply;
end Http_Client.HTTP2.Streams;
