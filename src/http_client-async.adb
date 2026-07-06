with Ada.Unchecked_Deallocation;

with Http_Client.Diagnostics; use Http_Client.Diagnostics;
with Http_Client.Resources;
with Http_Client.URI;
with Http_Client.Types;

package body Http_Client.Async is

   use Http_Client.Errors;

   protected body Future_State is
      procedure Request_Cancel
        (Status : out Http_Client.Errors.Result_Status)
      is
      begin
         if Done then
            Status := Stored.Status;
         else
            Cancelled := True;
            Status := Http_Client.Errors.Ok;
         end if;
      end Request_Cancel;

      procedure Force_Cancel is
      begin
         Cancelled := True;
      end Force_Cancel;

      function Cancellation_Requested return Boolean is
      begin
         return Cancelled;
      end Cancellation_Requested;

      procedure Mark_Started (May_Start : out Boolean) is
      begin
         if Done or else Cancelled then
            May_Start := False;
            if not Done then
               Stored.Status := Http_Client.Errors.Async_Cancelled;
               Done := True;
            end if;
         else
            Started := True;
            May_Start := True;
         end if;
      end Mark_Started;

      procedure Complete (Value : Http_Client.Clients.Client_Result) is
      begin
         if not Done then
            Stored := Value;
            if Cancelled and then Stored.Status = Http_Client.Errors.Ok then
               Stored.Status := Http_Client.Errors.Async_Cancelled;
            end if;
            Done := True;
         end if;
      end Complete;

      function Poll_Status return Http_Client.Errors.Result_Status is
      begin
         if not Done then
            return Http_Client.Errors.Async_Not_Ready;
         end if;
         return Stored.Status;
      end Poll_Status;

      entry Await (Status : out Http_Client.Errors.Result_Status) when Done is
      begin
         Status := Stored.Status;
      end Await;

      procedure Consume
        (Value  : out Http_Client.Clients.Client_Result;
         Status : out Http_Client.Errors.Result_Status)
      is
      begin
         if not Done then
            Value := (others => <>);
            Value.Status := Http_Client.Errors.Async_Not_Ready;
            Status := Http_Client.Errors.Async_Not_Ready;
         elsif Taken then
            Value := Stored;
            Status := Http_Client.Errors.Async_Result_Already_Taken;
         else
            Value := Stored;
            Taken := True;
            Status := Stored.Status;
         end if;
      end Consume;
   end Future_State;

   type Work_Item is record
      Request : Http_Client.Requests.Request := Http_Client.Requests.Default_Request;
      Future  : Future_Access := null;
      ID      : Natural := 0;
   end record;

   type Work_Item_Access is access Work_Item;
   type Work_Array is array (Positive range <>) of Work_Item_Access;

   procedure Free_Work is new Ada.Unchecked_Deallocation
     (Object => Work_Item,
      Name   => Work_Item_Access);

   protected type Work_Queue (Capacity : Positive) is
      procedure Enqueue
        (Item   : Work_Item_Access;
         Status : out Http_Client.Errors.Result_Status);
      entry Dequeue (Item : out Work_Item_Access; Stop : out Boolean);
      procedure Stop (Cancel_Pending : Boolean);
      function Is_Stopping return Boolean;
      function Cancelling_Pending return Boolean;
      function Current_Count return Natural;
      function Next_ID return Natural;
   private
      Items       : Work_Array (1 .. Capacity) := (others => null);
      Head        : Positive := 1;
      Tail        : Positive := 1;
      Count       : Natural := 0;
      Stopping     : Boolean := False;
      Cancel_Queued : Boolean := False;
      Next_Value   : Natural := 1;
   end Work_Queue;

   protected body Work_Queue is
      procedure Enqueue
        (Item   : Work_Item_Access;
         Status : out Http_Client.Errors.Result_Status)
      is
      begin
         if Stopping then
            Status := Http_Client.Errors.Async_Shutdown;
         elsif Count = Capacity then
            Status := Http_Client.Errors.Async_Queue_Full;
         else
            Items (Tail) := Item;
            if Tail = Capacity then
               Tail := 1;
            else
               Tail := Tail + 1;
            end if;
            Count := Count + 1;
            Status := Http_Client.Errors.Ok;
         end if;
      end Enqueue;

      entry Dequeue (Item : out Work_Item_Access; Stop : out Boolean)
        when Count > 0 or else Stopping
      is
      begin
         if Count = 0 and then Stopping then
            Item := null;
            Stop := True;
         else
            Item := Items (Head);
            Items (Head) := null;
            if Head = Capacity then
               Head := 1;
            else
               Head := Head + 1;
            end if;
            Count := Count - 1;
            Stop := False;
         end if;
      end Dequeue;

      procedure Stop (Cancel_Pending : Boolean) is
      begin
         Stopping := True;
         if Cancel_Pending then
            Cancel_Queued := True;
         end if;
      end Stop;

      function Is_Stopping return Boolean is
      begin
         return Stopping;
      end Is_Stopping;

      function Cancelling_Pending return Boolean is
      begin
         return Cancel_Queued;
      end Cancelling_Pending;

      function Current_Count return Natural is
      begin
         return Count;
      end Current_Count;

      function Next_ID return Natural is
         Result : constant Natural := Next_Value;
      begin
         --  Protected functions cannot mutate state, so the public handle id is
         --  assigned in Submit from a monotonically increasing package-local
         --  counter guarded by the caller-side state lock below.
         return Result;
      end Next_ID;
   end Work_Queue;

   protected type Execution_Gate is
      entry Lock;
      procedure Unlock;
   private
      Busy : Boolean := False;
   end Execution_Gate;

   protected body Execution_Gate is
      entry Lock when not Busy is
      begin
         Busy := True;
      end Lock;

      procedure Unlock is
      begin
         Busy := False;
      end Unlock;
   end Execution_Gate;

   protected type Worker_Counter (Initial : Natural) is
      procedure Worker_Stopped;
      entry Wait_All;
   private
      Remaining : Natural := Initial;
   end Worker_Counter;

   protected body Worker_Counter is
      procedure Worker_Stopped is
      begin
         if Remaining > 0 then
            Remaining := Remaining - 1;
         end if;
      end Worker_Stopped;

      entry Wait_All when Remaining = 0 is
      begin
         null;
      end Wait_All;
   end Worker_Counter;

   type Queue_Access is access Work_Queue;
   type Gate_Access is access Execution_Gate;
   type Counter_Access is access Worker_Counter;

   task type Worker (Owner : State_Access);
   type Worker_Access is access Worker;
   type Worker_Array is array (Positive range <>) of Worker_Access;
   type Worker_Array_Access is access Worker_Array;

   protected type Submit_State is
      procedure Allocate_ID (Value : out Natural);
   private
      Next : Natural := 1;
   end Submit_State;

   protected body Submit_State is
      procedure Allocate_ID (Value : out Natural) is
      begin
         Value := Next;
         if Next < Natural'Last then
            Next := Next + 1;
         end if;
      end Allocate_ID;
   end Submit_State;

   type Submit_State_Access is access Submit_State;

   type State is record
      Client      : Http_Client.Clients.Client := Http_Client.Clients.Create;
      Queue       : Queue_Access := null;
      Gate        : Gate_Access := null;
      Diag_Gate   : Gate_Access := null;
      Counter     : Counter_Access := null;
      Submitter   : Submit_State_Access := null;
      Workers     : Worker_Array_Access := null;
   end record;

   procedure Emit_Async
     (Owner   : State_Access;
      Kind    : Http_Client.Diagnostics.Event_Kind;
      ID      : Natural := 0;
      Status  : Http_Client.Errors.Result_Status := Http_Client.Errors.Ok;
      Message : String := "")
   is
      Config  : Http_Client.Clients.Client_Configuration;
      Context : Http_Client.Diagnostics.Context_Access;
      Event   : Http_Client.Diagnostics.Diagnostic_Event;
      Ignored : Http_Client.Errors.Result_Status;
      Locked  : Boolean := False;
   begin
      if Owner = null or else Owner.Diag_Gate = null then
         return;
      end if;

      Owner.Diag_Gate.Lock;
      Locked := True;
      Config := Http_Client.Clients.Configuration (Owner.Client);
      Context := Config.Execution.Diagnostics;

      if Context /= null then
         Event.Kind := Kind;
         Event.Request_ID := Http_Client.Diagnostics.Diagnostic_ID (ID);
         Event.Result := Status;
         Event.Message := Http_Client.Diagnostics.To_Text (Message);
         Ignored := Http_Client.Diagnostics.Emit (Context.all, Event);
      end if;

      Owner.Diag_Gate.Unlock;
   exception
      when others =>
         if Locked and then Owner /= null and then Owner.Diag_Gate /= null then
            begin
               Owner.Diag_Gate.Unlock;
            exception
               when others =>
                  null;
            end;
         end if;
   end Emit_Async;

   task body Worker is
      Item       : Work_Item_Access;
      Stop       : Boolean;
      May_Start  : Boolean;
      Result     : Http_Client.Clients.Client_Result;
      Status     : Http_Client.Errors.Result_Status;
   begin
      Emit_Async (Owner, Http_Client.Diagnostics.Async_Worker_Started);
      loop
         Owner.Queue.Dequeue (Item, Stop);
         exit when Stop;

         if Item /= null then
            Emit_Async
              (Owner,
               Http_Client.Diagnostics.Async_Request_Dequeued,
               Item.ID);
         end if;

         if Item /= null and then Item.Future /= null then
            if Owner.Queue.Cancelling_Pending then
               Item.Future.Force_Cancel;
            end if;
            Item.Future.Mark_Started (May_Start);
            if May_Start then
               Emit_Async
                 (Owner,
                  Http_Client.Diagnostics.Async_Request_Started,
                  Item.ID);
               begin
                  Owner.Gate.Lock;
                  begin
                     Status := Http_Client.Clients.Execute
                       (Owner.Client,
                        Item.Request,
                        Result);
                     Result.Status := Status;
                  exception
                     when others =>
                        Result.Status := Http_Client.Errors.Async_Worker_Failed;
                  end;
                  Owner.Gate.Unlock;
               exception
                  when others =>
                     Result.Status := Http_Client.Errors.Async_Worker_Failed;
                     begin
                        Owner.Gate.Unlock;
                     exception
                        when others =>
                           null;
                     end;
               end;

               if Item.Future.Cancellation_Requested then
                  Result.Status := Http_Client.Errors.Async_Cancelled;
                  Emit_Async
                    (Owner,
                     Http_Client.Diagnostics.Async_Cancel_Observed,
                     Item.ID,
                     Result.Status);
               end if;
               Item.Future.Complete (Result);
               Emit_Async
                 (Owner,
                  (if Result.Status = Http_Client.Errors.Ok then
                     Http_Client.Diagnostics.Async_Request_Completed
                   else
                     Http_Client.Diagnostics.Async_Request_Failed),
                  Item.ID,
                  Result.Status);
            else
               Emit_Async
                 (Owner,
                  Http_Client.Diagnostics.Async_Cancelled_Before_Start,
                  Item.ID,
                  Http_Client.Errors.Async_Cancelled);
            end if;
         end if;

         if Item /= null then
            Free_Work (Item);
         end if;
      end loop;

      Emit_Async (Owner, Http_Client.Diagnostics.Async_Worker_Stopped);
      Owner.Counter.Worker_Stopped;
   exception
      when others =>
         if Owner /= null and then Owner.Counter /= null then
            Emit_Async
              (Owner,
               Http_Client.Diagnostics.Async_Worker_Stopped,
               Status => Http_Client.Errors.Async_Worker_Failed);
            Owner.Counter.Worker_Stopped;
         end if;
   end Worker;

   function Initialize
     (Item          : in out Async_Client;
      Client        : Http_Client.Clients.Client;
      Configuration : Async_Configuration := Default_Async_Configuration)
      return Http_Client.Errors.Result_Status
   is
   begin
      if Item.Pool_State /= null then
         return Http_Client.Errors.Invalid_Configuration;
      end if;

      if not Http_Client.Clients.Is_Initialized (Client) then
         return Http_Client.Errors.Client_Not_Initialized;
      end if;

      Item.Config := Configuration;
      Item.Was_Shutdown := False;
      Item.Pool_State := new State;
      Item.Pool_State.Client := Client;
      Item.Pool_State.Queue := new Work_Queue (Configuration.Max_Queued);
      Item.Pool_State.Gate := new Execution_Gate;
      Item.Pool_State.Diag_Gate := new Execution_Gate;
      Item.Pool_State.Counter := new Worker_Counter (Configuration.Max_Workers);
      Item.Pool_State.Submitter := new Submit_State;
      Item.Pool_State.Workers := new Worker_Array (1 .. Configuration.Max_Workers);

      for Index in Item.Pool_State.Workers'Range loop
         Item.Pool_State.Workers (Index) := new Worker (Item.Pool_State);
      end loop;

      Http_Client.Resources.Increment
        (Http_Client.Resources.Async_Clients_Open);
      Http_Client.Resources.Increment
        (Http_Client.Resources.Async_Workers_Configured,
         Configuration.Max_Workers);

      return Http_Client.Errors.Ok;
   exception
      when others =>
         return Http_Client.Errors.Internal_Error;
   end Initialize;

   function Is_Initialized (Item : Async_Client) return Boolean is
   begin
      return Item.Pool_State /= null;
   end Is_Initialized;

   function Submit
     (Item    : in out Async_Client;
      Request : Http_Client.Requests.Request;
      Handle  : out Request_Handle) return Http_Client.Errors.Result_Status
   is
      Work   : Work_Item_Access;
      Status : Http_Client.Errors.Result_Status;
      ID     : Natural;
   begin
      Handle := (ID => 0, Future => null, Owner => null);

      if Item.Pool_State = null then
         if Item.Was_Shutdown then
            return Http_Client.Errors.Async_Shutdown;
         end if;
         return Http_Client.Errors.Client_Not_Initialized;
      end if;

      if not Http_Client.Requests.Is_Valid (Request) then
         return Http_Client.Errors.Invalid_Request;
      end if;

      Item.Pool_State.Submitter.Allocate_ID (ID);
      Handle := (ID => ID, Future => new Future_State, Owner => Item.Pool_State);
      Emit_Async
        (Item.Pool_State,
         Http_Client.Diagnostics.Async_Request_Submitted,
         ID);
      Work := new Work_Item'(Request => Request, Future => Handle.Future, ID => ID);
      Item.Pool_State.Queue.Enqueue (Work, Status);

      if Status = Http_Client.Errors.Ok then
         Emit_Async
           (Item.Pool_State,
            Http_Client.Diagnostics.Async_Request_Queued,
            ID);
      else
         Emit_Async
           (Item.Pool_State,
            (if Status = Http_Client.Errors.Async_Queue_Full then
               Http_Client.Diagnostics.Async_Queue_Full
             else
               Http_Client.Diagnostics.Async_Request_Failed),
            ID,
            Status);
      end if;

      if Status /= Http_Client.Errors.Ok then
         declare
            Cancelled : Http_Client.Clients.Client_Result;
         begin
            Cancelled.Status := Status;
            Handle.Future.Complete (Cancelled);
         end;
         Free_Work (Work);
         Handle := (ID => 0, Future => null, Owner => null);
      end if;

      return Status;
   exception
      when others =>
         Handle := (ID => 0, Future => null, Owner => null);
         return Http_Client.Errors.Internal_Error;
   end Submit;

   function Submit_Get
     (Item   : in out Async_Client;
      URL    : String;
      Handle : out Request_Handle) return Http_Client.Errors.Result_Status
   is
      Parsed  : Http_Client.URI.URI_Reference;
      Request : Http_Client.Requests.Request;
      Status  : Http_Client.Errors.Result_Status;
   begin
      Handle := (ID => 0, Future => null, Owner => null);
      Status := Http_Client.URI.Parse (URL, Parsed);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      Status := Http_Client.Requests.Create
        (Method => Http_Client.Types.GET,
         URI    => Parsed,
         Item   => Request);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;

      return Submit (Item, Request, Handle);
   end Submit_Get;

   function Poll
     (Handle : Request_Handle) return Http_Client.Errors.Result_Status is
   begin
      if Handle.Future = null then
         return Http_Client.Errors.Async_Handle_Invalid;
      end if;
      return Handle.Future.Poll_Status;
   end Poll;

   function Wait
     (Handle : Request_Handle) return Http_Client.Errors.Result_Status
   is
      Status : Http_Client.Errors.Result_Status;
   begin
      if Handle.Future = null then
         return Http_Client.Errors.Async_Handle_Invalid;
      end if;
      Handle.Future.Await (Status);
      return Status;
   end Wait;

   function Cancel
     (Handle : Request_Handle) return Http_Client.Errors.Result_Status
   is
      Status : Http_Client.Errors.Result_Status;
   begin
      if Handle.Future = null then
         return Http_Client.Errors.Async_Handle_Invalid;
      end if;

      Handle.Future.Request_Cancel (Status);
      Emit_Async
        (Handle.Owner,
         Http_Client.Diagnostics.Async_Cancel_Requested,
         Handle.ID,
         (if Status = Http_Client.Errors.Ok then
             Http_Client.Errors.Async_Cancelled
          else
             Status));
      return Status;
   end Cancel;

   function Result
     (Handle : Request_Handle;
      Value  : out Http_Client.Clients.Client_Result)
      return Http_Client.Errors.Result_Status
   is
      Status : Http_Client.Errors.Result_Status;
   begin
      if Handle.Future = null then
         Value.Status := Http_Client.Errors.Async_Handle_Invalid;
         return Http_Client.Errors.Async_Handle_Invalid;
      end if;
      Handle.Future.Consume (Value, Status);
      if Status /= Http_Client.Errors.Async_Not_Ready then
         Emit_Async
           (Handle.Owner,
            Http_Client.Diagnostics.Async_Result_Consumed,
            Handle.ID,
            Status);
      end if;
      return Status;
   end Result;

   procedure Shutdown
     (Item           : in out Async_Client;
      Cancel_Pending : Boolean := False) is
   begin
      if Item.Pool_State = null then
         return;
      end if;

      Emit_Async
        (Item.Pool_State,
         Http_Client.Diagnostics.Async_Pool_Shutdown,
         Status => (if Cancel_Pending then
                      Http_Client.Errors.Async_Cancelled
                    else
                      Http_Client.Errors.Ok));
      Item.Pool_State.Queue.Stop (Cancel_Pending);
      Item.Pool_State.Counter.Wait_All;
      Http_Client.Resources.Decrement
        (Http_Client.Resources.Async_Clients_Open);
      Http_Client.Resources.Decrement
        (Http_Client.Resources.Async_Workers_Configured,
         Item.Config.Max_Workers);
      Item.Pool_State := null;
      Item.Was_Shutdown := True;
   end Shutdown;

   overriding procedure Finalize (Item : in out Async_Client) is
   begin
      if Item.Pool_State /= null then
         Shutdown (Item, Item.Config.Cancel_On_Finalize);
      end if;
   end Finalize;

end Http_Client.Async;
