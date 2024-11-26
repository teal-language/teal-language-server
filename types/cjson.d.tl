
local record cjson
   record Null
      userdata
   end
   encode: function({string:any}): string
   decode: function(string): {string:any}
   null: Null
end

return cjson
