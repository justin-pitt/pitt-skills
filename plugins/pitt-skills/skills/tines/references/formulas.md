# Formulas — cheatsheet

Tines formulas are spreadsheet-style expressions used to read and transform data inside action fields. There are ~400 functions. You don't need them all — the ones below cover 95% of real use.

Source: https://www.tines.com/docs/formulas/

## Referencing data

Inside a pill (`<<...>>`) or inside a formula field, reference upstream events by the action's slug:

```
my_action.body                      # entire body of upstream action
my_action.body.user.email           # nested access
my_action.body.items[0]             # array index
event["weird key name"]             # bracket for spaces/special chars
```

Wrapping these references in an action field (URL, payload, headers, prompt, etc.) uses the **`<<...>>` pill delimiter**:

```
<<my_action.body.user.email>>
<<URL_ENCODE(my_action.body.url)>>
<<SWITCH(my_action.body.type, "ip", "IPv4", "domain", "domain", "unknown")>>
```

Not `{{ }}` (silently stripped to empty), not `<% %>` (triggers "Unknown tag" errors). See [gotchas.md](gotchas.md) for why this isn't discoverable from public docs.

The **slug** of an action is its name, lowercased, spaces → underscores, special chars stripped. Renaming an action changes its slug — downstream references break silently. Use test mode to catch this before deploying.

### Pill vs formula field — a common gotcha

- **Pills (`<<...>>`) in text fields** coerce the value to a string. If you pass an object or array through a text field, the downstream action sees `"[object Object]"` or `"[1,2,3]"`.
- **Formula fields** preserve types. Use these whenever you want to pass an object/array/number intact. In formula fields you write expressions directly (no `<<...>>` wrapping).
- A field labeled "Value" accepts either; a field that expects JSON/headers/etc. is usually a formula field.
- **Missing field paths resolve to empty string silently.** `<<foo.bar.baz>>` where `bar` doesn't exist substitutes empty. No warning, no error. Check `/api/v1/actions/{id}/logs` to see the final string Tines actually sent.

## String functions

```
UPCASE("abc")              → "ABC"
DOWNCASE("ABC")            → "abc"
CAPITALIZE("hello world")  → "Hello world"
STRIP("  hi  ")            → "hi"
REPLACE(s, pattern, with)  → substitution (regex supported)
SPLIT("a,b,c", ",")        → ["a","b","c"]
SIZE("hello")              → 5
CONTAINS(s, "abc")         → true/false    (substring only; rejects array args at runtime)
URL_ENCODE(s), URL_DECODE(s)
BASE64_ENCODE(s), BASE64_DECODE(s)
```

**Functions that do NOT exist** (will error at runtime with `Undefined function ...`):

- `String(x)` — use a plain pill `<<x>>` (auto-stringifies in a JSON string slot) or `JOIN([x], '')`.
- `REGEX_MATCH(s, pattern)` — use `IS_PRESENT(REGEX_EXTRACT(s, pattern))` for a boolean test.
- `CONTAINS(arr, value)` — `CONTAINS` is substring-only on strings. For array membership use `SIZE(FILTER(arr, LAMBDA(x, x == value))) > 0`, `WHERE(arr_of_objects, "field", value)`, or a `SWITCH` lookup against a known enum.
- `FORMAT_DATE(d, fmt)` — `NOW()` and date values render as ISO 8601 directly in pills; no wrapper needed.

`validate_story` does not catch any of these; they only fire at action-run time.

## Array functions

```
SIZE([1,2,3])                             → 3
FIRST(arr), LAST(arr)
SORT(arr), SORT(arr, "field")
UNIQ(arr)
FLATTEN(arr_of_arrays)
COMPACT(arr)                               # drop nulls/empties
JOIN(["a","b","c"], ", ")                 → "a, b, c"

FILTER(arr, LAMBDA(x, x > 5))             # functional filter
MAP(arr, "field.subfield")                # dotted-path: extract one field per element (auto-flattens nested arrays one level)
MAP_LAMBDA(arr, item.field)               # explicit per-item expression — `item` is the iterator name
MAP(arr, LAMBDA(x, x * 2))                # LAMBDA form — docs-correct but rejected at runtime on at least one tenant
                                          #   ("map: path should be a string, but it was an object"); prefer the two forms above
WHERE(arr_of_objects, "field", value)     # shorthand filter by field equality
```

## Date/time

```
NOW()                                      # current time; renders as ISO 8601 in pills
DATE(2026, 4, 17)
DATE_DIFF(d1, d2, "days")                 # also "hours", "minutes", "seconds"
UNIX_TIMESTAMP(d)                         # integer seconds
PARSE_DATE("2026-04-17", "%Y-%m-%d")
```

⚠️ **`FORMAT_DATE` does not exist** as a Tines formula function. `NOW()` renders as ISO 8601 directly when substituted into a pill — no wrapper needed. If you need a non-ISO format, experiment with variants against the live tenant (formula naming is inconsistently documented) or use string manipulation on `NOW()`'s output.

## Parsing

```
JSON_PARSE(text)                           # text → object
JSONPATH(obj, "$.data.users[*].email")     # JSONPath extraction
CSV_PARSE(text)
XML_PARSE(text)
YAML_PARSE(text)
```

## Conditional / lambdas

```
IF(cond, if_true, if_false)
AND(a, b, c)
OR(a, b, c)
NOT(x)
SWITCH(val, case1, v1, case2, v2, default) # default is REQUIRED (omitting it errors)

LAMBDA(x, expr)                            # used inside MAP/FILTER/WHERE
```

## Crypto / auth

```
SHA256(s)
MD5(s)
HMAC_SHA256(data, key)
JWT_SIGN(payload, key, "HS256")
JWT_DECODE(token)
AES_ENCRYPT(data, key)
```

## Object construction

```
OBJECT("name", user.name, "email", user.email)    # build object literal
MERGE(obj1, obj2)                                  # object merge
KEYS(obj), VALUES(obj)
```

## Worked examples

```ruby
# Fallback for missing data
IF(user.email, user.email, "unknown@example.com")

# Build an alert normalization object
OBJECT(
  "id", alert.id,
  "severity", UPCASE(alert.severity),
  "hostname", DOWNCASE(alert.host),
  "first_seen", PARSE_DATE(alert.timestamp, "%Y-%m-%dT%H:%M:%SZ")
)

# Filter critical indicators and extract IDs
MAP(
  WHERE(iocs, "severity", "critical"),
  LAMBDA(ioc, ioc.id)
)

# Safely read nested optional field
IF(response.body.data, JSONPATH(response.body, "$.data.users[0].email"), null)

# Hash a PII field for logging
OBJECT("user_hash", SHA256(DOWNCASE(STRIP(user.email))))

# Compute time since an event in hours
DATE_DIFF(PARSE_DATE(alert.timestamp, "%Y-%m-%dT%H:%M:%SZ"), NOW(), "hours")

# Build an Authorization header (string concat needs JOIN — see gotcha #8 below)
JOIN(["Bearer ", credential.token], "")

# Cases v2 PATCH: null = no-change, '' = destructive (see gotchas #28, #31)
# Use formula form with null fallback so the JSON null reaches the API.
"description":   "=DEFAULT(receive.body.fields.ai_summary, null)"
"sub_status_id": "=IF(IS_PRESENT(receive.body.fields.ai_verdict), 464168, null)"
```

## Gotchas

1. **Slug normalization**: an action named "Fetch User's Data" becomes slug `fetch_users_data`. Apostrophes dropped, spaces → underscores.
2. **Pill in text field stringifies** — see the section at top.
3. **`null` vs `undefined`**: accessing a missing field returns `null`, not an error. Conditions using `IS_EMPTY` or `IS_PRESENT` handle both null and missing.
4. **Date parsing is strict** — if the format string doesn't match exactly, you get `null`.
5. **Formulas don't short-circuit the way code does** — `IF(a, expensive_op_b, c)` evaluates all three arms. Watch for this with heavy network-backed pseudo-functions.
6. **Array indices are 0-based**.
7. **`WHERE` is shorthand for equality only** — for inequality or compound predicates, use `FILTER` with a `LAMBDA`.
8. **String concat needs `JOIN`, not `CONCAT` or `+`.** `CONCAT` is array-only at runtime (`CONCAT(["a","b","c"])` → `["a","b","c"]`, not `"abc"`). Calling it with scalar string args errors with `Invalid arguments to CONCAT, expected arrays`. `+` is number-only and rejects text with `Could not convert object of type Text to a number`. The correct primitive inside a formula is `JOIN(array, separator)` — e.g. `JOIN(["Bearer ", credential.token], "")` or `JOIN([vendor, external_id], " ")`. Outside a formula (a top-level field value), chain pills inline in plain text: `"<<a>> <<b>>"`. `validate_story` does not catch the bad cases; the runtime is the only signal.
9. **Functions that look like they should exist but don't:** `String(x)`, `REGEX_MATCH(s, pattern)`, `CONTAINS(arr, value)`, `FORMAT_DATE(d, fmt)`. See the "Functions that do NOT exist" block under String functions for the alternatives. All four error at runtime with `Undefined function ...`; `validate_story` does not catch them.
10. **`MAP` has three forms; the LAMBDA form may be unreliable.** Prefer `MAP(arr, "dotted.path")` for plain field extraction or `MAP_LAMBDA(arr, item.expr)` for per-item expressions. The standard `MAP(arr, LAMBDA(x, expr))` form is docs-correct but has been observed to fail at runtime on at least one tenant (`map: path should be a string, but it was an object`). Probe before relying on it.
11. **Cases v2 PATCH treats `null` and `""` very differently.** `null` is "no-change"; `""` either 422s (on integer-ID fields like `sub_status_id`) or destructively clears the field (on text fields like `description`). Pair this with gotcha #28 (silent error logging) and the common destructive Tines pattern `<<DEFAULT(..., '')>>` quietly wipes case fields. Use formula form `=DEFAULT(..., null)` instead. See the worked example above and gotcha #31 for the full behavior table.

## Where to look things up

- Formula docs: https://www.tines.com/docs/formulas/
- The Workbench "internal formula documentation" tool is authoritative and always reflects the current function set. If you're inside a tenant, ask Workbench.
