module suins::base_registry {
    use sui::event;
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self, VecMap};
    use std::option::{Self, Option};
    use std::string::{Self, String};

    friend suins::base_registrar;
    friend suins::reverse_registrar;
    friend suins::base_controller;
    friend suins::name_resolver;
    friend suins::addr_resolver;

    const MAX_TTL: u64 = 0x100000;

    // errors in the range of 101..200 indicate Registry errors
    const EUnauthorized: u64 = 101;
    const ERecordNotExists: u64 = 102;

    // https://examples.sui.io/patterns/capability.html
    struct AdminCap has key { id: UID }

    struct NewOwnerEvent has copy, drop {
        node: String,
        owner: address,
    }

    struct NewResolverEvent has copy, drop {
        node: String,
        resolver: address,
    }

    struct NewTTLEvent has copy, drop {
        node: String,
        ttl: u64,
    }

    struct NewRecordEvent has copy, drop {
        node: String,
        owner: address,
        resolver: address,
        ttl: u64,
    }

    // objects of this type are stored in the registry's map
    struct Record has store, drop {
        owner: address,
        resolver: address,
        ttl: u64,
    }

    struct Registry has key {
        id: UID,
        records: VecMap<String, Record>,
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(Registry {
            id: object::new(ctx),
            records: vec_map::empty(),
        });
        transfer::transfer(AdminCap {
            id: object::new(ctx)
        }, tx_context::sender(ctx));
    }

    public fun owner(registry: &Registry, node: vector<u8>): address {
        if (record_exists(registry, &string::utf8(node))) {
            return vec_map::get(&registry.records, &string::utf8(node)).owner
        };
        abort ERecordNotExists
    }

    public fun resolver(registry: &Registry, node: vector<u8>): address {
        if (record_exists(registry, &string::utf8(node))) {
            return vec_map::get(&registry.records, &string::utf8(node)).resolver
        };
        abort ERecordNotExists
    }

    public fun ttl(registry: &Registry, node: vector<u8>): u64 {
        if (record_exists(registry, &string::utf8(node))) {
            return vec_map::get(&registry.records, &string::utf8(node)).ttl
        };
        abort ERecordNotExists
    }

    public fun record_exists(registry: &Registry, node: &String): bool {
        vec_map::contains(&registry.records, node)
    }

    public entry fun set_record(
        registry: &mut Registry,
        node: vector<u8>,
        owner: address,
        resolver: address,
        ttl: u64,
        ctx: &mut TxContext,
    ) {
        authorised(registry, node, ctx);

        let node = string::utf8(node);
        set_owner_or_create_record(
            registry,
            node,
            owner,
            option::some(resolver),
            option::some(ttl),
        );
        event::emit(NewRecordEvent { node, owner, resolver, ttl });

        let record = vec_map::get_mut(&mut registry.records, &node);
        record.resolver = resolver;
        record.ttl = ttl;
    }

    public entry fun set_subnode_record(
        registry: &mut Registry,
        node: vector<u8>,
        label: vector<u8>,
        owner: address,
        resolver: address,
        ttl: u64,
        ctx: &mut TxContext,
    ) {
        authorised(registry, node, ctx);

        let subnode = make_node(label, string::utf8(node));
        set_node_record_internal(registry, subnode, owner, resolver, ttl);
        event::emit(NewRecordEvent { node: subnode, owner, resolver, ttl });
    }

    public entry fun set_subnode_owner(
        registry: &mut Registry,
        node: vector<u8>,
        label: vector<u8>,
        owner: address,
        ctx: &mut TxContext,
    ) {
        authorised(registry, node, ctx);

        let node = make_node(label, string::utf8(node));
        set_owner_or_create_record(
            registry,
            node,
            owner,
            option::none<address>(),
            option::none<u64>(),
        );
        event::emit(NewOwnerEvent { node, owner });
    }

    public entry fun set_owner(registry: &mut Registry, node: vector<u8>, owner: address, ctx: &mut TxContext) {
        authorised(registry, node, ctx);

        let node = string::utf8(node);
        set_owner_internal(registry, node, owner);
        event::emit(NewOwnerEvent { node, owner });
    }

    public entry fun set_resolver(registry: &mut Registry, node: vector<u8>, resolver: address, ctx: &mut TxContext) {
        authorised(registry, node, ctx);

        let node = string::utf8(node);
        let record = vec_map::get_mut(&mut registry.records, &node);
        record.resolver = resolver;
        event::emit(NewResolverEvent { node, resolver });
    }

    public entry fun set_TTL(registry: &mut Registry, node: vector<u8>, ttl: u64, ctx: &mut TxContext) {
        authorised(registry, node, ctx);

        let node = string::utf8(node);
        let record = vec_map::get_mut(&mut registry.records, &node);
        record.ttl = ttl;
        event::emit(NewTTLEvent { node, ttl });
    }

    public(friend) fun set_owner_internal(registry: &mut Registry, node: String, owner: address) {
        let record = vec_map::get_mut(&mut registry.records, &node);
        record.owner = owner;
    }

    public(friend) fun make_node(label: vector<u8>, base_node: String): String {
        let node = string::utf8(label);
        string::append_utf8(&mut node, b".");
        string::append(&mut node, base_node);
        node
    }

    // this func is meant to be call by registrar, no need to check for owner
    public(friend) fun set_node_record_internal(
        registry: &mut Registry,
        node: String,
        owner: address,
        resolver: address,
        ttl: u64,
    ) {
        set_owner_or_create_record(
            registry,
            node,
            owner,
            option::some(resolver),
            option::some(ttl),
        );

        let record = vec_map::get_mut(&mut registry.records, &node);
        record.resolver = resolver;
        record.ttl = ttl;
    }

    public(friend) fun authorised(registry: &Registry, node: vector<u8>, ctx: &TxContext) {
        let owner = owner(registry, node);
        if (tx_context::sender(ctx) != owner) abort EUnauthorized;
    }

    fun set_owner_or_create_record(
        registry: &mut Registry,
        node: String,
        owner: address,
        resolver: Option<address>,
        ttl: Option<u64>,
    ) {
        if (vec_map::contains(&registry.records, &node)) {
            let record = vec_map::get_mut(&mut registry.records, &node);
            record.owner = owner;
            return
        };
        if (option::is_none(&resolver)) option::fill(&mut resolver, @0x0);
        if (option::is_none(&ttl)) option::fill(&mut ttl, 0);
        new_record(
            registry,
            node,
            owner,
            option::extract(&mut resolver),
            option::extract(&mut ttl),
        );
    }

    public(friend) fun new_record(
        registry: &mut Registry,
        node: String,
        owner: address,
        resolver: address,
        ttl: u64,
    ) {
        let record = Record {
            owner,
            resolver,
            ttl,
        };
        vec_map::insert(&mut registry.records, node, record);
    }

    #[test_only]
    friend suins::base_registry_tests;
    #[test_only]
    friend suins::name_resolver_tests;

    #[test_only]
    public fun get_record_at_index(registry: &Registry, index: u64): (&String, &Record) {
        vec_map::get_entry_by_idx(&registry.records, index)
    }
    
    #[test_only]
    public fun get_records_len(registry: &Registry): u64 { vec_map::size(&registry.records) }

    #[test_only]
    public fun get_record_owner(record: &Record): address { record.owner }

    #[test_only]
    public fun get_record_resolver(record: &Record): address { record.resolver }

    #[test_only]
    public fun get_record_ttl(record: &Record): u64 { record.ttl }

    #[test_only]
    public fun new_record_test(registry: &mut Registry, node: String, owner: address) {
        new_record(registry, node, owner, @0x0, 0);
    }

    #[test_only]
    /// Wrapper of module initializer for testing
    public fun test_init(ctx: &mut TxContext) { init(ctx) }
}