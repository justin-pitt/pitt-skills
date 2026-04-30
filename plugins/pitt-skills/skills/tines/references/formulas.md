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
CONCAT("a","b","c")        → "abc"
SIZE("hello")              → 5
CONTAINS(s, "abc")         → true/false
URL_ENCODE(s), URL_DECODE(s)
BASE64_ENCODE(s), BASE64_DECODE(s)
```

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
MAP(arr, LAMBDA(x, x * 2))                # functional map
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

# Build an Authorization header
CONCAT("Bearer ", credential.token)
```

## Gotchas

1. **Slug normalization**: an action named "Fetch User's Data" becomes slug `fetch_users_data`. Apostrophes dropped, spaces → underscores.
2. **Pill in text field stringifies** — see the section at top.
3. **`null` vs `undefined`**: accessing a missing field returns `null`, not an error. Conditions using `IS_EMPTY` or `IS_PRESENT` handle both null and missing.
4. **Date parsing is strict** — if the format string doesn't match exactly, you get `null`.
5. **Formulas don't short-circuit the way code does** — `IF(a, expensive_op_b, c)` evaluates all three arms. Watch for this with heavy network-backed pseudo-functions.
6. **Array indices are 0-based**.
7. **`WHERE` is shorthand for equality only** — for inequality or compound predicates, use `FILTER` with a `LAMBDA`.

## Where to look things up

- Formula docs: https://www.tines.com/docs/formulas/
- The Workbench "internal formula documentation" tool is authoritative and always reflects the current function set. If you're inside a tenant, ask Workbench.
