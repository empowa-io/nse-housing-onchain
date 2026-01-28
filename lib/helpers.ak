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
  Datum, InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
  find_input, placeholder as tx_placeholder,
}
use config.{
  contract_bootstrap_utxo_hash, contract_bootstrap_utxo_index,
  contract_config_marker, contract_listing_marker, contract_order_marker,
  contract_order_min_ada,
}
use types.{
  Bootstrap, Buy, ConfigDatum, Configuration, ContractMode, ListingDatum, Marker,
  OrderChanging, OrderDatum, OrderExecution, OrderPlacing, OutputRefOrPolicyId,
  Sell,
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

pub fn as_config_datum(datum: Data) -> ConfigDatum {
  expect datum: ConfigDatum = unpack_datum(datum)
  datum
}

pub fn as_order_datum(datum: Data) -> OrderDatum {
  expect datum: OrderDatum = unpack_datum(datum)
  datum
}

pub fn as_listing_datum(datum: Data) -> ListingDatum {
  expect datum: ListingDatum = unpack_datum(datum)
  datum
}

pub fn read_config_datum(output: Output) -> ConfigDatum {
  let Output { datum, .. } = output
  datum |> as_config_datum()
}

pub fn read_order_datum(output: Output) -> OrderDatum {
  let Output { datum, .. } = output
  datum |> as_order_datum()
}

pub fn read_listing_datum(output: Output) -> ListingDatum {
  let Output { datum, .. } = output
  datum |> as_listing_datum()
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
    expect [output] = inputs |> to_outputs() |> find_outputs_by_address(address)
    (Some(output), address, anchor)
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
