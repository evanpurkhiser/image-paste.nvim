local M = {}
local api = vim.api

local options = {
  imgur_client_id = "",
  paste_script = [[osascript -e "get the clipboard as «class PNGf»" | sed "s/«data PNGf//; s/»//" | xxd -r -p]],
  image_name = "clipboard.png",
}

function M.paste_image()
  local template = "![%s](%s)"
  local placeholder_alt = string.format("Uploading %s…", options.image_name)
  local placeholder = string.format(template, placeholder_alt, "")

  -- Inserrt the upload template
  local buffer = api.nvim_get_current_buf()
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local line = api.nvim_get_current_line()
  local nline = line:sub(0, col) .. placeholder .. line:sub(col + 1)
  api.nvim_set_current_line(nline)

  -- Mark the location of the template for replacing later
  local mark_ns = api.nvim_create_namespace("image_upload")
  local mark_id = api.nvim_buf_set_extmark(
    buffer,
    mark_ns,
    row - 1,
    col,
    { end_col = col + placeholder:len(), hl_group = "Whitespace" }
  )

  local command = string.format(
    [[%s \
      | curl --silent \
        --request POST \
        --form "image=@-" \
        --header "Authorization: Client-ID %s" \
        "https://api.imgur.com/3/upload" \
      | jq --raw-output .data.link
  ]],
    options.paste_script,
    options.imgur_client_id
  )

  local url = ""

  -- Start uploading
  vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_stdout = function(id, data)
      url = vim.fn.join(data):gsub("^%s*(.-)%s*$", "%1")
    end,
    on_exit = function(id, exit_code)
      local replacement = ""
      if exit_code ~= 0 then
        error("Failed to upload or paste image")
      else
        replacement = string.format(template, options.image_name, url)
      end

      local mark_row, mark_col =
        unpack(api.nvim_buf_get_extmark_by_id(buffer, mark_ns, mark_id, {}))

      -- Handle updating the line containing the mark
      api.nvim_buf_del_extmark(buffer, mark_ns, mark_id)
      api.nvim_buf_set_text(
        buffer,
        mark_row,
        mark_col,
        mark_row,
        mark_col + placeholder:len(),
        { replacement }
      )
    end,
  })
end

function M.setup(opts)
  options = vim.tbl_deep_extend("force", options, opts or {})

  if options.imgur_client_id == "" then
    error("Missing imgur_client_id in image-paste.nvim")
  end
end

return M
