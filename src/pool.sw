contract;

dep cl_libs;

use core::num::*;
use std::{
    revert::require,
    identity::ContractId,
    token::transfer,
    identity::Identity,
    u128::U128,
    storage::StorageMap,
    token::transfer,
    auth::msg_sender,
};

use cl_libs::I24::I24;
use cl_libs::Q64x64::*;

pub enum ConcentratedLiquidityErrors {
    Locked: (),
    ZeroAddress: (),
    InvalidToken: (),
    InvalidSwapFee: (),
    LiquidityOverflow: (),
    Token0Missing: (),
    Token1Missing: (),
    InvalidTick: (),
    LowerEven: (),
    UpperOdd: (),
    MaxTickLiquidity: (),
    Overflow: (),
}

struct Tick {
    previous_tick: I24,
    next_tick: I24,
    liquidity: U128,
    fee_growth_outside0: u64,
    fee_growth_outside1: u64,
    seconds_growth_outside: U128
}

struct Position {
    liquidity: U128,
    fee_growth_inside0: u64,
    fee_growth_inside1: u64,
}

abi ConcentratedLiquidityPool {
    // Core functions
    #[storage(read, write)]
    fn set_price(price : U128);

    #[storage(read, write)]
    fn mint(lower_old: I24, lower: I24, upper_old: I24, upper: I24, amount0_desired: u64, amount1_desired: u64) -> U128;

    #[storage(read, write)]
    fn collect(tickLower: I24, tickUpper: I24) -> (u64, u64);

    #[storage(read, write)]
    fn burn(lower: I24, upper: I24, amount: u64) -> (u64, u64, u64, u64);

    #[storage(read, write)]
    fn swap(recipient: Address, token_zero_to_one: bool, amount: u64, sprtPriceLimit: Q64X64) -> u64;

    #[storage(read)]
    fn quote_amount_in(token_zero_to_one: bool, amount_out: u64) -> u64;

    #[storage(read, write)]
    fn collect_protocol_fee() -> (u64, u64);

    #[storage(read)]
    fn get_price_and_nearest_tick() -> (Q64X64, I24);

    #[storage(read)]
    fn get_protocol_fees() -> (u64, u64);

    #[storage(read)]
    fn get_reserves() -> (u64, u64);
}

// Should be all storage variables
storage {
    token0: ContractId = ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000),
    token1: ContractId = ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000),

    max_fee: u32 = 100000,
    tick_spacing: u32 = 10, // implicitly a u24
    swap_fee: u32 = 2500,
    
    bar_fee_to: Identity = ~ContractId::from(0x0000000000000000000000000000000000000000000000000000000000000000),

    liquidity: U128 = 0,

    seconds_growth_global: U128 = ~U128::from(0, 0),
    last_observation: u32 = 0,

    fee_growth_global0: u64 = 0,
    fee_growth_global1: u64 = 0,

    bar_fee: u64 = 0,

    token0_protocol_fee: u64 = 0,
    token1_protocol_fee: u64 = 0,

    reserve0: u64 = 0,
    reserve1: u64 = 0,

    // Orginally Sqrt of price aka. √(y/x), multiplied by 2^64.
    price: Q64x64 = ~Q64x64::from_uint(0), 
    
    nearest_tick: I24 = ~I24::from_uint(0),

    unlocked: bool = false,

    ticks: StorageMap<I24, Tick> = (),
    positions: StorageMap<(Identity, I24, I24), Position> = (),
}

impl ConcentratedLiquidityPool for Contract {
    #[storage(read, write)]
    fn mint(lower_old: I24, lower: I24, upper_old: I24, upper: I24, amount0_desired: u64, amount1_desired: u64) -> U128 {
        _ensure_tick_spacing(upper, lower).unwrap();

        let price_lower = get_price_at_tick(lower);
        let price_upper = get_price_at_tick(upper);
        let current_price = storage.price;

        let liquidity_minted = get_liquidity_for_amounts(price_lower, price_upper, current_price, amount1_desired, amount0_desired);

        // check to avoid overflow

        // update seconds per liquidity
    }

    
    #[storage(read, write)]
    fn collect_protocol_fee() -> (u64, u64) {
        if storage.token0_protocol_fee > 1 {
            let amount0: u64 = storage.token0_protocol_fee;
            storage.token0_protocol_fee = 0;
            storage.reserve0 -= amount0;
            transfer(storage.token0, amount0, storage.bar_fee_to)
        }
        if storage.token1_protocol_fee > 1 {
            let amount1: u64 = storage.token0_protocol_fee;
            storage.token1_protocol_fee = 0;
            storage.reserve1 -= amount1;
            transfer(storage.token1, amount1, storage.bar_fee_to)

        }
    }

    #[storage(read, write)]
    fn collect(tickLower: I24, tickUpper: I24) -> (u64, u64) {
        let (amount0_fees, amount1_fees) = _update_position(msg.sender, lower, upper, 0);

        storage.reserve0 -= amount0_fees;
        storage.reserve1 -= amount1_fees;

        let sender: Result<Identity, AuthError> = msg_sender().unwrap();

        transfer(storage.token0, amount0_fees, sender);
        transfer(storage.token1, amount1_fees, sender);

        (amount0_fees, amount1_fees)
    }

    #[storage(read)]
    fn get_price_and_nearest_tick() -> (Q64X64, I24){
        (storage.price, storage.nearest_tick)
    }

    #[storage(read)]
    fn get_protocol_fees() -> (u64, u64){
        (storage.token0_protocol_fee, storage.token1_protocol_fee)
    }

    #[storage(read)]
    fn get_reserves() -> (u64, u64){
        (storage.reserve0, storage.reserve1)
    }
}
#[storage(read)]
fn _ensure_tick_spacing(upper: I24, lower: I24) -> Result<(), ConcentratedLiquidityErrors> {
    if lower % I24::from_uint(tick_spacing) != 0 {
        return ConcentratedLiquidityErrors::InvalidTick;
    }
    if (lower / I24::from_uint(tick_spacing)) % 2 != 0 {
        return ConcentratedLiquidityErrors::LowerEven;
    }
    if upper % I24::from_uint(tick_spacing) != 0 {
        return ConcentratedLiquidityErrors::InvalidTick;
    }
    if (upper / I24::from_uint(tick_spacing)) % 2 == 0 {
        return ConcentratedLiquidityErrors::UpperOdd;
    }
    Ok(())
}

#[storage(read, write)]
fn _update_position( owner: Identity, lower: I24, upper: I24, amount: U128, add_or_remove: bool) -> (u64, u64) {
    let position = storage.positions.get(owner, lower, upper);

    let (range_fee_growth0, range_fee_growth1) = range_fee_growth(lower, upper);
}

#[storage(read,write)]
fn swap(recipient: Address, token_zero_to_one: bool, amount: u64, sprtPriceLimit: Q64X64) {
    ()
}

#[storage(read)]
fn quote_amount_in(token_zero_to_one: bool, amount_out: u64) {
    ()
}

#[storage(read, write)]
fn _update_reserves(token_zero_to_one: bool, amount_in: u64, amount_out: u64) {

    ()
}

#[storage(read, write)]
fn _update_fees(token_zero_to_one: bool, fee_growth_global: Q64X64, protocol_fee: Q64X64) {
    if token_zero_to_one {
        storage.fee_growth_global1 = fee_growth_global;
        storage.token1_protocol_fee += protocol_fee;
    } else {
        storage.fee_growth_global0 = fee_growth_global;
        storage.token0_protocol_fee += protocol_fee;
    }

    ()
}



#[storage(read)]
fn range_fee_growth(lower_tick : I24, upper_tick: I24) -> (u64, u64) {
    let current_tick = storage.nearest_tick;

    let lower: Tick = storage.ticks.get(lower_tick);
    let upper: Tick = storage.ticks.get(upper_tick);

    let _fee_growth_global0 = storage.fee_growth_global0;
    let _fee_growth_global1 = storage.fee_growth_global1;

    let fee_growth_below0:u64 = 0;
    let fee_growth_below1:u64 = 0;
    let fee_growth_above0:u64 = 0;
    let fee_growth_above1:u64 = 0;

    if lower_tick < current_tick || lower_tick == current_tick {
        fee_growth_below0 = lower.fee_growth_outside0;
        fee_growth_below1 = lower.fee_growth_outside1;
    } else {
        fee_growth_below0 = _fee_growth_global0 - lower.fee_growth_outside0;
        fee_growth_below1 = _fee_growth_global1 - lower.fee_growth_outside1;
    }

    if (current_tick < upper_tick) {
        fee_growth_above0 = upper.fee_growth_outside0;
        fee_growth_above1 = upper.fee_growth_outside1;
    } else {
        fee_growth_above0 = _fee_growth_global0 - upper.fee_growth_outside0;
        fee_growth_above1 = _fee_growth_global1 - upper.fee_growth_outside1;
    }

    let fee_growth_inside0 = _fee_growth_global0 - fee_growth_below0 - fee_growth_above0;
    let fee_growth_inside1 = _fee_growth_global1 - fee_growth_below1 - fee_growth_above1;

    (fee_growth_inside0, fee_growth_inside1)
}