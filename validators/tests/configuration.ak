use cardano/assets.{from_asset, from_lovelace}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, Transaction,
  placeholder as tx_placeholder,
}
use default.{
  base_platform_fee_decimal_part, base_platform_fee_min_amount,
  base_platform_fee_percent, config_marker, contract_address, input_placeholder,
  listing_operator_payment_keyhash, operator_payment_keyhash, output_placeholder,
  platform_address, utxo_ref_contract,
}
use nse_housing
use types.{ConfigDatum, Configuration}

const operator_keyhash_new = "new operator"

const listing_operator_payment_keyhash_new = "new listing vkey"

const good_conf_datum_old =
  ConfigDatum {
    platform_fee_percent: base_platform_fee_percent,
    platform_fee_decimal: base_platform_fee_decimal_part,
    platform_fee_min_amount: base_platform_fee_min_amount,
    platform_fee_address: platform_address,
    contract_operator_keyhash: operator_payment_keyhash,
    listing_operator_keyhash: listing_operator_payment_keyhash,
    is_market_open: False,
  }

const good_conf_datum_new =
  ConfigDatum {
    platform_fee_percent: base_platform_fee_percent * 2,
    platform_fee_decimal: base_platform_fee_decimal_part,
    platform_fee_min_amount: base_platform_fee_min_amount * 2,
    platform_fee_address: platform_address,
    contract_operator_keyhash: operator_keyhash_new,
    listing_operator_keyhash: listing_operator_payment_keyhash_new,
    is_market_open: True,
  }

const good_contract_output =
  Output {
    ..output_placeholder,
    address: contract_address,
    value: config_marker,
    datum: InlineDatum(good_conf_datum_new),
  }

const good_contract_config_input =
  Input {
    output_reference: utxo_ref_contract,
    output: Output {
      ..good_contract_output,
      datum: InlineDatum(good_conf_datum_old),
    },
  }

type BadDatum {
  val: Int,
}

// RUN: aiken check -S -m tests/exchange/configuration

// Test suite for the contract reconfiguration
// Technically, this is almost the same operation as bootstrap, differing only by:
//  - forbidding minting/burning of `contract_policy_id.contract_config_marker`
//  - no binding to `bootstrap_utxo`
//  - validation via Spend

// Mostly checks that protect against human error in case the operator makes a mistake

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

// Validatiors: Spending only

fn try(tx: Transaction, utxo: Input) -> Bool {
  let datum: Data = utxo.output.datum
  nse_housing.exchange.spend(
    Some(datum),
    Configuration,
    utxo.output_reference,
    tx,
  )
}

// Success cases
test success_and_operator_changed() {
  // Successful configureation where the operator correctly changes the configuration eUTXO
  // Needs two extra signatures
  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_contract_config_input, input_placeholder],
      outputs: [good_contract_output, output_placeholder],
      extra_signatories: [operator_payment_keyhash, operator_keyhash_new],
    },
    good_contract_config_input,
  )
}

test success_and_operator_not_changed() {
  // Successful configureation where the operator correctly changes the configuration eUTXO
  // Needs Only one signature
  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_contract_config_input, input_placeholder],
      outputs: [good_contract_config_input.output, output_placeholder],
      extra_signatories: [operator_payment_keyhash],
    },
    good_contract_config_input,
  )
}

// Failed cases
test failed_operator_changed_without_new_signature() fail {
  // Incorrect action violating the rule:
  //   Additional signers:
  //     - a signature corresponding to the `contract_operator_keyhash` field in the `spent utxo datum`
  //     - a signature corresponding to the `contract_operator_keyhash` field in the `contract tx output datum`
  //
  // Case where the operator tries to transfer control to another party without their signature.
  // If allowed, there is a risk of losing control because ownership of the new keys is not confirmed.
  // A minor typo could mean losing control of the contract forever.

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_contract_config_input, input_placeholder],
      outputs: [good_contract_output, output_placeholder],
      extra_signatories: [operator_payment_keyhash],
    },
    good_contract_config_input,
  )
}

test failed_operator_changed_without_old_signature() fail {
  // Incorrect action violating the rule:
  //   Additional signers:
  //     - a signature corresponding to the `contract_operator_keyhash` field in the `spent utxo datum`
  //     - a signature corresponding to the `contract_operator_keyhash` field in the `contract tx output datum`
  //
  // Case where the operator tries to transfer control to another party, but didn't sign it

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_contract_config_input, input_placeholder],
      outputs: [good_contract_output, output_placeholder],
      extra_signatories: [operator_keyhash_new],
    },
    good_contract_config_input,
  )
}

test failed_bad_outputs_position() fail {
  // Incorrect action violating the rule:
  //   Outputs:
  //       - index 0
  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_contract_config_input, input_placeholder],
      outputs: [output_placeholder, good_contract_output],
      extra_signatories: [operator_keyhash_new],
    },
    good_contract_config_input,
  )
}

test failed_bad_inputs() fail {
  // Incorrect action violating the rule:
  //   Inputs:
  //     - exactly one input with `contract_policy_id.contract_config_marker` inside

  let bad_contract_input =
    Input {
      ..input_placeholder,
      output: Output { ..input_placeholder.output, address: contract_address },
    }

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [bad_contract_input, input_placeholder],
      outputs: [good_contract_config_input.output, output_placeholder],
      extra_signatories: [operator_payment_keyhash],
    },
    bad_contract_input,
  )
}

test failed_bad_outputs() fail {
  // Incorrect action violating the rule:
  //   Outputs:
  //     - exactly one output to the contract address containing:
  //       - 1 token `contract_policy_id.contract_config_marker`
  let bad_contract_output =
    Output { ..good_contract_output, value: from_lovelace(0) }

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_contract_config_input, input_placeholder],
      outputs: [bad_contract_output, output_placeholder],
      extra_signatories: [operator_payment_keyhash],
    },
    good_contract_config_input,
  )
}

test failed_no_datum() fail {
  // Incorrect action violating the rule:
  //   Outputs:
  //     - exactly one output to the contract address containing:
  //       - a datum of type `ConfigDatum`

  let bad_contract_output = Output { ..good_contract_output, datum: NoDatum }

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_contract_config_input, input_placeholder],
      outputs: [bad_contract_output, output_placeholder],
      extra_signatories: [operator_payment_keyhash],
    },
    good_contract_config_input,
  )
}

test failed_bad_datum() fail {
  // Incorrect action violating the rule:
  //   Outputs:
  //     - exactly one output to the contract address containing:
  //       - a datum of type `ConfigDatum`

  let bad_contract_output =
    Output { ..good_contract_output, datum: InlineDatum(BadDatum(42)) }

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_contract_config_input, input_placeholder],
      outputs: [bad_contract_output, output_placeholder],
      extra_signatories: [operator_payment_keyhash],
    },
    good_contract_config_input,
  )
}

test failed_minting_presents() fail {
  // Incorrect action violating the rule:
  //   Minting:
  //     - forbidden

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_contract_config_input, input_placeholder],
      outputs: [good_contract_config_input.output, output_placeholder],
      mint: from_asset("any policy", "any asset name", 1),
      extra_signatories: [operator_payment_keyhash],
    },
    good_contract_config_input,
  )
}
