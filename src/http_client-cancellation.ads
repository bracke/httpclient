package Http_Client.Cancellation is
   --  Cooperative cancellation token for long-running HTTP operations.
   --
   --  Cancellation is explicit and deterministic: operations that observe a
   --  cancelled token return Http_Client.Errors.Cancelled and discard any
   --  affected connection because protocol state is no longer known clean.

   type Cancellation_Token is limited private;
   type Cancellation_Token_Access is access all Cancellation_Token;

   procedure Cancel (Item : in out Cancellation_Token);
   --  GNATdoc contract.
   --  @param Item Cancellation token to mark as cancelled.
   --  Request cancellation for operations observing Item.

   procedure Reset (Item : in out Cancellation_Token);
   --  GNATdoc contract.
   --  @param Item Cancellation token to reset.
   --  Clear cancellation so Item can be reused for a later operation.

   function Is_Cancelled (Item : Cancellation_Token) return Boolean;
   --  GNATdoc contract.
   --  @param Item Cancellation token to query.
   --  @return True after Cancel and before Reset.
   --  Return True after Cancel and before Reset.

private
   protected type Cancellation_State is
      procedure Cancel;
      procedure Reset;
      function Is_Cancelled return Boolean;
      --  GNATdoc contract.
      --  @return Current protected cancellation flag.
   private
      Flag : Boolean := False;
   end Cancellation_State;

   type Cancellation_Token is limited record
      State : Cancellation_State;
   end record;
end Http_Client.Cancellation;
