module Peel.Label

(** The public classification lattice for PEEL byte expressions. *)
[@@ erasable]
noeq type label =
  | Public
  | Secret

(** The least upper bound of two classifications. *)
let join (left right : label) : Tot label =
  match left, right with
  | Public, Public -> Public
  | Public, Secret -> Secret
  | Secret, Public -> Secret
  | Secret, Secret -> Secret

val join_commutative (left right : label) :
  Lemma (join left right == join right left)

val join_associative (left middle right : label) :
  Lemma
    (join (join left middle) right ==
     join left (join middle right))

val join_idempotent (classification : label) :
  Lemma (join classification classification == classification)

val join_public_identity (classification : label) :
  Lemma
    (join Public classification == classification /\
     join classification Public == classification)

val join_secret_absorbing (classification : label) :
  Lemma
    (join Secret classification == Secret /\
     join classification Secret == Secret)
