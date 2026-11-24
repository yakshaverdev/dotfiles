# Replace every ${VAR} in a server object with its literal value.
# Input: the server object. Arg: --slurpfile vals FILE (a JSON object of names
# to values). An empty or missing value is an error so the shell can fail that
# one server and keep going.
def replace_ref($needle; $value):
  split($needle) | join($value);

def walkrefs($vals):
  if type == "string" then
    reduce ([scan("\\$\\{([A-Za-z_][A-Za-z0-9_]*)\\}") | .[0]] | unique[]) as $n (.;
      if (($vals[$n] // "") == "") then
        error("empty:\($n)")
      else
        replace_ref("${" + $n + "}"; ($vals[$n] | tostring))
      end)
  elif type == "object" then
    with_entries(.value |= walkrefs($vals))
  elif type == "array" then
    map(walkrefs($vals))
  else
    .
  end;

$vals[0] as $v | walkrefs($v)
