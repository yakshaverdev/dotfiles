# Replace every ${VAR} in a server object with its literal value.
# Input: the server object. Arg: --slurpfile vals FILE (a JSON object of names
# to values). An empty or missing value is an error so the shell can fail that
# one server and keep going.
def refnames:
  [scan("\\$\\{([A-Za-z_][A-Za-z0-9_]*)\\}") | .[0]];

def walkrefs($vals):
  if type == "string" then
    # Check first, then replace every reference in one pass over the original
    # string: a value that itself contains ${VAR} must not be expanded again.
    ([refnames[] | select(($vals[.] // "") == "")] | .[0]) as $missing
    | if $missing != null then
        error("empty:\($missing)")
      else
        gsub("\\$\\{(?<n>[A-Za-z_][A-Za-z0-9_]*)\\}"; ($vals[.n] | tostring))
      end
  elif type == "object" then
    with_entries(.value |= walkrefs($vals))
  elif type == "array" then
    map(walkrefs($vals))
  else
    .
  end;

$vals[0] as $v | walkrefs($v)
