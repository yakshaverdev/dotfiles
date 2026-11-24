# Translate one source MCP server into Codex's `mcp_servers.<name>` fields.
# Input: the server object. Args: --arg name NAME and --arg format json|toml.
#
# Codex has no general ${VAR} expansion, so references are mapped onto its
# native fields:
#   Authorization: Bearer ${VAR}  -> bearer_token_env_var
#   <Header>: ${VAR}              -> env_http_headers
#   literal header                -> http_headers
#   env value ${VAR}              -> env_vars
#   literal env value             -> [mcp_servers.<name>.env]
# Anything else that mixes a literal and a reference fails this one server.
def hasref:
  test("\\$\\{[A-Za-z_][A-Za-z0-9_]*\\}");

def refname:
  capture("^\\$\\{(?<n>[A-Za-z_][A-Za-z0-9_]*)\\}$") | .n;

def table:
  if .kind == "http" then
    "[mcp_servers.\(.name)]\n"
    + "url = \(.url | tojson)\n"
    + (if .bearer_token_env_var != null
       then "bearer_token_env_var = \(.bearer_token_env_var | tojson)\n"
       else "" end)
    + (if ((.http_headers // {}) | length) > 0 then
         "[mcp_servers.\(.name).http_headers]\n"
         + ([.http_headers | to_entries[] | "\(.key | tojson) = \(.value | tojson)\n"] | join(""))
       else "" end)
    + (if ((.env_http_headers // {}) | length) > 0 then
         "[mcp_servers.\(.name).env_http_headers]\n"
         + ([.env_http_headers | to_entries[] | "\(.key | tojson) = \(.value | tojson)\n"] | join(""))
       else "" end)
  else
    "[mcp_servers.\(.name)]\n"
    + "command = \(.command | tojson)\n"
    + (if ((.args // []) | length) > 0
       then "args = [\([.args[] | tojson] | join(", "))]\n"
       else "" end)
    + (if ((.env_vars // []) | length) > 0
       then "env_vars = [\([.env_vars[] | tojson] | join(", "))]\n"
       else "" end)
    + (if ((.env // {}) | length) > 0 then
         "[mcp_servers.\(.name).env]\n"
         + ([.env | to_entries[] | "\(.key | tojson) = \(.value | tojson)\n"] | join(""))
       else "" end)
  end;

if type != "object" then
  error("server is not an object")
elif (.["type"] // "") == "http" then
  if ((.url // "") | length) == 0 then
    error("http server has no url")
  elif (.url | hasref) then
    error("http url uses ${VAR}; Codex cannot expand it")
  else
    . as $s
    | (reduce (($s.headers // {}) | to_entries[]) as $h
        ({bearer: null, http: {}, envh: {}, bad: null};
         $h.value as $v
         | if (($h.key | ascii_downcase) == "authorization")
              and ($v | test("^Bearer \\$\\{[A-Za-z_][A-Za-z0-9_]*\\}$"))
           then .bearer = ($v | sub("^Bearer "; "") | refname)
           elif ($v | test("^\\$\\{[A-Za-z_][A-Za-z0-9_]*\\}$"))
           then .envh[$h.key] = ($v | refname)
           elif ($v | hasref)
           then .bad = "header \($h.key) mixes a literal and a ${...} reference"
           else .http[$h.key] = $v
           end))
    | if .bad != null then error(.bad) else del(.bad) end
    | .name = $name
    | .kind = "http"
    | .url = $s.url
    | (if .bearer == null then del(.bearer) else .bearer_token_env_var = .bearer | del(.bearer) end)
    | (if (.http | length) == 0 then del(.http) else .http_headers = .http | del(.http) end)
    | (if (.envh | length) == 0 then del(.envh) else .env_http_headers = .envh | del(.envh) end)
  end
elif ((.command // "") | length) > 0 then
  if (.command | hasref) then
    error("stdio command uses ${VAR}; Codex cannot expand it")
  elif ([.args // [] | .[] | hasref] | any) then
    error("stdio args use ${VAR}; Codex cannot expand it")
  else
    . as $s
    | (reduce (($s.env // {}) | to_entries[]) as $e
        ({env: {}, env_vars: [], bad: null};
         $e.value as $v
         | if ($v | test("^\\$\\{[A-Za-z_][A-Za-z0-9_]*\\}$"))
           then .env_vars += [$v | refname]
           elif ($v | hasref)
           then .bad = "env \($e.key) mixes a literal and a ${...} reference"
           else .env[$e.key] = $v
           end))
    | if .bad != null then error(.bad) else del(.bad) end
    | .name = $name
    | .kind = "stdio"
    | .command = $s.command
    | .args = ($s.args // [])
    | (if (.env | length) == 0 then del(.env) else . end)
    | (if (.env_vars | length) == 0 then del(.env_vars) else .env_vars |= unique end)
  end
else
  error("server has neither type=http nor a command")
end
| if $format == "toml" then table else . end
