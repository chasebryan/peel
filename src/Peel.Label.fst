module Peel.Label

let join_commutative (left right : label) =
  match left, right with
  | Public, Public -> ()
  | Public, Secret -> ()
  | Secret, Public -> ()
  | Secret, Secret -> ()

let join_associative (left middle right : label) =
  match left, middle, right with
  | Public, Public, Public -> ()
  | Public, Public, Secret -> ()
  | Public, Secret, Public -> ()
  | Public, Secret, Secret -> ()
  | Secret, Public, Public -> ()
  | Secret, Public, Secret -> ()
  | Secret, Secret, Public -> ()
  | Secret, Secret, Secret -> ()

let join_idempotent (classification : label) =
  match classification with
  | Public -> ()
  | Secret -> ()

let join_public_identity (classification : label) =
  match classification with
  | Public -> ()
  | Secret -> ()

let join_secret_absorbing (classification : label) =
  match classification with
  | Public -> ()
  | Secret -> ()
