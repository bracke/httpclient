with Ada.Text_IO;

with AUnit;
with AUnit.Reporter.Text;
with AUnit.Run;
with All_Suites;
with GNAT.OS_Lib;
with Interfaces.C;
with System;
with System.Storage_Elements;

with Http_Client.Ada_Test_Fixtures;

procedure Tests is
   function C_Signal
     (Signum  : Interfaces.C.int;
      Handler : System.Address) return System.Address
   with Import, Convention => C, External_Name => "signal";

   SIGPIPE : constant Interfaces.C.int := 13;
   SIG_IGN : constant System.Address :=
     System.Storage_Elements.To_Address (1);

   Previous_SIGPIPE_Handler : constant System.Address :=
     C_Signal (SIGPIPE, SIG_IGN);

   function Runner is new AUnit.Run.Test_Runner_With_Status (All_Suites.Suite);
   Reporter   : AUnit.Reporter.Text.Text_Reporter;
   Run_Status : AUnit.Status;

   use type AUnit.Status;

   procedure Cleanup_Fixtures is
   begin
      Http_Client.Ada_Test_Fixtures.Stop_TLS;
      Http_Client.Ada_Test_Fixtures.Stop_CONNECT_Proxy;
      Http_Client.Ada_Test_Fixtures.Stop_SOCKS5_Proxy;
   exception
      when others =>
         null;
   end Cleanup_Fixtures;

   procedure Flush_Reports is
   begin
      Ada.Text_IO.Flush (Ada.Text_IO.Standard_Output);
      Ada.Text_IO.Flush (Ada.Text_IO.Standard_Error);
   exception
      when others =>
         null;
   end Flush_Reports;

   pragma Unreferenced (Previous_SIGPIPE_Handler);
begin
   Cleanup_Fixtures;

   Run_Status := Runner (Reporter);

   --  The proxy+TLS fixture suites can leave OpenSSL-backed Ada tasks alive
   --  long enough for environment finalization to prevent buffered AUnit text
   --  output from reaching the caller.  The status-returning AUnit runner has
   --  already produced the report at this point; flush it explicitly and then
   --  exit with the AUnit status instead of waiting for unrelated fixture task
   --  finalization.
   Cleanup_Fixtures;
   Flush_Reports;

   if Run_Status = AUnit.Success then
      GNAT.OS_Lib.OS_Exit (0);
   else
      GNAT.OS_Lib.OS_Exit (1);
   end if;
exception
   when others =>
      Cleanup_Fixtures;
      Flush_Reports;
      raise;
end Tests;
