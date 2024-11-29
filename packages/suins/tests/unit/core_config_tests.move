module suins::core_config_tests;

use sui::test_utils::assert_eq;
use suins::constants;
use suins::core_config;
use suins::domain;
use sui::vec_map;

#[test]
fun test_config_creation_and_field_access() {
    let config = core_config::new(
        b"",
        3,
        63,
        constants::payments_version!(),
        vector[constants::sui_tld()],
        vec_map::empty(),
    );

    assert_eq(config.public_key(), b"");
    assert_eq(config.min_label_length(), 3);
    assert_eq(config.max_label_length(), 63);
    assert_eq(config.payments_version(), constants::payments_version!());
    assert!(config.is_valid_tld(&constants::sui_tld()));
}

#[test]
fun test_valid_domains() {
    let config = core_config::default();
    let mut domain = domain::new(b"suins.sui".to_string());
    config.assert_is_valid_for_sale(&domain);

    domain = domain::new(b"sui.sui".to_string());
    config.assert_is_valid_for_sale(&domain);
}
