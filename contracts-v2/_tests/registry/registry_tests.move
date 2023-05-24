#[test_only]
module suins::registry_tests {

    use sui::test_scenario::{Self, Scenario};

    use suins::registrar;
    use std::string::utf8;
    use suins::suins::SuiNS;
    use suins::name_record;
    use suins::suins::{Self, AdminCap};

    const SUINS_ADDRESS: address = @0xA001;
    const FIRST_USER_ADDRESS: address = @0xB001;
    const SECOND_USER_ADDRESS: address = @0xB002;
    const FIRST_DOMAIN_NAME: vector<u8> = b"eastagile.sui";
    const SECOND_DOMAIN_NAME: vector<u8> = b"secondsuitest.sui";
    const THIRD_DOMAIN_NAME: vector<u8> = b"ea.eastagile.sui";

    fun test_init(): Scenario {
        let scenario = test_scenario::begin(SUINS_ADDRESS);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            suins::test_setup::setup(ctx);
        };

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            registrar::new_tld(&admin_cap, &mut suins, utf8(b"sui"), test_scenario::ctx(&mut scenario));
            registrar::new_tld(&admin_cap, &mut suins, utf8(b"addr.reverse"), test_scenario::ctx(&mut scenario));
            registrar::new_tld(&admin_cap, &mut suins, utf8(b"move"), test_scenario::ctx(&mut scenario));

            test_scenario::return_shared(suins);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
        };
        scenario
    }

    public fun mint_record(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, SUINS_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(scenario);
            suins::add_record_for_testing(
                &mut suins,
                utf8(FIRST_DOMAIN_NAME),
                FIRST_USER_ADDRESS,
            );
            test_scenario::return_shared(suins);
        };
    }

    // TODO: test for emitted events
    #[test]
    fun test_set_record_internal() {
        let scenario = test_init();
        mint_record(&mut scenario);
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            assert!(suins::record_owner(&suins, utf8(FIRST_DOMAIN_NAME)) == FIRST_USER_ADDRESS, 0);
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            suins::add_record_for_testing(
                &mut suins,
                utf8(FIRST_DOMAIN_NAME),
                SECOND_USER_ADDRESS,
            );
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let record = suins::name_record(&suins, utf8(FIRST_DOMAIN_NAME));
            let (owner, target_address) = (suins::record_owner(&suins, utf8(FIRST_DOMAIN_NAME)), name_record::target_address(record));

            assert!(owner == SECOND_USER_ADDRESS, 0);
            assert!(target_address == std::option::some(SECOND_USER_ADDRESS), 0);

            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_set_owner() {
        let scenario = test_init();
        mint_record(&mut scenario);

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            suins::transfer_ownership(
                &mut suins,
                utf8(FIRST_DOMAIN_NAME),
                SECOND_USER_ADDRESS,
                test_scenario::ctx(&mut scenario),
            );
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, SECOND_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            assert!(suins::record_owner(&suins, utf8(FIRST_DOMAIN_NAME)) == SECOND_USER_ADDRESS, 0);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = sui::dynamic_field::EFieldDoesNotExist)]
    fun test_set_owner_abort_if_domain_name_not_exists() {
        let scenario = test_init();
        mint_record(&mut scenario);

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            suins::transfer_ownership(
                &mut suins,
                utf8(SECOND_DOMAIN_NAME),
                SECOND_USER_ADDRESS,
                test_scenario::ctx(&mut scenario),
            );
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = suins::suins::ENotRecordOwner)]
    fun test_set_owner_abort_if_unauthorised() {
        let scenario = test_init();
        mint_record(&mut scenario);

        test_scenario::next_tx(&mut scenario, SECOND_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            suins::transfer_ownership(
                &mut suins,
                utf8(FIRST_DOMAIN_NAME),
                SECOND_USER_ADDRESS,
                test_scenario::ctx(&mut scenario),
            );
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }
}