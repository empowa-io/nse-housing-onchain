use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{VerificationKeyHash}
use aiken/interval.{Interval, is_entirely_before}
use aiken/math.{max, pow}
use cardano/address.{Address, Script}
use cardano/assets.{
  PolicyId, Value, from_asset, from_lovelace, has_nft, has_nft_strict,
  lovelace_of, policies, quantity_of, zero,
}
use cardano/transaction.{
  Datum, InlineDatum, Input, Output, OutputReference, Transaction, find_input,
}
use config.{
  contract_bootstrap_utxo_hash, contract_bootstrap_utxo_index,
  contract_config_marker, contract_listing_marker, contract_order_marker,
  contract_order_min_ada,
}
use types.{
  Buy, ConfigDatum, ContractMode, Delisting, Listing, ListingDatum, Marker,
  OrderDatum, OutputRefOrPolicyId, Sell,
}

fn unpack_datum(packed_datum: Data) -> Data {
  if packed_datum is Option<Data> {
    expect Some(datum) = packed_datum
    datum
  } else if packed_datum is Datum {
    expect InlineDatum(datum) = packed_datum
    datum
  } else {
    packed_datum
  }
}

pub fn read_config_datum(output: Output) -> ConfigDatum {
  let Output { datum, .. } = output
  expect datum: ConfigDatum = datum |> unpack_datum()
  datum
}

pub fn read_order_datum(output: Output) -> OrderDatum {
  let Output { datum, .. } = output
  expect datum: OrderDatum = datum |> unpack_datum()
  datum
}

pub fn read_listing_datum(output: Output) -> ListingDatum {
  let Output { datum, .. } = output
  expect datum: ListingDatum = datum |> unpack_datum()
  datum
}

pub fn find_outputs_by_address(
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

pub fn find_outputs_by_marker(
  outputs: List<Output>,
  marker: Marker,
  strict_mode: Bool,
) -> List<Output> {
  let Marker(marker_policy_id, marker_asset_name) = marker
  outputs
    |> list.reduce(
        [],
        fn(result, output) {
          let Output { value, .. } = output

          let check_function =
            when strict_mode is {
              True -> has_nft_strict
              False -> has_nft
            }

          when check_function(value, marker_policy_id, marker_asset_name) is {
            True -> [output, ..result]
            False -> result
          }
        },
      )
}

pub fn to_outputs(inputs: List<Input>) -> List<Output> {
  inputs
    |> list.map(fn(Input { output, .. }) { output })
}

pub fn build_markers(policy_id: PolicyId) -> List<Value> {
  [
    from_asset(policy_id, contract_config_marker, 1),
    from_asset(policy_id, contract_order_marker, 1),
    from_asset(policy_id, contract_listing_marker, 1),
  ]
}

pub fn discover_contract_utxo_addr_pid(
  tx: Transaction,
  anchor: OutputRefOrPolicyId,
) -> (Option<Output>, Address, PolicyId) {
  let Transaction { inputs, .. } = tx
  if anchor is OutputReference {
    expect Some(Input { output, .. }) = find_input(inputs, anchor)
    let Output { address, .. } = output
    expect Address { payment_credential: Script(policy_id), .. } = address
    (Some(output), address, policy_id)
  } else if anchor is PolicyId {
    let address =
      Address { payment_credential: Script(anchor), stake_credential: None }
    let output =
      when inputs |> to_outputs() |> find_outputs_by_address(address) is {
        [output, ..] -> Some(output)
        [] -> None
      }
    (output, address, anchor)
  } else {
    fail
  }
}

pub fn validate_sign(
  keyhash: VerificationKeyHash,
  tx_signatories: List<VerificationKeyHash>,
) -> Bool {
  tx_signatories
    |> list.has(keyhash)
}

pub fn validate_markers_mint(
  mint: Value,
  marker: Marker,
  amount_limit: Int,
) -> Bool {
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

pub fn validate_authorization(
  tx: Transaction,
  user_keyhash: VerificationKeyHash,
) -> Bool {
  let Transaction { extra_signatories, .. } = tx
  extra_signatories
    |> list.has(user_keyhash)
}

pub fn validate_marked_output(
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

pub fn validate_marked_input(
  marked_input: Input,
  marker: Marker,
  strict_mode: Bool,
) -> Bool {
  let Input { output, .. } = marked_input
  validate_marked_output(output, marker, strict_mode)
}

pub fn validate_config_update(tx: Transaction, config_marker: Marker) -> Bool {
  expect Transaction {
    inputs: tx_inputs,
    outputs: [contract_config_output, ..rest_outputs],
    mint: minted_value,
    ..
  } = tx
  let Marker(contract_policy_id, ..) = config_marker
  let contract_address = Address(Script(contract_policy_id), None)
  let ConfigDatum { contract_operator_keyhash: new_operator_keyhash, .. } =
    contract_config_output |> read_config_datum()
  let contract_inputs_outs =
    tx_inputs |> to_outputs() |> find_outputs_by_address(contract_address)
  expect [] = find_outputs_by_address(rest_outputs, contract_address)
  let bootstrap_phase =
    when contract_inputs_outs is {
      [] -> True
      _ -> False
    }

  let tx_approved_by_prev_operator =
    if bootstrap_phase {
      expect [bootstrap_input] = tx_inputs
      let expected_bootstrap_utxo_ref =
        OutputReference(
          contract_bootstrap_utxo_hash,
          contract_bootstrap_utxo_index,
        )
      bootstrap_input.output_reference == expected_bootstrap_utxo_ref
    } else {
      expect [
        ConfigDatum { contract_operator_keyhash: prev_operator_keyhash, .. },
      ] = contract_inputs_outs |> list.map(read_config_datum)
      tx |> validate_authorization(prev_operator_keyhash)
    }

  let is_minting_fine =
    if bootstrap_phase {
      validate_markers_mint(minted_value, config_marker, 1)
    } else {
      minted_value == zero
    }

  let is_config_output_addr_valid =
    contract_config_output.address == contract_address

  let config_output_marked_properly =
    contract_config_output
      |> validate_marked_output(config_marker, strict_mode: True)

  let tx_approved_by_new_operator =
    tx |> validate_authorization(new_operator_keyhash)

  and {
    tx_approved_by_prev_operator?,
    tx_approved_by_new_operator?,
    is_config_output_addr_valid?,
    config_output_marked_properly?,
    is_minting_fine?,
  }
}

pub fn validate_listing_update(
  tx: Transaction,
  mode: ContractMode,
  config_marker: Marker,
  listing_marker: Marker,
) -> Bool {
  let Transaction {
    reference_inputs: tx_ref_inputs,
    inputs: tx_inputs,
    outputs: tx_outputs,
    mint: tx_mint,
    ..
  } = tx
  let Marker(contract_policy_id, ..) = config_marker
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
    config_ref_input.output |> read_config_datum()

  let all_listings_are_valid =
    listings
      |> list.reduce(
          True,
          fn(result, listing_output) {
            let ListingDatum { listed_policy_id, listed_asset_name } =
              listing_output |> read_listing_datum()
            and {
              result,
              (listed_policy_id != "")?,
              (listed_asset_name != Some(""))?,
              (listing_output
                |> validate_marked_output(listing_marker, strict_mode: True))?,
            }
          },
        )

  let markers_are_ok =
    validate_markers_mint(tx_mint, listing_marker, markers_count)

  let is_action_authorized =
    tx |> validate_authorization(listing_operator_keyhash)

  and {
    all_listings_are_valid?,
    config_is_valid?,
    markers_are_ok?,
    is_action_authorized?,
  }
}

pub fn validate_deal(
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

pub fn validate_order_output(
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

  let is_asset_price_ok = traded_asset_price > 0

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
    is_asset_price_ok?,
    is_output_marker_ok?,
    is_traded_asset_listed?,
    is_order_amount_valid?,
    is_order_value_correct?,
    is_timeout_correct?,
  }
}
