use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}
use types.{ContractMode, OrderDatum}

validator nse_housing {
  mint(_redeemer: ContractMode, _policy_id: PolicyId, _self: Transaction) {
    todo @"mint logic goes here"
  }

  spend(
    _datum: Option<OrderDatum>,
    _redeemer: ContractMode,
    _utxo: OutputReference,
    _self: Transaction,
  ) {
    todo @"spend logic goes here"
  }
}
