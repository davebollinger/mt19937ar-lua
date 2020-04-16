--[[
mt19937ar.lua, a conversion of the Jan 26 2002 version of mt19937ar.c
ref:  http://www.math.sci.hiroshima-u.ac.jp/~m-mat/MT/MT2002/emt19937ar.html
Copyright (C) 2016 David Bollinger (davebollinger at gmail dot com)
for pure Lua 5.1 (tested against 5.1.5) 3/25/2016

Lua-specific differences in this translation:  support for multiple instances, init_by_array is 1-based, methods to get\set state, math library work-alikes
(granted that much of this is superfluous/redundant with the release of Lua 5.3, but I needed the 5.1 support, multiple instances, etc)
Bonus:  successfully passes the validation test :D

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


/* 
   A C-program for MT19937, with initialization improved 2002/1/26.
   Coded by Takuji Nishimura and Makoto Matsumoto.

   Before using, initialize the state by using init_genrand(seed)  
   or init_by_array(init_key, key_length).

   Copyright (C) 1997 - 2002, Makoto Matsumoto and Takuji Nishimura,
   All rights reserved.                          

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

     1. Redistributions of source code must retain the above copyright
        notice, this list of conditions and the following disclaimer.

     2. Redistributions in binary form must reproduce the above copyright
        notice, this list of conditions and the following disclaimer in the
        documentation and/or other materials provided with the distribution.

     3. The names of its contributors may not be used to endorse or promote 
        products derived from this software without specific prior written 
        permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


   Any feedback is very welcome.
   http://www.math.sci.hiroshima-u.ac.jp/~m-mat/MT/emt.html
   email: m-mat @ math.sci.hiroshima-u.ac.jp (remove space)
*/
--]]

--------------------------------
-- BEGIN INTERNAL SUPPORT STUFF
--------------------------------

---
-- bitwise support for pure Lua 5.1
-- of "32-bit integers"
-- (as represented by Lua's double-precision floating point number type)
---

local floor = math.floor

---
-- a 32bitUL * 32bitUL = 64bitUL can overflow the 53-bit precision of a double
-- (thus potentially corrupting the lower 32-bits)
-- this "longhand method" 48-bit version ignores the (unneeded) hiword * hiword
-- portion to avoid overflow of intermediate result prior to truncation to 32-bits
-- (only used when seeding, not when generating, so performance considerations should be negligible)
-- @param a number a "32-bit integer"
-- @param b number a "32-bit integer"
-- @return number the "32-bit integer" result of multiplication
local function SAFEMUL32(a,b)
	local alo = floor(a % 65536)
	local ahi = floor(a/65536) % 65536
	local blo = floor(b % 65536)
	local bhi = floor(b/65536) % 65536
	local lolo = alo * blo
	local lohi = alo * bhi
	local hilo = ahi * blo
	local llhh = lohi + hilo
	return floor((llhh*65536+lolo) % 4294967296)
end

---
-- 32-bit bitwise and
-- @param a number a "32-bit integer"
-- @param b number a "32-bit integer"
-- @return number the "32-bit integer" result of the bitwise operation
local function AND(a, b)
	local r,p = 0,1
	for i = 0, 31 do
		local a1 = a%2
		local b1 = b%2
		if ((a1>0) and (b1>0)) then r=r+p end
		if (a1>0) then a=a-1 end
		if (b1>0) then b=b-1 end
		a = a/2
		b = b/2
		p = p*2
	end
	return r
end

---
-- 32-bit bitwise or
-- @param a number a "32-bit integer"
-- @param b number a "32-bit integer"
-- @return number the "32-bit integer" result of the bitwise operation
local function OR(a, b)
	local r,p = 0,1
	for i = 0, 31 do
		local a1 = a%2
		local b1 = b%2
		if ((a1>0) or (b1>0)) then r = r + p end
		if (a1>0) then a=a-1 end
		if (b1>0) then b=b-1 end
		a = a/2
		b = b/2
		p = p*2
	end
	return r
end

---
-- 32-bit bitwise xor
-- @param a number a "32-bit integer"
-- @param b number a "32-bit integer"
-- @return number the "32-bit integer" result of the bitwise operation
local function XOR(a, b)
	local r,p = 0,1
	for i = 0, 31 do
		local a1 = a%2
		local b1 = b%2
		if (a1~=b1) then r = r + p end
		if (a1>0) then a=a-1 end
		if (b1>0) then b=b-1 end
		a = a/2
		b = b/2
		p = p*2
	end
	return r
end

--- various bitwise shifts and masks
local SHR1 = function(y) return floor(y / 2) end
local SHR30 = function(y) return floor(y / 1073741824) end
local SHR11 = function(y)  return floor(y / 2048)  end
local SHL7 = function(y)  return (y * 128)  end
local SHL15 = function(y)  return (y * 32768)  end
local SHR18 = function(y)  return floor(y / 262144)  end
local BIT0 = function(y) return (y%2) end -- should not be necessary to floor() this result, given its usage exclusively on "ints"

--------------------------------
-- END INTERNAL SUPPORT STUFF
-- BEGIN ACTUAL MERSENNE TWISTER
--------------------------------

local N = 624
local M = 397

local MATRIX_A = 0x9908B0DF
local UPPER_MASK = 0x80000000
local LOWER_MASK = 0x7FFFFFFF

local mt19937ar = {}
-- there is intentionally no metatable usage on mt19937ar to function as a "class"
-- everything is in the instance closures created by .new() (the single exposed "class" method) 

---
-- @description creates an instance of the rng
-- @return table an instance of the rng
--
function mt19937ar.new()
	local instance = {}
	--
	-- private members
	-- @see getState @see setState
	--
	local mt = {}
	local mti = N+1
	--
	-- public members
	--

	---
	-- @description seed the generator via number
	-- @param s number representing a 32-bit integer seed value
	function instance:init_genrand(s)
		mt[0] = AND(s, 0xFFFFFFFF)
		for i=1,N-1 do
			-- mt[i] = 1812433253 * XOR(mt[i-1], SHR30(mt[i-1])) + i -- the literal translation, but nope
			mt[i] = SAFEMUL32(1812433253, XOR(mt[i-1], SHR30(mt[i-1]))) + i -- yep
			mt[i] = AND(mt[i], 0xFFFFFFFF)
		end
		mti = N
	end

	---
	-- @description seed the generator via array
	-- @param init_key array of integer seeds, @note 1-based as per Lua conventions
	-- @param key_length number optional length of array to use (if not provided will be assumed to be #init_key)
	function instance:init_by_array(init_key, key_length)
		self:init_genrand(19650218);
		if (not key_length) then key_length = #init_key end
		local i,j,k = 1,0,(N>key_length and N) or key_length
		while k>0 do
			--mt[i] = XOR(mt[i], XOR(mt[i-1], SHR30(mt[i-1])) * 1664525) + init_key[j+1] + j -- the literal translation, but nope
			mt[i] = XOR(mt[i], SAFEMUL32(XOR(mt[i-1], SHR30(mt[i-1])), 1664525)) + init_key[j+1] + j -- yep
			mt[i] = AND(mt[i], 0xFFFFFFFF)
			i,j = i+1,j+1
			if (i>=N) then mt[0] = mt[N-1]; i=1 end
			if (j>=key_length) then j=0 end
			k = k-1
		end
		for k = N-1,1,-1 do
			--mt[i] = XOR(mt[i], XOR(mt[i-1], SHR30(mt[i-1])) * 1566083941) - i -- the literal translation, but nope
			mt[i] = XOR(mt[i], SAFEMUL32(XOR(mt[i-1], SHR30(mt[i-1])), 1566083941)) - i -- yep
			mt[i] = AND(mt[i], 0xFFFFFFFF)
			i = i+1
			if (i>=N) then mt[0] = mt[N-1]; i=1 end
		end
		mt[0] = 0x80000000
	end

	--- generates a random number on [0,0xffffffff]-interval
	function instance:genrand_int32()
		local y
		if mti>=N then
			if mti==N+1 then
				self:init_genrand(5489)
			end
			for kk = 0, N-M-1 do
				y = OR( AND(mt[kk],UPPER_MASK) , AND(mt[kk+1],LOWER_MASK) )
				mt[kk] = XOR(mt[kk+M], XOR( SHR1(y), BIT0(y)*MATRIX_A ))
				kk=kk+1
			end
			for kk = N-M, N-2 do
				y = OR( AND(mt[kk],UPPER_MASK) , AND(mt[kk+1],LOWER_MASK) )
				mt[kk] = XOR(mt[kk+(M-N)], XOR( SHR1(y), BIT0(y)*MATRIX_A ))
				kk=kk+1
			end
			y = OR( AND(mt[N-1],UPPER_MASK) , AND(mt[0],LOWER_MASK) )
			mt[N-1] = XOR(mt[M-1], XOR( SHR1(y), BIT0(y)*MATRIX_A ))
			mti=0
		end
		y = mt[mti]
		mti = mti+1
		y = XOR(y, SHR11(y))
		y = XOR(y, AND(SHL7(y), 0x9D2C5680) )
		y = XOR(y, AND(SHL15(y), 0xEFC60000) )
		y = XOR(y, SHR18(y))
		return y
	end

	-- Floating Point Versions

	--- generates a random number on [0,0x7fffffff]-interval
	function instance:genrand_int31()
		return floor(self:genrand_int32() / 2)
	end

	--- generates a random number on [0,1]-real-interval
	function instance:genrand_real1()
		return self:genrand_int32() * (1.0/4294967295.0) -- divided by 2^32-1
	end

	--- generates a random number on [0,1)-real-interval
	function instance:genrand_real2()
		return self:genrand_int32() * (1.0/4294967296.0) -- divided by 2^32
	end

	--- generates a random number on (0,1)-real-interval
	function instance:genrand_real3()
		return (self:genrand_int32() + 0.5) * (1.0/4294967296.0) -- divided by 2^32 
	end

	--- generates a random number on [0,1) with 53-bit resolution
	function instance:genrand_res53() 
		local a = floor(self:genrand_int32() / 32)
		local b = floor(self:genrand_int32() / 64)
			return (a*67108864.0+b) * (1.0/9007199254740992.0)
	end
	--/* These real versions are due to Isaku Wada, 2002/01/09 added */

	--- a math library work-alike for seeding the generator
	instance.randomseed = instance.init_genrand

	--- a math library work-alike for generating random numbers
	function instance:random(m,n)
		if (not m) then
			-- handle zero-argument form
			return self:genrand_real2()
		else
			if (not n) then
				-- handle one-argument form
				return self:genrand_int32() % m + 1
			else
				-- handle two-argument form
				return m + self:genrand_int32() % (n-m+1)
			end
		end
	end

	--
	-- Esoterica
	--

	---
	-- @description get a clone of the current state
	-- @return a table representing the full state, containing mti (number) and mt (table of numbers)
	function instance:getState()
		local r = {}
		r.mti = mti
		r.mt = {}
		for i=0,N-1 do
			r.mt[i] = mt[i]
		end
		return r
	end

	---
	-- @description set the current state
	-- @param s a table of the form returned by @see getState, containing mti (number) and mt (table of numbers)
	function instance:setState(s)
		if (s==nil) then return end
		if (type(s.mti)=="number") then mti = floor(s.mti) end
		if (type(s.mt)=="table") then
			for i = 0,N-1 do
				if (type(s.mt[i])=="number") then
					mt[i] = floor(s.mt[i])
				end
			end
		end
	end


	---
	-- this function replicates the test output from the original mt19937ar.c source code
	-- this output may be comp/diff'd against the original to validate the implementation
	-- writes a file named "mt19937ar.lua.out" in the current working directory
	-- reference:
	-- http://www.math.sci.hiroshima-u.ac.jp/~m-mat/MT/MT2002/CODES/mt19937ar.out
	--
	function instance:createValidationOutput()
		local filename = "mt19937ar.lua.out"
		local f = io.open(filename,"wb")
		self:init_by_array({291,564,837,1110})
		f:write("1000 outputs of genrand_int32()\n")
		for i=0,999 do
			f:write( string.format("%10.0f ", self:genrand_int32()) )
			if i%5==4 then f:write( "\n" ) end
		end
		f:write("\n1000 outputs of genrand_real2()\n")
		for i=0,999 do
			f:write( string.format("%10.8f ", self:genrand_real2()) )
			if i%5==4 then f:write( "\n" ) end
		end
		f:close()
	end

	--

	return instance
end


-------------------------------------------------------------------------------
-- END
-------------------------------------------------------------------------------
return mt19937ar
