local tested = require("tested")
local Document = require("teal_language_server.document")

tested.test("works on the colon", function()

   local test = [[math.]]
   local doc = Document("test", test, 1, {}, {})

   tested.assert({
      given="math.",
      should="return something expected",
      expected = {
         parent_source = "math.",
         parent_type = "ERROR",
         preceded_by = "math",
         source = ".",
         type = "."
      },
      actual = doc:tree_sitter_token(0, 4)
   })
end)

return tested