# Akashi language spec (v0.1)

Paste this whole file into an LLM prompt to teach it Akashi. It is short on purpose.

## Design rules (why the language looks like this)

1. **One way to write each thing.** No loops (use recursion, `range`, `map`, `filter`, `fold`), no methods, no operator overloading, no implicit conversion.
2. **Everything is checked before running.** Types, names, arguments, effects and contracts are checked by `akashi check`.
3. **Every error says how to fix it.** Each diagnostic has a stable code, a position and a `fix` text. See `docs/ERRORS.md`.
4. **Promises are code.** Pure functions must state `ensures` (a promise about `result`) and at least one `example`. Examples run on every `check`.

## Program

A program is a list of functions. `run` calls `main`.

```
fn name(param: Type, other: Type) -> ReturnType
  requires <Bool expr>      # optional, any number: what the caller must guarantee
  ensures <Bool expr>       # required for pure functions: may use `result`
  example <Bool expr>       # required for pure functions: a call and its expected value
  effects io                # only for functions that print (or call such functions)
do
  let x: Type = <expr>      # zero or more lines: let, or a Unit expression such as print(...)
  <expr>                    # the last line is the value of the function
end
```

- `main` must be `fn main() -> Unit effects io do ... end`. It needs no ensures or example.
- A function with `effects io` needs no ensures or example.
- Clauses come after `-> Type` and before `do`, in any order.

## Types

`Int` (whole numbers only, overflow is an error), `Bool`, `Str`, `Unit` (written `()`), `List[T]`.
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
| if | `if c then a else b end`; `else` is required; `else if` chains share one `end` |

## Built-in functions

| call | type |
| --- | --- |
| `print(value: x)` | any → Unit, effect io |
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

fn main() -> Unit
  effects io
do
  let total: Int = sum(xs: [3, 8, 1])
  print(value: "total = " ++ to_str(value: total))
end
```

## Commands

```
node bin/akashi.js check file.ak [--json]   # types, names, effects, contracts, and all examples
node bin/akashi.js run file.ak [--json]     # check, then run main (requires/ensures are checked on every call)
```
