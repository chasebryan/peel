# PEEL P0 Semantics

Phase P0 defines a deliberately small classification kernel for byte
expressions. It establishes static label propagation and a public-only
observation boundary. It does not define a general expression language,
dynamic labels, or declassification.

## Labels and join

There are exactly two labels:

- `Public` marks a byte that executable PEEL code may observe.
- `Secret` marks a byte that executable PEEL code may not observe.

`join` combines the labels of two inputs according to this complete table:

| left | right | result |
| --- | --- | --- |
| `Public` | `Public` | `Public` |
| `Public` | `Secret` | `Secret` |
| `Secret` | `Public` | `Secret` |
| `Secret` | `Secret` | `Secret` |

`Peel.Label` proves these five algebraic properties:

- `join_commutative`: `join left right == join right left`.
- `join_associative`: regrouping three joins does not change the result.
- `join_idempotent`: `join classification classification == classification`.
- `join_public_identity`: `Public` is an identity on the left and right.
- `join_secret_absorbing`: `Secret` is absorbing on the left and right.

Each proof covers every value of `label`; none relies on an unchecked proof
shortcut.

## Classified bytes

The public type is:

```fstar
byte : label -> Type
```

The label is a static type index. The concrete representation is hidden by
`Peel.Byte.fsti`. The `erasable` extraction attribute on `label` makes these
classification indices proof-only, so they do not become runtime C
parameters. P0 provides only these operations:

```fstar
public  : UInt8.t -> byte Public
secret  : UInt8.t -> byte Secret
xor     : byte left -> byte right -> byte (join left right)
observe : byte Public -> UInt8.t
view    : byte classification -> GTot UInt8.t
```

`public` and `secret` introduce a fixed-width byte at the indicated label.
`xor` applies `FStar.UInt8.logxor`, so its executable arithmetic is an
eight-bit operation, and joins the two input labels. `observe` returns the raw
byte only when its argument has type `byte Public`.

`view` is the logical model of a classified byte. Its `GTot` effect makes it
specification-only: proof code can use it, but executable extraction erases it.
There is no operation that changes a `Secret` label to `Public`, and there is
no executable operation that returns the raw value of a `byte Secret`.

## P0 theorems

In addition to the five `join` theorems above, `Peel.Byte` proves
`xor_view` for arbitrary input labels and values:

```text
view (xor x y) = UInt8.logxor (view x) (view y)
```

The theorem is uniform over all four combinations of `Public` and `Secret`.
The result refinements of `public`, `secret`, `xor`, and `observe` connect
their executable results to `view`; they do not add runtime proof data.

## Typing judgment and claim boundary

The compact P0 judgment is:

```text
Γ ⊢ e : byte[ℓ]
```

Here, `Γ` is the static typing context, `e` is a PEEL byte expression,
`byte` is the abstract indexed type, and `ℓ` is either `Public` or `Secret`.
The turnstile `⊢` means "derives," the colon `:` means "has type," and the
brackets in `byte[ℓ]` show that `ℓ` is the byte type's classification index.
The judgment says only that, under `Γ`, F* assigns expression `e` a byte type
carrying label `ℓ`.

For P0, the type system establishes that XOR labels follow the `join` table,
that only a statically public byte can be supplied to `observe`, and that the
logical value of XOR agrees with fixed-width `UInt8.logxor`. It does not
establish secrecy of machine state, constant-time execution, resistance to
side channels, correctness of any cryptographic algorithm, or production
security. It also does not independently certify F*, Z3, KaRaMeL, the C
compiler, or the execution platform.
