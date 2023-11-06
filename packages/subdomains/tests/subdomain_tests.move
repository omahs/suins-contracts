// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

#[test_only]
module subdomains::subdomain_tests {
    use std::vector;
    use std::string::{String, utf8};

    use sui::test_scenario::{Self as ts, Scenario, ctx};
    use sui::clock::{Self, Clock};
    use sui::transfer;

    use suins::domain;
    use suins::suins::{Self, SuiNS, AdminCap};
    use suins::registry::{Self, Registry};
    use suins::suins_registration::{Self, SuinsRegistration};

    use subdomains::subdomains::{Self, SubDomains};

    const USER_ADDRESS: address = @0x01;
    const TEST_ADDRESS: address = @0x02;


    #[test]
    /// A test scenario
    fun test_multiple_operation_cases() {

        let scenario_val = test_init();
        let scenario = &mut scenario_val;

        let parent = create_sld_name(utf8(b"test.sui"), scenario);

        let child = create_node_subdomain(&parent, utf8(b"node.test.sui"), 1, true, true, scenario);

        create_leaf_subdomain(&parent, utf8(b"leaf.test.sui"), TEST_ADDRESS, scenario);
        remove_leaf_subdomain(&parent, utf8(b"leaf.test.sui"), scenario);

        // Create a node name with the same name as the leaf that was deleted.
        let another_child = create_node_subdomain(&parent, utf8(b"leaf.test.sui"), 1, true, true, scenario);

        let nested = create_node_subdomain(&child, utf8(b"nested.node.test.sui"), 1, true, true, scenario);

        // extend node's subdomain expiration to the limit.
        extend_node_subdomain(&mut child, suins_registration::expiration_timestamp_ms(&parent), scenario);

        // update subdomain's setup for testing
        update_subdomain_setup(&parent, utf8(b"node.test.sui"), false, false, scenario);

        return_nfts(vector[parent, child, nested, another_child]);
        ts::end(scenario_val);
    }

    #[test, expected_failure(abort_code=subdomains::subdomains::EInvalidExpirationDate)]
    fun expiration_past_parents_expiration() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        let parent = create_sld_name(utf8(b"test.sui"), scenario);

        let _child = create_node_subdomain(&parent, utf8(b"node.test.sui"), suins_registration::expiration_timestamp_ms(&parent) + 1, true, true, scenario);

        abort 1337
    }

    #[test, expected_failure(abort_code=subdomains::utils::EInvalidParent)]
    /// tries to create a child node using an invalid parent.
    fun invalid_parent_failure(){
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        let parent = create_sld_name(utf8(b"test.sui"), scenario);

        let _child = create_node_subdomain(&parent, utf8(b"node.example.sui"), suins_registration::expiration_timestamp_ms(&parent), true, true, scenario);

        abort 1337  
    }


    #[test, expected_failure(abort_code=subdomains::subdomains::ECreationDisabledForSubDomain)]
    fun tries_to_create_subdomain_with_disallowed_node_parent() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        let parent = create_sld_name(utf8(b"test.sui"), scenario);

        let child = create_node_subdomain(&parent, utf8(b"node.test.sui"), suins_registration::expiration_timestamp_ms(&parent), false, true, scenario);

        let _nested = create_node_subdomain(&child, utf8(b"test.node.test.sui"), suins_registration::expiration_timestamp_ms(&child), false, true, scenario);

        abort 1337  
    }

    #[test, expected_failure(abort_code=subdomains::subdomains::EExtensionDisabledForSubDomain)]
    fun tries_to_extend_without_permissions() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        let parent = create_sld_name(utf8(b"test.sui"), scenario);

        let child = create_node_subdomain(&parent, utf8(b"node.test.sui"), 1, false, false, scenario);

        extend_node_subdomain(&mut child, 2, scenario);

        abort 1337  
    }

    #[test, expected_failure(abort_code=subdomains::subdomains::ENotSubdomain)]
    /// Tries to use an SLD name in the "time extension" feature.
    fun tries_to_extend_sld_name() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        let parent = create_sld_name(utf8(b"test.sui"), scenario);
        extend_node_subdomain(&mut parent, 2291929129219, scenario);
        abort 1337  
    }

    #[test, expected_failure(abort_code=suins::registry::ERecordExpired)]
    fun tries_to_use_expired_subdomain_to_create_new() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        let parent = create_sld_name(utf8(b"test.sui"), scenario);

        let child = create_node_subdomain(&parent, utf8(b"node.test.sui"), 1, true, true, scenario);


        ts::next_tx(scenario, USER_ADDRESS);
        // child 1 must be expired here.
        let clock = ts::take_shared<Clock>(scenario);
        clock::increment_for_testing(&mut clock, 2);
        ts::return_shared(clock);

        create_leaf_subdomain(&child, utf8(b"node.node.test.sui"), TEST_ADDRESS, scenario);

        abort 1337  
    }




    /// == Helpers == 
   
    /// Transfer the NFTs to the user to clean up tests easily
    fun return_nfts(nfts: vector<SuinsRegistration>) {
        let len = vector::length(&nfts);
        let i = len;

        while(i > 0) {
            i = i - 1;
            let nft = vector::pop_back(&mut nfts);
            
            transfer::public_transfer(nft, USER_ADDRESS);

        };

        vector::destroy_empty(nfts);
    }

    public fun test_init(): Scenario {
        let scenario_val = ts::begin(USER_ADDRESS);
        let scenario = &mut scenario_val;
        {
            let suins = suins::init_for_testing(ctx(scenario));
            suins::authorize_app_for_testing<SubDomains>(&mut suins);
            suins::share_for_testing(suins);
            let clock = clock::create_for_testing(ctx(scenario));
            clock::share_for_testing(clock);
        };
        {
            ts::next_tx(scenario, USER_ADDRESS);
            let admin_cap = ts::take_from_sender<AdminCap>(scenario);
            let suins = ts::take_shared<SuiNS>(scenario);

            subdomains::setup(&mut suins, &admin_cap, ctx(scenario));
            registry::init_for_testing(&admin_cap, &mut suins, ctx(scenario));

            ts::return_shared(suins);
            ts::return_to_sender(scenario, admin_cap);
        };
        scenario_val
    }

    /// Get the active registry of the current scenario. (mutable, so we can add extra names ourselves)
    public fun registry_mut(suins: &mut SuiNS): &mut Registry {

        let registry_mut = suins::app_registry_mut<SubDomains, Registry>(subdomains::auth_for_testing(), suins);

        registry_mut
    }
    
    /// Create a regular name to help with our tests.
    public fun create_sld_name(name: String, scenario: &mut Scenario): SuinsRegistration {
        ts::next_tx(scenario, USER_ADDRESS);
        let suins = ts::take_shared<SuiNS>(scenario);
        let clock = ts::take_shared<Clock>(scenario);
        let registry_mut = registry_mut(&mut suins);

        let parent = registry::add_record(registry_mut, domain::new(name), 1, &clock, ctx(scenario));

        ts::return_shared(clock);
        ts::return_shared(suins);
        parent
    } 

    /// Create a leaf subdomain
    public fun create_leaf_subdomain(parent: &SuinsRegistration, name: String, target: address, scenario: &mut Scenario) {
        ts::next_tx(scenario, USER_ADDRESS);
        let suins = ts::take_shared<SuiNS>(scenario);
        let clock = ts::take_shared<Clock>(scenario);

        subdomains::create_leaf(&mut suins, parent, &clock, name, target, ctx(scenario));

        ts::return_shared(suins);
        ts::return_shared(clock);
    }

    /// Remove a leaf subdomain
    public fun remove_leaf_subdomain(parent: &SuinsRegistration, name: String, scenario: &mut Scenario) {
        ts::next_tx(scenario, USER_ADDRESS);
        let suins = ts::take_shared<SuiNS>(scenario);
        let clock = ts::take_shared<Clock>(scenario);
        
        subdomains::remove_leaf(&mut suins, parent, &clock, name);

        ts::return_shared(suins);
        ts::return_shared(clock);
    }

    /// Create a node subdomain
    public fun create_node_subdomain(parent: &SuinsRegistration, name: String, expiration: u64, allow_creation: bool, allow_extension: bool, scenario: &mut Scenario): SuinsRegistration {
        ts::next_tx(scenario, USER_ADDRESS);
        let suins = ts::take_shared<SuiNS>(scenario);
        let clock = ts::take_shared<Clock>(scenario);

        let nft = subdomains::create_node(&mut suins, parent, &clock, name, expiration, allow_creation, allow_extension, ctx(scenario));

        ts::return_shared(suins);
        ts::return_shared(clock);

        nft
    }

    /// Extend a node subdomain's expiration.
    public fun extend_node_subdomain(nft: &mut SuinsRegistration, expiration: u64, scenario: &mut Scenario) {
        ts::next_tx(scenario, USER_ADDRESS);
        let suins = ts::take_shared<SuiNS>(scenario);
        let clock = ts::take_shared<Clock>(scenario);

        subdomains::extend_expiration(&mut suins, nft, expiration);

        ts::return_shared(suins);
        ts::return_shared(clock);
    }

    public fun update_subdomain_setup(parent: &SuinsRegistration, subdomain: String, allow_creation: bool, allow_extension: bool, scenario: &mut Scenario) {
        ts::next_tx(scenario, USER_ADDRESS);
        let suins = ts::take_shared<SuiNS>(scenario);
        let clock = ts::take_shared<Clock>(scenario);


        subdomains::edit_setup(&mut suins, parent, &clock, subdomain, allow_creation, allow_extension);


        ts::return_shared(suins);
        ts::return_shared(clock);
    } 

}
