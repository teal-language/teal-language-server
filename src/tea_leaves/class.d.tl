
-- TODO - change to use generics
local record SetupOptions
   getters:{string:string|function(any):any}
   setters:{string:string|function(any, any)}

   nilable_members: {string}

   interfaces: {any}
   attributes: {string: any}

   -- Closed = no new keys except in __init method
   closed:boolean
   -- Immutable = no changes to values except in __init method
   immutable:boolean
end

local record Class
   setup:function(rec:any, name:string, options:SetupOptions)

   get_name:function(any):string
   try_get_name:function(any):string

   get_class_name_for_instance:function(any):string
   try_get_class_name_for_instance:function(any):string

   get_class_for_instance:function(any):any
   try_get_class_for_instance:function(any):any

   is_instance:function(obj:any, cls:any):boolean
end

return Class
