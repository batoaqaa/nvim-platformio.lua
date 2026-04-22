local function get_metadata(attempts, env)
  local active_env = env or _G.metadata.active_env
  vim.system({ 'pio', 'project', 'metadata', '-e', active_env, '--json-output' }, { text = true }, function(int_obj)
    vim.schedule(function()
      vim.notify('PIO: Fetching metadata ...', vim.log.levels.INFO)

      if int_obj.code ~= 0 then
        -- Schedule notification to avoid error in the system callback thread
        vim.schedule(function()
          if int_obj.code == 127 then
            vim.notify("PIO Manager metadata: 'pio' command not found. Ensure PlatformIO Core is installed.", vim.log.levels.ERROR)
          else
            vim.notify('PIO Manager metadata: Failed to fetch metadata(' .. int_obj.stderr or 'Unknown Error' .. ')', vim.log.levels.WARN)
          end
        end)
        return
      end

      if int_obj.code == 0 and int_obj.stdout then
        local ok, raw_data = pcall(vim.json.decode, int_obj.stdout)
        if ok and raw_data then
          local _, data = next(raw_data)
          if data then
            -- 2. Process cc_compiler
            if data.cc_path then
              _G.metadata.query_driver = ''
              _G.metadata.includes_build = {}
              _G.metadata.includes_comaptlib = {}
              _G.metadata.includes_toolchain = {}
              _G.metadata.cc_flags = {}
              _G.metadata.cxx_path = ''
              _G.metadata.cxx_flags = {}
              _G.metadata.gdb_path = ''
              _G.metadata.defines = {}
              _G.metadata.triplet = ''
              _G.metadata.toolchain_root = ''
              _G.metadata.sysroot = ''
              _G.metadata.cc_compiler = misc.normalizePath(data.cc_path) or ''
              _G.metadata.cc_path = misc.normalizePath(data.cc_path) or ''

              -- 1. Process Includes
              if data.includes then
                for category, paths in pairs(data.includes) do
                  -- 1.1 Process Includes_build
                  if category == 'build' then
                    local includes_build = {}
                    local flag = '-I'
                    for _, path in ipairs(paths) do
                      table.insert(includes_build, string.format('%q', flag .. misc.normalizePath(path)))
                    end
                    _G.metadata.includes_build = includes_build
                  end

                  -- 1.2 Process includes_toolchain
                  if category == 'toolchain' then
                    local includes_toolchain = {}
                    local flag = '-isystem'
                    for _, path in ipairs(paths) do
                      table.insert(includes_toolchain, string.format('%q', flag .. misc.normalizePath(path)))
                    end
                    _G.metadata.includes_toolchain = includes_toolchain
                  end

                  -- 1.3 Process includes_compatlib
                  if category == 'compatlib' then
                    local includes_compatlib = {}
                    local flag = '-isystem'
                    for _, path in ipairs(paths) do
                      table.insert(includes_compatlib, string.format('%q', flag .. misc.normalizePath(path)))
                    end
                    _G.metadata.includes_build = includes_compatlib
                  end
                end
              end

              -- 3. Process cc_flags
              if data.cc_flags then
                local cc_flags = {}
                for _, flag in ipairs(data.cc_flags) do
                  table.insert(cc_flags, string.format('%q', flag))
                end
                _G.metadata.cc_flags = cc_flags
              end

              -- 4. Process cxx_compiler
              if data.cxx_path then
                _G.metadata.cxx_path = misc.normalizePath(data.cxx_path) or ''
              end

              -- 5. Process cxx_flags
              if data.cxx_flags then
                local cxx_flags = {}
                for _, flag in ipairs(data.cxx_flags) do
                  table.insert(cxx_flags, string.format('%q', flag))
                end
                _G.metadata.cxx_flags = cxx_flags
              end

              -- 6. Process gdb_path
              if data.gdb_path then
                _G.metadata.gdb_path = misc.normalizePath(data.gdb_path) or ''
              end

              -- 7. Process Defines
              if data.defines then
                local defines = {}
                for _, define in ipairs(data.defines) do
                  table.insert(defines, string.format('%q', define))
                end
                _G.metadata.defines = defines
              end

              pcall(M.get_sysroot_triplet, _G.metadata.cc_compiler)
              -- print(vim.inspect(_G.metadata))
              -- if callback then
              --   vim.schedule(function()
              --     vim.notify('PIO: Fetching metadata successful', vim.log.levels.INFO)
              --     callback()
              --   end)
              -- end
            end
          end
        else
          vim.schedule(function()
            vim.notify('PIO: Syncing Environment failed', vim.log.levels.WARN)
          end)
        end
      end
      -- RETRY LOGIC: Handles "Error 1" (file busy) or temporary syntax errors during save
      if attempts > 0 then
        vim.defer_fn(function()
          get_metadata(attempts - 1)
        end, 500)
      else
        if callback then
          vim.schedule(function()
            vim.notify('PIO: Fetching metadata successful', vim.log.levels.INFO)
            callback()
          end)
        end
      end
    end)
  end)
end
