module Peel.Byte

open Peel.Label

(** A byte whose classification is tracked by its type.
    Its concrete representation is private to [Peel.Byte]. *)
val byte : label -> Type0

(** The logical byte model. This function is ghost-only and is erased. *)
val view : #classification:label -> byte classification -> GTot FStar.UInt8.t

val public (value : FStar.UInt8.t) :
  Tot (result:byte Public { view result == value })

val secret (value : FStar.UInt8.t) :
  Tot (result:byte Secret { view result == value })

val xor :
  #left:label ->
  #right:label ->
  x:byte left ->
  y:byte right ->
  Tot
    (result:byte (join left right) {
       view result == FStar.UInt8.logxor (view x) (view y)
     })

val observe (value : byte Public) :
  Tot (result:FStar.UInt8.t { result == view value })

val xor_view :
  #left:label ->
  #right:label ->
  x:byte left ->
  y:byte right ->
  Lemma
    (view (xor x y) ==
     FStar.UInt8.logxor (view x) (view y))
