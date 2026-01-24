use aiken/collection/dict
use aiken/collection/list.{has}
use aiken/crypto.{VerificationKeyHash}
use aiken/interval.{Interval, after, before, is_entirely_before}
use aiken/math.{pow}
use cardano/address.{Address, Script}
use cardano/assets.{
  AssetName, PolicyId, Value, from_asset, from_lovelace, has_any_nft, has_nft,
  has_nft_strict, merge, negate, policies, zero,
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
  as_config_datum, as_listing_datum, discover_contract_utxo_addr_pid,
  find_outputs_by_address, find_outputs_by_marker, read_config_datum,
  read_listing_datum, read_order_datum, to_outputs,
}
use types.{
  Bootstrap, Buy, Cleaning, ConfigDatum, Configuration, ContractMode, Delisting,
  Listing, ListingDatum, Marker, OrderChanging, OrderDatum, OrderExecution,
  OrderPlacing, OutputRefOrPolicyId, Sell,
}

fn validate_markers_mint(mint: Value, marker: Marker, amount_limit: Int) -> Bool {
  let Marker(contract_policy_id, marker_asset_name) = marker
  let minting_by_contract_only = assets.policies(mint) == [contract_policy_id]
  let minted_tokens = assets.tokens(mint, contract_policy_id)

  let nothing_but_markers_minted = ( minted_tokens |> dict.size() ) == 1
  let markers_amount_is_ok =
    Some(amount_limit) == dict.get(minted_tokens, marker_asset_name)

  and {
    minting_by_contract_only?,
    nothing_but_markers_minted?,
    markers_amount_is_ok?,
  }
}

fn validate_authorization(
  tx: Transaction,
  user_keyhash: VerificationKeyHash,
) -> Bool {
  let Transaction { extra_signatories, .. } = tx
  extra_signatories
    |> list.has(user_keyhash)
}

fn validate_marked_output(
  marked_output: Output,
  marker: Marker,
  strict_mode: Bool,
) -> Bool {
  let Output { value, address, .. } = marked_output
  let Marker(contract_policy_id, marker_asset_name) = marker

  let check_function =
    when strict_mode is {
      True -> has_nft_strict
      False -> has_nft
    }

  let is_output_marked_properly =
    value
      |> check_function(contract_policy_id, marker_asset_name)

  let is_output_sent_to_contract =
    address == Address(Script(contract_policy_id), None)
  and {
    is_output_marked_properly?,
    is_output_sent_to_contract?,
  }
}

fn validate_marked_input(
  marked_input: Input,
  marker: Marker,
  strict_mode: Bool,
) -> Bool {
  let Input { output, .. } = marked_input
  validate_marked_output(output, marker, strict_mode)
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
  config_marker: Marker,
  listing_marker: Marker,
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
    validate_marked_input(config_ref_input, config_marker, True)

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
    validate_markers_mint(tx_mint, listing_marker, markers_count)

  let is_action_authorized = [listing_operator_keyhash] == tx_extra_signs

  and {
    all_listings_are_valid?,
    config_is_valid?,
    markers_are_ok?,
    is_action_authorized?,
  }
}

fn validate_config_output() {
  todo
}

fn validate_listing_output() {
  todo
}

fn validate_order_output(
  order_output: Output,
  order_marker: Marker,
  listing_data: ListingDatum,
  tx_validity_range: Interval,
) {
  let Marker(contract_policy_id, order_marker_asset_name) = order_marker
  let Output { value: order_value, .. } = order_output

  let ListingDatum { listed_policy_id, listed_asset_name } = listing_data

  let OrderDatum {
    order_type,
    traded_asset_policy_id,
    traded_asset_name,
    traded_asset_amount,
    traded_asset_price,
    order_timeout_date,
    ..
  } = order_output |> read_order_datum()

  let asset_price_is_ok = traded_asset_price > 0

  let is_output_marker_ok =
    order_output
      |> validate_marked_output(order_marker, strict_mode: False)

  let is_traded_asset_listed = and {
      (traded_asset_policy_id == listed_policy_id)?,
      when listed_asset_name is {
        None -> True
        Some(asset_name) -> (asset_name == traded_asset_name)?
      },
    }

  let desired_order_value =
    when order_type is {
      Buy ->
        from_lovelace(
          traded_asset_amount * traded_asset_price + contract_order_min_ada,
        )
      Sell ->
        from_lovelace(contract_order_min_ada)
          |> assets.add(
              traded_asset_policy_id,
              traded_asset_name,
              traded_asset_amount,
            )
    }
      |> assets.add(contract_policy_id, order_marker_asset_name, 1)

  let is_order_value_correct = desired_order_value == order_value

  let is_timeout_correct =
    if order_timeout_date > 0 {
      is_entirely_before(tx_validity_range, order_timeout_date)
    } else {
      True
    }

  and {
    asset_price_is_ok?,
    is_output_marker_ok?,
    is_traded_asset_listed?,
    is_order_value_correct?,
    is_timeout_correct?,
  }
}

validator exchange {
  mint(redeemer: ContractMode, contract_policy_id: PolicyId, tx: Transaction) {
    let (_, contract_address, _) =
      discover_contract_utxo_addr_pid(tx, contract_policy_id)

    let config_marker = Marker(contract_policy_id, contract_config_marker)
    let listing_marker = Marker(contract_policy_id, contract_listing_marker)
    let order_marker = Marker(contract_policy_id, contract_order_marker)

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
        validate_listing_update(
          tx,
          contract_policy_id,
          redeemer,
          config_marker,
          listing_marker,
        )

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
        validate_listing_update(
          tx,
          contract_policy_id,
          redeemer,
          config_marker,
          listing_marker,
        )
      OrderPlacing -> {
        // A correct order placing transaction must contain:
        //   Inputs: (not validated)
        //   Reference inputs[2]:
        //     - Reference to the `listing eUTxO` allowing interaction with the asset being listed in the order
        //     - Reference to the contract valid `config eUTxO`
        //   Outputs[>=1]:
        //     - exactly one output to the contract address containing:
        //       - index 0
        //       - 1 token `contract_policy_id.contract_order_marker`
        //       - a datum of type `OrderDatum`
        //       - the required amount of locked assets depending on the order type (Buy/Sell)
        //       - `contract_order_min_ada` ADA (returned to the owner after the order is closed/executed)
        //     - any number of outputs to other addresses if needed (not validated)
        //   Minting:
        //     - exactly 1 `contract_policy_id.contract_order_marker`
        //   Validity range[optional]:
        //     - may be omitted if `timeout` in the datum is 0
        //     - if `timeout` in the datum points to some date, the upper bound must be before that date
        //   Additional signers:
        //     - a signature corresponding to the `order_maker_keyhash` field in the spent utxo datum
        let ref_utxos = tx_ref_inputs |> to_outputs()
        expect [contract_output, ..rest] = tx_outputs

        expect [ConfigDatum { is_market_open, contract_operator_keyhash, .. }] =
          ref_utxos
            |> find_outputs_by_marker(config_marker, strict_mode: True)
            |> list.map(read_config_datum)

        expect [listing_data] =
          ref_utxos
            |> find_outputs_by_marker(listing_marker, strict_mode: True)
            |> list.map(read_listing_datum)

        let OrderDatum { order_maker_keyhash, .. } =
          contract_output |> read_order_datum()

        let is_order_output_valid =
          validate_order_output(
            contract_output,
            order_marker,
            listing_data,
            tx_validity_range,
          )
        let only_one_contract_output =
          [] == ( rest |> find_outputs_by_address(contract_address) )

        let marker_minted_properly =
          validate_markers_mint(tx_mint, order_marker, 1)

        let is_action_authorized_by_user =
          validate_authorization(tx, order_maker_keyhash)

        let is_action_authorized_by_operator =
          validate_authorization(tx, contract_operator_keyhash)

        let is_action_authorized = or {
            is_action_authorized_by_user,
            is_action_authorized_by_operator,
          }

        and {
          is_market_open?,
          is_order_output_valid?,
          only_one_contract_output?,
          marker_minted_properly?,
          is_action_authorized?,
        }
      }
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

    expect (Some(contract_utxo), contract_address, contract_policy_id) =
      discover_contract_utxo_addr_pid(tx, spent_utxo)

    let config_marker = Marker(contract_policy_id, contract_config_marker)
    let listing_marker = Marker(contract_policy_id, contract_listing_marker)
    let order_marker = Marker(contract_policy_id, contract_order_marker)

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
        // And the mint check is much cheaper (it has no utxo multiplier for mem\cpu)
        assets.quantity_of(tx_mint, contract_policy_id, contract_listing_marker) < 0
      Cleaning -> {
        // A correct order changing transaction must contain:
        //   Reference inputs:
        //     - Reference to the contract valid `config eUTxO`
        //   Inputs[>=1]:
        //      - Any number of UTXOs from the contract address that can be considered garbage:
        //          - UTXOs that do not contain markers with contract_policy_id: contract_order_marker|contract_config_marker|contract_listing_marker.
        //      - Any number of inputs from any other addresses
        //   Minting:
        //     - minting is prohibited as such and will not be possible because the Mint validator will not support the corresponding mode
        //   Additional signers:
        //     - a signature corresponding to the `contract_operator_keyhash` field in the config UTXO datum
        //  
        //   Here we cannot shift the check to Mint, and with multiple UTXOs
        //   we would multiply resource usage and cost. Fortunately, this
        //   sub-validator is very simple and cheap.

        expect [config_ref] =
          tx_ref_inputs
            |> to_outputs()
            |> find_outputs_by_marker(config_marker, strict_mode: True)

        let ConfigDatum { contract_operator_keyhash, .. } =
          config_ref |> read_config_datum()

        let Output { value: contract_utxo_value, .. } = contract_utxo

        let utxo_is_garbage =
          !(contract_utxo_value
            |> policies()
            |> has(contract_policy_id))

        let mint_is_empty = tx_mint == zero

        let is_action_authorized =
          validate_authorization(tx, contract_operator_keyhash)

        and {
          utxo_is_garbage?,
          mint_is_empty?,
          is_action_authorized?,
        }
      }

      OrderChanging -> {
        //   Reference inputs[1]:
        //     - Reference to the contract valid `config eUTxO`
        //     - Reference to the `listing eUTxO` allowing interaction with the asset being listed in the order
        //   Inputs[>=1]:
        //      - Exactly one input from the contract address containing the order eUTxO (`contract_policy_id.contract_order_marker` + OrderDatum)
        //      - Any number of user inputs if needed (not validated)
        //   Outputs[>=1]:
        //     - exactly one output to the contract address containing:
        //       - index 0
        //       - 1 token `contract_policy_id.contract_order_marker`
        //       - a datum of type `OrderDatum`
        //       - the required amount of locked assets depending on the order type (Buy/Sell)
        //       - `contract_order_min_ada` ADA (returned to the owner after the order is closed/executed)
        //      - any number of outputs to other addresses if needed (not validated)
        //   Minting:
        //     - forbidden
        //   Additional signers:    
        //     - a signature corresponding to the `order_maker_keyhash` field in the spent utxo datum
        //     - a signature corresponding to the `order_maker_keyhash` field in the contract output utxo datum
        let ref_utxos = tx_ref_inputs |> to_outputs()
        expect [contract_utxo] =
          tx_inputs |> to_outputs() |> find_outputs_by_address(contract_address)
        expect [contract_output, ..rest] = tx_outputs

        expect [ConfigDatum { is_market_open, .. }] =
          ref_utxos
            |> find_outputs_by_marker(config_marker, strict_mode: True)
            |> list.map(read_config_datum)

        expect [listing_data] =
          ref_utxos
            |> find_outputs_by_marker(listing_marker, strict_mode: True)
            |> list.map(read_listing_datum)

        let OrderDatum { order_maker_keyhash: new_order_maker_keyhash, .. } =
          contract_output |> read_order_datum()

        let OrderDatum { order_maker_keyhash: old_order_maker_keyhash, .. } =
          contract_utxo |> read_order_datum()

        let is_order_output_valid =
          validate_order_output(
            contract_output,
            order_marker,
            listing_data,
            tx_validity_range,
          )
        let only_one_contract_output =
          [] == ( rest |> find_outputs_by_address(contract_address) )

        let tx_has_no_mint = tx_mint == zero

        let is_action_authorized_by_old_owner =
          validate_authorization(tx, old_order_maker_keyhash)

        let is_action_authorized_by_new_owner =
          validate_authorization(tx, new_order_maker_keyhash)

        let is_action_authorized = or {
            is_action_authorized_by_old_owner,
            is_action_authorized_by_new_owner,
          }

        and {
          is_market_open?,
          is_order_output_valid?,
          only_one_contract_output?,
          tx_has_no_mint?,
          is_action_authorized?,
        }
      }
      _ -> False
    }
  }

  else(_) {
    fail
  }
}
