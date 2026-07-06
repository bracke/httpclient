with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP2.Frames;
with Http_Client.Request_Bodies;
with Http_Client.Types;

private package Http_Client.HTTP2_Execution_Common is
   --  Internal helpers shared by the conservative HTTP/2 execution paths.

   type Peer_Settings is record
      Header_Table_Size    : Natural := 4_096;
      Initial_Window_Size  : Natural := 65_535;
      Max_Frame_Size       : Natural := 16_384;
      Max_Header_List_Size : Natural := 65_536;
   end record;

   function Has_Flag (Flags : Natural; Mask : Natural) return Boolean;

   function U8 (C : Character) return Natural;

   function U32_Value
     (B0 : Character;
      B1 : Character;
      B2 : Character;
      B3 : Character) return Natural;

   function Parse_Natural (Text : String; Value : out Natural) return Boolean;

   function Response_Body_Is_Disallowed
     (Request_Method : Http_Client.Types.Method_Name;
      Code           : Http_Client.Types.Status_Code) return Boolean;

   function Serialize_Frame
     (Kind    : Http_Client.HTTP2.Frames.Frame_Type;
      Flags   : Natural;
      Stream  : Natural;
      Payload : String) return String;

   function Serialize_Window_Update
     (Stream    : Natural;
      Increment : Natural) return String;

   function Serialize_Data_Frames
     (Payload            : String;
      Max_Frame_Size     : Natural;
      End_Stream_On_Last : Boolean := True) return String;

   function Parse_Peer_Settings
     (Payload : String;
      Peer    : in out Peer_Settings) return Http_Client.Errors.Result_Status;

   function Encoded_Header_List_Size
     (Headers : Http_Client.Headers.Header_List;
      Size    : out Natural) return Boolean;

   function Ensure_Content_Length_Header
     (Headers     : in out Http_Client.Headers.Header_List;
      Body_Length : Natural) return Http_Client.Errors.Result_Status;

   function Request_Content_Length_Is_Valid
     (Headers     : Http_Client.Headers.Header_List;
      Body_Length : Natural) return Http_Client.Errors.Result_Status;

   function Collect_Request_Body
     (Req_Body  : Http_Client.Request_Bodies.Request_Body;
      Max_Bytes : Natural;
      Output    : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status;
end Http_Client.HTTP2_Execution_Common;
