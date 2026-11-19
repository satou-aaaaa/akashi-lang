# Akashi language spec (v0.4)

Paste this whole file into an LLM prompt to teach it Akashi. It is short on purpose.

## Design rules (why the language looks like this)

1. **One way to write each thing.** No loops (use recursion, `range`, `map`, `filter`, `fold`), no methods, no operator overloading, no implicit conversion.
2. **Everything is checked before running.** Types, names, arguments, capabilities and contracts are checked by `akashi check`.
3. **Every error says how to fix it.** Each diagnostic has a stable code, a position and a `fix` text. See `docs/ERRORS.md`.
4. **Promises are code.** Pure functions must state `ensures` (a promise about `result`) and at least one `example`. Examples run on every `check`. Then `check` also calls every pure function with many generated inputs that satisfy `requires`; a broken `ensures` (R511) or a crash (R512) is reported with the smallest such input.
5. **No ambient authority.** A function can touch the outside world (screen, files) only through a capability it was given as a parameter. Only `main` receives capabilities, from the runtime; nobody can create one.
6. **Outside text never changes the shape of HTML or SQL.** `Html` and `Sql` are built only from a literal template plus values (see below).

## Program

A program is a list of functions. `run` calls `main`.

```
fn name(param: Type, other: Type) -> ReturnType
  requires <Bool expr>      # optional, any number: what the caller must guarantee
  ensures <Bool expr>       # required for pure functions: may use `result`
  example <Bool expr>       # required for pure functions: a call and its expected value
do
  let x: Type = <expr>      # zero or more lines: let, or a Unit expression such as print(...)
  <expr>                    # the last line is the value of the function
end
```

- `main` is `fn main(console: Console) -> Unit do ... end`. Add `folder: Folder` only if the program reads files. It needs no ensures or example.
- A function that takes a capability parameter needs no ensures or example. All other functions are pure.
- Clauses come after `-> Type` and before `do`, in any order.

## Capabilities (authority)

| type | lets you | given by |
| --- | --- | --- |
| `Console` | `print(to: console, value: x)` | always |
| `Folder` | `read_text(from: folder, path: "a.txt")`, read-only, only files inside that folder (no `..`, no absolute paths, no links out) | only when run with `--allow-read <folder>` |

- Pass a capability down as an argument: `report(console: console, total: t)`.
- A capability can only be a parameter: it cannot be stored in `let`, returned, put in a list, or compared (E309).
- `requires`, `ensures` and `example` cannot use capabilities.

## HTML and SQL (injection-safe by construction)

```
html(template: "<li>{}</li>", values: [html_text(value: name)])          # -> Html
sql(template: "SELECT id FROM users WHERE name = ?", values: [name])  # -> Sql
```

- `template` must be a string literal written in the code (E310). Never build it with `++`.
- One value per hole, in order: `{}` for html, `?` for sql (E311 / R510).
- An html hole takes `Html`. Turn a `Str` into `Html` with `html_text(value: s)`, which escapes `< > & " '`. Join pieces with `html_join(parts: [...])`.
- `Sql` keeps the values separate from the query text (parameters), so they are never read as SQL.
- `Html` and `Sql` cannot be joined with `++`. `to_str` / `print` show them.
- There is no `eval` and no way to run code from a string.
- Not covered yet: putting a URL into `href`/`src` (a `javascript:` URL is still possible). Do not put outside values into URL attributes.

## Types

`Int` (whole numbers only, overflow is an error), `Bool`, `Str`, `Unit` (written `()`), `List[T]`, `Html`, `Sql`, and the capabilities `Console`, `Folder`.
There are no decimals, no null and no user-defined types yet.

## Names

- Every `let` has a type: `let total: Int = 0`.
- A name is never reused in the same function (no shadowing, no re-assignment). Pick a new name.
- Names: letters, digits, `_`. Comments start with `#`.

## Calls

All arguments are **named** and written **in the declared order**, for your own functions and built-ins:

```
area(w: 3, h: 4)        # ok
area(3, 4)              # E206
area(h: 4, w: 3)        # E207
```

## Expressions

| kind | syntax |
| --- | --- |
| numbers, text, truth | `42`, `"hi\n"`, `true`, `false`, `()` |
| list | `[1, 2, 3]`, `[]` (the empty list takes its type from `let`) |
| arithmetic (Int only) | `+ - * / %` (`/` truncates toward zero; dividing by 0 is an error) |
| join (Str or List) | `"a" ++ "b"`, `[1] ++ [2]` |
| compare | `== !=` (any type, same on both sides), `< <= > >=` (Int) |
| logic | `and`, `or`, `not`. Mixing `and` with `or` needs parentheses. Comparisons cannot be chained: write `0 <= x and x < 10` |
| if | `if c then a else b end`; `else` is required; every `if` has its own `end` |
| when | several cases with one `end` (prefer this over nested if): `when` / `cond then value` lines / `else value` / `end`. The first true line wins |

Example of `when`:

```
when
  n % 15 == 0 then "FizzBuzz"
  n % 3 == 0 then "Fizz"
  else to_str(value: n)
end
```

## Built-in functions

| call | type |
| --- | --- |
| `print(to: console, value: x)` | any → Unit (needs a Console) |
| `read_text(from: folder, path: p)` | Str (needs a Folder) |
| `lines(text: s)` | List[Str], split at line ends |
| `html(template: "...", values: [...])` | Html (values: List[Html]) |
| `html_text(value: s)` | Html, escaped |
| `html_join(parts: xs)` | Html |
| `sql(template: "...", values: [...])` | Sql (values: List[Str]) |
| `len(list: xs)` | List[T] → Int |
| `str_len(text: s)` | Str → Int |
| `to_str(value: x)` | any → Str |
| `range(from: a, to: b)` | List[Int] from a up to b-1 |
| `get(list: xs, index: i)` | T; index out of range is an error |
| `append(list: xs, item: x)` | List[T] |
| `map(list: xs, func: f)` | f: fn(T) -> U, gives List[U] |
| `filter(list: xs, func: f)` | f: fn(T) -> Bool |
| `fold(list: xs, init: z, func: f)` | f: fn(acc, item) -> acc |

`func:` takes the **name** of one of your pure functions (no lambdas). Its parameters are passed by position.
Recursion deeper than 500 calls is an error; use `range` with `fold` for long repetition.

## Complete example

```
fn add(acc: Int, x: Int) -> Int
  ensures result == acc + x
  example add(acc: 1, x: 2) == 3
do
  acc + x
end

fn sum(xs: List[Int]) -> Int
  ensures len(list: xs) > 0 or result == 0
  example sum(xs: [1, 2, 3]) == 6
  example sum(xs: []) == 0
do
  fold(list: xs, init: 0, func: add)
end

fn main(console: Console) -> Unit
do
  let total: Int = sum(xs: [3, 8, 1])
  print(to: console, value: "total = " ++ to_str(value: total))
end
```

## Commands

```
node bin/akashi.js check file.ak [--json]   # types, names, effects, contracts, and all examples
node bin/akashi.js run file.ak [--json] [--allow-read <folder>]   # check, then run main (requires/ensures are checked on every call)
```
