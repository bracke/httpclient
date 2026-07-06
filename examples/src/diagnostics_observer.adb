with Http_Client.Diagnostics;

procedure Diagnostics_Observer is
   Context : Http_Client.Diagnostics.Diagnostics_Context;
begin
   Http_Client.Diagnostics.Initialize
     (Context, Enabled => True, Observer => null);
end Diagnostics_Observer;
