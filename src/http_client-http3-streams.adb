package body Http_Client.HTTP3.Streams
  with SPARK_Mode => On
is
   function Validate_Frame_On_Stream
     (Kind       : Stream_Kind;
      Frame      : Http_Client.HTTP3.Frames.Frame_Type;
      Push_Enabled : Boolean := False) return Http_Client.Errors.Result_Status is
      use Http_Client.HTTP3.Frames;
   begin
      if (Frame = PUSH_PROMISE or else Frame = CANCEL_PUSH or else Frame = MAX_PUSH_ID)
        and then not Push_Enabled
      then
         return Http_Client.Errors.HTTP3_Unsupported;
      end if;

      case Kind is
         when Request_Bidirectional =>
            case Frame is
               when DATA | HEADERS | UNKNOWN => return Http_Client.Errors.Ok;
               when PUSH_PROMISE =>
                  if Push_Enabled then return Http_Client.Errors.Ok;
                  else return Http_Client.Errors.HTTP3_Unsupported; end if;
               when others => return Http_Client.Errors.HTTP3_Stream_Error;
            end case;
         when Control_Unidirectional =>
            case Frame is
               when SETTINGS | GOAWAY | MAX_PUSH_ID | CANCEL_PUSH | UNKNOWN =>
                  if (Frame = MAX_PUSH_ID or else Frame = CANCEL_PUSH) and then not Push_Enabled then
                     return Http_Client.Errors.HTTP3_Unsupported;
                  else
                     return Http_Client.Errors.Ok;
                  end if;
               when others => return Http_Client.Errors.HTTP3_Stream_Error;
            end case;
         when QPACK_Encoder_Unidirectional | QPACK_Decoder_Unidirectional =>
            return Http_Client.Errors.HTTP3_Stream_Error;
         when Push_Unidirectional =>
            if Push_Enabled then
               return Http_Client.Errors.Ok;
            else
               return Http_Client.Errors.HTTP3_Unsupported;
            end if;
         when Unknown_Unidirectional =>
            if Frame = UNKNOWN then
               return Http_Client.Errors.Ok;
            else
               return Http_Client.Errors.HTTP3_Stream_Error;
            end if;
      end case;
   end Validate_Frame_On_Stream;
end Http_Client.HTTP3.Streams;
