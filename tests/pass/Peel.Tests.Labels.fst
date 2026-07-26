module Peel.Tests.Labels

open Peel.Label
open Peel.Byte

let test_join_truth_table () :
  Lemma
    (join Public Public == Public /\
     join Public Secret == Secret /\
     join Secret Public == Secret /\
     join Secret Secret == Secret) =
  ()

let test_join_commutative (left right : label) :
  Lemma (join left right == join right left) =
  join_commutative left right

let test_join_associative (left middle right : label) :
  Lemma
    (join (join left middle) right ==
     join left (join middle right)) =
  join_associative left middle right

let test_join_idempotent (classification : label) :
  Lemma (join classification classification == classification) =
  join_idempotent classification

let test_join_public_identity (classification : label) :
  Lemma
    (join Public classification == classification /\
     join classification Public == classification) =
  join_public_identity classification

let test_join_secret_absorbing (classification : label) :
  Lemma
    (join Secret classification == Secret /\
     join classification Secret == Secret) =
  join_secret_absorbing classification

let public_zero : value:byte Public { view value == 0x00uy } =
  public 0x00uy

let public_ff : value:byte Public { view value == 0xFFuy } =
  public 0xFFuy

let secret_zero : value:byte Secret { view value == 0x00uy } =
  secret 0x00uy

let secret_ff : value:byte Secret { view value == 0xFFuy } =
  secret 0xFFuy

let test_xor_public_public :
  value:byte Public {
    view value == FStar.UInt8.logxor (view public_zero) (view public_ff)
  } =
  xor public_zero public_ff

let test_xor_public_secret : byte Secret =
  xor public_zero secret_ff

let test_xor_secret_public : byte Secret =
  xor secret_zero public_ff

let test_xor_secret_secret : byte Secret =
  xor secret_zero secret_ff

let test_observe_public :
  value:FStar.UInt8.t { value == view test_xor_public_public } =
  observe test_xor_public_public

let test_observe_public_value () :
  Lemma (test_observe_public == 0xFFuy) =
  FStar.UInt8.v_inj
    (FStar.UInt8.logxor 0x00uy 0xFFuy)
    0xFFuy

let test_xor_specification
  #left
  #right
  (x : byte left)
  (y : byte right)
  : Lemma
      (view (xor x y) ==
       FStar.UInt8.logxor (view x) (view y)) =
  xor_view x y
