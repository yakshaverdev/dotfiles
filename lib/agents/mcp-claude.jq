# Translate one source MCP server into the JSON that `claude mcp add-json` takes.
# Input: the server object from a .mcp.json file. `${VAR}` stays as-is because
# Claude Code expands it from the agent process environment.
if type != "object" then
  error("server is not an object")
elif (.["type"] // "") == "http" then
  if ((.url // "") | length) == 0 then
    error("http server has no url")
  else
    {type: "http", url: .url}
    + (if ((.headers // {}) | length) > 0 then {headers: .headers} else {} end)
  end
elif ((.command // "") | length) > 0 then
  {command: .command}
  + (if ((.args // []) | length) > 0 then {args: .args} else {} end)
  + (if ((.env // {}) | length) > 0 then {env: .env} else {} end)
else
  error("server has neither type=http nor a command")
end
