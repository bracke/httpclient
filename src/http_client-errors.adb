package body Http_Client.Errors
  with SPARK_Mode => On
is

   function Category (Value : Result_Status) return Result_Category is
   begin
      case Value is
         when Ok =>
            return Success_Category;

         when Invalid_URI
            | Invalid_Header
            | Invalid_Request
            | Invalid_Cookie
            | Invalid_Proxy
            | Invalid_SOCKS_Proxy
            | Invalid_Credentials
            | Invalid_Configuration
            | Invalid_Multipart_Boundary
            | Invalid_Form_Field
            | Invalid_File_Name
            | Invalid_Cache_Metadata =>
            return Validation_Category;

         when Response_Too_Large
            | Integrity_Check_Failed
            | Header_Too_Large
            | Unsupported_Content_Encoding
            | Decompression_Failed
            | Decoded_Body_Too_Large =>
            return Request_Category;

         when Connection_Failed
            | DNS_Failed
            | Not_Connected
            | Write_Failed
            | Read_Failed
            | End_Of_Stream
            | Incomplete_Message
            | Timeout
            | Cancelled =>
            return Transport_Category;

         when TLS_Failed
            | Certificate_Verification_Failed
            | Hostname_Verification_Failed
            | TLS_Handshake_Failed
            | CA_Store_Failed
            | TLS_Client_Certificate_Load_Failed
            | TLS_Client_Key_Load_Failed
            | TLS_Client_Key_Mismatch
            | TLS_Client_Key_Passphrase_Required
            | TLS_Client_Key_Passphrase_Invalid
            | TLS_Client_Certificate_Unsupported
            | TLS_Client_Certificate_Rejected
            | TLS_Client_Certificate_Scope_Mismatch
            | TLS_Client_Certificate_Configuration_Invalid
            | ALPN_Negotiation_Failed =>
            return TLS_Category;

         when Proxy_Unsupported
            | Proxy_Connection_Failed
            | Proxy_Tunnel_Failed
            | Proxy_Authentication_Required
            | SOCKS_Unsupported_Version
            | SOCKS_Unsupported_Authentication_Method
            | SOCKS_Authentication_Failed
            | SOCKS_Connect_Failed
            | SOCKS_General_Server_Failure
            | SOCKS_Connection_Not_Allowed
            | SOCKS_TTL_Expired
            | SOCKS_Command_Unsupported
            | SOCKS_Malformed_Reply
            | SOCKS_Address_Type_Unsupported
            | SOCKS_Reply_Connection_Refused
            | SOCKS_Reply_Network_Unreachable
            | SOCKS_Reply_Host_Unreachable =>
            return Proxy_Category;

         when Unsupported_Authentication_Scheme
            | Authentication_Required
            | Authentication_Failed
            | Authentication_Replay_Disallowed
            | Authentication_Challenge_Malformed
            | Authentication_Scope_Mismatch
            | Digest_Algorithm_Unsupported
            | Digest_QOP_Unsupported
            | Digest_Nonce_Stale
            | Authentication_Loop_Detected =>
            return Authentication_Category;

         when Client_Not_Initialized =>
            return Configuration_Category;

         when Too_Many_Redirects
            | Invalid_Redirect
            | Retry_Disallowed
            | Retry_Body_Not_Replayable
            | Redirect_Downgrade_Blocked
            | Redirect_Body_Replay_Disallowed =>
            return Retry_Redirect_Category;

         when Body_Not_Replayable
            | Body_Length_Mismatch
            | Body_Producer_Failed
            | Upload_Too_Large
            | Chunked_Upload_Unsupported
            | Multipart_Too_Large
            | Too_Many_Parts
            | Part_Length_Unknown
            | Part_Producer_Failed =>
            return Body_Category;

         when Cache_Miss
            | Cache_Entry_Stale
            | Cache_Revalidation_Failed
            | Cache_Entry_Too_Large
            | Cache_Disabled
            | Cache_Open_Failed
            | Cache_Read_Failed
            | Cache_Write_Failed
            | Cache_Corrupt_Entry
            | Cache_Format_Unsupported
            | Cache_Limit_Exceeded
            | Cache_Storage_Unavailable
            | Cache_Encryption_Failed
            | Cache_Decryption_Failed
            | Cache_Authentication_Failed
            | Cache_Key_Invalid
            | Cache_KDF_Failed
            | Cache_Random_Failed
            | Cache_Encrypted_Format_Unsupported
            | Cache_Wrong_Key
            | Cookie_Rejected
            | Cookie_Too_Large =>
            return Cache_Category;

         when HTTP2_Protocol_Error
            | HTTP2_Frame_Error
            | HTTP2_Compression_Error
            | HTTP2_Flow_Control_Error
            | HTTP2_Settings_Error
            | HTTP2_Header_Error
            | HTTP2_Stream_Reset
            | HTTP2_Stream_Refused
            | HTTP2_Stream_Limit_Reached
            | HTTP2_Stream_State_Error
            | HTTP2_Connection_Goaway
            | HTTP2_Header_Block_Interleaving_Error
            | HTTP2_Multiplexing_Unsupported
            | HTTP2_Unsupported_Feature
            | HPACK_Decode_Failed
            | HPACK_Huffman_Error =>
            return HTTP2_Category;

         when HTTP3_Unsupported
            | HTTP3_Frame_Error
            | HTTP3_Settings_Error
            | HTTP3_QPACK_Error
            | HTTP3_Stream_Error
            | HTTP3_Goaway
            | HTTP3_Protocol_Error
            | QUIC_Unsupported
            | QUIC_Connection_Failed
            | QUIC_Handshake_Failed
            | QUIC_Transport_Error
            | HTTP3_Proxy_Unsupported
            | HTTP3_Fallback_Disallowed =>
            return HTTP3_Category;

         when Pool_Closed
            | Pool_Exhausted
            | Connection_Not_Reusable
            | Stale_Connection =>
            return Pool_Category;

         when Protocol_Error
            | Unsupported_Feature =>
            return Protocol_Category;

         when Async_Queue_Full
            | Async_Cancelled
            | Async_Shutdown
            | Async_Not_Ready
            | Async_Result_Already_Taken
            | Async_Handle_Invalid
            | Async_Worker_Failed
            | Async_Unsupported_Mode =>
            return Async_Category;

         when Internal_Error =>
            return Internal_Category;
      end case;
   end Category;

   function Is_Success (Value : Result_Status) return Boolean is
   begin
      return Value = Ok;
   end Is_Success;

end Http_Client.Errors;
