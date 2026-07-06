with Ada.Strings.Unbounded;

with Http_Client.Errors;

package Http_Client.HTTP2.Settings
  with SPARK_Mode => On
is
   --  Release surface: stable public API for 1.0.0.
   --  Source compatibility for documented public declarations in this
   --  package is covered by docs/compatibility.md unless a declaration
   --  is explicitly marked experimental or implementation-only below.
   --  HTTP/2 SETTINGS payload helpers.
   --
   --  The package validates setting identifiers and values independently from
   --  transport I/O. Server push is disabled by the default initial
   --  settings. SETTINGS ACK frames must carry an empty payload and are
   --  validated by Http_Client.HTTP2.Frames.

   subtype Setting_Value is Natural range 0 .. 16#7FFF_FFFF#;

   type Setting_Identifier is
     (SETTINGS_HEADER_TABLE_SIZE,
      SETTINGS_ENABLE_PUSH,
      SETTINGS_MAX_CONCURRENT_STREAMS,
      SETTINGS_INITIAL_WINDOW_SIZE,
      SETTINGS_MAX_FRAME_SIZE,
      SETTINGS_MAX_HEADER_LIST_SIZE,
      SETTINGS_UNKNOWN);

   type Setting is record
      Identifier : Setting_Identifier := SETTINGS_UNKNOWN;
      Raw_ID     : Natural range 0 .. 16#FFFF# := 0;
      Value      : Setting_Value := 0;
   end record;

   type Setting_List is array (Positive range <>) of Setting;

   function Identifier_Code
     (Identifier : Setting_Identifier;
      Raw_ID     : Natural := 0) return Natural;
   --  GNATdoc contract.
   --  @param Identifier Subprogram parameter.
   --  @param Raw_ID Subprogram parameter.
   --  @return Subprogram result.

   function Identifier_From_Code (Code : Natural) return Setting_Identifier;
   --  GNATdoc contract.
   --  @param Code Subprogram parameter.
   --  @return Subprogram result.

   function Validate
     (Item : Setting) return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Item Subprogram parameter.
   --  @return Subprogram result.
   --  Validate a setting value. Unknown settings are accepted and ignored by
   --  higher layers, as required by HTTP/2.

   function Serialize
     (Items  : Setting_List;
      Output : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status
      with SPARK_Mode => Off;
   --  GNATdoc contract.
   --  @param Items Subprogram parameter.
   --  @param Output Subprogram parameter.
   --  @return Subprogram result.
   --  Serialize SETTINGS payload entries as exact 6-octet network-order pairs.

   function Parse
     (Payload : String;
      Output  : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status
      with SPARK_Mode => Off;
   --  GNATdoc contract.
   --  @param Payload Subprogram parameter.
   --  @param Output Subprogram parameter.
   --  @return Subprogram result.
   --  Parse and validate a SETTINGS payload. Output is a deterministic textual
   --  summary in the form "id=value;" for tests and diagnostics. Values
   --  are decoded as audited network-order 32-bit quantities and rejected
   --  deterministically when they cannot be represented in Setting_Value.

   function Initial_Settings_Payload
     (Header_Table_Size     : Natural := 4_096;
      Enable_Push           : Boolean := False;
      Max_Concurrent_Streams : Natural := 1;
      Initial_Window_Size   : Natural := 65_535;
      Max_Frame_Size        : Natural := 16_384;
      Max_Header_List_Size  : Natural := 65_536) return String
      with SPARK_Mode => Off;
   --  GNATdoc contract.
   --  @param Header_Table_Size Subprogram parameter.
   --  @param Enable_Push Subprogram parameter.
   --  @param Max_Concurrent_Streams Subprogram parameter.
   --  @param Initial_Window_Size Subprogram parameter.
   --  @param Max_Frame_Size Subprogram parameter.
   --  @param Max_Header_List_Size Subprogram parameter.
   --  @return Subprogram result.
   --  Return a deterministic client initial SETTINGS payload. the HTTP/2 connection layer uses a
   --  conservative default and advertises server push disabled.
end Http_Client.HTTP2.Settings;
