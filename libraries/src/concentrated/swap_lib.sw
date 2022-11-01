library swap_lib;

dep full_math;

use std::u128::U128;
use core::num::*;
use full_math::*;

pub fn handle_fees(output: u64, swap_fee: u32, bar_fee: u64, current_liquidity: U128, total_fee_amount: u64, amount_out: u64, protocol_fee: u64, ref mut fee_growth_global:U128) -> (u64, u64, u64, U128) {
    let PRECISION = U128::from(0, u64::max());
    let mut fee_amount: u64 = mul_div_rounding_up_u64(output, swap_fee, 100000); // precison on swap_fee
    let mut total_fee_amount = total_fee_amount;
    let mut amount_out = amount_out;
    let mut protocol_fee = protocol_fee;

    total_fee_amount = total_fee_amount + fee_amount;

    amount_out = amount_out + (output - fee_amount);

    let fee_delta: u64 = mul_div_rounding_up_u64(fee_amount, bar_fee, 10000); // precision on bar_fee
    
    //TODO: is u64 large enough for protocol_fee?
    protocol_fee += fee_delta;
    fee_amount   -= fee_delta;

    fee_growth_global += mul_div(U128::from(0, fee_amount), PRECISION, current_liquidity);

    return (total_fee_amount, amount_out, protocol_fee, fee_growth_global);
}

