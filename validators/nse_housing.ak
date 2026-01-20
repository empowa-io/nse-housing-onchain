use aiken/collection/dict
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
  as_config_datum, as_listing_datum, discover_contract_addr_pid,
  find_outputs_by_address, find_outputs_by_marker, to_outputs,
}
use types.{
  Bootstrap, Buy, ConfigDatum, Configuration, ContractMode, Delisting, Listing,
  ListingDatum, Marker, OrderChanging, OrderDatum, OrderExecution, OrderPlacing,
  OutputRefOrPolicyId, Sell,
}

fn validate_config_update(
  tx: Transaction,
  contract_address: Address,
  contract_policy_id: PolicyId,
  current_config_datum: Option<Data>,
) -> Bool {
  expect Transaction {
    inputs: tx_inputs,
    outputs: [contract_config_output, ..rest_outputs],
    mint: minted_value,
    extra_signatories,
    ..
  } = tx

  let tx_approved_by_prev_operator =
    if current_config_datum == None {
      expect [bootstrap_input] = tx_inputs
      let expected_bootstrap_utxo_ref =
        OutputReference(
          contract_bootstrap_utxo_hash,
          contract_bootstrap_utxo_index,
        )
      bootstrap_input.output_reference == expected_bootstrap_utxo_ref
    } else {
      let ConfigDatum { contract_operator_keyhash: prev_operator_keyhash, .. } =
        current_config_datum |> as_config_datum()

      extra_signatories
        |> list.has(prev_operator_keyhash)
    }

  let minting_is_fine =
    if current_config_datum == None {
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
    is_new_operator_valid?,
    config_output_addr_is_valid?,
    config_output_marked_properly?,
    minting_is_fine?,
  }
}

fn validate_listing_update(
  tx: Transaction,
  contract_policy_id: PolicyId,
  mode: ContractMode,
) -> Bool {
  let Transaction {
    reference_inputs: tx_ref_inputs,
    inputs: tx_inputs,
    outputs: tx_outputs,
    mint: tx_mint,
    extra_signatories: tx_extra_signs,
    ..
  } = tx

  let contract_adress = Address(Script(contract_policy_id), None)

  let (listings, markers_count) =
    when mode is {
      Listing -> {
        let listings = tx_outputs |> find_outputs_by_address(contract_adress)
        (listings, list.length(listings))
      }

      Delisting -> {
        let listings =
          tx_inputs |> to_outputs() |> find_outputs_by_address(contract_adress)
        (listings, -list.length(listings))
      }
      _ -> fail
    }

  expect [config_ref_input] = tx_ref_inputs
  let config_is_valid =
    validate_marked_input(
      config_ref_input,
      contract_policy_id,
      contract_config_marker,
    )

  let ConfigDatum { listing_operator_keyhash, .. } =
    config_ref_input.output.datum |> as_config_datum()

  let all_listings_are_valid =
    listings
      |> list.reduce(
          True,
          fn(result, Output { value, datum, .. }) {
            let ListingDatum { listed_policy_id, listed_asset_name } =
              datum |> as_listing_datum()
            and {
              result,
              (listed_policy_id != "")?,
              (listed_asset_name != Some(""))?,
              (value
                |> has_nft_strict(contract_policy_id, contract_listing_marker))?,
            }
          },
        )

  let markers_are_ok =
    validate_markers_mint(
      tx_mint,
      contract_policy_id,
      contract_listing_marker,
      markers_count,
    )

  let action_is_authorized = [listing_operator_keyhash] == tx_extra_signs

  and {
    all_listings_are_valid?,
    config_is_valid?,
    markers_are_ok?,
    action_is_authorized?,
  }
}

fn validate_marked_input(
  marked_input: Input,
  contract_policy_id: PolicyId,
  marker: Marker,
) -> Bool {
  let Input { output: Output { value, address, .. }, .. } = marked_input
  and {
    value
      |> has_nft_strict(contract_policy_id, marker),
    address == Address(Script(contract_policy_id), None),
  }
}

fn validate_markers_mint(
  mint: Value,
  contract_policy_id: PolicyId,
  marker: Marker,
  amount_limit: Int,
) -> Bool {
  let minting_by_contract_only = assets.policies(mint) == [contract_policy_id]
  let minted_tokens = assets.tokens(mint, contract_policy_id)

  let nothing_but_markers_minted = ( minted_tokens |> dict.size() ) == 1
  let markers_amount_is_ok =
    Some(amount_limit) == dict.get(minted_tokens, marker)

  and {
    minting_by_contract_only?,
    nothing_but_markers_minted?,
    markers_amount_is_ok?,
  }
}

validator exchange {
  mint(redeemer: ContractMode, contract_policy_id: PolicyId, tx: Transaction) {
    let (contract_address, _) =
      discover_contract_addr_pid(tx, contract_policy_id)
    let Transaction {
      reference_inputs: tx_ref_inputs,
      inputs: tx_inputs,
      outputs: tx_outputs,
      validity_range: tx_validity_range,
      mint: tx_mint,
      extra_signatories: tx_extra_signs,
      ..
    } = tx

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
          contract_address,
          contract_policy_id,
          current_config_datum: None,
        )
      Listing ->
        // A correct order placing transaction must contain:
        //   Reference inputs:
        //     - Reference to the contract valid `config eUTxO`
        //   Outputs[>=1]:
        //     - one or many outputs to the contract address containing:
        //       - 1 token `contract_policy_id.contract_listing_marker` per output
        //       - a valid datum of type `ListingDatum`
        //     - any number of outputs to other addresses if needed (not validated)
        //   Minting:
        //     - exactly 1 `contract_policy_id.contract_listing_marker` per contract output
        //   Additional signers:
        //     - a signature corresponding to the `listing_operator_credential` field in the reference utxo datum
        validate_listing_update(tx, contract_policy_id, redeemer)

      Delisting ->
        // A correct delisting transaction must contain:
        //   Reference inputs[1]:
        //     - Reference to the contract valid `config eUTxO`
        //   Inputs[>=1]:
        //     - one or many inputs from the contract address containing:
        //       - 1 token `contract_policy_id.contract_listing_marker` per input
        //   Outputs[>=0]:
        //     - any number of outputs to other addresses if needed (not validated)
        //      - no outputs containing `contract_policy_id.contract_listing_marker`
        //   Minting:
        //     - exactly -1 `contract_policy_id.contract_listing_marker` per listing input
        //   Additional signers:
        //     - a signature corresponding to the `listing_operator_credential` field in the reference utxo datum
        validate_listing_update(tx, contract_policy_id, redeemer)

      _ -> False
    }
  }

  spend(
    spent_utxo_datum: Option<Data>,
    redeemer: ContractMode,
    spent_utxo: OutputReference,
    tx: Transaction,
  ) {
    let Transaction {
      reference_inputs: tx_ref_inputs,
      inputs: tx_inputs,
      outputs: tx_outputs,
      validity_range: tx_validity_range,
      mint: tx_mint,
      extra_signatories: tx_extra_signs,
      ..
    } = tx

    let (contract_address, contract_policy_id) =
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
          contract_address,
          contract_policy_id,
          current_config_datum: spent_utxo_datum,
        )

      Delisting ->
        // Since the delisting process requires both Spend and Mint checks,
        // validation can be implemented in just one sub-validator without code duplication.
        // During delisting, markers must be burned, so the transaction must include
        // burning markers on behalf of the contract.
        // If this requirement is met, allow spending the UTXO, because the Mint
        // sub-validator will be invoked next and perform the full validation.
        assets.quantity_of(tx_mint, contract_policy_id, contract_listing_marker) < 0
      _ -> False
    }
  }

  else(_) {
    fail
  }
}
