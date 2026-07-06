with Http_Client.Async.Tests;
with Http_Client.Auth.Tests;
with Http_Client.Cache.Persistent.Tests;
with Http_Client.Cache.Tests;
with Http_Client.Binary_Safety_Tests;
with Http_Client.Cancellation_Tests;
with Http_Client.Clients.Tests;
with Http_Client.Conformance.Tests;
with Http_Client.Connection_Pools.Tests;
with Http_Client.Cookies.Tests;
with Http_Client.Decompression.Tests;
with Http_Client.Diagnostics.Tests;
with Http_Client.HTTP1.Tests;
with Http_Client.HTTP2.Tests;
with Http_Client.HTTP2.Trailers_Tests;
with Http_Client.HTTP3.Tests;
with Http_Client.HTTP3.Boundary_Tests;
with Http_Client.Multipart.Tests;
with Http_Client.Protocol_Discovery.Tests;
with Http_Client.Proxies.SOCKS.Tests;
with Http_Client.Proxies.Tests;
with Http_Client.Redirects.Tests;
with Http_Client.Release_Core.Tests;
with Http_Client.Request_Bodies.Tests;
with Http_Client.Requests_Headers.Tests;
with Http_Client.Resources.Tests;
with Http_Client.Response_Streams.Tests;
with Http_Client.Responses.Tests;
with Http_Client.Retry.Tests;
with Http_Client.Security_Corpus.Tests;
with Http_Client.TLS.Tests;
with Http_Client.Connect_TLS_Tests;
with Http_Client.SOCKS5_TLS_Tests;
with Http_Client.Timeout_Tests;
with Http_Client.URI.Tests;

package body Http_Suite is

   function Suite return Access_Test_Suite is
      Ret : constant Access_Test_Suite := new Test_Suite;
   begin
      Ret.Add_Test (new Http_Client.Async.Tests.Section_Test_Case);

      Ret.Add_Test (new Http_Client.Auth.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Cache.Persistent.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Cache.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Binary_Safety_Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Cancellation_Tests.Section_Test_Case);

      Ret.Add_Test (new Http_Client.Clients.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Conformance.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Connection_Pools.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Cookies.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Decompression.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Diagnostics.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.HTTP1.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.HTTP2.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.HTTP2.Trailers_Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.HTTP3.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.HTTP3.Boundary_Tests.Section_Test_Case);

      Ret.Add_Test (new Http_Client.Multipart.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Protocol_Discovery.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Proxies.SOCKS.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Proxies.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Redirects.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Release_Core.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Request_Bodies.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Requests_Headers.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Resources.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Responses.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Response_Streams.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Retry.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Security_Corpus.Tests.Section_Test_Case);

      Ret.Add_Test (new Http_Client.TLS.Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Connect_TLS_Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.SOCKS5_TLS_Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.Timeout_Tests.Section_Test_Case);
      Ret.Add_Test (new Http_Client.URI.Tests.Section_Test_Case);
      return Ret;
   end Suite;

end Http_Suite;