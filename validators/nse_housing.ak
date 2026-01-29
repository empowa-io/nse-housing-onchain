use aiken/collection/dict
use aiken/collection/list.{has}
use aiken/crypto.{VerificationKeyHash}
use aiken/interval.{
  Interval, after, before, is_entirely_after, is_entirely_before,
}
use aiken/math.{max, pow}
use cardano/address.{Address, Script, VerificationKey}
use cardano/assets.{
  AssetName, PolicyId, Value, from_asset, from_lovelace, has_any_nft, has_nft,
  has_nft_strict, lovelace_of, merge, negate, policies, quantity_of, zero,
}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction, find_input,
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
  Listing, ListingDatum, Marker, OrderCanceling, OrderChanging, OrderDatum,
  OrderExecution, OrderPlacing, OutputRefOrPolicyId, Sell,
}

fn validate_markers_mint(mint: Value, marker: Marker, amount_limit: Int) -> Bool {
  let Marker(contract_policy_id, marker_asset_name) = marker
  let minting_by_contract_only = ( mint |> policies() ) == [contract_policy_id]
  let minted_tokens = assets.tokens(mint, contract_policy_id)

  let nothing_but_markers_minted = ( minted_tokens |> dict.size() ) == 1
  let is_markers_amount_ok =
    Some(amount_limit) == dict.get(minted_tokens, marker_asset_name)

  and {
    minting_by_contract_only?,
    nothing_but_markers_minted?,
    is_markers_amount_ok?,
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

fn validate_deal(
  contract_utxo: Output,
  config: ConfigDatum,
  listing: ListingDatum,
  tx_validity_range: Interval,
  order_marker: Marker,
  tx_outputs: List<Output>,
) -> (Bool, Bool) {
  // First, extract the validated UTXO data
  let Output { address: contract_address, .. } = contract_utxo
  // Then the order parameters
  let OrderDatum {
    order_type: order_type_init,
    traded_asset_policy_id: traded_asset_policy_id_init,
    traded_asset_name: traded_asset_name_init,
    traded_asset_amount: traded_asset_amount_init,
    traded_asset_price: traded_asset_price_init,
    partial_fulfillment_allowed: partial_fulfillment_allowed_init,
    order_timeout_date: order_timeout_date_init,
    order_maker_address: order_maker_address_init,
  } = contract_utxo |> read_order_datum()
  let ConfigDatum {
    platform_fee_percent,
    platform_fee_decimal,
    platform_fee_min_amount,
    platform_fee_address,
    ..
  } = config
  let ListingDatum { .. } = listing
  // Then read the required transaction outputs (there may also be an optional contract output for partial fulfillment)
  expect [maker_output,
    taker_output, platform_fee_output, ..rest_outputs] = tx_outputs
  let Output { address: maker_address, .. } = maker_output

  // Extract maker keyhash
  expect Address(VerificationKey(order_maker_keyhash), ..) =
    order_maker_address_init

  // Also validate the maker address:
  let is_maker_address_correct = maker_address == order_maker_address_init

  // And the fee address as well:
  let is_platform_address_correct =
    platform_fee_output.address == platform_fee_address
  // And that timeouts are respected
  let is_validity_range_ok = or {
      order_timeout_date_init == 0,
      tx_validity_range |> is_entirely_before(order_timeout_date_init),
    }

  // Precompute the fee percentage
  let base_fee = platform_fee_percent / pow(10, platform_fee_decimal)
  // Then check that the deal outputs are correct and compute the deal size
  let (is_deal_balanced, deal_amount) =
    when order_type_init is {
      Buy -> {
        let maker_income =
          maker_output.value
            |> quantity_of(traded_asset_policy_id_init, traded_asset_name_init)
        let maker_lovelace_income = maker_output.value |> lovelace_of()
        let taker_income = taker_output.value |> lovelace_of()
        let platform_fee = platform_fee_output.value |> lovelace_of()
        let is_deal_balanced = and {
            (maker_lovelace_income >= if maker_income == traded_asset_amount_init {
              contract_order_min_ada
            } else {
              0
            })?,
            (maker_income == ( taker_income + platform_fee ) / traded_asset_price_init)?,
            (platform_fee == max(
              maker_income * traded_asset_price_init / ( 100 * base_fee ),
              platform_fee_min_amount,
            ))?,
          }
        (is_deal_balanced, maker_income)
      }
      Sell -> {
        let maker_income = maker_output.value |> lovelace_of()
        let taker_income =
          taker_output.value
            |> quantity_of(traded_asset_policy_id_init, traded_asset_name_init)
        let platform_fee = platform_fee_output.value |> lovelace_of()
        let base_maker_income = taker_income * traded_asset_price_init
        let is_deal_balanced = and {
            (maker_income == if taker_income == traded_asset_amount_init {
              base_maker_income + contract_order_min_ada
            } else {
              base_maker_income
            })?,
            (platform_fee == max(
              taker_income * traded_asset_price_init / ( 100 * base_fee ),
              platform_fee_min_amount,
            ))?,
          }
        (is_deal_balanced, taker_income)
      }
    }
  // Then check whether a deal of this amount is allowed
  let (is_deal_allowed, is_deal_partial) =
    if deal_amount < traded_asset_amount_init && partial_fulfillment_allowed_init {
      // If the deal is partially fulfilled and that is allowed, check that there is a correct contract output with the updated order
      expect [new_order_output, ..rest_outputs] = rest_outputs
      // Then check that it is formed and populated correctly:
      let is_new_order_valid =
        validate_order_output(
          new_order_output,
          order_marker,
          listing,
          tx_validity_range,
          Some(traded_asset_amount_init - deal_amount),
        )
      // Then check that the updated order datum has no changes except the asset amount
      let is_new_order_datum_not_corrupted = {
        let OrderDatum {
          order_type: order_type_new,
          traded_asset_policy_id: traded_asset_policy_id_new,
          traded_asset_name: traded_asset_name_new,
          traded_asset_amount: traded_asset_amount_new,
          traded_asset_price: traded_asset_price_new,
          partial_fulfillment_allowed: partial_fulfillment_allowed_new,
          order_timeout_date: order_timeout_date_new,
          order_maker_address: order_maker_address_new,
        } = new_order_output |> read_order_datum()
        and {
          (order_type_new == order_type_init)?,
          (traded_asset_policy_id_new == traded_asset_policy_id_init)?,
          (traded_asset_name_new == traded_asset_name_init)?,
          (traded_asset_amount_new == traded_asset_amount_init - deal_amount)?,
          (traded_asset_price_new == traded_asset_price_init)?,
          (partial_fulfillment_allowed_new == partial_fulfillment_allowed_init)?,
          (order_timeout_date_new == order_timeout_date_init)?,
          (order_maker_address_new == order_maker_address_init)?,
        }
      }
      // Then make sure there are no more contract outputs left
      expect [] = rest_outputs |> find_outputs_by_address(contract_address)
      (and {
          is_new_order_valid?,
          is_new_order_datum_not_corrupted?,
        }, True)
    } else if deal_amount == traded_asset_amount_init {
      // If the deal amount equals the order amount
      // Make sure there are no more contract or maker outputs left
      (and {
          ([] == ( rest_outputs |> find_outputs_by_address(contract_address) ))?,
          ([] == ( rest_outputs |> find_outputs_by_address(maker_address) ))?,
        }, False)
    } else {
      // All other cases are invalid
      (False, False)
    }
  // Then ensure that the maker received nothing except ada + traded_asset
  let is_maker_output_ok =
    ( maker_output.value |> policies() ) == when order_type_init is {
      Buy -> ["", traded_asset_policy_id_init]
      Sell -> [""]
    }

  (and {
      is_maker_address_correct?,
      is_maker_output_ok?,
      is_platform_address_correct?,
      is_validity_range_ok?,
      is_deal_allowed?,
      is_deal_balanced?,
    }, is_deal_partial)
}

fn validate_order_output(
  order_output: Output,
  order_marker: Marker,
  listing_data: ListingDatum,
  tx_validity_range: Interval,
  expected_asset_amount: Option<Int>,
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
  let is_order_amount_valid =
    when expected_asset_amount is {
      Some(expected_asset_amount) ->
        expected_asset_amount == traded_asset_amount
      None -> True
    }

  and {
    asset_price_is_ok?,
    is_output_marker_ok?,
    is_traded_asset_listed?,
    is_order_amount_valid?,
    is_order_value_correct?,
    is_timeout_correct?,
  }
}

validator exchange {
  mint(redeemer: ContractMode, contract_policy_id: PolicyId, tx: Transaction) {
    let (contract_utxo, contract_address, _) =
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
        //     - a signature corresponding to the `order_maker_address` field in the spent utxo datum
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

        expect OrderDatum {
          order_maker_address: Address(VerificationKey(order_maker_keyhash), ..),
          ..
        } = contract_output |> read_order_datum()

        let is_order_output_valid =
          validate_order_output(
            contract_output,
            order_marker,
            listing_data,
            tx_validity_range,
            expected_asset_amount: None,
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
      OrderExecution ->
        // Minting during order execution is optional, so we just check whether the contract is involved in validating the UTXO spend and delegate to it
        and {
          validate_markers_mint(tx_mint, order_marker, -1),
          contract_utxo != None,
        }
      OrderCanceling -> {
        // A correct order canceling transaction must contain:
        //   Reference inputs[1]:
        //     - Reference to the contract valid `config eUTxO`
        //   Inputs[>=1]:
        //      - Exactly one input from the contract address containing the order eUTxO (`contract_policy_id.contract_order_marker` + OrderDatum)
        //      - Any number of user inputs if needed (not validated)
        //   Outputs[>=1]:
        //      - the output to the address associated with the `order_maker_address` keyhash in the order datum that holds the funds locked in the order
        //        - index 0
        //      - any number of outputs to other addresses if needed (not validated)
        //   Minting:
        //     - exactly -1 `contract_policy_id.contract_order_marker`
        //   Validity range[optional]:
        //     - may be omitted if cancellation is performed by an authorized party
        //     - For unauthorized closure, if `timeout` in the datum points to some date, the upper bound must be after that date
        //   Additional signers:    
        //     a) a signature corresponding to the `order_maker_address` field in the spent utxo datum
        //     b) OR a signature corresponding to the `contract_operator_keyhash` field in the config utxo datum
        // Validatiors: Minting + Spending
        let ref_utxos = tx_ref_inputs |> to_outputs()
        expect [maker_output, ..rest] = tx_outputs
        expect [ConfigDatum { is_market_open, contract_operator_keyhash, .. }] =
          ref_utxos
            |> find_outputs_by_marker(config_marker, strict_mode: True)
            |> list.map(read_config_datum)
        expect [order_input_output] =
          tx_inputs
            |> to_outputs()
            |> find_outputs_by_address(contract_address)

        expect Output { value: order_value, .. } = order_input_output
        expect OrderDatum {
          order_type,
          order_maker_address,
          order_timeout_date,
          ..
        } = order_input_output |> read_order_datum()
        expect Address {
          payment_credential: VerificationKey(order_maker_keyhash),
          ..
        } = order_maker_address
        let is_maker_output_address_valid =
          maker_output.address == order_maker_address
        let is_maker_output_value_valid =
          maker_output.value == (
            order_value
              |> merge(
                  from_asset(contract_policy_id, contract_order_marker, -1),
                )
          )
        let only_one_maker_output =
          [] == ( tx_outputs |> find_outputs_by_address(contract_address) )
        let marker_minted_properly =
          validate_markers_mint(tx_mint, order_marker, -1)
        let is_action_authorized_by_user =
          validate_authorization(tx, order_maker_keyhash)
        let is_action_authorized_by_operator =
          validate_authorization(tx, contract_operator_keyhash)
        let is_tx_outdated =
          tx_validity_range |> is_entirely_after(order_timeout_date)
        let is_action_authorized = or {
            (is_action_authorized_by_user && is_market_open)?,
            is_action_authorized_by_operator?,
            is_tx_outdated?,
          }
        and {
          is_market_open?,
          is_maker_output_address_valid?,
          is_maker_output_value_valid?,
          only_one_maker_output?,
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
        //     - a signature corresponding to the `order_maker_address` field in the spent utxo datum
        //     - a signature corresponding to the `order_maker_address` field in the contract output utxo datum
        let ref_utxos = tx_ref_inputs |> to_outputs()

        expect [ConfigDatum { is_market_open, .. }] =
          ref_utxos
            |> find_outputs_by_marker(config_marker, strict_mode: True)
            |> list.map(read_config_datum)

        expect [listing_data] =
          ref_utxos
            |> find_outputs_by_marker(listing_marker, strict_mode: True)
            |> list.map(read_listing_datum)

        expect [contract_utxo] =
          tx_inputs |> to_outputs() |> find_outputs_by_address(contract_address)
        expect [contract_output, ..rest] = tx_outputs

        expect OrderDatum {
          order_maker_address: Address {
            payment_credential: VerificationKey(new_order_maker_keyhash),
            ..
          },
          ..
        } = contract_output |> read_order_datum()

        expect OrderDatum {
          order_maker_address: Address {
            payment_credential: VerificationKey(old_order_maker_keyhash),
            ..
          },
          ..
        } = contract_utxo |> read_order_datum()

        let is_order_output_valid =
          validate_order_output(
            contract_output,
            order_marker,
            listing_data,
            tx_validity_range,
            expected_asset_amount: None,
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
      OrderExecution -> {
        //   Reference inputs[2]:
        //     - Reference to the contract valid `config eUTxO`
        //     - Reference to the `listing eUTxO` allowing interaction with the asset being listed in the order
        //   Inputs[>=1]:
        //      - Exactly one input from the `contract_address` containing the order eUTxO (`contract_policy_id.contract_order_marker` + OrderDatum)
        //      - Any number of user inputs if needed (not validated)
        //   Outputs[>=3]:
        //     - exactly one output to the `maker_address` containing:
        //       - index 0
        //       - the amount of assets/ada paid by the taker depending on the contract type (Buy/Sell)
        //       - [optional] the order's `contract_order_min_ada` if the order was closed
        //     - output to the `taker_address` containing:
        //       - index 1
        //       - the amount of assets/ada paid to the taker depending on the contract type (Buy/Sell)
        //     -exactly one output to the platform address containing:
        //       - platform fee equals (base_platform_fee_percent/10^base_platform_fee_decimal_part)% payed by the taker
        //          - but not less than `platform_fee_min_amount` value, e.g. because we have to respect Cardano's min ada...
        //       - index 2
        //     - [optional] exactly one output to the `contract_address` containing:
        //       - index 3
        //       - 1 token `contract_policy_id.contract_order_marker`
        //       - a datum of type `OrderDatum` (correctly describing the current state of the order)
        //       - the required amount of locked assets depending on the order type (Buy/Sell)
        //       - `contract_order_min_ada` ADA (returned to the owner after the order is closed/executed)
        //       - for PARTIAL payments only
        //    - any number of outputs to other addresses if needed (not validated)
        //   Minting:
        //     - positive minting is forbidden in any case
        //     - if the order was not fully executed, burning is forbidden
        //     - if the order was closed entirely, the token `contract_policy_id.contract_order_marker` must be burned
        //   Validity range:
        //     - Invalid after the timeout specified in the input datum
        //        - Not required if timeout equals 0, but it still does no harm
        //   Partial execution of an order is available only if this is explicitly specified in the order settings!
        // The order datum will change during partial redemption, but in a limited way:
        //  - only the quantity of the asset being sold/purchased, only by the amount sent to the taker
        //  - Changing the remaining fields is strictly forbidden
        let ref_utxos = tx_ref_inputs |> to_outputs()
        expect [config_data] =
          ref_utxos
            |> find_outputs_by_marker(config_marker, strict_mode: True)
            |> list.map(read_config_datum)
        expect [listing_data] =
          ref_utxos
            |> find_outputs_by_marker(listing_marker, strict_mode: True)
            |> list.map(read_listing_datum)

        expect [contract_utxo] =
          tx_inputs |> to_outputs() |> find_outputs_by_address(contract_address)

        let ConfigDatum { is_market_open, .. } = config_data
        let (is_deal_valid, is_deal_partial) =
          validate_deal(
            contract_utxo,
            config_data,
            listing_data,
            tx_validity_range,
            order_marker,
            tx_outputs,
          )
        // Check that there is no extra minting in the transaction
        let is_minting_ok =
          when is_deal_partial is {
            True -> tx_mint == zero
            False -> tx_mint |> validate_markers_mint(order_marker, -1)
          }
        and {
          is_market_open?,
          is_deal_valid?,
          is_minting_ok?,
        }
      }
      OrderCanceling ->
        // Since the order canceling process requires both Spend and Mint checks,
        // validation can be implemented in just one sub-validator without code duplication.
        // During order canceling, markers must be burned, so the transaction must include
        // burning markers on behalf of the contract.
        // If this requirement is met, allow spending the UTXO, because the Mint
        // sub-validator will be invoked next and perform the full validation.
        // And the mint check is much cheaper (it has no utxo multiplier for mem\cpu)
        assets.quantity_of(tx_mint, contract_policy_id, contract_order_marker) < 0
      _ -> False
    }
  }

  else(_) {
    fail
  }
}
