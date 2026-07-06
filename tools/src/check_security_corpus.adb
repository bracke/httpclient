with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;

with Project_Tools.Security_Corpus;

procedure Check_Security_Corpus is
   Root   : constant String := ".";
   Corpus : constant String := Root & "/tests/fixtures/security_corpus";
   Errors : Natural := 0;

   Required : constant Project_Tools.Security_Corpus.Text_List :=
     [To_Unbounded_String ("async"), To_Unbounded_String ("auth"), To_Unbounded_String ("cache"),
      To_Unbounded_String ("compression"), To_Unbounded_String ("connection_pooling"),
      To_Unbounded_String ("cookies"), To_Unbounded_String ("diagnostics"),
      To_Unbounded_String ("encrypted_cache"), To_Unbounded_String ("fallback"),
      To_Unbounded_String ("headers"), To_Unbounded_String ("hpack"), To_Unbounded_String ("http1"),
      To_Unbounded_String ("http2_frames"), To_Unbounded_String ("http3_frames"),
      To_Unbounded_String ("multipart"), To_Unbounded_String ("persistent_cache"),
      To_Unbounded_String ("proxies"), To_Unbounded_String ("qpack"), To_Unbounded_String ("quic"),
      To_Unbounded_String ("redirects"), To_Unbounded_String ("socks"), To_Unbounded_String ("tls"),
      To_Unbounded_String ("uri")];

   Forbidden_Secrets : constant Project_Tools.Security_Corpus.Text_List :=
     [To_Unbounded_String ("-----BEGIN PRIVATE KEY-----"),
      To_Unbounded_String ("-----BEGIN RSA PRIVATE KEY-----"),
      To_Unbounded_String ("-----BEGIN EC PRIVATE KEY-----"),
      To_Unbounded_String ("-----BEGIN OPENSSH PRIVATE KEY-----"),
      To_Unbounded_String ("AKIA"),
      To_Unbounded_String ("production_token"),
      To_Unbounded_String ("production-secret"),
      To_Unbounded_String ("production_password"),
      To_Unbounded_String ("live_token"),
      To_Unbounded_String ("live-secret"),
      To_Unbounded_String ("live_password")];

   Required_README_Tokens : constant Project_Tools.Security_Corpus.Text_List :=
     [To_Unbounded_String ("do not include production credentials"),
      To_Unbounded_String ("random fuzz campaigns must print")];
begin
   Project_Tools.Security_Corpus.Check_Corpus
     (Errors, Corpus, Required, Forbidden_Secrets, Required_README_Tokens, 4096);

   if Errors = 0 then
      Ada.Text_IO.Put_Line ("security corpus checks passed");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Check_Security_Corpus;
