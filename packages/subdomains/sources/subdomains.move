// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// A registration module for subdomains.
/// 
/// This module is responsible for creating subdomains and managing their settings.
/// 
/// It allows the following functionality:
/// 
/// 1. Registering a new subdomain as a holder of Parent NFT.
/// 2. Setup the subdomain with capabilities (creating nested names, extending to parent's renewal time).
/// 3. Registering `leaf` names (who have no Cap)
/// 4. Extending a subdomain expiration's time
/// 
/// Comments:
/// 
/// 1. By attaching the creation/extension attributes as metadata to the subdomain's NameRecord, we can easily
/// turn off this package completely, and retain the state on a different package deployment. This is useful
/// both for effort-less upgrade-ability and gas-cost savings.
/// 
/// TODOS:
/// 
/// 1. Add offensive list of words (to prevent creating offensive subdomains) once the PR is landed
/// 2. Add tests
/// 3. Create a `Managed SuinsRegistration` package (completely external) to allow delegating subdomain creation (ENOKI requirement)
/// 
module subdomains::subdomains {
    use std::option::{Self, Option};
    use std::string::{String, utf8};

    use sui::object::{Self, ID};
    use sui::tx_context::{TxContext};
    use sui::clock::Clock;
    use sui::dynamic_field::{Self as df};
    use sui::vec_map::{Self, VecMap};
    use sui::event;

    use suins::domain::{Self, Domain, is_subdomain, parent_from_child};
    use suins::registry::{Self, Registry};
    use suins::suins::{Self, SuiNS, AdminCap};
    use suins::suins_registration::{Self, SuinsRegistration};
    use suins::constants::{subdomain_allow_extension_key, subdomain_allow_creation_key, leaf_expiration_timestamp};
    use suins::name_record;

    use subdomains::utils::{Self, SubDomainConfig, validate_subdomain};

    /// Tries to create a subdomain that expires later than the parent.
    const EInvalidExpirationDate: u64 = 1;
    /// Tries to create a subdomain with a parent that is not allowed to do so.
    const ECreationDisabledForSubDomain: u64 = 2;
    /// Tries to extend the expiration of a subdomain which doesn't have the permission to do so.
    const EExtensionDisabledForSubDomain: u64 = 3;
    /// Tries to extend the time using a domain that is not a subdomain.
    const ENotSubdomain: u64 = 4;
    /// The subdomain has been replaced by a newer NFT, so it can't be renewed.
    const ESubdomainReplaced: u64 = 5;

    /// The authentication scheme for SuiNS.
    struct SubDomains has drop {}

    /// The key to store the parent's ID in the subdomain object.
    struct ParentKey has copy, store, drop {}

    /// The subdomain's config Holds the configuration for all subdomains registered in the system.
    struct App has store {
        config: SubDomainConfig
    }

    // We initialize the `App`
    public fun setup(suins: &mut SuiNS, cap: &AdminCap, _ctx: &mut TxContext){
        suins::add_registry(cap, suins, App {
            config: utils::default_config()
        })
    }

    /// Creates a `leaf` subdomain
    /// 
    /// A `leaf` subdomain, is a subdomain that is managed by the parent's NFT.
    /// 
    public fun create_leaf(
        suins: &mut SuiNS,
        parent: &SuinsRegistration,
        clock: &Clock,
        subdomain_name: String,
        target: address,
        ctx: &mut TxContext
    ) {
        let subdomain = domain::new(subdomain_name);

        // all validation logic for subdomain creation / management.
        internal_validate_nft_can_manage_subdomain(suins, parent, clock, subdomain, true);

        // emit event for indexing
        internal_emit_tweak_event(subdomain, leaf_expiration_timestamp(), true, option::some(target));

        // Aborts with `suins::registry::ERecordExists` if the subdomain already exists.
        registry::add_leaf_record(registry_mut(suins), subdomain, clock, target, ctx)
    }

    /// 
    /// Removes a `leaf` subdomain from the registry.
    /// 
    /// Management of the `leaf` subdomain can only be achieved through the parent's valid NFT.
    /// 
    public fun remove_leaf(
        suins: &mut SuiNS,
        parent: &SuinsRegistration,
        clock: &Clock,
        subdomain_name: String,
    ) {
        let subdomain = domain::new(subdomain_name);
        
        // all validation logic for subdomain creation / management.
        // We pass `false` as last argument because even if we don't have create capabilities (anymore),
        // we can still remove a leaf name (we just can't add a new one).
        internal_validate_nft_can_manage_subdomain(suins, parent, clock, subdomain, false);

        // indexing purposes.
        event::emit(SubDomainRemovedEvent {
            domain: subdomain,
            is_leaf: true
        });

        registry::remove_leaf_record(registry_mut(suins), subdomain)
    }

    /// Creates a new `node` subdomain
    /// 
    /// The following script does the following lookups:
    /// 1. Checks if app is authorized.
    /// 2. Validates that the parent NFT is valid and non expired.
    /// 3. Validates that the parent can create subdomains (based on the on-chain setup). [all 2nd level names with valid tld can create names]
    /// 4. Validates the subdomain validity.
    ///     2.1 Checks that the TLD is in the list of supported tlds.
    ///     2.2 Checks that the length of the new label has the min lenth.
    ///     2.3 Validates that this subdomain can indeed be registered by that parent.
    ///     2.4 Validates that the subdomain's expiration timestamp is less or equal to the parents.
    ///     2.5 Checks if this subdomain already exists. [If it does, it aborts if it's not expired, overrides otherwise]
    /// 
    /// It then saves the configuration for that child (manage-able by the parent), and returns the SuinsRegistration object.
    /// 
    public fun create_node(
        suins: &mut SuiNS,
        parent: &SuinsRegistration,
        clock: &Clock,
        subdomain_name: String,
        expiration_timestamp_ms: u64,
        allow_creation: bool,
        allow_time_extension: bool,
        ctx: &mut TxContext
    ): SuinsRegistration {
        let subdomain = domain::new(subdomain_name);
        // all validation logic for subdomain creation / management.
        internal_validate_nft_can_manage_subdomain(suins, parent, clock, subdomain, true);

        // validate that the requested expiration timestamp is not greater than the parent's one.
        assert!(expiration_timestamp_ms <= suins_registration::expiration_timestamp_ms(parent), EInvalidExpirationDate);

        // We register the subdomain (e.g. `subdomain.example.sui`) and return the SuinsRegistration object.
        // Aborts with `suins::registry::ERecordExists` if the subdomain already exists.
        let nft = internal_create_subdomain(registry_mut(suins), subdomain, expiration_timestamp_ms, object::id(parent), clock, ctx);

        // We create the `setup` for the particular SubDomain.
        // We save a setting like: `subdomain.example.sui` -> { allow_creation: true/false, allow_time_extension: true/false }
        internal_set_flag(suins, subdomain, subdomain_allow_creation_key(), allow_creation);
        internal_set_flag(suins, subdomain, subdomain_allow_extension_key(), allow_time_extension);

        nft
    }

    /// Extends the expiration of a `node` subdomain.
    public fun extend_expiration(
        suins: &mut SuiNS,
        nft: &mut SuinsRegistration,
        expiration_timestamp_ms: u64,
    ) {
        let registry = registry(suins);
        let subdomain = suins_registration::domain(nft);
        let parent_domain = parent_from_child(&subdomain);

        // first, we validate that we are indeed looking at a subdomain.
        assert!(is_subdomain(&subdomain), ENotSubdomain);

        // Check if time extension is allowed for this subdomain.
        assert!(is_extension_allowed(&internal_get_domain_config(suins, subdomain)), EExtensionDisabledForSubDomain);

        let existing_name_record = registry::lookup(registry, subdomain);
        let parent_name_record = registry::lookup(registry, parent_domain);

        // we need to make sure this name record exists (both child + parent), otherwise we don't have a valid object.
        assert!(option::is_some(&existing_name_record) && option::is_some(&parent_name_record), ESubdomainReplaced);
        // Validate that the parent of the name is the same as the actual parent
        // (to prevent cases where owner of the parent changed. When that happens, subdomains lose all abilities to renew / create subdomains)
        assert!(parent(nft) == name_record::nft_id(option::borrow(&parent_name_record)), ESubdomainReplaced);
    
        // validate that the requested expiration timestamp is not greater than the parent's one.
        assert!(expiration_timestamp_ms <= name_record::expiration_timestamp_ms(option::borrow(&parent_name_record)), EInvalidExpirationDate);

        // emit event for indexing.
        internal_emit_tweak_event(subdomain, expiration_timestamp_ms, false, name_record::target_address(&option::extract(&mut existing_name_record)));

        registry::set_expiration_timestamp_ms(registry_mut(suins), nft, subdomain, expiration_timestamp_ms);
    }

    /// Called by the parent domain to edit a subdomain's settings.
    /// - Allows the parent domain to `disable` time extension.
    /// - Allows the parent to `disable` subdomain (grand-children) creation --> Can't retract already created ones <--
    public fun edit_setup(
        suins: &mut SuiNS,
        parent: &SuinsRegistration,
        clock: &Clock,
        subdomain_name: String,
        allow_creation: bool,
        allow_time_extension: bool
    ) {
        // validate that parent is a valid, non expired object.
        registry::assert_nft_is_authorized(registry(suins), parent, clock);

        let parent_domain = suins_registration::domain(parent);
        let subdomain = domain::new(subdomain_name);

        // validate that the subdomain is valid for the supplied parent
        // (as well as it is valid in label length, total length, depth, etc).
        validate_subdomain(&parent_domain, &subdomain, &app_config(suins).config);

        // // validate that the parent can create subdomains, otherwise there's no point in allowing it to edit the setup.
        // internal_assert_parent_can_create_subdomains(suins, parent_domain);

        // We create the `setup` for the particular SubDomain.
        // We save a setting like: `subdomain.example.sui` -> { allow_creation: true/false, allow_time_extension: true/false }
        internal_set_flag(suins, subdomain, subdomain_allow_creation_key(), allow_creation);
        internal_set_flag(suins, subdomain, subdomain_allow_extension_key(), allow_time_extension);
    }

    /// Parent ID of a subdomain
    public fun parent(subdomain: &SuinsRegistration): ID {
        *df::borrow(suins_registration::uid(subdomain), ParentKey {})
    }

    // Sets/removes a (key,value) on the domain's NameRecord metadata (depending on cases).
    // Validation needs to happen on the calling function.
    fun internal_set_flag(
        self: &mut SuiNS,
        subdomain: Domain,
        key: String,
        enable: bool
    ) {
        let config = internal_get_domain_config(self, subdomain);
        let is_enabled = vec_map::contains(&config, &key);

        if(enable) {
            if(!is_enabled){
                vec_map::insert(&mut config, key,  utf8(b"1"));
            }
        }else {
            if(is_enabled){
                vec_map::remove(&mut config, &key);
            }
        };

        registry::set_data(registry_mut(self), subdomain, config);
    }

    /// Check if subdomain creation is allowed.
    fun is_creation_allowed(config: &VecMap<String, String>): bool {
        vec_map::contains(config, &subdomain_allow_creation_key())
    }

    /// Check if time extension is allowed.
    fun is_extension_allowed(config: &VecMap<String, String>): bool {
        vec_map::contains(config, &subdomain_allow_extension_key())
    }

    /// Get the name record's metadata for a subdomain.
    fun internal_get_domain_config(
        self: &SuiNS,
        subdomain: Domain
    ): VecMap<String, String> {
        let registry = registry(self);
        *registry::get_data(registry, subdomain)
    }

    /// Does all the regular checks for validating that a parent `SuinsRegistration` object
    /// can operate on a given subdomain.
    /// 
    /// 1. Checks that NFT is authorized.
    /// 2. Checks that the parent can create subdomains (applies to subdomain `node` names).
    /// 3. Validates that the subdomain is valid (accepted TLD, depth, length, is child of given parent, etc).
    fun internal_validate_nft_can_manage_subdomain(
        suins: &SuiNS,
        parent: &SuinsRegistration,
        clock: &Clock,
        subdomain: Domain,
        // pass `true` for `validate_creation` if you want to validate that the parent can create subdomains.
        // Not needed when editing the setup of a subdomain or removing leaf names.
        validate_creation: bool
    ) {
        // validate that parent is a valid, non expired object.
        registry::assert_nft_is_authorized(registry(suins), parent, clock);

        if(validate_creation) {
            // validate that the parent can create subdomains.
            internal_assert_parent_can_create_subdomains(suins, suins_registration::domain(parent));
        };

        // validate that the subdomain is valid for the supplied parent.
        validate_subdomain(&suins_registration::domain(parent), &subdomain, &app_config(suins).config);
    }

    /// Validate whether a `SuinsRegistration` object is eligible for creating a subdomain.
    /// 1. If the NFT is authorized (not expired, active)
    /// 2. If the parent is a subdomain, check whether it is allowed to create subdomains.
    fun internal_assert_parent_can_create_subdomains(
        self: &SuiNS,
        parent: Domain,
    ) {
        // if the parent is not a subdomain, we can always create subdomains.
        if(!is_subdomain(&parent)) {
            return
        };

        // if `parent` is a subdomain. We check the subdomain config to see if we are allowed to mint subdomains.
        // For regular names (e.g. example.sui), we can always mint subdomains.
        // if there's no config for this parent, and the parent is a subdomain, we can't create deeper names.
         assert!(is_creation_allowed(&internal_get_domain_config(self, parent)), ECreationDisabledForSubDomain);
    }


    /// An internal function to add a subdomain to the registry with the correct expiration timestamp. 
    /// It doesn't check whether the expiration is valid. This needs to be checked on the calling function.
    fun internal_create_subdomain(
        registry: &mut Registry,
        subdomain: Domain,
        expiration_timestamp_ms: u64,
        parent_nft_id: ID,
        clock: &Clock,
        ctx: &mut TxContext,
    ): SuinsRegistration {
        let nft = registry::add_record_ignoring_grace_period(registry, subdomain, 1, clock, ctx);
        // set the timestamp to the correct one. `add_record` only works with years but we can correct it easily.
        registry::set_expiration_timestamp_ms(registry, &mut nft, subdomain, expiration_timestamp_ms);

        // attach the `ParentID` to the SuinsRegistration, so we validate that the parent who created this subdomain
        // is the same as the one currently holding the parent domain.
        df::add(suins_registration::uid_mut(&mut nft), ParentKey {}, parent_nft_id);

        // emits an event for our indexing purposes.
        internal_emit_tweak_event(subdomain, expiration_timestamp_ms, false, option::none());
        nft
    }

    /// Emits an event to help us index on our BE.
    fun internal_emit_tweak_event(domain: Domain, expiration_timestamp_ms: u64, is_leaf: bool, target: Option<address>) {
        event::emit(SubDomainTweakEvent {
            domain: domain,
            expiration_timestamp_ms: expiration_timestamp_ms,
            is_leaf: is_leaf,
            target: target
        });
    }

    // == Internal helper to access registry & app setup ==
    fun registry(suins: &SuiNS): &Registry {
        suins::registry<Registry>(suins)
    }

    fun registry_mut(suins: &mut SuiNS): &mut Registry {
        suins::app_registry_mut<SubDomains, Registry>(SubDomains {}, suins)
    }

    fun app_config(suins: &SuiNS): &App {
        suins::registry<App>(suins)
    }

    // === Events ===

    /// Event that's indexed on our Indexer.
    /// We save the created subdomain (out of which we can also extract the parent) and the expiration timestamp.
    /// We reuse the same event both for creation and renewal of subdomain's expiration.
    struct SubDomainTweakEvent has copy, drop {
        domain: Domain,
        expiration_timestamp_ms: u64,
        is_leaf: bool,
        target: Option<address>
    }

    /// Even called when a `leaf` name is removed.
    struct SubDomainRemovedEvent has copy, drop {
        domain: Domain,
        is_leaf: bool,
    }

    #[test_only]
    public fun auth_for_testing(): SubDomains {
        SubDomains {}
    }
}