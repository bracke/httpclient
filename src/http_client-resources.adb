package body Http_Client.Resources is

   protected Counters is
      procedure Add (Kind : Counter_Kind; Amount : Natural);
      procedure Subtract (Kind : Counter_Kind; Amount : Natural);
      procedure Clear;
      function Take return Resource_Snapshot;
      function Get (Kind : Counter_Kind) return Natural;
   private
      Data : Resource_Snapshot;
   end Counters;

   protected body Counters is
      procedure Add (Kind : Counter_Kind; Amount : Natural) is
         procedure Sat_Add (Value : in out Natural) is
         begin
            if Amount > Natural'Last - Value then
               Value := Natural'Last;
            else
               Value := Value + Amount;
            end if;
         end Sat_Add;
      begin
         if Amount = 0 then
            return;
         end if;

         case Kind is
            when Streaming_Responses_Open =>
               Sat_Add (Data.Streaming_Responses_Open);
            when Async_Clients_Open =>
               Sat_Add (Data.Async_Clients_Open);
            when Async_Workers_Configured =>
               Sat_Add (Data.Async_Workers_Configured);
            when Pool_Idle_Entries =>
               Sat_Add (Data.Pool_Idle_Entries);
            when Persistent_Cache_Stores_Open =>
               Sat_Add (Data.Persistent_Cache_Stores_Open);
            when Diagnostics_Events_Emitted =>
               Sat_Add (Data.Diagnostics_Events_Emitted);
         end case;
      end Add;

      procedure Subtract (Kind : Counter_Kind; Amount : Natural) is
         procedure Sat_Sub (Value : in out Natural) is
         begin
            if Amount >= Value then
               Value := 0;
            else
               Value := Value - Amount;
            end if;
         end Sat_Sub;
      begin
         if Amount = 0 then
            return;
         end if;

         case Kind is
            when Streaming_Responses_Open =>
               Sat_Sub (Data.Streaming_Responses_Open);
            when Async_Clients_Open =>
               Sat_Sub (Data.Async_Clients_Open);
            when Async_Workers_Configured =>
               Sat_Sub (Data.Async_Workers_Configured);
            when Pool_Idle_Entries =>
               Sat_Sub (Data.Pool_Idle_Entries);
            when Persistent_Cache_Stores_Open =>
               Sat_Sub (Data.Persistent_Cache_Stores_Open);
            when Diagnostics_Events_Emitted =>
               Sat_Sub (Data.Diagnostics_Events_Emitted);
         end case;
      end Subtract;

      procedure Clear is
      begin
         Data := (others => 0);
      end Clear;

      function Take return Resource_Snapshot is
      begin
         return Data;
      end Take;

      function Get (Kind : Counter_Kind) return Natural is
      begin
         case Kind is
            when Streaming_Responses_Open =>
               return Data.Streaming_Responses_Open;
            when Async_Clients_Open =>
               return Data.Async_Clients_Open;
            when Async_Workers_Configured =>
               return Data.Async_Workers_Configured;
            when Pool_Idle_Entries =>
               return Data.Pool_Idle_Entries;
            when Persistent_Cache_Stores_Open =>
               return Data.Persistent_Cache_Stores_Open;
            when Diagnostics_Events_Emitted =>
               return Data.Diagnostics_Events_Emitted;
         end case;
      end Get;
   end Counters;

   procedure Increment (Kind : Counter_Kind; Amount : Natural := 1) is
   begin
      Counters.Add (Kind, Amount);
   end Increment;

   procedure Decrement (Kind : Counter_Kind; Amount : Natural := 1) is
   begin
      Counters.Subtract (Kind, Amount);
   end Decrement;

   procedure Reset_All is
   begin
      Counters.Clear;
   end Reset_All;

   function Snapshot return Resource_Snapshot is
   begin
      return Counters.Take;
   end Snapshot;

   function Value (Kind : Counter_Kind) return Natural is
   begin
      return Counters.Get (Kind);
   end Value;

end Http_Client.Resources;
