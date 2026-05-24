
local asserts <const> = require("teal_language_server.asserts")

local record SetupOptions
   getters: {string: string | function(any): any}
   setters: {string: string | function(any, any)}
   nilable_members: {string}
   interfaces: {any}
   attributes: {string: any}
   closed: boolean
   immutable: boolean
end

local record Class
   setup: function<T>(rec: T, name: string, options?: SetupOptions)

   get_name: function(cls: any): string
   try_get_name: function(cls: any): string | nil

   get_class_name_for_instance: function(instance: any): string
   try_get_class_name_for_instance: function(instance: any): string | nil

   get_class_for_instance: function<T>(obj: any): T
   try_get_class_for_instance: function<T>(obj: any): T | nil

   is_instance: function<T>(obj: any, cls: T): boolean
end

function Class.try_get_name(cls: any): string | nil
   return (cls as {string: any})["__name"] as string | nil
end

function Class.get_name(cls: any): string
   local name = Class.try_get_name(cls)
   if name == nil then
      error("Attempted to get class name for non-class type!")
   end
   return name
end

function Class.try_get_class_name_for_instance(instance: any): string | nil
   if instance == nil or type(instance) ~= "table" then
      return nil
   end
   local cls = (instance as {string: any})["__class"]
   if cls == nil then
      return nil
   end
   return Class.try_get_name(cls)
end

function Class.try_get_class_for_instance<T>(obj: any): T | nil
   return (obj as {string: any})["__class"] as T | nil
end

function Class.get_class_for_instance<T>(obj: any): T
   local cls = Class.try_get_class_for_instance(obj) as T | nil
   if cls == nil then
      error("Attempted to get class for non-class type!")
   end
   return cls
end

function Class.is_instance<T>(obj: any, cls: T): boolean
   return (obj as {string: any})["__class"] == (cls as any)
end

function Class.get_class_name_for_instance(instance: any): string
   local name = Class.try_get_class_name_for_instance(instance)
   if name == nil then
      error("Attempted to get class name for non-class type!")
   end
   return name
end

function Class.setup<T>(rec: T, name: string, options?: SetupOptions)
   local cls = rec as {string: any}
   local opts = (options or {}) as SetupOptions

   cls["__name"] = name
   cls["__is_class"] = true

   if opts.attributes ~= nil then
      cls["_attributes"] = opts.attributes
   end

   if opts.interfaces ~= nil then
      cls["_interfaces"] = opts.interfaces
   end

   if opts.getters then
      for k, v in pairs(opts.getters) do
         if type(v) == "string" then
            asserts.that(cls[v as string] ~= nil, "Found getter property '{}' mapped to non-existent method '{}' for class '{}'", k, v, name)
         end
      end
   end

   local nilable_members: {string: boolean} = {}

   if opts.nilable_members ~= nil then
      for _, value in ipairs(opts.nilable_members) do
         nilable_members[value] = true
      end
   end

   if opts.setters then
      for k, v in pairs(opts.setters) do
         if type(v) == "string" then
            asserts.that(cls[v as string] ~= nil, "Found setter property '{}' mapped to non-existent method '{}' for class '{}'", k, v, name)
         end
      end
   end

   local is_closed = true
   if opts.closed ~= nil and not opts.closed then
      is_closed = false
   end

   local is_immutable = false
   if opts.immutable ~= nil and opts.immutable then
      is_immutable = true
   end

   if is_immutable then
      asserts.that(is_closed, "Attempted to create a non-closed immutable class '{}'.  This is not allowed", name)
   end

   local raw_setmt = setmetatable as function(any, any): any

   local function create_immutable_wrapper(t: {string: any}, wrapper_name: string): {string: any}
      local proxy: {string: any} = {}
      raw_setmt(proxy, {
         __index = t,
         __newindex = function(_t: any, k: any, _v: any)
            asserts.fail("Attempted to change field '{}' of immutable class '{}'", k, wrapper_name)
         end,
         __len = function(): integer
            return #(t as {integer: any})
         end,
         __pairs = function(): (function({string: any}, string): (string, any), {string: any}, string)
            return pairs(t)
         end,
         __ipairs = function(): (function({any}, integer): (integer, any), {any}, integer)
            return ipairs(t as {any})
         end,
         __tostring = function(): string
            return tostring(t)
         end,
      })
      return proxy
   end

   raw_setmt(cls, {
      __call = function(_self: any, ...: any): any
         local instance_mt: {string: any} = {}
         local instance = raw_setmt({__class = cls}, instance_mt) as {string: any}

         if cls["__init"] ~= nil then
            (cls["__init"] as function(any, ...: any))(instance, ...)
         end

         local tostring_handler = cls["__tostring"]
         if tostring_handler ~= nil then
            instance_mt["__tostring"] = tostring_handler
         end

         instance_mt["__index"] = function(_: any, k: any): any
            if opts.getters then
               local getter_value = opts.getters[k as string]
               if getter_value then
                  if type(getter_value) == "string" then
                     return (cls[getter_value as string] as function(any): any)(instance)
                  end
                  return (getter_value as function(any): any)(instance)
               end
            end

            local static_member = cls[k as string]
            if is_closed then
               asserts.that(
                  static_member ~= nil or nilable_members[k as string] ~= nil,
                  "Attempted to get non-existent member '{}' on class '{}'.  If its valid for the class to have nil members, then pass 'closed=false' to class.setup",
                  k, name
               )
            end
            return static_member
         end

         instance_mt["__newindex"] = function(_: any, k: any, value: any)
            if is_closed and nilable_members[k as string] == nil then
               local setters = opts.setters
               asserts.that(setters ~= nil, "Attempted to set non-existent property '{}' on class '{}'", k, name)
               if setters then
                  local setter_value = setters[k as string]
                  asserts.that(setter_value ~= nil, "Attempted to set non-existent property '{}' on class '{}'", k, name)
                  if type(setter_value) == "string" then
                     (cls[setter_value as string] as function(any, any))(instance, value)
                  else
                     (setter_value as function(any, any))(instance, value)
                  end
               end
            else
               asserts.that(not is_immutable)
               local raw_rawset = rawset as function(any, any, any)
               raw_rawset(instance, k, value)
            end
         end

         if is_immutable then
            return create_immutable_wrapper(instance, name)
         end

         return instance
      end,
   })
end

return Class
