// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module coupons::coupon_tests {
    use std::option;
    use std::string::{utf8};

    use sui::test_scenario::{Self, Scenario, ctx};

    // test dependencies.
    use coupons::setup::{Self, TestApp, user, user_two, mist_per_sui};
    use coupons::coupons::{Self, CouponHouse};
    use coupons::constants::{Self};
    use coupons::rules;
    use coupons::range;

    // populate a lot of coupons with different cases.
    // This populates the coupon as an authorized app
    fun populate_coupons(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, user());
        let coupon_house = test_scenario::take_shared<CouponHouse>(scenario);

        let data_mut = coupons::app_data_mut<TestApp>(setup::test_app(), &mut coupon_house);
        setup::populate_coupons(data_mut, ctx(scenario));
        test_scenario::return_shared(coupon_house);
    }

    // Please look up at `setup` file to see all the coupon names and their respective logic.
    // Tests the e2e experience for coupons (a list of different coupons with different rules)
    #[test]
    fun test_e2e() {
        let scenario_val = setup::test_init();
        let scenario = &mut scenario_val;
        // populate all coupons.
        populate_coupons(scenario);

        // 5 SUI discount coupon.
        setup::register_with_coupon(utf8(b"5_SUI_DISCOUNT"), utf8(b"test.sui"), 1, 195 * mist_per_sui(), 0, user(), scenario);

        // original price would be 400 (200*2 years). 25% discount should bring it down to 300.
        setup::register_with_coupon(utf8(b"25_PERCENT_DISCOUNT_MAX_2_YEARS"), utf8(b"jest.sui"), 2, 300 * mist_per_sui(), 0, user(), scenario);

        // Test that this user-specific coupon works as expected
        setup::register_with_coupon(utf8(b"25_PERCENT_DISCOUNT_USER_ONLY"), utf8(b"fest.sui"), 2, 300 * mist_per_sui(), 0, user(), scenario);

        // 50% discount only on names 5+ digits
        setup::register_with_coupon(utf8(b"50_PERCENT_5_PLUS_NAMES"), utf8(b"testo.sui"), 1, 25 * mist_per_sui(), 0, user(), scenario);

        // 50% discount only on names 3 digit names.
        setup::register_with_coupon(utf8(b"50_PERCENT_3_DIGITS"), utf8(b"tes.sui"), 1, 600 * mist_per_sui(), 0, user(), scenario);

        // 50% DISCOUNT, with all possible rules involved.
        setup::register_with_coupon(utf8(b"50_DISCOUNT_SALAD"), utf8(b"teso.sui"), 1, 100 * mist_per_sui(), 0, user(), scenario);

        test_scenario::end(scenario_val);
    }
    #[test]
    fun zero_fee_purchase(){
        let scenario_val = setup::test_init();
        let scenario = &mut scenario_val;
        // populate all coupons.
        populate_coupons(scenario);
        // 5 SUI discount coupon.
        setup::admin_add_coupon(utf8(b"100_SUI_OFF"), constants::fixed_price_discount_type(), 100 * mist_per_sui(),  scenario);
        // Buy a name for free using the 100 SUI OFF coupon! 
        setup::register_with_coupon(utf8(b"100_SUI_OFF"), utf8(b"testo.sui"), 1, 0 * mist_per_sui(), 0, user(), scenario);
        test_scenario::end(scenario_val);
    }
    #[test]
    fun specific_max_years(){
        rules::new_coupon_rules(
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::some(range::new(1,1))
        );
    }
    #[test, expected_failure(abort_code=coupons::rules::EInvalidYears)]
    fun max_years_failure(){
        rules::new_coupon_rules(
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::some(range::new(0,1))
        );
    }
    #[test, expected_failure(abort_code=coupons::range::EInvalidRange)]
    fun max_years_two_failure(){
        rules::new_coupon_rules(
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::some(range::new(5,4))
        );
    }

    #[test]
    fun test_price_calculation(){
        let scenario_val = setup::test_init();
        let scenario = &mut scenario_val;
        populate_coupons(scenario);
        {
            test_scenario::next_tx(scenario, user());
            let coupon_house = test_scenario::take_shared<CouponHouse>(scenario);
            
            let sale_price = coupons::calculate_sale_price(&mut coupon_house, 100, utf8(b"50_PERCENT_5_PLUS_NAMES"));
            assert!(sale_price == 50, 1);
            test_scenario::return_shared(coupon_house);
        };
        test_scenario::end(scenario_val);
    }
    // Tests the e2e experience for coupons (a list of different coupons with different rules)
    #[test, expected_failure(abort_code=coupons::coupons::EIncorrectAmount)]
    fun test_invalid_coin_failure() {
        let scenario_val = setup::test_init();
        let scenario = &mut scenario_val;
        // populate all coupons.
        populate_coupons(scenario);
        // 5 SUI discount coupon.
        setup::register_with_coupon(utf8(b"5_SUI_DISCOUNT"), utf8(b"test.sui"), 1, 200 * mist_per_sui(), 0, user(), scenario);
        test_scenario::end(scenario_val);
    }
     #[test, expected_failure(abort_code=coupons::coupons::ECouponNotExists)]
    fun no_more_available_claims_failure() {
        let scenario_val = setup::test_init();
        let scenario = &mut scenario_val;
        populate_coupons(scenario);
        setup::register_with_coupon(utf8(b"25_PERCENT_DISCOUNT_USER_ONLY"), utf8(b"test.sui"), 1, 150 * mist_per_sui(), 0, user(), scenario);
        setup::register_with_coupon(utf8(b"25_PERCENT_DISCOUNT_USER_ONLY"), utf8(b"tost.sui"), 1, 150 * mist_per_sui(), 0, user(), scenario);
        test_scenario::end(scenario_val);
    }
    #[test, expected_failure(abort_code=coupons::coupons::EInvalidYearsArgument)]
    fun invalid_years_claim_failure() {
        let scenario_val = setup::test_init();
        let scenario = &mut scenario_val;
        populate_coupons(scenario);
        setup::register_with_coupon(utf8(b"25_PERCENT_DISCOUNT_USER_ONLY"), utf8(b"test.sui"), 6, 150 * mist_per_sui(), 0, user(), scenario);
        test_scenario::end(scenario_val);
    }
    #[test, expected_failure(abort_code=coupons::coupons::EInvalidYearsArgument)]
    fun invalid_years_claim_1_failure() {
        let scenario_val = setup::test_init();
        let scenario = &mut scenario_val;
        populate_coupons(scenario);
        setup::register_with_coupon(utf8(b"25_PERCENT_DISCOUNT_USER_ONLY"), utf8(b"test.sui"), 0, 150 * mist_per_sui(), 0, user(), scenario);
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code=coupons::rules::EInvalidUser)]
    fun invalid_user_failure() {
        let scenario_val = setup::test_init();
        let scenario = &mut scenario_val;
        populate_coupons(scenario);
        setup::register_with_coupon(utf8(b"25_PERCENT_DISCOUNT_USER_ONLY"), utf8(b"test.sui"), 1, 150 * mist_per_sui(), 0, user_two(), scenario);
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code=coupons::rules::ECouponExpired)]
    fun coupon_expired_failure() {
        let scenario_val = setup::test_init();
        let scenario = &mut scenario_val;
        populate_coupons(scenario);
        setup::register_with_coupon(utf8(b"50_PERCENT_3_DIGITS"), utf8(b"tes.sui"), 1, 150 * mist_per_sui(), 2, user_two(), scenario);
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code=coupons::rules::ENotValidYears)]
    fun coupon_not_valid_for_years_failure() {
        let scenario_val = setup::test_init();
        let scenario = &mut scenario_val;
        populate_coupons(scenario);
        setup::register_with_coupon(utf8(b"50_DISCOUNT_SALAD"), utf8(b"tes.sui"), 3, 150 * mist_per_sui(), 0, user(), scenario);
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code=coupons::rules::EInvalidForDomainLength)]
    fun coupon_invalid_length_1_failure() {
        let scenario_val = setup::test_init();
        let scenario = &mut scenario_val;
        populate_coupons(scenario);
        setup::register_with_coupon(utf8(b"50_PERCENT_3_DIGITS"), utf8(b"test.sui"), 1, 150 * mist_per_sui(), 2, user_two(), scenario);
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code=coupons::rules::EInvalidForDomainLength)]
    fun coupon_invalid_length_2_failure() {
        let scenario_val = setup::test_init();
        let scenario = &mut scenario_val;
        populate_coupons(scenario);
        // Tries to use 5 digit name for a <=4 digit one.
        setup::register_with_coupon(utf8(b"50_DISCOUNT_SALAD"), utf8(b"testo.sui"), 1, 150 * mist_per_sui(), 2, user(), scenario);
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code=coupons::rules::EInvalidForDomainLength)]
    fun coupon_invalid_length_3_failure() {
        let scenario_val = setup::test_init();
        let scenario = &mut scenario_val;
        populate_coupons(scenario);
        // Tries to use 4 digit name for a 5+ chars coupon.
        setup::register_with_coupon(utf8(b"50_PERCENT_5_PLUS_NAMES"), utf8(b"test.sui"), 1, 150 * mist_per_sui(), 2, user(), scenario);
        test_scenario::end(scenario_val);
    }

    #[test]
    fun add_coupon_as_admin() {
        let scenario_val = setup::test_init();
        let scenario = &mut scenario_val;
        populate_coupons(scenario);
        // add a no rule coupon as an admin
        setup::admin_add_coupon(utf8(b"TEST_SUCCESS_ADDITION"), constants::fixed_price_discount_type(), 100 * mist_per_sui(),  scenario);
        setup::admin_remove_coupon(utf8(b"TEST_SUCCESS_ADDITION"), scenario);

        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code=coupons::rules::EInvalidType)]
    fun add_coupon_invalid_type_failure() {
        let scenario_val = setup::test_init();
        let scenario = &mut scenario_val;
        populate_coupons(scenario);
        setup::admin_add_coupon(utf8(b"TEST_SUCCESS_ADDITION"), 5, 100 * mist_per_sui(),  scenario);
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code=coupons::rules::EInvalidAmount)]
    fun add_coupon_invalid_amount_failure() {
        let scenario_val = setup::test_init();
        let scenario = &mut scenario_val;
        populate_coupons(scenario);
        setup::admin_add_coupon(utf8(b"TEST_SUCCESS_ADDITION"), constants::percentage_discount_type(), 101,  scenario);
        test_scenario::end(scenario_val);
    }
    #[test, expected_failure(abort_code=coupons::rules::EInvalidAmount)]
    fun add_coupon_invalid_amount_2_failure() {
        let scenario_val = setup::test_init();
        let scenario = &mut scenario_val;
        populate_coupons(scenario);
        setup::admin_add_coupon(utf8(b"TEST_SUCCESS_ADDITION"), constants::percentage_discount_type(), 0,  scenario);
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code=coupons::coupons::ECouponAlreadyExists)]
    fun add_coupon_twice_failure() {
        let scenario_val = setup::test_init();
        let scenario = &mut scenario_val;
        populate_coupons(scenario);
        setup::admin_add_coupon(utf8(b"TEST_SUCCESS_ADDITION"), constants::percentage_discount_type(), 100,  scenario);
        setup::admin_add_coupon(utf8(b"TEST_SUCCESS_ADDITION"), constants::percentage_discount_type(), 100,  scenario);
        test_scenario::end(scenario_val);
    }
}