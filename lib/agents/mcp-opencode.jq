# Translate one source MCP server into an OpenCode `mcp.<name>` value.
# Input: the server object from a .mcp.json file. `${VAR}` becomes `{env:VAR}`.
def envrefs:
  gsub("\\$\\{(?<n>[A-Za-z_][A-Za-z0-9_]*)\\}"; "{env:\(.n)}");

if type != "object" then
  error("server is not an object")
elif (.["type"] // "") == "http" then
  if ((.url // "") | length) == 0 then
    error("http server has no url")
  else
    {type: "remote", url: (.url | envrefs), enabled: true}
    + (if ((.headers // {}) | length) > 0
       then {headers: (.headers | map_values(envrefs))}
       else {} end)
  end
elif ((.command // "") | length) > 0 then
  {type: "local", command: ([.command] + (.args // []) | map(envrefs)), enabled: true}
  + (if ((.env // {}) | length) > 0
     then {environment: (.env | map_values(envrefs))}
     else {} end)
else
  error("server has neither type=http nor a command")
end
