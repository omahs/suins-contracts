// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module suins::controller_tests {
    use std::string::{utf8, String};
    use std::option::{Option, extract, some, none};

    use sui::test_scenario::{Self, Scenario, ctx};
    use sui::clock::{Self, Clock};
    use sui::transfer;
    use sui::test_utils::assert_eq;
    use sui::dynamic_field;
    use sui::vec_map::{Self, VecMap};

    use suins::register_sample::Register;
    use suins::constants::{mist_per_sui, year_ms};
    use suins::suins::{Self, SuiNS, AdminCap};
    use suins::suins_registration::SuinsRegistration;
    use suins::register_sample_tests::register_util;
    use suins::controller::{Self, Controller, set_target_address_for_testing, set_reverse_lookup_for_testing, unset_reverse_lookup_for_testing, set_user_data_for_testing, unset_user_data_for_testing};
    use suins::registry::{Self, Registry, lookup, reverse_lookup};
    use suins::name_record;
    use suins::domain::{Self, Domain};

    const SUINS_ADDRESS: address = @0xA001;
    const FIRST_ADDRESS: address = @0xB001;
    const SECOND_ADDRESS: address = @0xB002;
    const AUCTIONED_DOMAIN_NAME: vector<u8> = b"tes-t2.sui";
    const DOMAIN_NAME: vector<u8> = b"abc.sui";
    const AVATAR: vector<u8> = b"avatar";
    const CONTENT_HASH: vector<u8> = b"content_hash";

    fun test_init(): Scenario {
        let scenario_val = test_scenario::begin(SUINS_ADDRESS);
        let scenario = &mut scenario_val;
        {
            let suins = suins::init_for_testing(ctx(scenario));
            suins::authorize_app_for_testing<Register>(&mut suins);
            suins::authorize_app_for_testing<Controller>(&mut suins);
            suins::share_for_testing(suins);
            let clock = clock::create_for_testing(ctx(scenario));
            clock::share_for_testing(clock);
        };
        {
            test_scenario::next_tx(scenario, SUINS_ADDRESS);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);
            let suins = test_scenario::take_shared<SuiNS>(scenario);

            registry::init_for_testing(&admin_cap, &mut suins, ctx(scenario));

            test_scenario::return_shared(suins);
            test_scenario::return_to_sender(scenario, admin_cap);
        };
        scenario_val
    }

    fun setup(scenario: &mut Scenario, sender: address, clock_tick: u64) {
        let nft = register_util(scenario, utf8(DOMAIN_NAME), 1, 1200 * mist_per_sui(), clock_tick);
        transfer::public_transfer(nft, sender);
    }

    public fun set_target_address_util(scenario: &mut Scenario, sender: address, target: Option<address>, clock_tick: u64) {
        test_scenario::next_tx(scenario, sender);
        let suins = test_scenario::take_shared<SuiNS>(scenario);
        let nft = test_scenario::take_from_sender<SuinsRegistration>(scenario);
        let clock = test_scenario::take_shared<Clock>(scenario);

        clock::increment_for_testing(&mut clock, clock_tick);
        set_target_address_for_testing(&mut suins, &nft, target, &clock);

        test_scenario::return_shared(clock);
        test_scenario::return_to_sender(scenario, nft);
        test_scenario::return_shared(suins);
    }

    public fun set_reverse_lookup_util(scenario: &mut Scenario, sender: address, domain_name: String) {
        test_scenario::next_tx(scenario, sender);
        let suins = test_scenario::take_shared<SuiNS>(scenario);

        set_reverse_lookup_for_testing(&mut suins, domain_name, ctx(scenario));

        test_scenario::return_shared(suins);
    }

    public fun unset_reverse_lookup_util(scenario: &mut Scenario, sender: address) {
        test_scenario::next_tx(scenario, sender);
        let suins = test_scenario::take_shared<SuiNS>(scenario);

        unset_reverse_lookup_for_testing(&mut suins, ctx(scenario));

        test_scenario::return_shared(suins);
    }

    public fun set_user_data_util(scenario: &mut Scenario, sender: address, key: String, value: String, clock_tick: u64) {
        test_scenario::next_tx(scenario, sender);
        let suins = test_scenario::take_shared<SuiNS>(scenario);
        let nft = test_scenario::take_from_sender<SuinsRegistration>(scenario);
        let clock = test_scenario::take_shared<Clock>(scenario);

        clock::increment_for_testing(&mut clock, clock_tick);
        set_user_data_for_testing(&mut suins, &nft, key, value, &clock);

        test_scenario::return_shared(clock);
        test_scenario::return_to_sender(scenario, nft);
        test_scenario::return_shared(suins);
    }

    public fun unset_user_data_util(scenario: &mut Scenario, sender: address, key: String, clock_tick: u64) {
        test_scenario::next_tx(scenario, sender);
        let suins = test_scenario::take_shared<SuiNS>(scenario);
        let nft = test_scenario::take_from_sender<SuinsRegistration>(scenario);
        let clock = test_scenario::take_shared<Clock>(scenario);

        clock::increment_for_testing(&mut clock, clock_tick);
        unset_user_data_for_testing(&mut suins, &nft, key, &clock);

        test_scenario::return_shared(clock);
        test_scenario::return_to_sender(scenario, nft);
        test_scenario::return_shared(suins);
    }

    fun lookup_util(scenario: &mut Scenario, domain_name: String, expected_target_addr: Option<address>) {
        test_scenario::next_tx(scenario, SUINS_ADDRESS);
        let suins = test_scenario::take_shared<SuiNS>(scenario);

        let registry = suins::registry<Registry>(&suins);
        let record = extract(&mut lookup(registry, domain::new(domain_name)));
        assert_eq(name_record::target_address(&record), expected_target_addr);

        test_scenario::return_shared(suins);
    }

    fun get_user_data(scenario: &mut Scenario, domain_name: String): VecMap<String, String> {
        test_scenario::next_tx(scenario, SUINS_ADDRESS);
        let suins = test_scenario::take_shared<SuiNS>(scenario);

        let registry = suins::registry<Registry>(&suins);
        let record = extract(&mut lookup(registry, domain::new(domain_name)));
        let data = *name_record::data(&record);
        test_scenario::return_shared(suins);

        data
    }

    fun reverse_lookup_util(scenario: &mut Scenario, addr: address, expected_domain_name: Option<Domain>) {
        test_scenario::next_tx(scenario, SUINS_ADDRESS);
        let suins = test_scenario::take_shared<SuiNS>(scenario);

        let registry = suins::registry<Registry>(&suins);
        let domain_name = reverse_lookup(registry, addr);
        assert_eq(domain_name, expected_domain_name);

        test_scenario::return_shared(suins);
    }

    fun deauthorize_app_util(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, SUINS_ADDRESS);
        let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);
        let suins = test_scenario::take_shared<SuiNS>(scenario);

        suins::deauthorize_app<Controller>(&admin_cap, &mut suins);

        test_scenario::return_shared(suins);
        test_scenario::return_to_sender(scenario, admin_cap);
    }

    #[test]
    fun test_set_target_address() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);

        set_target_address_util(scenario, FIRST_ADDRESS, some(SECOND_ADDRESS), 0);
        lookup_util(scenario, utf8(DOMAIN_NAME), some(SECOND_ADDRESS));
        set_target_address_util(scenario, FIRST_ADDRESS, some(FIRST_ADDRESS), 0);
        lookup_util(scenario, utf8(DOMAIN_NAME), some(FIRST_ADDRESS));
        set_target_address_util(scenario, FIRST_ADDRESS, none(), 0);
        lookup_util(scenario, utf8(DOMAIN_NAME), none());

        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = registry::ERecordExpired)]
    fun test_set_target_address_aborts_if_nft_expired() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);

        set_target_address_util(scenario, FIRST_ADDRESS, some(SECOND_ADDRESS), 2 * year_ms());

        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = registry::EIdMismatch)]
    fun test_set_target_address_aborts_if_nft_expired_2() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);
        setup(scenario, SECOND_ADDRESS, 2 * year_ms());

        set_target_address_util(scenario, FIRST_ADDRESS, some(SECOND_ADDRESS), 0);

        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_set_target_address_works_if_domain_is_registered_again() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);
        setup(scenario, SECOND_ADDRESS, 2 * year_ms());

        set_target_address_util(scenario, SECOND_ADDRESS, some(SECOND_ADDRESS), 0);
        lookup_util(scenario, utf8(DOMAIN_NAME), some(SECOND_ADDRESS));

        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = suins::suins::EAppNotAuthorized)]
    fun test_set_target_address_aborts_if_controller_is_deauthorized() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);

        deauthorize_app_util(scenario);
        set_target_address_util(scenario, FIRST_ADDRESS, some(SECOND_ADDRESS), 0);

        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_set_reverse_lookup() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);

        set_target_address_util(scenario, FIRST_ADDRESS, some(SECOND_ADDRESS), 0);
        reverse_lookup_util(scenario, SECOND_ADDRESS, none());
        set_reverse_lookup_util(scenario, SECOND_ADDRESS, utf8(DOMAIN_NAME));
        reverse_lookup_util(scenario, SECOND_ADDRESS, some(domain::new(utf8(DOMAIN_NAME))));

        set_target_address_util(scenario, FIRST_ADDRESS, some(FIRST_ADDRESS), 0);
        reverse_lookup_util(scenario, FIRST_ADDRESS, none());
        reverse_lookup_util(scenario, SECOND_ADDRESS, none());
        set_reverse_lookup_util(scenario, FIRST_ADDRESS, utf8(DOMAIN_NAME));
        reverse_lookup_util(scenario, FIRST_ADDRESS, some(domain::new(utf8(DOMAIN_NAME))));
        reverse_lookup_util(scenario, SECOND_ADDRESS, none());

        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = registry::ETargetNotSet)]
    fun test_set_reverse_lookup_aborts_if_target_address_not_set() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);

        reverse_lookup_util(scenario, SECOND_ADDRESS, none());
        set_reverse_lookup_util(scenario, SECOND_ADDRESS, utf8(DOMAIN_NAME));

        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = registry::ERecordMismatch)]
    fun test_set_reverse_lookup_aborts_if_target_address_not_match() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);

        set_target_address_util(scenario, FIRST_ADDRESS, some(FIRST_ADDRESS), 0);
        reverse_lookup_util(scenario, SECOND_ADDRESS, none());
        set_reverse_lookup_util(scenario, SECOND_ADDRESS, utf8(DOMAIN_NAME));

        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = suins::suins::EAppNotAuthorized)]
    fun test_set_reverse_lookup_aborts_if_controller_is_deauthorized() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);

        set_target_address_util(scenario, FIRST_ADDRESS, some(SECOND_ADDRESS), 0);
        deauthorize_app_util(scenario);
        set_reverse_lookup_util(scenario, SECOND_ADDRESS, utf8(DOMAIN_NAME));

        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_unset_reverse_lookup() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);

        set_target_address_util(scenario, FIRST_ADDRESS, some(SECOND_ADDRESS), 0);
        set_reverse_lookup_util(scenario, SECOND_ADDRESS, utf8(DOMAIN_NAME));
        reverse_lookup_util(scenario, SECOND_ADDRESS, some(domain::new(utf8(DOMAIN_NAME))));
        unset_reverse_lookup_util(scenario, SECOND_ADDRESS);
        reverse_lookup_util(scenario, SECOND_ADDRESS, none());

        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = suins::suins::EAppNotAuthorized)]
    fun test_unset_reverse_lookup_if_controller_is_deauthorized() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);

        set_target_address_util(scenario, FIRST_ADDRESS, some(SECOND_ADDRESS), 0);
        set_reverse_lookup_util(scenario, SECOND_ADDRESS, utf8(DOMAIN_NAME));
        deauthorize_app_util(scenario);
        unset_reverse_lookup_util(scenario, SECOND_ADDRESS);

        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = dynamic_field::EFieldDoesNotExist)]
    fun test_unset_reverse_lookup_aborts_if_not_set() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);

        unset_reverse_lookup_util(scenario, SECOND_ADDRESS);

        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_set_user_data() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);

        let data = &get_user_data(scenario, utf8(DOMAIN_NAME));
        assert_eq(vec_map::size(data), 0);
        set_user_data_util(scenario, FIRST_ADDRESS, utf8(AVATAR), utf8(b"value_avatar"), 0);
        let data = &get_user_data(scenario, utf8(DOMAIN_NAME));
        assert_eq(vec_map::size(data), 1);
        assert_eq(*vec_map::get(data, &utf8(AVATAR)), utf8(b"value_avatar"));

        set_user_data_util(scenario, FIRST_ADDRESS, utf8(CONTENT_HASH), utf8(b"value_content_hash"), 0);
        let data = &get_user_data(scenario, utf8(DOMAIN_NAME));
        assert_eq(vec_map::size(data), 2);
        assert_eq(*vec_map::get(data, &utf8(AVATAR)), utf8(b"value_avatar"));
        assert_eq(*vec_map::get(data, &utf8(CONTENT_HASH)), utf8(b"value_content_hash"));

        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = controller::EUnsupportedKey)]
    fun test_set_user_data_aborts_if_key_is_unsupported() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);

        set_user_data_util(scenario, FIRST_ADDRESS, utf8(b"key"), utf8(b"value"), 0);

        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = registry::ERecordExpired)]
    fun test_set_user_data_aborts_if_nft_expired() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);

        set_user_data_util(scenario, FIRST_ADDRESS, utf8(AVATAR), utf8(b"value"), 2 * year_ms());

        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = registry::EIdMismatch)]
    fun test_set_user_data_aborts_if_nft_expired_2() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);
        setup(scenario, SECOND_ADDRESS, 2 * year_ms());

        set_user_data_util(scenario, FIRST_ADDRESS, utf8(AVATAR), utf8(b"value"), 0);

        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_set_user_data_works_if_domain_is_registered_again() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);
        setup(scenario, SECOND_ADDRESS, 2 * year_ms());

        set_user_data_util(scenario, SECOND_ADDRESS, utf8(AVATAR), utf8(b"value"), 0);
        let data = &get_user_data(scenario, utf8(DOMAIN_NAME));
        assert_eq(vec_map::size(data), 1);
        assert_eq(*vec_map::get(data, &utf8(AVATAR)), utf8(b"value"));

        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = suins::suins::EAppNotAuthorized)]
    fun test_set_user_data_aborts_if_controller_is_deauthorized() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);

        deauthorize_app_util(scenario);
        set_user_data_util(scenario, FIRST_ADDRESS, utf8(AVATAR), utf8(b"value_avatar"), 0);

        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_unset_user_data() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);

        set_user_data_util(scenario, FIRST_ADDRESS, utf8(AVATAR), utf8(b"value_avatar"), 0);
        unset_user_data_util(scenario, FIRST_ADDRESS, utf8(AVATAR), 0);
        let data = &get_user_data(scenario, utf8(DOMAIN_NAME));
        assert_eq(vec_map::size(data), 0);

        set_user_data_util(scenario, FIRST_ADDRESS, utf8(CONTENT_HASH), utf8(b"value_content_hash"), 0);
        set_user_data_util(scenario, FIRST_ADDRESS, utf8(AVATAR), utf8(b"value_avatar"), 0);
        unset_user_data_util(scenario, FIRST_ADDRESS, utf8(CONTENT_HASH), 0);
        let data = &get_user_data(scenario, utf8(DOMAIN_NAME));
        assert_eq(vec_map::size(data), 1);
        assert_eq(*vec_map::get(data, &utf8(AVATAR)), utf8(b"value_avatar"));

        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_unset_user_data_works_if_key_not_exists() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);

        unset_user_data_util(scenario, FIRST_ADDRESS, utf8(AVATAR), 0);

        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = registry::ERecordExpired)]
    fun test_unset_user_data_aborts_if_nft_expired() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);

        unset_user_data_util(scenario, FIRST_ADDRESS, utf8(AVATAR), 2 * year_ms());

        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = suins::suins::EAppNotAuthorized)]
    fun test_unset_user_data_works_if_controller_is_deauthorized() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        setup(scenario, FIRST_ADDRESS, 0);

        deauthorize_app_util(scenario);
        unset_user_data_util(scenario, FIRST_ADDRESS, utf8(AVATAR), 0);

        test_scenario::end(scenario_val);
    }
}