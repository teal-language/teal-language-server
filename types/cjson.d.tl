
local record cjson
   record Null
      userdata
   end
   encode: function({string:any}): string
   decode: function(string): {string:any}
   null: Null
   empty_array_mt: metatable<any>
end

return cjson
