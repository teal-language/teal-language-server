
local asserts = require("tea_leaves.asserts")

local Class = {}

function Class.try_get_name(cls)
  return cls.__name
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
  local class = instance.__class
  if class == nil then
    return nil
  end
  return Class.try_get_name(class)
end

function Class.try_get_class_for_instance(obj)
  return obj.__class
end

function Class.get_class_for_instance(obj)
  local cls = Class.try_get_class_for_instance(obj)
  if cls == nil then
    error("Attempted to get class for non-class type!")
  end
  return cls
end

function Class.is_instance(obj, cls)
  return obj.__class == cls
end

function Class.get_class_name_for_instance(instance)
  local name = Class.try_get_class_name_for_instance(instance)
  if name == nil then
    error("Attempted to get class name for non-class type!")
  end
  return name
end

function Class.setup(class, class_name, options)
  class.__name = class_name

  options = options or {}

  -- This is useful sometimes to verify that a given table represents a class
  class.__is_class = true

  if options.attributes ~= nil then
      class._attributes = options.attributes
  end

  if options.interfaces ~= nil then
      class._interfaces = options.interfaces
  end

  if options.getters then
    for k, v in pairs(options.getters) do
      if type(v) == "string" then
        asserts.that(class[v] ~= nil, "Found getter property '{}' mapped to non-existent method '{}' for class '{}'", k, v, class_name)
      end
    end
  end

  local nilable_members = {}

  if options.nilable_members ~= nil then
    for _, value in ipairs(options.nilable_members) do
      nilable_members[value] = true
    end
  end

  if options.setters then
    for k, v in pairs(options.setters) do
      if type(v) == "string" then
        asserts.that(class[v] ~= nil, "Found setter property '{}' mapped to non-existent method '{}' for class '{}'", k, v, class_name)
      end
    end
  end

  -- Assume closed by default
  local is_closed = true

  if options.closed ~= nil and not options.closed then
    is_closed = false
  end

  local is_immutable = false

  if options.immutable ~= nil and options.immutable then
    is_immutable = true
  end

  if is_immutable then
    asserts.that(is_closed, "Attempted to create a non-closed immutable class '{}'.  This is not allowed", class_name)
  end

  local function create_immutable_wrapper(t, class_name)
    local proxy = {}
    local mt = {
        __index = t,
        __newindex = function(t, k, v)
            asserts.fail("Attempted to change field '{}' of immutable class '{}'", k, class_name)
        end,
        __len = function()
            return #t
        end,
        __pairs = function()
            return pairs(t)
        end,
        __ipairs = function()
            return ipairs(t)
        end,
        __tostring = function()
            return tostring(t)
        end
    }
    setmetatable(proxy, mt)
    return proxy
  end

  setmetatable(
     class, {
       __call = function(_, ...)
         local mt = {}
         local instance = setmetatable({ __class = class }, mt)

         -- We need to call __init before defining __newindex below
         -- This is also nice because all classes are required to define
         -- default values for all their members in __init
         if class.__init ~= nil then
           class.__init(instance, ...)
         end

         local tostring_handler = class["__tostring"]
         if tostring_handler ~= nil then
           mt.__tostring = tostring_handler
         end

         mt.__index = function(_, k)
           if options.getters then
             local getter_value = options.getters[k]
             if getter_value then
               if type(getter_value) == "string" then
                 return class[getter_value](instance)
               end

               return getter_value(instance)
             end
           end

           local static_member = class[k]
           if is_closed then
             -- This check means that member values cannot ever be set to nil
             -- So we provide the closed flag to allow for this case
             asserts.that(static_member ~= nil or nilable_members[k] ~= nil, "Attempted to get non-existent member '{}' on class '{}'.  If its valid for the class to have nil members, then pass 'closed=false' to class.setup", k, class_name)
           end
           return static_member
         end

         mt.__newindex = function(_, k, value)
           if is_closed and nilable_members[k] == nil then
             asserts.that(options.setters, "Attempted to set non-existent property '{}' on class '{}'", k, class_name)

             local setter_value = options.setters[k]
             asserts.that(setter_value, "Attempted to set non-existent property '{}' on class '{}'", k, class_name)

             if type(setter_value) == "string" then
               rawget(class, setter_value)(instance, value)
             else
               setter_value(instance, value)
             end
           else
             asserts.that(not is_immutable)
             rawset(instance, k, value)
           end
         end

         if is_immutable then
           return create_immutable_wrapper(instance, class_name)
         end

         return instance
       end,
     }
  )
end

return Class
