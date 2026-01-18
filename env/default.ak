use cardano/address.{Address, Script, VerificationKey}
use cardano/assets.{from_asset, from_lovelace}
use cardano/transaction.{Input, NoDatum, Output, OutputReference}
use config.{
  contract_bootstrap_utxo_hash, contract_bootstrap_utxo_index,
  contract_config_marker, contract_listing_marker, contract_order_marker,
}

// A set of constants defined here to simplify writing tests
pub const utxo_ref_placeholder = OutputReference("any", 0)

pub const utxo_ref_contract = OutputReference("contract", 0)

pub const utxo_ref_bootstrap =
  OutputReference(contract_bootstrap_utxo_hash, contract_bootstrap_utxo_index)

pub const address_placeholder = Address(VerificationKey("Any"), None)

pub const output_placeholder =
  Output {
    address: address_placeholder,
    value: from_lovelace(0),
    datum: NoDatum,
    reference_script: None,
  }

pub const input_placeholder =
  Input { output_reference: utxo_ref_placeholder, output: output_placeholder }

pub const base_platform_fee_decimal_part = 2

//1%, because there is 10^2 decimal part
pub const base_platform_fee_percent = 100

pub const base_platform_fee_min_amount = 1_000_000

pub const platform_fee_payment_keyhash = "platform"

pub const operator_payment_keyhash = "Operator"

pub const listing_operator_payment_keyhash = "Listing"

pub const maker_payment_keyhash = "Maker"

pub const taker_payment_keyhash = "Taker"

pub const contract_policy_id = "CONTRACT"

pub const contract_payment_cred = Script(contract_policy_id)

pub const operator_payment_cred = VerificationKey(operator_payment_keyhash)

pub const listing_operator_payment_cred =
  VerificationKey(listing_operator_payment_keyhash)

pub const platform_fee_payment_cred =
  VerificationKey(platform_fee_payment_keyhash)

pub const maker_payment_cred = VerificationKey(maker_payment_keyhash)

pub const taker_payment_cred = VerificationKey(taker_payment_keyhash)

pub const contract_address = Address(contract_payment_cred, None)

pub const platform_address = Address(platform_fee_payment_cred, None)

pub const maker_address = Address(maker_payment_cred, None)

pub const taker_address = Address(taker_payment_cred, None)

pub const operator_address = Address(operator_payment_cred, None)

pub const listing_operator_address =
  Address(listing_operator_payment_cred, None)

pub const order_marker =
  from_asset(contract_policy_id, contract_order_marker, 1)

pub const config_marker =
  from_asset(contract_policy_id, contract_config_marker, 1)

pub const listing_marker =
  from_asset(contract_policy_id, contract_listing_marker, 1)
