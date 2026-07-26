module Peel.Example.Xor

open Peel.Label
open Peel.Byte

let public_aa : value:byte Public { view value == 0xAAuy } =
  public 0xAAuy

let public_55 : value:byte Public { view value == 0x55uy } =
  public 0x55uy

let secret_aa : value:byte Secret { view value == 0xAAuy } =
  secret 0xAAuy

let secret_55 : value:byte Secret { view value == 0x55uy } =
  secret 0x55uy

let public_xor_public :
  value:byte Public {
    view value == FStar.UInt8.logxor (view public_aa) (view public_55)
  } =
  xor public_aa public_55

let secret_xor_public : byte Secret =
  xor secret_aa public_55

let secret_xor_secret : byte Secret =
  xor secret_aa secret_55

let observed_public :
  value:FStar.UInt8.t { value == view public_xor_public } =
  observe public_xor_public

let public_xor_is_ff () :
  Lemma (observed_public == 0xFFuy) =
  FStar.UInt8.v_inj
    (FStar.UInt8.logxor 0xAAuy 0x55uy)
    0xFFuy
