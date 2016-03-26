# mt19937ar-lua
Mersenne Twister RNG for pure Lua 5.1


mt19937ar.lua, a conversion of the Jan 26 2002 version of mt19937ar.c
ref:  http://www.math.sci.hiroshima-u.ac.jp/~m-mat/MT/MT2002/emt19937ar.html
Copyright (C) 2016 David Bollinger (davebollinger at gmail dot com)
for pure Lua 5.1 (tested against 5.1.5) 3/25/2016

Lua-specific differences in this translation:
  support for multiple instances
  init_by_array is 1-based (per Lua idiom)
  methods to get\set state
  math library work-alikes
(granted that much of this is superfluous/redundant with the release of Lua 5.3)
Bonus:  successfully passes the validation test :D
...
--example usage (long-form / multiple-instance form):
mt19937ar = require("mt19937ar")
mt1 = mt19937ar.new()
mt1:createValidationOutput()

mt2 = mt19937ar.new()
mt2:init_genrand(1234)
r = mt:genrand_int32()

mt3 = mt19937ar.new()
mt3:init_genrand(2345)
s = mt3:getState() -- save prior to gen
r = mt3:genrand_real2() -- advance state
mt3:setState(s) -- restore prior state
r = mt3:genrand_real2() -- regen from same prior state

--validation usage (short-form / single-instance form)
require("mt19937ar").new():createValidationOutput()
...
