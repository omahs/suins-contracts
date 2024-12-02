// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module coupons::coupon_tests;

use coupons::constants;
use coupons::coupon_house;
use coupons::data;
use coupons::range;
use coupons::rules;
use coupons::setup::{
    Self,
    TestApp,
    user,
    user_two,
    test_app,
    admin_add_coupon,
    test_init
};
use std::string::String;
use sui::clock::Clock;
use sui::test_scenario::{Scenario, return_shared};
use sui::test_utils::{Self, destroy};
use suins::payment::PaymentIntent;
use suins::suins::SuiNS;
use suins::suins_registration::SuinsRegistration;

// populate a lot of coupons with different cases.
// This populates the coupon as an authorized app
fun populate_coupons(scenario: &mut Scenario) {
    scenario.next_tx(user());
    let mut suins = scenario.take_shared<SuiNS>();

    let data_mut = coupon_house::app_data_mut<TestApp>(&mut suins, test_app());
    setup::populate_coupons(data_mut, scenario.ctx());
    return_shared(suins);
}

// // Please look up at `setup` file to see all the coupon names and their
// // respective logic.
// // Tests the e2e experience for coupons (a list of different coupons with
// // different rules)
// #[test]
// fun test_e2e() {
//     let mut scenario_val = test_init();
//     let scenario = &mut scenario_val;
//     // populate all coupons.
//     populate_coupons(scenario);

//     // 5 SUI discount coupon.
//     register_with_coupon(
//         b"5_SUI_DISCOUNT".to_string(),
//         b"test.sui".to_string(),
//         1,
//         195 * mist_per_sui(),
//         0,
//         user(),
//         scenario,
//     );

//     // original price would be 400 (200*2 years). 25% discount should bring it
//     // down to 300.
//     register_with_coupon(
//         b"25_PERCENT_DISCOUNT_MAX_2_YEARS".to_string(),
//         b"jest.sui".to_string(),
//         2,
//         300 * mist_per_sui(),
//         0,
//         user(),
//         scenario,
//     );

//     // Test that this user-specific coupon works as expected
//     register_with_coupon(
//         b"25_PERCENT_DISCOUNT_USER_ONLY".to_string(),
//         b"fest.sui".to_string(),
//         2,
//         300 * mist_per_sui(),
//         0,
//         user(),
//         scenario,
//     );

//     // 50% discount only on names 5+ digits
//     register_with_coupon(
//         b"50_PERCENT_5_PLUS_NAMES".to_string(),
//         b"testo.sui".to_string(),
//         1,
//         25 * mist_per_sui(),
//         0,
//         user(),
//         scenario,
//     );

//     // 50% discount only on names 3 digit names.
//     register_with_coupon(
//         b"50_PERCENT_3_DIGITS".to_string(),
//         b"tes.sui".to_string(),
//         1,
//         600 * mist_per_sui(),
//         0,
//         user(),
//         scenario,
//     );

//     // 50% DISCOUNT, with all possible rules involved.
//     register_with_coupon(
//         b"50_DISCOUNT_SALAD".to_string(),
//         b"teso.sui".to_string(),
//         1,
//         100 * mist_per_sui(),
//         0,
//         user(),
//         scenario,
//     );

//     scenario_val.end();
// }

#[test]
fun zero_fee_purchase() {
    let mut scenario_val = test_init();
    let scenario = &mut scenario_val;
    // populate all coupons.
    populate_coupons(scenario);
    // 100% discount coupon.
    admin_add_coupon(
        b"100%_OFF".to_string(),
        constants::percentage_discount_type(),
        100,
        scenario,
    );
    test_coupon_register(
        scenario,
        b"test.sui".to_string(),
        b"100%_OFF".to_string(),
        user(),
        option::some(0),
    );

    scenario_val.end();
}

#[test]
fun fifty_percent_off_4() {
    let mut scenario_val = test_init();
    let scenario = &mut scenario_val;
    // populate all coupons.
    populate_coupons(scenario);
    // 100% discount coupon.
    admin_add_coupon(
        b"50%_OFF".to_string(),
        constants::percentage_discount_type(),
        50,
        scenario,
    );
    test_coupon_register(
        scenario,
        b"test.sui".to_string(),
        b"50%_OFF".to_string(),
        user(),
        option::some(
            100 * suins::constants::mist_per_sui(),
        ), // 4 character in test is 200 SUI, 50% discount
    );

    scenario_val.end();
}

#[test]
fun specific_max_years() {
    rules::new_coupon_rules(
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::some(range::new(1, 1)),
    );
}

#[test, expected_failure(abort_code = ::coupons::range::EInvalidRange)]
fun max_years_two_failure() {
    rules::new_coupon_rules(
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::some(range::new(5, 4)),
    );
}

// Tests the e2e experience for coupons (a list of different coupons with
// different rules)
#[
    test,
    expected_failure(
        abort_code = ::coupons::coupon_house::ECouponNotExists,
    ),
]
fun no_more_available_claims_failure() {
    let mut scenario_val = test_init();
    let scenario = &mut scenario_val;
    populate_coupons(scenario);
    test_coupon_register(
        scenario,
        b"test.sui".to_string(),
        b"25_PERCENT_DISCOUNT_USER_ONLY".to_string(),
        user(),
        option::none(),
    );
    test_coupon_register(
        scenario,
        b"tost.sui".to_string(),
        b"25_PERCENT_DISCOUNT_USER_ONLY".to_string(),
        user(),
        option::none(),
    );
    scenario_val.end();
}

#[test, expected_failure(abort_code = ::coupons::rules::EInvalidUser)]
fun invalid_user_failure() {
    let mut scenario_val = test_init();
    let scenario = &mut scenario_val;
    populate_coupons(scenario);
    test_coupon_register(
        scenario,
        b"test.sui".to_string(),
        b"25_PERCENT_DISCOUNT_USER_ONLY".to_string(),
        user_two(),
        option::none(),
    );
    scenario_val.end();
}

#[test, expected_failure(abort_code = ::coupons::rules::ECouponExpired)]
fun coupon_expired_failure() {
    let mut scenario_val = test_init();
    let scenario = &mut scenario_val;
    // set the clock to 5, coupon is expired at time 1
    let mut clock = scenario.take_shared<Clock>();
    clock.set_for_testing(5);
    return_shared(clock);
    populate_coupons(scenario);
    test_coupon_register(
        scenario,
        b"tes.sui".to_string(),
        b"50_PERCENT_3_DIGITS".to_string(),
        user(),
        option::none(),
    );
    scenario_val.end();
}

#[test, expected_failure(abort_code = ::coupons::rules::ENotValidYears)]
fun coupon_not_valid_for_years_failure() {
    let mut scenario_val = test_init();
    let scenario = &mut scenario_val;
    populate_coupons(scenario);
    // Test 3 years of renewal with a coupon that only allows 1-2 years.
    test_coupon_renewal(
        scenario,
        b"test.sui".to_string(),
        3,
        b"50_DISCOUNT_SALAD".to_string(),
        user(),
    );
    scenario_val.end();
}

#[
    test,
    expected_failure(
        abort_code = ::coupons::rules::EInvalidForDomainLength,
    ),
]
fun coupon_invalid_length_1_failure() {
    let mut scenario_val = test_init();
    let scenario = &mut scenario_val;
    populate_coupons(scenario);
    // Tries to use 3 digit coupon on <=4 digit name
    test_coupon_register(
        scenario,
        b"test.sui".to_string(),
        b"50_PERCENT_3_DIGITS".to_string(),
        user(),
        option::none(),
    );
    scenario_val.end();
}

#[
    test,
    expected_failure(
        abort_code = ::coupons::rules::EInvalidForDomainLength,
    ),
]
fun coupon_invalid_length_2_failure() {
    let mut scenario_val = test_init();
    let scenario = &mut scenario_val;
    populate_coupons(scenario);
    // Tries to use <=4 digit coupon for 5 digit name
    test_coupon_register(
        scenario,
        b"testo.sui".to_string(),
        b"50_DISCOUNT_SALAD".to_string(),
        user(),
        option::none(),
    );
    scenario_val.end();
}

#[
    test,
    expected_failure(
        abort_code = ::coupons::rules::EInvalidForDomainLength,
    ),
]
fun coupon_invalid_length_3_failure() {
    let mut scenario_val = test_init();
    let scenario = &mut scenario_val;
    populate_coupons(scenario);
    // Tries to use 5+ digit coupon on 4 digit name
    test_coupon_register(
        scenario,
        b"test.sui".to_string(),
        b"50_PERCENT_5_PLUS_NAMES".to_string(),
        user(),
        option::none(),
    );

    scenario_val.end();
}

#[test]
fun add_coupon_as_admin() {
    let mut scenario_val = test_init();
    let scenario = &mut scenario_val;
    populate_coupons(scenario);
    // add a no rule coupon as an admin
    admin_add_coupon(
        b"TEST_SUCCESS_ADDITION".to_string(),
        constants::percentage_discount_type(),
        50,
        scenario,
    );
    setup::admin_remove_coupon(b"TEST_SUCCESS_ADDITION".to_string(), scenario);

    scenario_val.end();
}

#[test, expected_failure(abort_code = ::coupons::rules::EInvalidType)]
fun add_coupon_invalid_type_failure() {
    let mut scenario_val = test_init();
    let scenario = &mut scenario_val;
    populate_coupons(scenario);
    admin_add_coupon(
        b"TEST_SUCCESS_ADDITION".to_string(),
        5,
        50,
        scenario,
    );
    scenario_val.end();
}

#[test, expected_failure(abort_code = ::coupons::rules::EInvalidAmount)]
fun add_coupon_invalid_amount_failure() {
    let mut scenario_val = test_init();
    let scenario = &mut scenario_val;
    populate_coupons(scenario);
    admin_add_coupon(
        b"TEST_SUCCESS_ADDITION".to_string(),
        constants::percentage_discount_type(),
        101,
        scenario,
    );
    scenario_val.end();
}
#[test, expected_failure(abort_code = ::coupons::rules::EInvalidAmount)]
fun add_coupon_invalid_amount_2_failure() {
    let mut scenario_val = test_init();
    let scenario = &mut scenario_val;
    populate_coupons(scenario);
    admin_add_coupon(
        b"TEST_SUCCESS_ADDITION".to_string(),
        constants::percentage_discount_type(),
        0,
        scenario,
    );
    scenario_val.end();
}

#[test, expected_failure(abort_code = ::coupons::data::ECouponAlreadyExists)]
fun add_coupon_twice_failure() {
    let mut scenario_val = test_init();
    let scenario = &mut scenario_val;
    populate_coupons(scenario);
    admin_add_coupon(
        b"TEST_SUCCESS_ADDITION".to_string(),
        constants::percentage_discount_type(),
        100,
        scenario,
    );
    admin_add_coupon(
        b"TEST_SUCCESS_ADDITION".to_string(),
        constants::percentage_discount_type(),
        100,
        scenario,
    );
    scenario_val.end();
}

#[test, expected_failure(abort_code = ::coupons::data::ECouponDoesNotExist)]
fun remove_non_existing_coupon() {
    let mut ctx = tx_context::dummy();
    let mut data = data::new(&mut ctx);
    data.remove_coupon(b"TEST_SUCCESS_ADDITION".to_string());
    test_utils::destroy(data);
}

fun test_coupon_register(
    scenario: &mut Scenario,
    domain: String,
    coupon_code: String,
    user: address,
    amount: Option<u64>,
) {
    scenario.next_tx(user);
    {
        let mut suins = scenario.take_shared<SuiNS>();
        let mut intent = init_registration(
            &mut suins,
            domain,
        );
        let clock = scenario.take_shared<Clock>();
        coupon_house::apply_coupon(
            &mut suins,
            &mut intent,
            coupon_code,
            &clock,
            scenario.ctx(),
        );
        if (amount.is_some()) {
            assert!(
                intent.request_data().base_amount() == amount.get_with_default(0),
                0,
            );
        };

        return_shared(suins);
        return_shared(clock);
        destroy(intent);
    };
}

fun test_coupon_renewal(
    scenario: &mut Scenario,
    domain: String,
    renewal_years: u8,
    coupon_code: String,
    user: address,
) {
    scenario.next_tx(user);
    {
        let mut suins = scenario.take_shared<SuiNS>();
        let clock = scenario.take_shared<Clock>();
        let nft = suins::suins_registration::new_for_testing(
            suins::domain::new(domain),
            1,
            &clock,
            scenario.ctx(),
        );

        let mut intent = init_renewal(
            &mut suins,
            &nft,
            renewal_years,
        );
        coupon_house::apply_coupon(
            &mut suins,
            &mut intent,
            coupon_code,
            &clock,
            scenario.ctx(),
        );

        return_shared(suins);
        return_shared(clock);
        destroy(intent);
        destroy(nft);
    };
}

fun init_registration(suins: &mut SuiNS, domain: String): PaymentIntent {
    let intent = suins::payment::init_registration(suins, domain);

    intent
}

fun init_renewal(
    suins: &mut SuiNS,
    nft: &SuinsRegistration,
    years: u8,
): PaymentIntent {
    let intent = suins::payment::init_renewal(suins, nft, years);

    intent
}
