return {
   build_dir = "build/tealls",
   source_dir = "src",
   include_dir = { "src", "types" },
   module_name = "tealls",

   scripts = {
      build = { pre = "scripts/check-for-teal-types.tl" },
   },
}
