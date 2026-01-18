use aiken/collection/list
use aiken/interval.{after, before}
use aiken/math.{pow}
use cardano/address.{Address, Script}
use cardano/assets.{
  PolicyId, from_asset, from_lovelace, has_nft_strict, merge, negate, zero,
}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
  placeholder as tx_placeholder,
}
use config.{
  contract_bootstrap_utxo_hash, contract_bootstrap_utxo_index,
  contract_config_marker, contract_order_marker, contract_order_min_ada,
}
use types.{
  Bootstrap, Buy, ConfigDatum, ContractMode, ListingDatum, OrderChanging,
  OrderDatum, OrderExecution, OrderPlacing, Sell,
}

fn find_outputs_by_address(
  outputs: List<Output>,
  address: Address,
) -> List<Output> {
  list.reduce(
    outputs,
    [],
    fn(result, output) {
      let Output { address: output_address, .. } = output
      if output_address == address {
        [output, ..result]
      } else {
        result
      }
    },
  )
}

validator exchange {
  mint(redeemer: ContractMode, contract_policy_id: PolicyId, tx: Transaction) {
    when redeemer is {
      Bootstrap -> {
        // A correct bootstrap transaction must contain:
        //   Inputs [just 1]:
        //     - exactly one input using contract_bootstrap_utxo_hash#contract_bootstrap_utxo_index
        //   Outputs [>= 1]:
        //     - exactly one output to the contract address containing:
        //       - index 0
        //       - 1 token `contract_policy_id.contract_config_marker`
        //       - a datum of type `ConfigDatum`
        //     - any number of outputs to other addresses if needed (not validated)
        //   Minting [just 1]:
        //     - exactly one `contract_policy_id.contract_config_marker`
        //   Additional signers:
        //     - a signature corresponding to the `contract_operator_keyhash` field in the datum
        expect Transaction {
          inputs: [bootstrap_utxo],
          outputs: contract_config_outputs,
          mint: minted_value,
          extra_signatories: [new_operator_keyhash],
          ..
        } = tx

        let expected_bootstrap_utxo_ref =
          OutputReference(
            contract_bootstrap_utxo_hash,
            contract_bootstrap_utxo_index,
          )

        let expected_contract_address =
          Address(Script(contract_policy_id), None)

        expect [contract_config_output] =
          find_outputs_by_address(
            contract_config_outputs,
            expected_contract_address,
          )

        expect Output {
          address: contract_conf_out_address,
          value: contract_conf_out_value,
          datum: InlineDatum(contract_conf_out_datum),
          ..
        } = contract_config_output

        expect contract_conf_out_datum: ConfigDatum = contract_conf_out_datum

        let ConfigDatum { contract_operator_keyhash, .. } =
          contract_conf_out_datum

        let bootstrap_utxo_is_valid =
          bootstrap_utxo.output_reference == expected_bootstrap_utxo_ref

        let config_output_addr_is_valid =
          contract_conf_out_address == expected_contract_address

        let config_output_marked_properly =
          has_nft_strict(
            contract_conf_out_value,
            contract_policy_id,
            contract_config_marker,
          )

        let marker_minted_properly =
          has_nft_strict(
            minted_value,
            contract_policy_id,
            contract_config_marker,
          )

        let is_new_operator_valid =
          contract_operator_keyhash == new_operator_keyhash

        and {
          bootstrap_utxo_is_valid?,
          config_output_addr_is_valid?,
          config_output_marked_properly?,
          marker_minted_properly?,
          is_new_operator_valid?,
        }
      }
      _ -> False
    }
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
  mint(_redeemer: ContractMode, _policy_id: PolicyId, _tx: Transaction) {
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
