#[test_only]
module suins::payment_tests;

use sui::clock;
use sui::coin;
use sui::sui::SUI;
use sui::test_utils::{assert_eq, destroy};
use suins::payment::{Self, PaymentIntent, Receipt};
use suins::pricing_config::{Self, PricingConfig};
use suins::suins::{Self, SuiNS};
use suins::registry;
use suins::constants;
use suins::suins_registration;
use suins::domain;

public struct PaymentsApp() has drop;
public struct DiscountsApp() has drop;

#[test]
fun test_e2e() {
    let mut ctx = tx_context::dummy();
    let mut suins = setup_suins(&mut ctx);
    let clock = clock::create_for_testing(&mut ctx);

    let domain = b"test.sui".to_string();

    let intent = payment::init_registration(
        &mut suins,
        domain,
    );
    // checking the price is valid.
    assert_eq(intent.request_data().base_amount(), 100);

    // calling our "payments" package here.
    let receipt = handle_payment(intent, &mut suins, &mut ctx);

    // Now we can use our receipt to get a SuiNS name directly from the core protocol.
    let mut nft = receipt.register(&mut suins, &clock, &mut ctx);

    // let's validate our nft is the same name we expected for sanity check.
    assert_eq(nft.domain().to_string(), domain);

    // now let's renew this nft for 4 years.
    let mut intent = payment::init_renewal(&mut suins, &nft, 4);
    assert_eq(intent.request_data().discount_applied(), false);

    // our DiscountsApp is now applying a 40% discount to the renewal.
    intent.apply_percentage_discount(
        &mut suins,
        DiscountsApp(),
        40,
        false, // we shouldn't apply this discount if there have been more discounts applied.
    );

    intent.apply_percentage_discount(
        &mut suins,
        DiscountsApp(),
        50,
        true, // we shouldn't apply this discount if there have been more discounts applied.
    );

    // Checking the price is valid.
    // It should be 10 * 4 minus 40% (from the applied discount) divided by 2 (another 50% discount added in the end.)
    assert_eq(intent.request_data().base_amount(), 10 * 4 * (100-40) / 100 / 2);
    assert_eq(intent.request_data().years(), 4);
    assert_eq(intent.request_data().domain().to_string(), domain);
    assert_eq(intent.request_data().discount_applied(), true);

    // calling our "payments" package here.
    let receipt = handle_payment(intent, &mut suins, &mut ctx);

    // our nft expires in exactly 1 year (1 from purchase).
    assert_eq(nft.expiration_timestamp_ms(), constants::year_ms());

    // now using our renewal receipt, we can renew the NFT.
    receipt.renew(&mut suins, &mut nft, &clock, &mut ctx);

    // our nft expires in exactly 5 years (1 from purchase + 4 from renewal).
    assert_eq(nft.expiration_timestamp_ms(), constants::year_ms() * 5);

    destroy(suins);
    destroy(nft);
    destroy(clock);
}

#[test, expected_failure(abort_code = ::suins::payment::ENotMultipleDiscountsAllowed)]
fun try_apply_two_discounts_while_both_require_single(){
    let mut ctx = tx_context::dummy();
    let mut suins = setup_suins(&mut ctx);

    let mut intent = payment::init_registration(
        &mut suins,
        b"test.sui".to_string(),
    );
    intent.apply_percentage_discount(
        &mut suins,
        DiscountsApp(),
        40,
        false,
    );

    intent.apply_percentage_discount(
        &mut suins,
        DiscountsApp(),
        50,
        false,
    );

    abort 1337
}

#[test, expected_failure(abort_code = ::suins::payment::EInvalidDiscountPercentage)]
fun discount_overflow(){
    let mut ctx = tx_context::dummy();
    let mut suins = setup_suins(&mut ctx);

    let mut intent = payment::init_registration(
        &mut suins,
        b"test.sui".to_string(),
    );
    intent.apply_percentage_discount(
        &mut suins,
        DiscountsApp(),
        101,
        false,
    );

    abort 1337
}

#[test, expected_failure(abort_code = ::suins::payment::ENotSupportedType)]
fun try_to_register_using_renewal_receipt(){
    let mut ctx = tx_context::dummy();
    let mut suins = setup_suins(&mut ctx);
    let clock = clock::create_for_testing(&mut ctx);

    let receipt = payment::test_renewal_receipt(
        b"test.sui".to_string(),
        4,
        1, // version should be valid here.
    );

    let _nft = receipt.register(&mut suins, &clock, &mut ctx);

    abort 1337
}

#[test, expected_failure(abort_code = ::suins::payment::ENotSupportedType)]
fun try_to_renew_using_registration_receipt(){
    let mut ctx = tx_context::dummy();
    let mut suins = setup_suins(&mut ctx);
    let clock = clock::create_for_testing(&mut ctx);

    let mut nft = suins_registration::new_for_testing(
        domain::new(b"test.sui".to_string()),
        1,
        &clock,
        &mut ctx
    );

    let receipt = payment::test_registration_receipt(
        b"test.sui".to_string(),
        1,
        1, // version should be valid here.
    );

    receipt.renew(&mut suins, &mut nft, &clock, &mut ctx);
    abort 1337
}

#[test, expected_failure(abort_code = ::suins::payment::EReceiptDomainMissmatch)]
fun try_to_renew_with_other_name_receipt(){
    let mut ctx = tx_context::dummy();
    let mut suins = setup_suins(&mut ctx);
    let clock = clock::create_for_testing(&mut ctx);

    let mut nft = suins_registration::new_for_testing(
        domain::new(b"test2.sui".to_string()),
        1,
        &clock,
        &mut ctx
    );

    let receipt = payment::test_renewal_receipt(
        b"test.sui".to_string(),
        1,
        1, // version should be valid here.
    );

    receipt.renew(&mut suins, &mut nft, &clock, &mut ctx);
    abort 1337
}

#[test, expected_failure(abort_code = ::suins::payment::EVersionMismatch)]
fun try_to_register_using_invalid_receipt_version(){
    let mut ctx = tx_context::dummy();
    let mut suins = setup_suins(&mut ctx);
    let clock = clock::create_for_testing(&mut ctx);

    let receipt = payment::test_registration_receipt(
        b"test.sui".to_string(),
        1,
        2, // version should be valid here.
    );

    let _nft = receipt.register(&mut suins, &clock, &mut ctx);

    abort 1337
}

#[test, expected_failure(abort_code = ::suins::payment::EVersionMismatch)]
fun try_to_renew_using_invalid_receipt_version(){
    let mut ctx = tx_context::dummy();
    let mut suins = setup_suins(&mut ctx);
    let clock = clock::create_for_testing(&mut ctx);

   let mut nft = suins_registration::new_for_testing(
        domain::new(b"test.sui".to_string()),
        1,
        &clock,
        &mut ctx
    );

    let receipt = payment::test_renewal_receipt(
        b"test.sui".to_string(),
        1,
        2, // version should be valid here.
    );

    receipt.renew(&mut suins, &mut nft, &clock, &mut ctx);

    abort 1337
}

fun setup_suins(ctx: &mut TxContext): SuiNS {
    let (mut suins, cap)= suins::new_for_testing(ctx);

    let renewal_config = pricing_config::new_renewal_config(
        test_pricing_config(true),
    );

    cap.add_config(&mut suins, test_pricing_config(false));
    // add a renewal config.
    cap.add_config(&mut suins, renewal_config);

    // authorize a "payments" app that is responsible for handling payments and
    // issuing receipts.
    cap.authorize_app<PaymentsApp>(&mut suins);
    // authorize a "discounts" app that is responsible for applying discounts.
    cap.authorize_app<DiscountsApp>(&mut suins);

    registry::init_for_testing(&cap, &mut suins, ctx);

    destroy(cap);
    suins
}

// handles the payment, and if successful (always in this e2e test), issues the receipt.
fun handle_payment(
    intent: PaymentIntent,
    suins: &mut SuiNS,
    ctx: &mut TxContext,
): Receipt {
    // the amount the user needs to pay.
    let amount = intent.request_data().base_amount();
    let coin = coin::mint_for_testing<SUI>(amount, ctx);

    intent.finalize_payment(suins, PaymentsApp(), coin)
}

fun test_pricing_config(renewal: bool): PricingConfig {
    let ranges = vector[
        pricing_config::new_range(vector[3, 3]),
        pricing_config::new_range(vector[4, 4]),
        pricing_config::new_range(vector[5, 64]),
    ];

    let prices = if (renewal) {
        vector[50, 10, 2]
    } else {
        vector[500, 100, 20]
    };

    pricing_config::new(
        ranges,
        prices,
    )
}
