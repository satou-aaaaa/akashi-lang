# Akashi language spec (v0.7)

Paste this whole file into an LLM prompt to teach it Akashi. It is short on purpose.

## Design rules (why the language looks like this)

1. **One way to write each thing.** No loops (use recursion, `range`, `map`, `filter`, `fold`), no methods, no operator overloading, no implicit conversion.
2. **Everything is checked before running.** Types, names, arguments, capabilities and contracts are checked by `akashi check`.
3. **Every error says how to fix it.** Each diagnostic has a stable code, a position and a `fix` text. See `docs/ERRORS.md`.
4. **Promises are code.** Pure functions must state `ensures` (a promise about `result`) and at least one `example`. Examples run on every `check`. Then `check` also calls every pure function with many generated inputs that satisfy `requires`; a broken `ensures` (R511) or a crash (R512) is reported with the smallest such input.
5. **No ambient authority.** A function can touch the outside world (screen, files) only through a capability it was given as a parameter. Only `main` receives capabilities, from the runtime; nobody can create one.
6. **Outside text never changes the shape of HTML or SQL.** `Html` and `Sql` are built only from a literal template plus values (see below).
7. **No null, no exceptions to forget.** A value that may be missing is `Option[T]`; an operation that may fail returns `Result[T]`. You get the value out only with `match`, which must handle every case.

## Program

A program is a list of functions and types (`type`, see below), in any order. `run` calls `main`.

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

- `main` is `fn main(console: Console) -> Unit do ... end`. Add `folder: Folder` only if the program reads files, and `out: OutFolder` only if it writes files. It needs no ensures or example.
- A function that takes a capability parameter needs no ensures or example. All other functions are pure.
- Clauses come after `-> Type` and before `do`, in any order.

### Several files

```
use "lib/words.ak"          # only at the top of a file, before any fn or type
```

- The path is relative to the file with the `use` line, ends in `.ak`, and stays inside the folder of the main file (no `..`, no absolute path: E113). A missing file is E114.
- All functions and types of all used files form one program. Names must be unique across all files (E203). Using a file twice reads it once.
- Only the file you run has `main` (E115).

## Capabilities (authority)

| type | lets you | given by |
| --- | --- | --- |
| `Console` | `print(to: console, value: x)` | always |
| `Folder` | `read_text(from: folder, path: "a.txt")` → `Result[Str]`, read-only, only files inside that folder (no `..`, no absolute paths, links are never followed) | only when run with `--allow-read <folder>` |
| `OutFolder` | `write_text(to: out, path: "a.txt", text: s)` → `Result[Unit]`, creates or replaces one file inside that folder (never creates folders, never deletes, links are never followed); `write_bytes` writes raw bytes | only when run with `--allow-write <folder>` |

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
- A `{}` may only be between tags or inside a quoted attribute value (E312). Not inside a tag, an unquoted value, `<script>`/`<style>`, a comment, `on…`, `style`, `srcdoc` or `srcset`.
- In a URL attribute (`href`, `src`, `action`, ...) the template must fix how the URL starts before the hole: `href="/users/{}"`, `href="?q={}"`, `href="mailto:{}"`. `href="{}"` is E312 (it could become `javascript:`).

## Types

`Int` (whole numbers only, overflow is an error), `Bool`, `Str`, `Unit` (written `()`), `List[T]`, `Dict[T]` (keys are always Str, kept in code point order), `Option[T]`, `Result[T]`, `Html`, `Sql`, the capabilities `Console`, `Folder`, and your own types.
There are no decimals and no null.

## Your own types and match

```
type Shape
  case Circle(radius: Int)
  case Rect(width: Int, height: Int)
  case Dot
end
```

- Type and case names start with a capital letter. A record is a type with one case. Types may refer to themselves (trees).
- Build a value like a call, with named fields in order: `Rect(width: 2, height: 3)`. A case without fields is just its name: `Dot`.
- Case names are unique in the whole program. Fields cannot hold capabilities (E309).
- `==` compares values field by field. `print` shows `Rect(width: 2, height: 3)`.

Read a value only with `match`:

```
match shape
  case Circle(radius: r) then 3 * r * r
  case Rect(width: w, height: h) then w * h
  case Dot then 0
end
```

- Every case of the type appears exactly once (missing: E210). There is no `else` and no `_` case (E211), so adding a case later shows every `match` that must handle it.
- A pattern lists all fields of the case in declared order (E212). Give each field a new name, or `_` to ignore it.
- Each line is `case Pattern then value`; all lines give the same type.

Built-in types (no need to declare):

| type | cases | use |
| --- | --- | --- |
| `Option[T]` | `Some(value: T)`, `None` | a value that may be missing (instead of null) |
| `Result[T]` | `Ok(value: T)`, `Err(message: Str)` | an operation that may fail (instead of exceptions) |

An `Option` or `Result` is not its value: `parse_int(text: s) + 1` is E201. Use `match`.

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
| match | `match x` / `case Pattern then value` lines / `end` (see above) |
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
| `read_text(from: folder, path: p)` | Result[Str] (needs a Folder); a missing file is `Err` |
| `write_text(to: out, path: p, text: s)` | Result[Unit] (needs an OutFolder); a missing parent folder is `Err` |
| `write_bytes(to: out, path: p, bytes: xs)` | Result[Unit], writes raw bytes (each item 0..255, else R506), e.g. a .wasm file |
| `parse_int(text: s)` | Option[Int]; `None` unless s is a whole number (spaces around are ok) |
| `lines(text: s)` | List[Str], split at line ends |
| `html(template: "...", values: [...])` | Html (values: List[Html]) |
| `html_text(value: s)` | Html, escaped |
| `html_join(parts: xs)` | Html |
| `sql(template: "...", values: [...])` | Sql (values: List[Str]) |
| `len(list: xs)` | List[T] → Int |
| `str_len(text: s)` | Str → Int |
| `slice(text: s, from: a, to: b)` | Str, characters a..b-1 (code points); out of range is R506 |
| `code_of(char: c)` | Int, the code point of one character (R506 if not exactly one) |
| `char_of(code: n)` | Str, one character from a code point (R506 if not a valid code point) |
| `to_str(value: x)` | any → Str |
| `range(from: a, to: b)` | List[Int] from a up to b-1 |
| `at(list: xs, index: i)` | Option[T]; `None` when i is out of range (prefer this) |
| `get(list: xs, index: i)` | T; out of range is an error, so only use it after checking `i < len(list: xs)` |
| `find(list: xs, func: f)` | Option[T], the first item where f gives true |
| `append(list: xs, item: x)` | List[T] (copies; to build a long list, collect small lists and `concat`) |
| `concat(lists: xss)` | List[T] (joins a list of lists, linear time) |
| `reverse(list: xs)` | List[T] |
| `take(list: xs, count: n)` / `drop(list: xs, count: n)` | List[T]; first n items / all but the first n (n < 0 is an error) |
| `sort(list: xs)` | List[Int], ascending |
| `sum(list: xs)` | Int |
| `max(list: xs)` / `min(list: xs)` | Option[Int]; None for [] |
| `any(list: xs, func: f)` / `all(list: xs, func: f)` | Bool |
| `chars(text: s)` | List[Str], one per character |
| `split(text: s, by: sep)` | List[Str] (sep must not be "") |
| `join(parts: xs, by: sep)` | Str |
| `contains(text: s, part: p)` / `starts_with(text: s, prefix: p)` / `ends_with(text: s, suffix: p)` | Bool |
| `dict(keys: ks, values: vs)` | Dict[T]; R506 if the counts differ or a key appears twice |
| `dict_put(dict: d, key: k, value: v)` | Dict[T], a new dictionary with k set to v |
| `dict_get(dict: d, key: k)` | Option[T]; `None` if k is missing |
| `dict_has(dict: d, key: k)` | Bool |
| `dict_remove(dict: d, key: k)` | Dict[T] without k (unchanged if missing) |
| `dict_keys(dict: d)` / `dict_values(dict: d)` | List[Str] / List[T], in key order |
| `dict_size(dict: d)` | Int
| `trim(text: s)` | Str without spaces and line ends around it |
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

fn add_all(xs: List[Int]) -> Int
  ensures len(list: xs) > 0 or result == 0
  example add_all(xs: [1, 2, 3]) == 6
  example add_all(xs: []) == 0
do
  fold(list: xs, init: 0, func: add)
end

fn main(console: Console) -> Unit
do
  let total: Int = add_all(xs: [3, 8, 1])
  print(to: console, value: "total = " ++ to_str(value: total))
end
```

## Commands

```
node bin/akashi.js check file.ak [--json]   # types, names, capabilities, contracts, generated inputs, and all examples
node bin/akashi.js run file.ak [--json] [--allow-read <folder>]   # check, then run main (requires/ensures are checked on every call)
node bin/akashi.js build file.ak [-o out.wasm]   # compile to WebAssembly (all but functions kept in let or parameters, which give E600)
node bin/akashi.js wasm out.wasm [--allow-read <folder>]   # run a compiled program
node bin/akashi.js fmt file.ak [--check]    # format: 2-space indent, standard spacing (keeps line breaks and comments)
node bin/akashi.js spec                     # print this spec (to paste into a prompt)
```
