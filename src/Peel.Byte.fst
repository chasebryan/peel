module Peel.Byte

open Peel.Label

let byte (_ : label) = FStar.UInt8.t

let view #classification (value : byte classification) : GTot FStar.UInt8.t =
  value

let public value = value

let secret value = value

let xor #left #right x y =
  FStar.UInt8.logxor x y

let observe value = value

let xor_view #left #right x y = ()
