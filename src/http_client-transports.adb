package body Http_Client.Transports
  with SPARK_Mode => On
is

   function Is_Implemented (Kind : Transport_Kind) return Boolean is
   begin
      case Kind is
         when Plain_HTTP =>
            return True;
         when HTTPS_TLS =>
            return True;
      end case;
   end Is_Implemented;

end Http_Client.Transports;
