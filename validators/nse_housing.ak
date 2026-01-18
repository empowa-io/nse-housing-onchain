use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use types.{ContractMode}

validator exchange {
  mint(_redeemer: ContractMode, _policy_id: PolicyId, _self: Transaction) {
    todo @"mint logic goes here"
  }

  spend(
    _datum: Option<Data>,
    _redeemer: ContractMode,
    _utxo: OutputReference,
    _self: Transaction,
  ) {
    todo @"spend logic goes here"
  }

  else(_) {
    fail
  }
}

validator listing {
  mint(_redeemer: ContractMode, _policy_id: PolicyId, _self: Transaction) {
    todo @"mint logic goes here"
  }

  spend(
    _datum: Option<Data>,
    _redeemer: ContractMode,
    _utxo: OutputReference,
    _self: Transaction,
  ) {
    todo @"spend logic goes here"
  }

  else(_) {
    fail
  }
}
