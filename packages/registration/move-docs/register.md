
<a name="0x0_register"></a>

# Module `0x0::register`



-  [Struct `Register`](#0x0_register_Register)
-  [Constants](#@Constants_0)
-  [Function `register`](#0x0_register_register)


<pre><code><b>use</b> <a href="dependencies/move-stdlib/string.md#0x1_string">0x1::string</a>;
<b>use</b> <a href="dependencies/sui-framework/balance.md#0x2_balance">0x2::balance</a>;
<b>use</b> <a href="dependencies/sui-framework/clock.md#0x2_clock">0x2::clock</a>;
<b>use</b> <a href="dependencies/sui-framework/coin.md#0x2_coin">0x2::coin</a>;
<b>use</b> <a href="dependencies/sui-framework/sui.md#0x2_sui">0x2::sui</a>;
<b>use</b> <a href="dependencies/sui-framework/tx_context.md#0x2_tx_context">0x2::tx_context</a>;
<b>use</b> <a href="dependencies/suins/config.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_config">0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0::config</a>;
<b>use</b> <a href="dependencies/suins/domain.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_domain">0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0::domain</a>;
<b>use</b> <a href="dependencies/suins/registry.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_registry">0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0::registry</a>;
<b>use</b> <a href="dependencies/suins/suins.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_suins">0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0::suins</a>;
<b>use</b> <a href="dependencies/suins/suins_registration.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_suins_registration">0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0::suins_registration</a>;
</code></pre>



<a name="0x0_register_Register"></a>

## Struct `Register`

Authorization token for the app.


<pre><code><b>struct</b> <a href="register.md#0x0_register_Register">Register</a> <b>has</b> drop
</code></pre>



<details>
<summary>Fields</summary>


<dl>
<dt>
<code>dummy_field: bool</code>
</dt>
<dd>

</dd>
</dl>


</details>

<a name="@Constants_0"></a>

## Constants


<a name="0x0_register_EIncorrectAmount"></a>

Trying to register a subdomain (only *.sui is currently allowed).
The payment does not match the price for the domain.


<pre><code><b>const</b> <a href="register.md#0x0_register_EIncorrectAmount">EIncorrectAmount</a>: u64 = 4;
</code></pre>



<a name="0x0_register_EInvalidYearsArgument"></a>

Number of years passed is not within [1-5] interval.


<pre><code><b>const</b> <a href="register.md#0x0_register_EInvalidYearsArgument">EInvalidYearsArgument</a>: u64 = 0;
</code></pre>



<a name="0x0_register_register"></a>

## Function `register`



<pre><code><b>public</b> <b>fun</b> <a href="register.md#0x0_register">register</a>(<a href="dependencies/suins/suins.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_suins">suins</a>: &<b>mut</b> <a href="dependencies/suins/suins.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_suins_SuiNS">suins::SuiNS</a>, domain_name: <a href="dependencies/move-stdlib/string.md#0x1_string_String">string::String</a>, no_years: u8, payment: <a href="dependencies/sui-framework/coin.md#0x2_coin_Coin">coin::Coin</a>&lt;<a href="dependencies/sui-framework/sui.md#0x2_sui_SUI">sui::SUI</a>&gt;, <a href="dependencies/sui-framework/clock.md#0x2_clock">clock</a>: &<a href="dependencies/sui-framework/clock.md#0x2_clock_Clock">clock::Clock</a>, ctx: &<b>mut</b> <a href="dependencies/sui-framework/tx_context.md#0x2_tx_context_TxContext">tx_context::TxContext</a>): <a href="dependencies/suins/suins_registration.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_suins_registration_SuinsRegistration">suins_registration::SuinsRegistration</a>
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="register.md#0x0_register">register</a>(
    <a href="dependencies/suins/suins.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_suins">suins</a>: &<b>mut</b> SuiNS,
    domain_name: String,
    no_years: u8,
    payment: Coin&lt;SUI&gt;,
    <a href="dependencies/sui-framework/clock.md#0x2_clock">clock</a>: &Clock,
    ctx: &<b>mut</b> TxContext
): SuinsRegistration {
    <a href="dependencies/suins/suins.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_suins">suins</a>.assert_app_is_authorized&lt;<a href="register.md#0x0_register_Register">Register</a>&gt;();

    <b>let</b> <a href="dependencies/suins/config.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_config">config</a> = <a href="dependencies/suins/suins.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_suins">suins</a>.get_config&lt;Config&gt;();

    <b>let</b> <a href="dependencies/suins/domain.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_domain">domain</a> = <a href="dependencies/suins/domain.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_domain_new">domain::new</a>(domain_name);
    <a href="dependencies/suins/config.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_config_assert_valid_user_registerable_domain">config::assert_valid_user_registerable_domain</a>(&<a href="dependencies/suins/domain.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_domain">domain</a>);

    <b>assert</b>!(0 &lt; no_years && no_years &lt;= 5, <a href="register.md#0x0_register_EInvalidYearsArgument">EInvalidYearsArgument</a>);

    <b>let</b> label = <a href="dependencies/suins/domain.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_domain">domain</a>.sld();
    <b>let</b> price = <a href="dependencies/suins/config.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_config">config</a>.calculate_price((label.length() <b>as</b> u8), no_years);

    <b>assert</b>!(payment.value() == price, <a href="register.md#0x0_register_EIncorrectAmount">EIncorrectAmount</a>);

    <a href="dependencies/suins/suins.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_suins_app_add_balance">suins::app_add_balance</a>(<a href="register.md#0x0_register_Register">Register</a> {}, <a href="dependencies/suins/suins.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_suins">suins</a>, payment.into_balance());
    <b>let</b> <a href="dependencies/suins/registry.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_registry">registry</a> = <a href="dependencies/suins/suins.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_suins_app_registry_mut">suins::app_registry_mut</a>&lt;<a href="register.md#0x0_register_Register">Register</a>, Registry&gt;(<a href="register.md#0x0_register_Register">Register</a> {}, <a href="dependencies/suins/suins.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_suins">suins</a>);
    <a href="dependencies/suins/registry.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_registry">registry</a>.add_record(<a href="dependencies/suins/domain.md#0xd22b24490e0bae52676651b4f56660a5ff8022a2576e0089f79b3c88d44e08f0_domain">domain</a>, no_years, <a href="dependencies/sui-framework/clock.md#0x2_clock">clock</a>, ctx)
}
</code></pre>



</details>