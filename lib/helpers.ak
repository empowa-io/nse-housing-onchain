use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{VerificationKeyHash}
use aiken/interval.{Interval, is_entirely_before}
use cardano/address.{Address, Script}
use cardano/assets.{
  AssetName, PolicyId, Value, from_lovelace, has_nft, has_nft_strict, policies,
}
use cardano/transaction.{
  Datum, InlineDatum, Input, Output, OutputReference, Transaction, find_input,
}
use config.{
  contract_config_marker, contract_listing_marker, contract_order_marker,
  contract_order_min_ada,
}
use types.{
  Buy, ConfigDatum, ListingDatum, Marker, OrderDatum, OutputRefOrPolicyId, Sell,
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

pub fn build_markers(policy_id: PolicyId) -> (Marker, Marker, Marker) {
  (
    Marker(policy_id, contract_config_marker),
    Marker(policy_id, contract_listing_marker),
    Marker(policy_id, contract_order_marker),
  )
}

pub fn discover_contract_utxo_addr_pid(
  tx: Transaction,
  anchor: OutputRefOrPolicyId,
) -> (Option<Output>, Address, PolicyId) {
  let Transaction { inputs, .. } = tx
  // It would be cleaner to use `when`, but `when` doesn't support soft-casting...
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

pub fn validate_authorization(
  tx: Transaction,
  user_keyhash: VerificationKeyHash,
) -> Bool {
  let Transaction { extra_signatories, .. } = tx
  extra_signatories
    |> list.has(user_keyhash)
}

/// Helper to verify correct minting/burning of the contract output marker
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

/// Helper to validate marked contract outputs
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

/// Helper to validate marked contract inputs
pub fn validate_marked_input(
  marked_input: Input,
  marker: Marker,
  strict_mode: Bool,
) -> Bool {
  let Input { output, .. } = marked_input
  validate_marked_output(output, marker, strict_mode)
}

pub fn validate_order_output(
  order_output: Output,
  order_marker: Marker,
  listing_data: ListingDatum,
  tx_validity_range: Interval,
  expected_asset_amount: Option<Int>,
) -> Bool {
  let Marker(contract_policy_id, order_marker_asset_name) = order_marker
  let Output { value: order_value, .. } = order_output

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
  let is_asset_amount_ok = traded_asset_amount > 0

  let is_output_marker_ok =
    order_output
      |> validate_marked_output(order_marker, strict_mode: False)

  let is_traded_asset_listed =
    validate_asset_listing(
      traded_asset_policy_id,
      traded_asset_name,
      listing_data,
    )

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
    is_asset_amount_ok?,
    is_output_marker_ok?,
    is_traded_asset_listed?,
    is_order_amount_valid?,
    is_order_value_correct?,
    is_timeout_correct?,
  }
}

pub fn validate_asset_listing(
  traded_policy_id: PolicyId,
  traded_asset_name: AssetName,
  listing_data: ListingDatum,
) -> Bool {
  let ListingDatum { listed_policy_id, listed_asset_name } = listing_data
  and {
    (traded_policy_id == listed_policy_id)?,
    when listed_asset_name is {
      None -> True
      Some(asset_name) -> (asset_name == traded_asset_name)?
    },
  }
}
