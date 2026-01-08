use cardano/address.{Address, Script, VerificationKey}
use cardano/transaction.{OutputReference}

// A set of constants defined here to simplify writing tests
pub const utxo_ref_default = OutputReference("any", 0)

pub const utxo_ref_contract = OutputReference("contract", 0)

pub const contract_policy_id = "CONTRACT"

pub const operator_payment_cred = VerificationKey("Operator")

pub const maker_payment_cred = VerificationKey("Maker")

pub const taker_payment_cred = VerificationKey("Taker")

pub const contract_payment_cred = Script(contract_policy_id)

pub const maker_address = Address(maker_payment_cred, None)

pub const taker_address = Address(taker_payment_cred, None)

pub const owner_address = Address(operator_payment_cred, None)

pub const contract_address = Address(contract_payment_cred, None)
