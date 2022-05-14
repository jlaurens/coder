local CDR=_ENV.CDR

CDR:activate_test(true)
local callback_push = CDR.TEST.callback_push
local Block = CDR.TEST.Block
debug_msg = function(...)
  print('**** **** CDR DEBUG', ...)
end
local Block_import_begin = Block.import_begin
function Block:import_begin ()
  local resume
  resume, self.synchronize = CDR:coroutine_create(Block_import_begin)
  resume()
end


function Block:synctex_tag_catch(path)
  debug_msg('synctex_tag_catch...', path)
    local pop
    pop = callback_push(
      'open_read_file',
      function (file_name)
  debug_msg('synctex_tag_catch open_read_file', file_name)
        return {
          reader = function (env)
            function env.close ()
              self.synctex_tag_catched = tex.get_synctex_tag()
              pop()
              debug_msg('synctex_tag_catched', self.synctex_tag_catched)
            end
          end,
        }
      end,
      'CDRBlockImport'
    )
    tex.runtoks(function()
      debug_msg('\\input{'..path..'}')
      tex.sprint('\\input{'..path..'}')
    end)
    texio.write_nl('NORMALY FOUND')
  end
  