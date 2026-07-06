with Ada.Calendar;
with Ada.Strings.Fixed;
with Ada.Text_IO;

with Http_Client.Errors;
with Http_Client.Headers;
with Http_Client.HTTP3.Frames;
with Http_Client.Resources;
with Http_Client.URI;

procedure Benchmark_Runner is
   use type Ada.Calendar.Time;
   use type Http_Client.Errors.Result_Status;
   use type Http_Client.HTTP3.Frames.Varint_Value;

   Iterations : constant Positive := 10_000;

   procedure Report (Name : String; Count : Natural; Started : Ada.Calendar.Time) is
      Finished : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      Elapsed  : constant Duration := Finished - Started;
   begin
      Ada.Text_IO.Put_Line
        (Name & ": count=" & Natural'Image (Count) &
         " elapsed_seconds=" & Duration'Image (Elapsed));
   end Report;

   procedure Benchmark_URI_Parse is
      Started : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      Item    : Http_Client.URI.URI_Reference;
      Status  : Http_Client.Errors.Result_Status;
      pragma Unreferenced (Status);
   begin
      for I in 1 .. Iterations loop
         Status := Http_Client.URI.Parse
           ("https://example.test:443/path/to/resource?q=" &
            Ada.Strings.Fixed.Trim (I'Image, Ada.Strings.Left),
            Item);
      end loop;
      Report ("uri_parse", Iterations, Started);
   end Benchmark_URI_Parse;

   procedure Benchmark_Header_Lookup is
      Started : Ada.Calendar.Time;
      Headers : Http_Client.Headers.Header_List := Http_Client.Headers.Empty;
      Status  : Http_Client.Errors.Result_Status;
      Hits    : Natural := 0;
   begin
      for I in 1 .. 64 loop
         Status := Http_Client.Headers.Add
           (Headers,
            "X-Bench-" & Ada.Strings.Fixed.Trim (I'Image, Ada.Strings.Left),
            "value");
         pragma Assert (Status = Http_Client.Errors.Ok);
      end loop;
      Status := Http_Client.Headers.Add (Headers, "Content-Type", "text/plain");
      pragma Assert (Status = Http_Client.Errors.Ok);

      Started := Ada.Calendar.Clock;
      for I in 1 .. Iterations loop
         if Http_Client.Headers.Contains (Headers, "content-type") then
            Hits := Hits + 1;
         end if;
      end loop;
      Report ("header_lookup", Hits, Started);
   end Benchmark_Header_Lookup;

   procedure Benchmark_HTTP3_Varint is
      Started : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      Encoded : constant String := Http_Client.HTTP3.Frames.Encode_Varint (16#3FFF#);
      Value   : Http_Client.HTTP3.Frames.Varint_Value;
      Used    : Natural;
      Status  : Http_Client.Errors.Result_Status;
   begin
      for I in 1 .. Iterations loop
         Status := Http_Client.HTTP3.Frames.Decode_Varint (Encoded, Value, Used);
      end loop;
      pragma Assert (Status = Http_Client.Errors.Ok);
      pragma Assert (Value = 16#3FFF#);
      pragma Assert (Used = Encoded'Length);
      Report ("http3_varint_decode", Iterations, Started);
   end Benchmark_HTTP3_Varint;

   Snapshot : Http_Client.Resources.Resource_Snapshot;
begin
   Http_Client.Resources.Reset_All;
   Benchmark_URI_Parse;
   Benchmark_Header_Lookup;
   Benchmark_HTTP3_Varint;
   Snapshot := Http_Client.Resources.Snapshot;
   Ada.Text_IO.Put_Line
     ("resource_snapshot streaming=" & Natural'Image (Snapshot.Streaming_Responses_Open) &
      " async_clients=" & Natural'Image (Snapshot.Async_Clients_Open) &
      " pool_idle=" & Natural'Image (Snapshot.Pool_Idle_Entries) &
      " diagnostics_events=" & Natural'Image (Snapshot.Diagnostics_Events_Emitted));
end Benchmark_Runner;
