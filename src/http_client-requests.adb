with Ada.Strings.Unbounded;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.Request_Bodies;
with Http_Client.Types;
with Http_Client.URI;

package body Http_Client.Requests is
   use Ada.Strings.Unbounded;
   use Http_Client.Errors;
   use Http_Client.Types;

   function Method_Image
     (Method : Http_Client.Types.Method_Name) return String
   is
   begin
      case Method is
         when GET =>
            return "GET";
         when HEAD =>
            return "HEAD";
         when POST =>
            return "POST";
         when PUT =>
            return "PUT";
         when PATCH =>
            return "PATCH";
         when DELETE =>
            return "DELETE";
         when OPTIONS =>
            return "OPTIONS";
      end case;
   end Method_Image;

   function Create
     (Method    : Http_Client.Types.Method_Name;
      URI       : Http_Client.URI.URI_Reference;
      Item      : out Request;
      Headers   : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Payload   : String := "";
      Auto_Host : Boolean := True) return Http_Client.Errors.Result_Status
   is
      Result : Request := Default_Request;
      Status : Result_Status;
   begin
      if not Http_Client.URI.Is_Parsed (URI) then
         Item := Default_Request;
         return Invalid_URI;
      end if;

      Result.Valid := True;
      Result.Method_Name := Method;
      Result.Request_URI := URI;
      Result.Header_List := Headers;
      Result.Payload_Text := To_Unbounded_String (Payload);
      Result.Body_Value := Http_Client.Request_Bodies.From_String (Payload);
      Result.Legacy_Target := Null_Unbounded_String;

      if Auto_Host
        and then not Http_Client.Headers.Contains (Result.Header_List, "Host")
      then
         Status :=
           Http_Client.Headers.Set
             (Result.Header_List,
              "Host",
              Http_Client.URI.Host_Header_Value (URI));

         if Status /= Ok then
            Item := Default_Request;
            return Status;
         end if;
      end if;

      Item := Result;
      return Ok;
   end Create;

   function Default_Request return Request is
   begin
      return
        (Valid         => False,
         Method_Name   => GET,
         Request_URI   => Http_Client.URI.Create_Unchecked (""),
         Header_List   => Http_Client.Headers.Empty,
         Payload_Text  => Null_Unbounded_String,
         Body_Value    => Http_Client.Request_Bodies.Empty,
         Legacy_Target => Null_Unbounded_String);
   end Default_Request;

   function Is_Valid (Item : Request) return Boolean is
   begin
      return Item.Valid;
   end Is_Valid;

   function Method (Item : Request) return Http_Client.Types.Method_Name is
   begin
      return Item.Method_Name;
   end Method;

   function URI (Item : Request) return Http_Client.URI.URI_Reference is
   begin
      return Item.Request_URI;
   end URI;

   function Headers (Item : Request) return Http_Client.Headers.Header_List is
   begin
      return Item.Header_List;
   end Headers;

   function Payload (Item : Request) return String is
   begin
      return Http_Client.Request_Bodies.Buffered_Payload (Item.Body_Value);
   end Payload;

   function Request_Body (Item : Request) return Http_Client.Request_Bodies.Request_Body is
   begin
      return Item.Body_Value;
   end Request_Body;

   function Has_Payload (Item : Request) return Boolean is
   begin
      return Http_Client.Request_Bodies.Has_Body (Item.Body_Value);
   end Has_Payload;

   function Request_Target (Item : Request) return String is
   begin
      if Item.Valid then
         return Http_Client.URI.Request_Target (Item.Request_URI);
      else
         return To_String (Item.Legacy_Target);
      end if;
   end Request_Target;

   function Host_Header_Value (Item : Request) return String is
   begin
      if Item.Valid then
         return Http_Client.URI.Host_Header_Value (Item.Request_URI);
      else
         return "";
      end if;
   end Host_Header_Value;

   function Set_Payload
     (Item    : in out Request;
      Payload : String) return Http_Client.Errors.Result_Status
   is
   begin
      if not Item.Valid then
         return Invalid_Request;
      end if;

      Item.Payload_Text := To_Unbounded_String (Payload);
      Item.Body_Value := Http_Client.Request_Bodies.From_String (Payload);
      return Ok;
   end Set_Payload;

   function Set_Body
     (Item : in out Request;
      New_Body : Http_Client.Request_Bodies.Request_Body)
      return Http_Client.Errors.Result_Status
   is
   begin
      if not Item.Valid then
         return Invalid_Request;
      end if;

      Item.Body_Value := New_Body;
      Item.Payload_Text :=
        To_Unbounded_String
          (Http_Client.Request_Bodies.Buffered_Payload (New_Body));
      return Ok;
   end Set_Body;

   function Is_Body_Replayable (Item : Request) return Boolean is
   begin
      return Item.Valid and then
        Http_Client.Request_Bodies.Is_Replayable (Item.Body_Value);
   end Is_Body_Replayable;

   function Reset_Body (Item : Request) return Http_Client.Errors.Result_Status is
   begin
      if not Item.Valid then
         return Invalid_Request;
      end if;

      return Http_Client.Request_Bodies.Reset_Body (Item.Body_Value);
   end Reset_Body;

   procedure Set_Target
     (Item   : in out Request;
      Target : String)
   is
   begin
      Item.Valid := False;
      Item.Legacy_Target := To_Unbounded_String (Target);
   end Set_Target;

   function Target_Text (Item : Request) return String is
   begin
      return Request_Target (Item);
   end Target_Text;

end Http_Client.Requests;
