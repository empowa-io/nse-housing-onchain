use aiken/collection/list
use cardano/assets.{from_asset, merge, negate}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
  placeholder as tx_placeholder,
}
use config.{contract_config_marker}
use default.{
  base_platform_fee_decimal_part, base_platform_fee_min_amount,
  base_platform_fee_percent, contract_address, contract_policy_id,
  input_placeholder, listing_marker, listing_operator_payment_keyhash,
  operator_payment_keyhash, output_placeholder, platform_address, taker_address,
  taker_payment_keyhash,
}
use nse_housing
use types.{ConfigDatum, Delisting, ListingDatum}

const approved_policy_id = "approved policy"

const approved_asset_name = "approved asset name"

const good_conf_datum =
  ConfigDatum {
    platform_fee_percent: base_platform_fee_percent,
    platform_fee_decimal: base_platform_fee_decimal_part,
    platform_fee_min_amount: base_platform_fee_min_amount,
    platform_fee_address: platform_address,
    contract_operator_keyhash: operator_payment_keyhash,
    listing_operator_keyhash: listing_operator_payment_keyhash,
    is_market_open: True,
  }

const good_listing_datum_no_wildcard =
  ListingDatum {
    listed_policy_id: approved_policy_id,
    listed_asset_name: Some(approved_asset_name),
  }

const good_listing_datum_wildcard =
  ListingDatum { listed_policy_id: approved_policy_id, listed_asset_name: None }

const good_config_reference_input =
  Input {
    ..input_placeholder,
    output: Output {
      ..output_placeholder,
      address: contract_address,
      value: from_asset(contract_policy_id, contract_config_marker, 1),
      datum: InlineDatum(good_conf_datum),
    },
  }

const good_listing_input_wildcard =
  Input {
    output_reference: OutputReference("hash", 0),
    output: Output {
      ..output_placeholder,
      address: contract_address,
      value: listing_marker,
      datum: InlineDatum(good_listing_datum_wildcard),
    },
  }

const good_listing_input_no_wildcard =
  Input {
    output_reference: OutputReference("hash", 1),
    output: Output {
      ..output_placeholder,
      address: contract_address,
      value: listing_marker,
      datum: InlineDatum(good_listing_datum_no_wildcard),
    },
  }

// Test suite for the asset delisting action
//  - Works as the inverse of listing:
//      - listing UTXOs are consumed as inputs
//      - no listing markers appear in outputs
//      - all listing markers are burned
//  - Requires a separate `listing_operator_credential` signature

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

// Validatiors: Minting + Spending

fn try(tx: Transaction, utxos: List<Input>) -> Bool {
  let spending_validation =
    list.reduce(
      utxos,
      True,
      fn(res, utxo) {
        let contract_datum =
          when utxo.output.datum is {
            InlineDatum(datum) -> Some(datum)
            _ -> None
          }
        let spending_validation =
          nse_housing.exchange.spend(
            contract_datum,
            Delisting,
            utxo.output_reference,
            tx,
          )

        and {
          res,
          spending_validation,
        }
      },
    )

  and {
    nse_housing.exchange.mint(Delisting, contract_policy_id, tx),
    spending_validation,
  }
}

// Success cases
test success_delisting() {
  // Since only the marker presence is validated, the input type (wildcard/no_wildcard)
  // does not affect anything and does not require separate coverage
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [good_listing_input_wildcard, input_placeholder],
      outputs: [output_placeholder],
      mint: negate(listing_marker),
      extra_signatories: [listing_operator_payment_keyhash],
    },
    [good_listing_input_wildcard],
  )
}

test success_delisting_many_assets() {
  // Successful removal of multiple listings in a single transaction
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [
        good_listing_input_wildcard, good_listing_input_no_wildcard,
        input_placeholder,
      ],
      outputs: [output_placeholder],
      mint: negate(listing_marker)
        |> merge(negate(listing_marker)),
      extra_signatories: [listing_operator_payment_keyhash],
    },
    [good_listing_input_wildcard, good_listing_input_no_wildcard],
  )
}

// Failed cases
test failed_no_conf_reference_input() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[1]:
  //     - Reference to the contract valid `config eUTxO`
  // User forgot to include the correct config

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_listing_input_wildcard, input_placeholder],
      outputs: [output_placeholder],
      mint: negate(listing_marker),
      extra_signatories: [listing_operator_payment_keyhash],
    },
    [good_listing_input_wildcard],
  )
}

test failed_bad_conf_reference_input() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[1]:
  //     - Reference to the contract valid `config eUTxO`
  // User attached a third-party config to bypass authentication

  let bad_conf_datum =
    ConfigDatum {
      ..good_conf_datum,
      listing_operator_keyhash: taker_payment_keyhash,
    }

  let bad_config_reference_input =
    Input {
      ..input_placeholder,
      output: Output {
        ..output_placeholder,
        address: taker_address,
        value: from_asset("unknown policy", contract_config_marker, 1),
        datum: InlineDatum(bad_conf_datum),
      },
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [bad_config_reference_input],
      inputs: [good_listing_input_wildcard, input_placeholder],
      outputs: [output_placeholder],
      mint: negate(listing_marker),
      extra_signatories: [taker_payment_keyhash],
    },
    [good_listing_input_wildcard],
  )
}

test failed_input_without_listing_marker() fail {
  // Incorrect action violating the rule:
  //   Inputs[>=1]:
  //     - one or many inputs from the contract address containing:
  //       - 1 token `contract_policy_id.contract_listing_marker` per input
  // User attempts to delist without a listing marker on the input

  let bad_listing_input =
    Input {
      ..input_placeholder,
      output: Output {
        ..output_placeholder,
        address: contract_address,
        value: from_asset("any policy", "any asset", 1),
      },
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [bad_listing_input, input_placeholder],
      outputs: [output_placeholder],
      mint: negate(listing_marker),
      extra_signatories: [listing_operator_payment_keyhash],
    },
    [bad_listing_input],
  )
}

test failed_marker_burn_mismatch() fail {
  // Incorrect action violating the rule:
  //   Minting:
  //     - exactly -1 `contract_policy_id.contract_listing_marker` per listing input

  // User burned fewer markers than spent listing inputs
  // Attempt to move a marker to an external address
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [
        good_listing_input_wildcard, good_listing_input_no_wildcard,
        input_placeholder,
      ],
      outputs: [output_placeholder],
      mint: negate(listing_marker),
      extra_signatories: [listing_operator_payment_keyhash],
    },
    [good_listing_input_wildcard, good_listing_input_no_wildcard],
  )
}

test failed_no_operator_signature() fail {
  // Incorrect action violating the rule:
  //   Additional signers:
  //     - a signature corresponding to the `listing_operator_credential` field in the reference utxo datum
  // User forgot to add the listing operator signature

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [good_listing_input_wildcard, input_placeholder],
      outputs: [output_placeholder],
      mint: negate(listing_marker),
    },
    [good_listing_input_wildcard],
  )
}

test failed_bad_operator_signature() fail {
  // Incorrect action violating the rule:
  //   Additional signers:
  //     - a signature corresponding to the `listing_operator_credential` field in the reference utxo datum
  // User provided an incorrect listing operator signature

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [good_listing_input_wildcard, input_placeholder],
      outputs: [output_placeholder],
      mint: negate(listing_marker),
      extra_signatories: [taker_payment_keyhash],
    },
    [good_listing_input_wildcard],
  )
}
