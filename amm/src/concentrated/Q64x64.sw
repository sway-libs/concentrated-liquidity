// Copied from https://github.com/FuelLabs/sway-libs/pull/32
library Q64x64;

dep Q128x128;

use core::num::*;
use std::{
    assert::assert, 
    math::*, 
    revert::revert, 
    u128::*, 
    u256::*
};

use Q128x128::*;

pub struct Q64x64 {
    value: U128,
}
impl Q64x64 {
    pub fn u128(self) -> U128 {
        self.value
    }
}
impl Q64x64 {
    pub fn from(value: U128) -> Self {
        Self { value }
    }
}
impl Q64x64 {
    pub fn denominator() -> u64 {
        1 << 64
    }
    pub fn zero() -> Self {
        Self {
            value: ~U128::from(0, 0),
        }
    }
    pub fn bits() -> u32 {
        128
    }
}
impl U128 {
    fn ge(self, other: Self) -> bool {
        self > other || self == other
    }
    fn le(self, other: Self) -> bool {
        self < other || self == other
    }
}
impl core::ops::Eq for Q64x64 {
    fn eq(self, other: Self) -> bool {
        self.value == other.value
    }
}
impl core::ops::Ord for Q64x64 {
    fn gt(self, other: Self) -> bool {
        self.value > other.value
    }
    fn lt(self, other: Self) -> bool {
        self.value < other.value
    }
}
impl core::ops::Add for Q64x64 {
    /// Add a Q64x64 to a Q64x64. Panics on overflow.
    fn add(self, other: Self) -> Self {
        Self {
            value: self.value + other.value,
        }
    }
}
impl core::ops::Subtract for Q64x64 {
    /// Subtract a Q64x64 from a Q64x64. Panics of overflow.
    fn subtract(self, other: Self) -> Self {
        // If trying to subtract a larger number, panic.
        assert(self.value >= other.value);
        Self {
            value: self.value - other.value,
        }
    }
}
impl Q64x64 {
    /// Multiply a Q64x64 with a Q64x64. Panics of overflow.
    fn multiply(self, other: Self) -> Q128x128 {
        let int_u128 = ~U128::from(0, self.value.upper) * ~U128::from(0, other.value.upper);
        let dec_u128 = ~U128::from(0, self.value.lower) * ~U128::from(0, other.value.lower);
        return ~Q128x128::from(int_u128, dec_u128);
    }
}
impl core::ops::Divide for Q64x64 {
    /// Divide a Q64x64 by a Q64x64. Panics if divisor is zero.
    fn divide(self, divisor: Self) -> Self {
        let zero = ~Q64x64::zero();
        assert(divisor != zero);
        let denominator = ~U256::from(0, 0, 0, ~Self::denominator());
        // Conversion to U128 done to ensure no overflow happen
        // and maximal precision is avaliable
        // as it makes possible to multiply by the denominator in 
        // all cases
        let self_u128 = ~U256::from(0, 0, self.value.upper, self.value.lower);
        let divisor_u128 = ~U256::from(0, 0, divisor.value.upper, divisor.value.lower);

        // Multiply by denominator to ensure accuracy 
        let res_u256 = self_u128 * denominator / divisor_u128;
        if res_u256.b != 0 || res_u256.a != 0 {
            // panic on overflow
            revert(0);
        }
        let res_u128 = ~U128::from(res_u256.c, res_u256.d);
        Self {
            value: res_u128,
        }
    }
}
impl core::ops::Mod for U128 {
    /// Modulo of a U128 by a U128. Panics if divisor is zero.
    fn modulo(self, divisor: Self) -> Self {
        let zero = ~U128::from(0, 0);
        let one = ~U128::from(0, 1);
        assert(divisor != zero);
        let mut quotient = ~U128::new();
        let mut remainder = ~U128::new();
        let mut i = 128 - 1;
        while true {
            quotient <<= 1;
            remainder <<= 1;
            remainder = remainder | ((self & (one << i)) >> i);
            // TODO use >= once OrdEq can be implemented.
            if remainder > divisor || remainder == divisor {
                remainder -= divisor;
                quotient = quotient | one;
            }
            if i == 0 {
                break;
            }
            i -= 1;
        }
        remainder
    }
}
impl U128 {
    pub fn sqrt(self) -> Self {
        let z = ~U128::from(0, 181);
        let x = self;
        let y = self;
        if y < ~U128::from(0x100, 0x0000000000000000) {
            y >> 64;
            z << 32;
        }
        if y < ~U128::from(0, 0x10000000000) {
            y >> 32;
            z << 16;
        }
        if y < ~U128::from(0, 0x1000000) {
            y >> 16;
            z << 8;
        }
        let z = (z * (y + ~U128::from(0, 65536))) >> 18;
        let z = (z + (x / z)) >> 1;
        let z = (z + (x / z)) >> 1;
        let z = (z + (x / z)) >> 1;
        let z = (z + (x / z)) >> 1;
        let z = (z + (x / z)) >> 1;
        let z = (z + (x / z)) >> 1;
        let mut z = (z + (x / z)) >> 1;
        if (x / z) < z {
            z = x / z;
        }
        z
    }
}
impl Q64x64 {
    /// Creates Q64x64 that correponds to a unsigned integer
    pub fn from_uint(uint: u64) -> Self {
        let value = ~U128::from(uint, 0);
        Self {
            value
        }
    }
}
impl Root for Q64x64 {
    /// Sqaure root for Q64x64
    fn sqrt(self) -> Self {
        let nominator_root = self.value.sqrt();
        // Need to multiple over 2 ^ 16, as the sqare root of the denominator 
        // is also taken and we need to ensure that the denominator is constant
        let nominator = nominator_root << 16;
        Self {
            value: nominator,
        }
    }
}