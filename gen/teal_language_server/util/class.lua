local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pairs = _tl_compat and _tl_compat.pairs or pairs
local asserts = require("teal_language_server.util.asserts")











local Class = {}














function Class.try_get_name(cls)
   return (cls)["__name"]
end

function Class.get_name(cls)
   local name = Class.try_get_name(cls)
   if name == nil then
      error("Attempted to get class name for non-class type!")
   end
   return name
end

function Class.try_get_class_name_for_instance(instance)
   if instance == nil or type(instance) ~= "table" then
      return nil
   end
   local cls = (instance)["__class"]
   if cls == nil then
      return nil
   end
   return Class.try_get_name(cls)
end

function Class.try_get_class_for_instance(obj)
   return (obj)["__class"]
end

function Class.get_class_for_instance(obj)
   local cls = Class.try_get_class_for_instance(obj)
   if cls == nil then
      error("Attempted to get class for non-class type!")
   end
   return cls
end

function Class.is_instance(obj, cls)
   return (obj)["__class"] == (cls)
end

function Class.get_class_name_for_instance(instance)
   local name = Class.try_get_class_name_for_instance(instance)
   if name == nil then
      error("Attempted to get class name for non-class type!")
   end
   return name
end

function Class.setup(rec, name, options)
   local cls = rec
   local opts = (options or {})

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
            asserts.that(cls[v] ~= nil, "Found getter property '{}' mapped to non-existent method '{}' for class '{}'", k, v, name)
         end
      end
   end

   local nilable_members = {}

   if opts.nilable_members ~= nil then
      for _, value in ipairs(opts.nilable_members) do
         nilable_members[value] = true
      end
   end

   if opts.setters then
      for k, v in pairs(opts.setters) do
         if type(v) == "string" then
            asserts.that(cls[v] ~= nil, "Found setter property '{}' mapped to non-existent method '{}' for class '{}'", k, v, name)
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

   local raw_setmt = setmetatable

   local function create_immutable_wrapper(t, wrapper_name)
      local proxy = {}
      raw_setmt(proxy, {
         __index = t,
         __newindex = function(_t, k, _v)
            asserts.fail("Attempted to change field '{}' of immutable class '{}'", k, wrapper_name)
         end,
         __len = function()
            return #(t)
         end,
         __pairs = function()
            return pairs(t)
         end,
         __ipairs = function()
            return ipairs(t)
         end,
         __tostring = function()
            return tostring(t)
         end,
      })
      return proxy
   end

   raw_setmt(cls, {
      __call = function(_self, ...)
         local instance_mt = {}
         local instance = raw_setmt({ __class = cls }, instance_mt)

         if cls["__init"] ~= nil then
            (cls["__init"])(instance, ...)
         end

         local tostring_handler = cls["__tostring"]
         if tostring_handler ~= nil then
            instance_mt["__tostring"] = tostring_handler
         end

         instance_mt["__index"] = function(_, k)
            if opts.getters then
               local getter_value = opts.getters[k]
               if getter_value then
                  if type(getter_value) == "string" then
                     return (cls[getter_value])(instance)
                  end
                  return (getter_value)(instance)
               end
            end

            local static_member = cls[k]
            if is_closed then
               asserts.that(
               static_member ~= nil or nilable_members[k] ~= nil,
               "Attempted to get non-existent member '{}' on class '{}'.  If its valid for the class to have nil members, then pass 'closed=false' to class.setup",
               k, name)

            end
            return static_member
         end

         instance_mt["__newindex"] = function(_, k, value)
            if is_closed and nilable_members[k] == nil then
               local setters = opts.setters
               asserts.that(setters ~= nil, "Attempted to set non-existent property '{}' on class '{}'", k, name)
               if setters then
                  local setter_value = setters[k]
                  asserts.that(setter_value ~= nil, "Attempted to set non-existent property '{}' on class '{}'", k, name)
                  if type(setter_value) == "string" then
                     (cls[setter_value])(instance, value)
                  else
                     (setter_value)(instance, value)
                  end
               end
            else
               asserts.that(not is_immutable)
               local raw_rawset = rawset
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
