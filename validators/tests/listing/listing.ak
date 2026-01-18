use aiken/interval.{after, before}
use aiken/math.{pow}
use cardano/address.{Address}
use cardano/assets.{from_asset, from_lovelace, merge, negate, zero}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
  placeholder as tx_placeholder,
}
use config.{
  contract_bootstrap_utxo_hash, contract_bootstrap_utxo_index,
  contract_config_marker, contract_order_marker, contract_order_min_ada,
}
use default.{
  base_platform_fee_decimal_part, base_platform_fee_min_amount,
  base_platform_fee_percent, config_marker, contract_address,
  contract_payment_cred, contract_policy_id, input_placeholder, listing_marker,
  listing_operator_payment_keyhash, maker_address, maker_payment_cred,
  maker_payment_keyhash, operator_address, operator_payment_cred,
  operator_payment_keyhash, order_marker, output_placeholder, platform_address,
  taker_address, taker_payment_cred, taker_payment_keyhash, utxo_ref_bootstrap,
  utxo_ref_contract, utxo_ref_placeholder,
}
use nse_housing
use types.{
  Bootstrap, Buy, ConfigDatum, Listing, ListingDatum, OrderChanging, OrderDatum,
  OrderExecution, OrderPlacing, Sell,
}

const approved_policy_id = "approved policy"

const approved_asset_name = "approved asset name"

const good_conf_datum =
  ConfigDatum {
    platform_fee_percent: base_platform_fee_percent,
    platform_fee_decimal: base_platform_fee_decimal_part,
    platform_fee_min_amount: base_platform_fee_min_amount,
    platform_fee_address: platform_address,
    contract_operator_credential: operator_payment_keyhash,
    listing_operator_credential: listing_operator_payment_keyhash,
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

const good_listing_output =
  Output {
    ..output_placeholder,
    address: contract_address,
    value: listing_marker,
  }

const good_listing_output_wildcard =
  Output {
    ..good_listing_output,
    datum: InlineDatum(good_listing_datum_wildcard),
  }

const good_listing_output_no_wildcard =
  Output {
    ..good_listing_output,
    datum: InlineDatum(good_listing_datum_no_wildcard),
  }

type BadDatum {
  val: Int,
}

// Test suite for the asset listing action
//  - Note: working with listings requires a separate `listing_operator_credential` role
//  - This adds flexibility by allowing responsibilities to be split
//  - `listing_operator_credential` can match `contract_operator_credential` if no split is needed

// Mostly checks that protect against human error in case the operator makes a mistake
// It also covers potential attack vectors.

// A correct order placing transaction must contain:
//   Reference inputs[2]:
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

// Validatiors: Minting only

fn try(tx: Transaction) -> Bool {
  nse_housing.exchange.mint(Listing, contract_policy_id, tx)
}

// Success cases
test success_listing_wildcard() {
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      outputs: [good_listing_output_wildcard, output_placeholder],
      mint: listing_marker,
      extra_signatories: [listing_operator_payment_keyhash],
    },
  )
}

test success_listing_no_wildcard() {
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      outputs: [good_listing_output_no_wildcard, output_placeholder],
      mint: listing_marker,
      extra_signatories: [listing_operator_payment_keyhash],
    },
  )
}

test success_listing_many_assets() {
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      outputs: [
        good_listing_output_wildcard, good_listing_output_wildcard,
        output_placeholder,
      ],
      mint: listing_marker
        |> merge(listing_marker),
      extra_signatories: [listing_operator_payment_keyhash],
    },
  )
}

//Failed cases
test failed_no_conf_reference_input() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[2]:
  //     - Reference to the contract valid `config eUTxO`

  // User forgot to include the correct config

  try(
    Transaction {
      ..tx_placeholder,
      outputs: [good_listing_output_no_wildcard, output_placeholder],
      mint: listing_marker,
      extra_signatories: [listing_operator_payment_keyhash],
    },
  )
}

test failed_bad_conf_reference_input() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[2]:
  //     - Reference to the contract valid `config eUTxO`

  // User attached a third-party config to bypass authentication

  let bad_conf_datum =
    ConfigDatum {
      ..good_conf_datum,
      listing_operator_credential: taker_payment_keyhash,
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
      outputs: [good_listing_output_no_wildcard, output_placeholder],
      mint: listing_marker,
      extra_signatories: [taker_payment_keyhash],
    },
  )
}

test failed_contract_outputs_marker_mismatch_GT() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //     - one or many outputs to the contract address containing:
  //       - 1 token `contract_policy_id.contract_listing_marker` per output
  //   Minting:
  //     - exactly 1 `contract_policy_id.contract_listing_marker` per contract output
  // For some reason the number of `contract_policy_id.contract_listing_marker` markers
  // and valid outputs do not match
  //  - more markers than outputs
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      outputs: [good_listing_output_wildcard, output_placeholder],
      mint: listing_marker
        |> merge(listing_marker),
      extra_signatories: [listing_operator_payment_keyhash],
    },
  )
}

test failed_contract_outputs_marker_mismatch_LT() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //     - one or many outputs to the contract address containing:
  //       - 1 token `contract_policy_id.contract_listing_marker` per output
  //   Minting:
  //     - exactly 1 `contract_policy_id.contract_listing_marker` per contract output

  // For some reason the number of `contract_policy_id.contract_listing_marker` markers
  // and valid outputs do not match
  //  - fewer markers than outputs
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      outputs: [
        good_listing_output_wildcard, good_listing_output_wildcard,
        output_placeholder,
      ],
      mint: listing_marker,
      extra_signatories: [listing_operator_payment_keyhash],
    },
  )
}

test failed_bad_listing_datum() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //       - a valid datum of type `ListingDatum`

  // User made an error in the datum
  let bad_listing_output =
    Output { ..good_listing_output, datum: InlineDatum(BadDatum(42)) }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      outputs: [bad_listing_output],
      mint: listing_marker,
      extra_signatories: [listing_operator_payment_keyhash],
    },
  )
}

test failed_no_listing_datum() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //       - a valid datum of type `ListingDatum`

  // User forgot to include the datum
  let bad_listing_output = Output { ..good_listing_output, datum: NoDatum }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      outputs: [bad_listing_output],
      mint: listing_marker,
      extra_signatories: [listing_operator_payment_keyhash],
    },
  )
}

test failed_no_marker_minted() fail {
  // Incorrect action violating the rule:
  //   Minting:
  //     - exactly 1 `contract_policy_id.contract_listing_marker` per contract output

  // User forgot to mint `contract_policy_id.contract_listing_marker`
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      outputs: [good_listing_output_wildcard],
      extra_signatories: [listing_operator_payment_keyhash],
    },
  )
}

test failed_no_operator_signature() fail {
  // Incorrect action violating the rule:
  //   Additional signers:
  //     - a signature corresponding to the `listing_operator_credential` field in the reference utxo datum

  // User forgot to add the listing operator signature
  // Or intentionally tries to bypass contract authentication
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      outputs: [good_listing_output_wildcard],
      mint: listing_marker,
    },
  )
}

test failed_bad_operator_signature() fail {
  // Incorrect action violating the rule:
  //   Additional signers:
  //     - a signature corresponding to the `listing_operator_credential` field in the reference utxo datum

  // User provided an incorrect listing operator signature
  // Or intentionally tries to bypass contract authentication
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      outputs: [good_listing_output_wildcard],
      mint: listing_marker,
      extra_signatories: [taker_payment_keyhash],
    },
  )
}
