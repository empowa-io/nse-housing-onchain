use cardano/assets.{from_asset, merge}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, Transaction,
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
use types.{ConfigDatum, Listing, ListingDatum}

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

// RUN: aiken check -S -m tests/listing

// Test suite for the asset listing action
//  - Note: working with listings requires a separate `listing_operator_credential` role
//  - This adds flexibility by allowing responsibilities to be split
//  - `listing_operator_credential` can match `contract_operator_keyhash` if no split is needed

// Mostly checks that protect against human error in case the operator makes a mistake
// It also covers potential attack vectors.

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
  //   Reference inputs:
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
  //   Reference inputs:
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

  // Attempt to mint something other than the marker on behalf of the contract
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

test failed_bad_listing_datum_empty_policy() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //       - a valid datum of type `ListingDatum`

  // User supplied an empty policy_id
  // This is not a problem, but it is better to reject clearly invalid transactions, even if they are safe for the contract
  let bad_listing_output =
    Output {
      ..good_listing_output,
      datum: InlineDatum(
        ListingDatum { ..good_listing_datum_wildcard, listed_policy_id: "" },
      ),
    }

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

test failed_bad_listing_datum_empty_asset_name() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //       - a valid datum of type `ListingDatum`

  // User supplied an empty asset_name instead of None
  // This is not a problem, but it is better to reject clearly invalid transactions, even if they are safe for the contract
  let bad_listing_output =
    Output {
      ..good_listing_output,
      datum: InlineDatum(
        ListingDatum {
          ..good_listing_datum_no_wildcard,
          listed_asset_name: Some(""),
        },
      ),
    }

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

test failed_bad_mint_not_only_markers() fail {
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
        |> merge(from_asset(contract_policy_id, "bad asset name", 1)),
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
