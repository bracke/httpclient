with Ada.Strings.Unbounded;
with Interfaces;

with Http_Client.Errors;

package Http_Client.HTTP3.Settings
  with SPARK_Mode => On
is
   --  Release surface: experimental public API for 1.0.0.
   --  This package may change before production HTTP/3 or QUIC backend
   --  support is finalized. It must not be treated as browser-like
   --  networking, proxy discovery, proxy bypass, 0-RTT, or server push.
   --  HTTP/3 SETTINGS modeling for control-stream initialization.

   subtype Setting_ID is Interfaces.Unsigned_64 range 0 .. 16#3FFF_FFFF_FFFF_FFFF#;
   subtype Setting_Value is Interfaces.Unsigned_64 range 0 .. 16#3FFF_FFFF_FFFF_FFFF#;

   SETTINGS_QPACK_MAX_TABLE_CAPACITY : constant Setting_ID := 16#01#;
   SETTINGS_MAX_FIELD_SECTION_SIZE   : constant Setting_ID := 16#06#;
   SETTINGS_QPACK_BLOCKED_STREAMS    : constant Setting_ID := 16#07#;
   SETTINGS_ENABLE_CONNECT_PROTOCOL  : constant Setting_ID := 16#08#;
   SETTINGS_H3_DATAGRAM              : constant Setting_ID := 16#33#;

   type Settings_Record is record
      QPACK_Max_Table_Capacity : Natural := 0;
      QPACK_Blocked_Streams    : Natural := 0;
      Max_Field_Section_Size   : Natural := 65_536;
      Enable_Connect_Protocol  : Boolean := False;
      H3_Datagram              : Boolean := False;
   end record;

   Default_Settings : constant Settings_Record :=
     (QPACK_Max_Table_Capacity => 0,
      QPACK_Blocked_Streams => 0,
      Max_Field_Section_Size => 65_536,
      Enable_Connect_Protocol => False,
      H3_Datagram => False);

   function Validate (Settings : Settings_Record)
      return Http_Client.Errors.Result_Status;
   --  GNATdoc contract.
   --  @param Settings Subprogram parameter.
   --  @return Subprogram result.

   function Serialize_Payload
     (Settings : Settings_Record;
      Output   : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status
      with SPARK_Mode => Off;
   --  GNATdoc contract.
   --  @param Settings Subprogram parameter.
   --  @param Output Subprogram parameter.
   --  @return Subprogram result.

   function Parse_Payload
     (Payload  : String;
      Settings : out Settings_Record)
      return Http_Client.Errors.Result_Status
      with SPARK_Mode => Off;
   --  GNATdoc contract.
   --  @param Payload Subprogram parameter.
   --  @param Settings Subprogram parameter.
   --  @return Subprogram result.

end Http_Client.HTTP3.Settings;
