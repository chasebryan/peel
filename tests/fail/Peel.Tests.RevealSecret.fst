module Peel.Tests.RevealSecret

open Peel.Label
open Peel.Byte

[@@ expect_failure [12]]
let direct_secret_observation : FStar.UInt8.t =
  observe (secret 0xA5uy)

let derived_secret_observation : FStar.UInt8.t =
  observe (xor (secret 0xA5uy) (public 0x5Auy))
