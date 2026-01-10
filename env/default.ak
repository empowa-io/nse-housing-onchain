use cardano/address.{Address, Script, VerificationKey}
use cardano/assets.{from_lovelace}
use cardano/transaction.{Input, NoDatum, Output, OutputReference}
use config.{contract_bootstrap_utxo_hash, contract_bootstrap_utxo_index}

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

pub const listing_verification_key =
  #"36286b097e17d1f4d82391f0540cb6608f044ea1f79366296d70ce05892ba1e9"

pub const listing_signing_key =
  #"67bb93be72ab65080b9e86e6b19f63d7b2a57ce6a3724c8c70ba66e4a4fac765"

//1%
pub const base_fee_size = 100

pub const contract_policy_id = "CONTRACT"

pub const operator_payment_keyhash = "Operator"

pub const maker_payment_keyhash = "Maker"

pub const taker_payment_keyhash = "Taker"

pub const contract_payment_cred = Script(contract_policy_id)

pub const operator_payment_cred = VerificationKey(operator_payment_keyhash)

pub const maker_payment_cred = VerificationKey(maker_payment_keyhash)

pub const taker_payment_cred = VerificationKey(taker_payment_keyhash)

pub const contract_address = Address(contract_payment_cred, None)

pub const maker_address = Address(maker_payment_cred, None)

pub const taker_address = Address(taker_payment_cred, None)

pub const operator_address = Address(operator_payment_cred, None)
