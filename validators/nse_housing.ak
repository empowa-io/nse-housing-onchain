use aiken/collection/list
use aiken/crypto.{VerificationKeyHash}
use aiken/interval.{after, before}
use aiken/math.{pow}
use cardano/address.{Address, Script}
use cardano/assets.{
  AssetName, PolicyId, Value, from_asset, from_lovelace, has_nft, has_nft_strict,
  merge, negate, zero,
}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, find_input,
  placeholder as tx_placeholder,
}
use config.{
  contract_bootstrap_utxo_hash, contract_bootstrap_utxo_index,
  contract_config_marker, contract_listing_marker, contract_order_marker,
  contract_order_min_ada,
}
use helpers.{
  discover_contract_addr_pid, find_outputs_by_address, find_outputs_by_marker,
  to_outputs,
}
use types.{
  Bootstrap, Buy, ConfigDatum, Configuration, ContractMode, ListingDatum,
  OrderChanging, OrderDatum, OrderExecution, OrderPlacing, OutputRefOrPolicyId,
  Sell,
}

fn validate_config_update(
  tx: Transaction,
  contract_address: Address,
  contract_policy_id: PolicyId,
  bootstrap_mode: Bool,
) -> Bool {
  expect Transaction {
    inputs: tx_inputs,
    outputs: [contract_config_output, ..rest_outputs],
    mint: minted_value,
    extra_signatories,
    ..
  } = tx

  let prev_config_inputs_outputs =
    tx_inputs
      |> to_outputs()
      |> find_outputs_by_marker(
          contract_policy_id,
          contract_config_marker,
          strict_mode: True,
        )

  let tx_approved_by_prev_operator =
    when prev_config_inputs_outputs is {
      [prev_config_output] -> {
        expect Output { datum: InlineDatum(datum), .. } = prev_config_output
        expect ConfigDatum {
          contract_operator_keyhash: prev_operator_keyhash,
          ..
        } = datum

        extra_signatories
          |> list.has(prev_operator_keyhash)
      }
      [] -> {
        expect [bootstrap_input] = tx_inputs
        let expected_bootstrap_utxo_ref =
          OutputReference(
            contract_bootstrap_utxo_hash,
            contract_bootstrap_utxo_index,
          )
        bootstrap_input.output_reference == expected_bootstrap_utxo_ref
      }
      _ -> fail
    }

  let minting_is_fine =
    if bootstrap_mode {
      minted_value
        |> has_nft_strict(contract_policy_id, contract_config_marker)
    } else {
      minted_value == zero
    }

  expect Output {
    address: contract_conf_out_address,
    value: contract_conf_out_value,
    datum: InlineDatum(contract_conf_out_datum),
    ..
  } = contract_config_output

  expect contract_conf_out_datum: ConfigDatum = contract_conf_out_datum

  let ConfigDatum { contract_operator_keyhash: new_operator_keyhash, .. } =
    contract_conf_out_datum

  let config_output_addr_is_valid =
    contract_conf_out_address == contract_address

  let config_output_marked_properly =
    has_nft_strict(
      contract_conf_out_value,
      contract_policy_id,
      contract_config_marker,
    )

  let is_new_operator_valid =
    extra_signatories
      |> list.has(new_operator_keyhash)

  expect [] = find_outputs_by_address(rest_outputs, contract_address)

  and {
    tx_approved_by_prev_operator?,
    minting_is_fine?,
    config_output_addr_is_valid?,
    config_output_marked_properly?,
    is_new_operator_valid?,
  }
}

validator exchange {
  mint(redeemer: ContractMode, contract_policy_id: PolicyId, tx: Transaction) {
    let (contract_addr, _) = discover_contract_addr_pid(tx, contract_policy_id)

    when redeemer is {
      Bootstrap ->
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

        validate_config_update(
          tx,
          contract_addr,
          contract_policy_id,
          bootstrap_mode: True,
        )

      // expect Transaction {
      //   inputs: [bootstrap_utxo],
      //   outputs: [contract_config_output, ..rest_outputs],
      //   mint: minted_value,
      //   extra_signatories: [new_operator_keyhash],
      //   ..
      // } = tx
      // let expected_bootstrap_utxo_ref =
      //   OutputReference(
      //     contract_bootstrap_utxo_hash,
      //     contract_bootstrap_utxo_index,
      //   )
      // let expected_contract_address =
      //   Address(Script(contract_policy_id), None)
      // expect [] =
      //   find_outputs_by_address(rest_outputs, expected_contract_address)
      // expect Output {
      //   address: contract_conf_out_address,
      //   value: contract_conf_out_value,
      //   datum: InlineDatum(contract_conf_out_datum),
      //   ..
      // } = contract_config_output
      // expect contract_conf_out_datum: ConfigDatum = contract_conf_out_datum
      // let ConfigDatum { contract_operator_keyhash, .. } =
      //   contract_conf_out_datum
      // let bootstrap_utxo_is_valid =
      //   bootstrap_utxo.output_reference == expected_bootstrap_utxo_ref
      // let config_output_addr_is_valid =
      //   contract_conf_out_address == expected_contract_address
      // let config_output_marked_properly =
      //   has_nft_strict(
      //     contract_conf_out_value,
      //     contract_policy_id,
      //     contract_config_marker,
      //   )
      // let marker_minted_properly =
      //   has_nft_strict(
      //     minted_value,
      //     contract_policy_id,
      //     contract_config_marker,
      //   )
      // let is_new_operator_valid =
      //   contract_operator_keyhash == new_operator_keyhash
      // and {
      //   bootstrap_utxo_is_valid?,
      //   config_output_addr_is_valid?,
      //   config_output_marked_properly?,
      //   marker_minted_properly?,
      //   is_new_operator_valid?,
      // }
      _ -> False
    }
  }

  spend(
    spent_datum: Option<Data>,
    redeemer: ContractMode,
    spent_utxo: OutputReference,
    tx: Transaction,
  ) {
    let (contract_addr, contract_policy_id) =
      discover_contract_addr_pid(tx, spent_utxo)

    when redeemer is {
      Configuration ->
        // A correct reconfiguration transaction must contain:
        //   Inputs [>=1]:
        //     - exactly one input with `contract_policy_id.contract_config_marker` inside
        //     - any other inputs if needed
        //   Outputs:
        //     - exactly one output to the contract address containing:
        //       - index 0
        //       - 1 token `contract_policy_id.contract_config_marker`
        //       - a datum of type `ConfigDatum`
        //     - any number of outputs to other addresses if needed
        //   Minting:
        //     - forbidden
        //   Additional signers:
        //     - a signature corresponding to the `contract_operator_keyhash` field in the spent utxo datum
        //     - a signature corresponding to the `contract_operator_keyhash` field in the contract tx output datum

        validate_config_update(
          tx,
          contract_addr,
          contract_policy_id,
          bootstrap_mode: False,
        )
      _ -> False
    }
  }

  else(_) {
    fail
  }
}
