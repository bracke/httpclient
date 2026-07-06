with Ada.Characters.Handling;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Http_Client.HTTP2.HPACK is
   use type Http_Client.Errors.Result_Status;

   function B (Value : Natural) return Character is
   begin
      return Character'Val (Value mod 256);
   end B;

   function U8 (C : Character) return Natural is
   begin
      return Character'Pos (C);
   end U8;

   function Mask (Bits : Positive) return Natural is
   begin
      if Bits >= Natural'Size then
         return Natural'Last;
      else
         return (2 ** Bits) - 1;
      end if;
   end Mask;

   function Has_Flag (Value : Natural; Flag : Natural) return Boolean is
   begin
      return (Value / Flag) mod 2 = 1;
   end Has_Flag;



   type Huffman_Code is record
      Bits   : Natural;
      Length : Natural range 0 .. 30;
   end record;

   HPACK_Huffman_Table : constant array (Natural range 0 .. 256) of Huffman_Code :=
     (
        0 => (Bits => 8184, Length => 13),
        1 => (Bits => 8388568, Length => 23),
        2 => (Bits => 268435426, Length => 28),
        3 => (Bits => 268435427, Length => 28),
        4 => (Bits => 268435428, Length => 28),
        5 => (Bits => 268435429, Length => 28),
        6 => (Bits => 268435430, Length => 28),
        7 => (Bits => 268435431, Length => 28),
        8 => (Bits => 268435432, Length => 28),
        9 => (Bits => 16777194, Length => 24),
       10 => (Bits => 1073741820, Length => 30),
       11 => (Bits => 268435433, Length => 28),
       12 => (Bits => 268435434, Length => 28),
       13 => (Bits => 1073741821, Length => 30),
       14 => (Bits => 268435435, Length => 28),
       15 => (Bits => 268435436, Length => 28),
       16 => (Bits => 268435437, Length => 28),
       17 => (Bits => 268435438, Length => 28),
       18 => (Bits => 268435439, Length => 28),
       19 => (Bits => 268435440, Length => 28),
       20 => (Bits => 268435441, Length => 28),
       21 => (Bits => 268435442, Length => 28),
       22 => (Bits => 1073741822, Length => 30),
       23 => (Bits => 268435443, Length => 28),
       24 => (Bits => 268435444, Length => 28),
       25 => (Bits => 268435445, Length => 28),
       26 => (Bits => 268435446, Length => 28),
       27 => (Bits => 268435447, Length => 28),
       28 => (Bits => 268435448, Length => 28),
       29 => (Bits => 268435449, Length => 28),
       30 => (Bits => 268435450, Length => 28),
       31 => (Bits => 268435451, Length => 28),
       32 => (Bits => 20, Length => 6),
       33 => (Bits => 1016, Length => 10),
       34 => (Bits => 1017, Length => 10),
       35 => (Bits => 4090, Length => 12),
       36 => (Bits => 8185, Length => 13),
       37 => (Bits => 21, Length => 6),
       38 => (Bits => 248, Length => 8),
       39 => (Bits => 2042, Length => 11),
       40 => (Bits => 1018, Length => 10),
       41 => (Bits => 1019, Length => 10),
       42 => (Bits => 249, Length => 8),
       43 => (Bits => 2043, Length => 11),
       44 => (Bits => 250, Length => 8),
       45 => (Bits => 22, Length => 6),
       46 => (Bits => 23, Length => 6),
       47 => (Bits => 24, Length => 6),
       48 => (Bits => 0, Length => 5),
       49 => (Bits => 1, Length => 5),
       50 => (Bits => 2, Length => 5),
       51 => (Bits => 25, Length => 6),
       52 => (Bits => 26, Length => 6),
       53 => (Bits => 27, Length => 6),
       54 => (Bits => 28, Length => 6),
       55 => (Bits => 29, Length => 6),
       56 => (Bits => 30, Length => 6),
       57 => (Bits => 31, Length => 6),
       58 => (Bits => 92, Length => 7),
       59 => (Bits => 251, Length => 8),
       60 => (Bits => 32764, Length => 15),
       61 => (Bits => 32, Length => 6),
       62 => (Bits => 4091, Length => 12),
       63 => (Bits => 1020, Length => 10),
       64 => (Bits => 8186, Length => 13),
       65 => (Bits => 33, Length => 6),
       66 => (Bits => 93, Length => 7),
       67 => (Bits => 94, Length => 7),
       68 => (Bits => 95, Length => 7),
       69 => (Bits => 96, Length => 7),
       70 => (Bits => 97, Length => 7),
       71 => (Bits => 98, Length => 7),
       72 => (Bits => 99, Length => 7),
       73 => (Bits => 100, Length => 7),
       74 => (Bits => 101, Length => 7),
       75 => (Bits => 102, Length => 7),
       76 => (Bits => 103, Length => 7),
       77 => (Bits => 104, Length => 7),
       78 => (Bits => 105, Length => 7),
       79 => (Bits => 106, Length => 7),
       80 => (Bits => 107, Length => 7),
       81 => (Bits => 108, Length => 7),
       82 => (Bits => 109, Length => 7),
       83 => (Bits => 110, Length => 7),
       84 => (Bits => 111, Length => 7),
       85 => (Bits => 112, Length => 7),
       86 => (Bits => 113, Length => 7),
       87 => (Bits => 114, Length => 7),
       88 => (Bits => 252, Length => 8),
       89 => (Bits => 115, Length => 7),
       90 => (Bits => 253, Length => 8),
       91 => (Bits => 8187, Length => 13),
       92 => (Bits => 524272, Length => 19),
       93 => (Bits => 8188, Length => 13),
       94 => (Bits => 16380, Length => 14),
       95 => (Bits => 34, Length => 6),
       96 => (Bits => 32765, Length => 15),
       97 => (Bits => 3, Length => 5),
       98 => (Bits => 35, Length => 6),
       99 => (Bits => 4, Length => 5),
      100 => (Bits => 36, Length => 6),
      101 => (Bits => 5, Length => 5),
      102 => (Bits => 37, Length => 6),
      103 => (Bits => 38, Length => 6),
      104 => (Bits => 39, Length => 6),
      105 => (Bits => 6, Length => 5),
      106 => (Bits => 116, Length => 7),
      107 => (Bits => 117, Length => 7),
      108 => (Bits => 40, Length => 6),
      109 => (Bits => 41, Length => 6),
      110 => (Bits => 42, Length => 6),
      111 => (Bits => 7, Length => 5),
      112 => (Bits => 43, Length => 6),
      113 => (Bits => 118, Length => 7),
      114 => (Bits => 44, Length => 6),
      115 => (Bits => 8, Length => 5),
      116 => (Bits => 9, Length => 5),
      117 => (Bits => 45, Length => 6),
      118 => (Bits => 119, Length => 7),
      119 => (Bits => 120, Length => 7),
      120 => (Bits => 121, Length => 7),
      121 => (Bits => 122, Length => 7),
      122 => (Bits => 123, Length => 7),
      123 => (Bits => 32766, Length => 15),
      124 => (Bits => 2044, Length => 11),
      125 => (Bits => 16381, Length => 14),
      126 => (Bits => 8189, Length => 13),
      127 => (Bits => 268435452, Length => 28),
      128 => (Bits => 1048550, Length => 20),
      129 => (Bits => 4194258, Length => 22),
      130 => (Bits => 1048551, Length => 20),
      131 => (Bits => 1048552, Length => 20),
      132 => (Bits => 4194259, Length => 22),
      133 => (Bits => 4194260, Length => 22),
      134 => (Bits => 4194261, Length => 22),
      135 => (Bits => 8388569, Length => 23),
      136 => (Bits => 4194262, Length => 22),
      137 => (Bits => 8388570, Length => 23),
      138 => (Bits => 8388571, Length => 23),
      139 => (Bits => 8388572, Length => 23),
      140 => (Bits => 8388573, Length => 23),
      141 => (Bits => 8388574, Length => 23),
      142 => (Bits => 16777195, Length => 24),
      143 => (Bits => 8388575, Length => 23),
      144 => (Bits => 16777196, Length => 24),
      145 => (Bits => 16777197, Length => 24),
      146 => (Bits => 4194263, Length => 22),
      147 => (Bits => 8388576, Length => 23),
      148 => (Bits => 16777198, Length => 24),
      149 => (Bits => 8388577, Length => 23),
      150 => (Bits => 8388578, Length => 23),
      151 => (Bits => 8388579, Length => 23),
      152 => (Bits => 8388580, Length => 23),
      153 => (Bits => 2097116, Length => 21),
      154 => (Bits => 4194264, Length => 22),
      155 => (Bits => 8388581, Length => 23),
      156 => (Bits => 4194265, Length => 22),
      157 => (Bits => 8388582, Length => 23),
      158 => (Bits => 8388583, Length => 23),
      159 => (Bits => 16777199, Length => 24),
      160 => (Bits => 4194266, Length => 22),
      161 => (Bits => 2097117, Length => 21),
      162 => (Bits => 1048553, Length => 20),
      163 => (Bits => 4194267, Length => 22),
      164 => (Bits => 4194268, Length => 22),
      165 => (Bits => 8388584, Length => 23),
      166 => (Bits => 8388585, Length => 23),
      167 => (Bits => 2097118, Length => 21),
      168 => (Bits => 8388586, Length => 23),
      169 => (Bits => 4194269, Length => 22),
      170 => (Bits => 4194270, Length => 22),
      171 => (Bits => 16777200, Length => 24),
      172 => (Bits => 2097119, Length => 21),
      173 => (Bits => 4194271, Length => 22),
      174 => (Bits => 8388587, Length => 23),
      175 => (Bits => 8388588, Length => 23),
      176 => (Bits => 2097120, Length => 21),
      177 => (Bits => 2097121, Length => 21),
      178 => (Bits => 4194272, Length => 22),
      179 => (Bits => 2097122, Length => 21),
      180 => (Bits => 8388589, Length => 23),
      181 => (Bits => 4194273, Length => 22),
      182 => (Bits => 8388590, Length => 23),
      183 => (Bits => 8388591, Length => 23),
      184 => (Bits => 1048554, Length => 20),
      185 => (Bits => 4194274, Length => 22),
      186 => (Bits => 4194275, Length => 22),
      187 => (Bits => 4194276, Length => 22),
      188 => (Bits => 8388592, Length => 23),
      189 => (Bits => 4194277, Length => 22),
      190 => (Bits => 4194278, Length => 22),
      191 => (Bits => 8388593, Length => 23),
      192 => (Bits => 67108832, Length => 26),
      193 => (Bits => 67108833, Length => 26),
      194 => (Bits => 1048555, Length => 20),
      195 => (Bits => 524273, Length => 19),
      196 => (Bits => 4194279, Length => 22),
      197 => (Bits => 8388594, Length => 23),
      198 => (Bits => 4194280, Length => 22),
      199 => (Bits => 33554412, Length => 25),
      200 => (Bits => 67108834, Length => 26),
      201 => (Bits => 67108835, Length => 26),
      202 => (Bits => 67108836, Length => 26),
      203 => (Bits => 134217694, Length => 27),
      204 => (Bits => 134217695, Length => 27),
      205 => (Bits => 67108837, Length => 26),
      206 => (Bits => 16777201, Length => 24),
      207 => (Bits => 33554413, Length => 25),
      208 => (Bits => 524274, Length => 19),
      209 => (Bits => 2097123, Length => 21),
      210 => (Bits => 67108838, Length => 26),
      211 => (Bits => 134217696, Length => 27),
      212 => (Bits => 134217697, Length => 27),
      213 => (Bits => 67108839, Length => 26),
      214 => (Bits => 134217698, Length => 27),
      215 => (Bits => 16777202, Length => 24),
      216 => (Bits => 2097124, Length => 21),
      217 => (Bits => 2097125, Length => 21),
      218 => (Bits => 67108840, Length => 26),
      219 => (Bits => 67108841, Length => 26),
      220 => (Bits => 268435453, Length => 28),
      221 => (Bits => 134217699, Length => 27),
      222 => (Bits => 134217700, Length => 27),
      223 => (Bits => 134217701, Length => 27),
      224 => (Bits => 1048556, Length => 20),
      225 => (Bits => 16777203, Length => 24),
      226 => (Bits => 1048557, Length => 20),
      227 => (Bits => 2097126, Length => 21),
      228 => (Bits => 4194281, Length => 22),
      229 => (Bits => 2097127, Length => 21),
      230 => (Bits => 2097128, Length => 21),
      231 => (Bits => 8388595, Length => 23),
      232 => (Bits => 4194282, Length => 22),
      233 => (Bits => 4194283, Length => 22),
      234 => (Bits => 33554414, Length => 25),
      235 => (Bits => 33554415, Length => 25),
      236 => (Bits => 16777204, Length => 24),
      237 => (Bits => 16777205, Length => 24),
      238 => (Bits => 67108842, Length => 26),
      239 => (Bits => 8388596, Length => 23),
      240 => (Bits => 67108843, Length => 26),
      241 => (Bits => 134217702, Length => 27),
      242 => (Bits => 67108844, Length => 26),
      243 => (Bits => 67108845, Length => 26),
      244 => (Bits => 134217703, Length => 27),
      245 => (Bits => 134217704, Length => 27),
      246 => (Bits => 134217705, Length => 27),
      247 => (Bits => 134217706, Length => 27),
      248 => (Bits => 134217707, Length => 27),
      249 => (Bits => 268435454, Length => 28),
      250 => (Bits => 134217708, Length => 27),
      251 => (Bits => 134217709, Length => 27),
      252 => (Bits => 134217710, Length => 27),
      253 => (Bits => 134217711, Length => 27),
      254 => (Bits => 134217712, Length => 27),
      255 => (Bits => 67108846, Length => 26),
      256 => (Bits => 1073741823, Length => 30)
     );

   function Lower (S : String) return String is
   begin
      return Ada.Characters.Handling.To_Lower (S);
   end Lower;

   function Entry_Size (Name, Value : String) return Natural is
   begin
      return Name'Length + Value'Length + 32;
   end Entry_Size;

   function Static_Name (Index : Positive) return String is
   begin
      case Index is
         when 1  => return ":authority";
         when 2  => return ":method";
         when 3  => return ":method";
         when 4  => return ":path";
         when 5  => return ":path";
         when 6  => return ":scheme";
         when 7  => return ":scheme";
         when 8  => return ":status";
         when 9  => return ":status";
         when 10 => return ":status";
         when 11 => return ":status";
         when 12 => return ":status";
         when 13 => return ":status";
         when 14 => return ":status";
         when 15 => return "accept-charset";
         when 16 => return "accept-encoding";
         when 17 => return "accept-language";
         when 18 => return "accept-ranges";
         when 19 => return "accept";
         when 20 => return "access-control-allow-origin";
         when 21 => return "age";
         when 22 => return "allow";
         when 23 => return "authorization";
         when 24 => return "cache-control";
         when 25 => return "content-disposition";
         when 26 => return "content-encoding";
         when 27 => return "content-language";
         when 28 => return "content-length";
         when 29 => return "content-location";
         when 30 => return "content-range";
         when 31 => return "content-type";
         when 32 => return "cookie";
         when 33 => return "date";
         when 34 => return "etag";
         when 35 => return "expect";
         when 36 => return "expires";
         when 37 => return "from";
         when 38 => return "host";
         when 39 => return "if-match";
         when 40 => return "if-modified-since";
         when 41 => return "if-none-match";
         when 42 => return "if-range";
         when 43 => return "if-unmodified-since";
         when 44 => return "last-modified";
         when 45 => return "link";
         when 46 => return "location";
         when 47 => return "max-forwards";
         when 48 => return "proxy-authenticate";
         when 49 => return "proxy-authorization";
         when 50 => return "range";
         when 51 => return "referer";
         when 52 => return "refresh";
         when 53 => return "retry-after";
         when 54 => return "server";
         when 55 => return "set-cookie";
         when 56 => return "strict-transport-security";
         when 57 => return "transfer-encoding";
         when 58 => return "user-agent";
         when 59 => return "vary";
         when 60 => return "via";
         when 61 => return "www-authenticate";
         when others => return "";
      end case;
   end Static_Name;

   function Static_Value (Index : Positive) return String is
   begin
      case Index is
         when 2  => return "GET";
         when 3  => return "POST";
         when 4  => return "/";
         when 5  => return "/index.html";
         when 6  => return "http";
         when 7  => return "https";
         when 8  => return "200";
         when 9  => return "204";
         when 10 => return "206";
         when 11 => return "304";
         when 12 => return "400";
         when 13 => return "404";
         when 14 => return "500";
         when 16 => return "gzip, deflate";
         when others => return "";
      end case;
   end Static_Value;

   function Static_Length return Natural is (61);

   function Static_Exact_Index (Name, Value : String) return Natural is
      N : constant String := Lower (Name);
   begin
      for I in 1 .. Static_Length loop
         if Static_Name (Positive (I)) = N
           and then Static_Value (Positive (I)) = Value
         then
            return I;
         end if;
      end loop;
      return 0;
   end Static_Exact_Index;

   function Static_Name_Index (Name : String) return Natural is
      N : constant String := Lower (Name);
   begin
      for I in 1 .. Static_Length loop
         if Static_Name (Positive (I)) = N then
            return I;
         end if;
      end loop;
      return 0;
   end Static_Name_Index;

   procedure Evict_To_Limit (Item : in out Decoder) is
   begin
      while Item.Count > 0 and then Item.Current_Size > Item.Effective_Table_Size loop
         Item.Current_Size := Item.Current_Size - Item.Table (Item.Count).Size;
         Item.Table (Item.Count) :=
           (Name => Null_Unbounded_String, Value => Null_Unbounded_String, Size => 0);
         Item.Count := Item.Count - 1;
      end loop;
   end Evict_To_Limit;

   procedure Add_Dynamic (Item : in out Decoder; Name, Value : String) is
      S : constant Natural := Entry_Size (Name, Value);
   begin
      if S > Item.Effective_Table_Size or else Item.Effective_Table_Size = 0 then
         for I in 1 .. Item.Count loop
            Item.Table (I) :=
              (Name => Null_Unbounded_String, Value => Null_Unbounded_String, Size => 0);
         end loop;
         Item.Count := 0;
         Item.Current_Size := 0;
         return;
      end if;

      while Item.Count > 0
        and then (Item.Current_Size + S > Item.Effective_Table_Size
                  or else Item.Count = Max_Dynamic_Entries)
      loop
         Item.Current_Size := Item.Current_Size - Item.Table (Item.Count).Size;
         Item.Table (Item.Count) :=
           (Name => Null_Unbounded_String, Value => Null_Unbounded_String, Size => 0);
         Item.Count := Item.Count - 1;
      end loop;

      if Item.Count > 0 then
         for I in reverse 1 .. Item.Count loop
            Item.Table (I + 1) := Item.Table (I);
         end loop;
      end if;

      Item.Table (1) :=
        (Name => To_Unbounded_String (Name),
         Value => To_Unbounded_String (Value),
         Size => S);
      Item.Count := Item.Count + 1;
      Item.Current_Size := Item.Current_Size + S;
   end Add_Dynamic;

   function Lookup
     (Item  : Decoder;
      Index : Natural;
      Name  : out Unbounded_String;
      Value : out Unbounded_String) return Http_Client.Errors.Result_Status
   is
      Dyn : Natural;
   begin
      Name := Null_Unbounded_String;
      Value := Null_Unbounded_String;

      if Index = 0 then
         return Http_Client.Errors.HPACK_Decode_Failed;
      elsif Index <= Static_Length then
         Name := To_Unbounded_String (Static_Name (Positive (Index)));
         Value := To_Unbounded_String (Static_Value (Positive (Index)));
         return Http_Client.Errors.Ok;
      else
         Dyn := Index - Static_Length;
         if Dyn = 0 or else Dyn > Item.Count then
            return Http_Client.Errors.HPACK_Decode_Failed;
         end if;
         Name := Item.Table (Dyn).Name;
         Value := Item.Table (Dyn).Value;
         return Http_Client.Errors.Ok;
      end if;
   end Lookup;

   function Lookup_Name
     (Item  : Decoder;
      Index : Natural;
      Name  : out Unbounded_String) return Http_Client.Errors.Result_Status
   is
      V : Unbounded_String;
   begin
      return Lookup (Item, Index, Name, V);
   end Lookup_Name;

   function Create_Decoder
     (Max_Dynamic_Table_Size : Natural := 4_096;
      Max_Header_List_Size   : Natural := 65_536) return Decoder
   is
      Result : Decoder;
   begin
      Result.Max_Dynamic_Table_Size := Max_Dynamic_Table_Size;
      Result.Effective_Table_Size := Max_Dynamic_Table_Size;
      Result.Max_Header_List_Size := Max_Header_List_Size;
      return Result;
   end Create_Decoder;

   function Create_Encoder
     (Peer_Dynamic_Table_Size : Natural := 4_096) return Encoder
   is
   begin
      return (Peer_Dynamic_Table_Size => Peer_Dynamic_Table_Size);
   end Create_Encoder;

   procedure Set_Peer_Dynamic_Table_Size
     (Item : in out Encoder;
      Size : Natural) is
   begin
      Item.Peer_Dynamic_Table_Size := Size;
   end Set_Peer_Dynamic_Table_Size;

   function Encode_Integer
     (Value       : Natural;
      Prefix_Bits : Positive;
      High_Bits   : Natural := 0) return String
   is
      Prefix_Max : constant Natural := Mask (Prefix_Bits);
      Rest       : Natural := Value;
      Outp       : Unbounded_String := Null_Unbounded_String;
   begin
      if Prefix_Bits > 8 or else High_Bits > 255 or else (High_Bits mod (Prefix_Max + 1)) /= 0 then
         return "";
      end if;

      if Value < Prefix_Max then
         return String'(1 => B (High_Bits + Value));
      end if;

      Append (Outp, B (High_Bits + Prefix_Max));
      Rest := Value - Prefix_Max;
      while Rest >= 128 loop
         Append (Outp, B ((Rest mod 128) + 128));
         Rest := Rest / 128;
      end loop;
      Append (Outp, B (Rest));
      return To_String (Outp);
   end Encode_Integer;

   function Decode_Integer
     (Data        : String;
      Position    : in out Positive;
      Prefix_Bits : Positive;
      Value       : out Natural) return Http_Client.Errors.Result_Status
   is
      Prefix_Max : Natural;
      M          : Natural := 0;
      Addend     : Natural;
      Continuation_Count : Natural := 0;
   begin
      Value := 0;
      if Prefix_Bits > 8 or else Position > Data'Last then
         return Http_Client.Errors.HPACK_Decode_Failed;
      end if;

      Prefix_Max := Mask (Prefix_Bits);
      Value := U8 (Data (Position)) mod (Prefix_Max + 1);
      Position := Position + 1;

      if Value < Prefix_Max then
         return Http_Client.Errors.Ok;
      end if;

      loop
         if Position > Data'Last or else M > 28 then
            return Http_Client.Errors.HPACK_Decode_Failed;
         end if;

         Addend := (U8 (Data (Position)) mod 128) * (2 ** M);
         if Natural'Last - Value < Addend then
            return Http_Client.Errors.HPACK_Decode_Failed;
         end if;
         Value := Value + Addend;
         Continuation_Count := Continuation_Count + 1;

         if not Has_Flag (U8 (Data (Position)), 128) then
            declare
               Rest  : Natural := Value - Prefix_Max;
               Need  : Natural := 1;
            begin
               while Rest >= 128 loop
                  Need := Need + 1;
                  Rest := Rest / 128;
               end loop;
               if Continuation_Count /= Need then
                  return Http_Client.Errors.HPACK_Decode_Failed;
               end if;
            end;

            Position := Position + 1;
            return Http_Client.Errors.Ok;
         end if;

         Position := Position + 1;
         M := M + 7;
      end loop;
   end Decode_Integer;

   function Decode_Huffman_String
     (Data  : String;
      Text  : out Unbounded_String) return Http_Client.Errors.Result_Status
   is
      Code        : Natural := 0;
      Code_Length : Natural := 0;
      Found       : Boolean;
   begin
      Text := Null_Unbounded_String;

      for I in Data'Range loop
         declare
            Oct : constant Natural := U8 (Data (I));
         begin
            for Bit_Index in reverse 0 .. 7 loop
               Code := Code * 2 + ((Oct / (2 ** Bit_Index)) mod 2);
               Code_Length := Code_Length + 1;
               Found := False;

               for Symbol in HPACK_Huffman_Table'Range loop
                  if HPACK_Huffman_Table (Symbol).Length = Code_Length
                    and then HPACK_Huffman_Table (Symbol).Bits = Code
                  then
                     if Symbol = 256 then
                        return Http_Client.Errors.HPACK_Huffman_Error;
                     end if;

                     Append (Text, Character'Val (Symbol));
                     Code := 0;
                     Code_Length := 0;
                     Found := True;
                     exit;
                  end if;
               end loop;

               if not Found and then Code_Length >= 30 then
                  return Http_Client.Errors.HPACK_Huffman_Error;
               end if;
            end loop;
         end;
      end loop;

      if Code_Length = 0 then
         return Http_Client.Errors.Ok;
      elsif Code_Length <= 7 and then Code = (2 ** Code_Length) - 1 then
         return Http_Client.Errors.Ok;
      else
         return Http_Client.Errors.HPACK_Huffman_Error;
      end if;
   end Decode_Huffman_String;

   function Decode_String
     (Data     : String;
      Position : in out Positive;
      Text     : out Unbounded_String) return Http_Client.Errors.Result_Status
   is
      Huffman_Encoded : Boolean;
      Len             : Natural;
      P               : Positive := Position;
      Status          : Http_Client.Errors.Result_Status;
   begin
      Text := Null_Unbounded_String;
      if Position > Data'Last then
         return Http_Client.Errors.HPACK_Decode_Failed;
      end if;

      Huffman_Encoded := Has_Flag (U8 (Data (Position)), 128);

      Status := Decode_Integer (Data, P, 7, Len);
      if Status /= Http_Client.Errors.Ok then
         return Status;
      end if;
      Position := P;

      if Len = 0 then
         Text := Null_Unbounded_String;
         return Http_Client.Errors.Ok;
      end if;

      if Position > Data'Last
        or else Len > Natural (Data'Last - Position + 1)
      then
         return Http_Client.Errors.HPACK_Decode_Failed;
      end if;

      if Huffman_Encoded then
         Status := Decode_Huffman_String
           (Data (Position .. Position + Len - 1), Text);
         if Status /= Http_Client.Errors.Ok then
            return Status;
         end if;
      else
         Text := To_Unbounded_String (Data (Position .. Position + Len - 1));
      end if;

      Position := Position + Integer (Len);
      return Http_Client.Errors.Ok;
   end Decode_String;

   function Add_Output_Header
     (Headers : in out Http_Client.Headers.Header_List;
      Name    : String;
      Value   : String) return Http_Client.Errors.Result_Status
   is
   begin
      if Name'Length = 0 then
         return Http_Client.Errors.Invalid_Header;
      elsif Lower (Name) /= Name then
         return Http_Client.Errors.Invalid_Header;
      elsif Name (Name'First) = ':' then
         return Http_Client.Headers.Add_HTTP2_Pseudo (Headers, Name, Value);
      else
         return Http_Client.Headers.Add (Headers, Name, Value);
      end if;
   end Add_Output_Header;

   function Decode_Header_Block
     (Item    : in out Decoder;
      Block   : String;
      Headers : out Http_Client.Headers.Header_List)
      return Http_Client.Errors.Result_Status
   is
      P       : Positive := Block'First;
      Index   : Natural;
      Name_U  : Unbounded_String;
      Value_U : Unbounded_String;
      Total   : Natural := 0;
      Status  : Http_Client.Errors.Result_Status;
      Emit    : Boolean;
   begin
      Headers := Http_Client.Headers.Empty;
      Item.Saw_Field := False;

      if Block'Length = 0 then
         return Http_Client.Errors.Ok;
      end if;

      while P <= Block'Last loop
         Emit := True;
         declare
            Oct : constant Natural := U8 (Block (P));
         begin
            if Has_Flag (Oct, 128) then
               Status := Decode_Integer (Block, P, 7, Index);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               Status := Lookup (Item, Index, Name_U, Value_U);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               Item.Saw_Field := True;

            elsif Has_Flag (Oct, 64) then
               Status := Decode_Integer (Block, P, 6, Index);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;

               if Index = 0 then
                  Status := Decode_String (Block, P, Name_U);
               else
                  Status := Lookup_Name (Item, Index, Name_U);
               end if;
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               Status := Decode_String (Block, P, Value_U);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               Item.Saw_Field := True;
               Add_Dynamic (Item, To_String (Name_U), To_String (Value_U));

            elsif Has_Flag (Oct, 32) then
               if Item.Saw_Field then
                  return Http_Client.Errors.HPACK_Decode_Failed;
               end if;
               Status := Decode_Integer (Block, P, 5, Index);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               if Index > Item.Max_Dynamic_Table_Size then
                  return Http_Client.Errors.HPACK_Decode_Failed;
               end if;
               Item.Effective_Table_Size := Index;
               Evict_To_Limit (Item);
               Emit := False;

            elsif Has_Flag (Oct, 16) then
               Status := Decode_Integer (Block, P, 4, Index);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               if Index = 0 then
                  Status := Decode_String (Block, P, Name_U);
               else
                  Status := Lookup_Name (Item, Index, Name_U);
               end if;
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               Status := Decode_String (Block, P, Value_U);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               Item.Saw_Field := True;

            else
               Status := Decode_Integer (Block, P, 4, Index);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               if Index = 0 then
                  Status := Decode_String (Block, P, Name_U);
               else
                  Status := Lookup_Name (Item, Index, Name_U);
               end if;
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               Status := Decode_String (Block, P, Value_U);
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
               Item.Saw_Field := True;
            end if;

            if Emit then
               declare
                  Field_Size : constant Natural :=
                    Length (Name_U) + Length (Value_U) + 32;
               begin
                  if Field_Size > Natural'Last - Total then
                     return Http_Client.Errors.Header_Too_Large;
                  end if;
                  Total := Total + Field_Size;
               end;
               if Total > Item.Max_Header_List_Size then
                  return Http_Client.Errors.Header_Too_Large;
               end if;

               Status := Add_Output_Header
                 (Headers, To_String (Name_U), To_String (Value_U));
               if Status /= Http_Client.Errors.Ok then
                  return Status;
               end if;
            end if;
         end;
      end loop;

      return Http_Client.Errors.Ok;
   end Decode_Header_Block;

   function Is_Sensitive (Name : String) return Boolean is
      L : constant String := Lower (Name);
   begin
      return L = "authorization" or else L = "proxy-authorization" or else L = "cookie";
   end Is_Sensitive;

   function Encode_String_Raw (Text : String) return String is
   begin
      return Encode_Integer (Text'Length, 7, 0) & Text;
   end Encode_String_Raw;

   function Encode_Header_Block
     (Item    : in out Encoder;
      Headers : Http_Client.Headers.Header_List;
      Output  : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status
   is
      pragma Unreferenced (Item);
      S          : Unbounded_String := Null_Unbounded_String;
      Name       : Unbounded_String;
      Val        : Unbounded_String;
      Prefix     : Natural;
      Exact_Index : Natural;
      Name_Index : Natural;
   begin
      for I in 1 .. Http_Client.Headers.Length (Headers) loop
         Name := To_Unbounded_String (Lower (Http_Client.Headers.Name_At (Headers, I)));
         Val := To_Unbounded_String (Http_Client.Headers.Value_At (Headers, I));

         if Length (Name) = 0 then
            Output := Null_Unbounded_String;
            return Http_Client.Errors.Invalid_Header;
         end if;

         Exact_Index := Static_Exact_Index (To_String (Name), To_String (Val));
         if Exact_Index /= 0 then
            --  Use the HPACK static table for exact common fields such as
            --  :method GET, :scheme https, and :path /.  Sending every
            --  request field as a literal-with-new-name is legal, but several
            --  deployed HTTP/2 endpoints are stricter than the RFC examples
            --  and reset streams that do not look like normal client request
            --  header blocks.  Static indexing also keeps request blocks small
            --  without introducing dynamic-table stickiness.
            Append (S, Encode_Integer (Exact_Index, 7, 16#80#));
         else
            Name_Index := Static_Name_Index (To_String (Name));
            Prefix := (if Is_Sensitive (To_String (Name)) then 16#10# else 16#00#);
            Append (S, Encode_Integer (Name_Index, 4, Prefix));
            if Name_Index = 0 then
               Append (S, Encode_String_Raw (To_String (Name)));
            end if;
            Append (S, Encode_String_Raw (To_String (Val)));
         end if;
      end loop;

      Output := S;
      return Http_Client.Errors.Ok;
   end Encode_Header_Block;

   function Encode_Literal_Without_Indexing
     (Headers : Http_Client.Headers.Header_List;
      Output  : out Ada.Strings.Unbounded.Unbounded_String)
      return Http_Client.Errors.Result_Status
   is
      E : Encoder := Create_Encoder;
   begin
      return Encode_Header_Block (E, Headers, Output);
   end Encode_Literal_Without_Indexing;

   function Decode_Literal_Without_Indexing
     (Block                 : String;
      Max_Header_List_Size  : Natural;
      Headers               : out Http_Client.Headers.Header_List)
      return Http_Client.Errors.Result_Status
   is
      D : Decoder := Create_Decoder (4_096, Max_Header_List_Size);
   begin
      return Decode_Header_Block (D, Block, Headers);
   end Decode_Literal_Without_Indexing;
end Http_Client.HTTP2.HPACK;
