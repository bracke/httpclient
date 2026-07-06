package body Http_Client.Cancellation is

   protected body Cancellation_State is
      procedure Cancel is
      begin
         Flag := True;
      end Cancel;

      procedure Reset is
      begin
         Flag := False;
      end Reset;

      function Is_Cancelled return Boolean is
      begin
         return Flag;
      end Is_Cancelled;
   end Cancellation_State;

   procedure Cancel (Item : in out Cancellation_Token) is
   begin
      Item.State.Cancel;
   end Cancel;

   procedure Reset (Item : in out Cancellation_Token) is
   begin
      Item.State.Reset;
   end Reset;

   function Is_Cancelled (Item : Cancellation_Token) return Boolean is
   begin
      return Item.State.Is_Cancelled;
   end Is_Cancelled;

end Http_Client.Cancellation;
