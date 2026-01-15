use cardano/assets.{from_asset, from_lovelace, merge}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, OutputReference, Transaction,
  placeholder as tx_placeholder,
}
use config.{
  contract_bootstrap_utxo_hash, contract_bootstrap_utxo_index,
  contract_config_marker, contract_order_marker, contract_order_min_ada,
}
use default.{
  base_fee_size, contract_address, contract_payment_cred, contract_policy_id,
  input_placeholder, listing_verification_key, maker_address, maker_payment_cred,
  operator_address, operator_payment_cred, operator_payment_keyhash,
  output_placeholder, taker_address, taker_payment_cred, utxo_ref_bootstrap,
  utxo_ref_contract, utxo_ref_placeholder,
}
use nse_housing
use types.{Bootstrap, ConfigDatum}

const config_marker = from_asset(contract_policy_id, contract_config_marker, 1)

const good_conf_datum =
  ConfigDatum {
    fee_size: base_fee_size,
    contract_operator_credential: operator_payment_keyhash,
    listing_verification_key,
    is_market_open: False,
  }

const good_bootstrap_input =
  Input { ..input_placeholder, output_reference: utxo_ref_bootstrap }

const good_contract_output =
  Output {
    ..output_placeholder,
    address: contract_address,
    value: config_marker,
    datum: InlineDatum(good_conf_datum),
  }

type BadDatum {
  val: Int,
}

// TODO: add output index check
// Test suite for the contract launch phase
// Bootstrapping can only be performed once, so we must ensure everything goes through without errors
// Mostly checks that protect against human error in case the operator makes a mistake

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
//     - a signature corresponding to the `contract_operator_credential` field in the datum

// Validatiors: Minting only

fn try(tx: Transaction) -> Bool {
  nse_housing.exchange.mint(Bootstrap, contract_policy_id, tx)
}

// Success cases
test succes_bootstrap() {
  // Successful bootstrap where the operator correctly registers the configuration eUTXO

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_bootstrap_input],
      outputs: [good_contract_output, output_placeholder],
      mint: config_marker,
      extra_signatories: [operator_payment_keyhash],
    },
  )
}

// Failed cases
test failed_bad_inputs() fail {
  // Incorrect action violating the rule:
  //   Inputs:
  //     - exactly one input

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_bootstrap_input, input_placeholder],
      outputs: [good_contract_output, output_placeholder],
      mint: config_marker,
      extra_signatories: [operator_payment_keyhash],
    },
  )
}

test failed_bad_bootstrap_utxo_hash() fail {
  // Incorrect action violating the rule:
  //   Inputs:
  //     - exactly one input using contract_bootstrap_utxo_hash

  let bad_bootstrap_input =
    Input {
      ..good_bootstrap_input,
      output_reference: OutputReference(
        "wrong hash",
        contract_bootstrap_utxo_index,
      ),
    }

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [bad_bootstrap_input],
      outputs: [good_contract_output, output_placeholder],
      mint: config_marker,
      extra_signatories: [operator_payment_keyhash],
    },
  )
}

test failed_bad_bootstrap_utxo_index() fail {
  // Incorrect action violating the rule:
  //   Inputs:
  //     - exactly one input using contract_bootstrap_utxo_hash#contract_bootstrap_utxo_index

  let bad_bootstrap_input =
    Input {
      ..good_bootstrap_input,
      output_reference: OutputReference(
        contract_bootstrap_utxo_hash,
        contract_bootstrap_utxo_index + 1,
      ),
    }

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [bad_bootstrap_input],
      outputs: [good_contract_output, output_placeholder],
      mint: config_marker,
      extra_signatories: [operator_payment_keyhash],
    },
  )
}

test failed_many_contract_outputs() fail {
  // Incorrect action violating the rule:
  //   Outputs:
  //     - exactly one output to the contract address

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_bootstrap_input],
      outputs: [good_contract_output, good_contract_output, output_placeholder],
      mint: config_marker,
      extra_signatories: [operator_payment_keyhash],
    },
  )
}

test failed_no_marker_in_contract_output() fail {
  // Incorrect action violating the rule:
  //   Outputs:
  //   Outputs:
  //     - exactly one output to the contract address containing:
  //       - 1 token `contract_policy_id.contract_config_marker`
  let bad_contract_output =
    Output { ..good_contract_output, value: from_lovelace(0) }

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_bootstrap_input],
      outputs: [bad_contract_output, output_placeholder],
      mint: config_marker,
      extra_signatories: [operator_payment_keyhash],
    },
  )
}

test failed_bad_datum_v1() fail {
  // Incorrect action violating the rule:
  //   Outputs:
  //     - exactly one output to the contract address containing:
  //       - a datum of type `ConfigDatum`

  let bad_contract_output = Output { ..good_contract_output, datum: NoDatum }

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_bootstrap_input],
      outputs: [bad_contract_output, output_placeholder],
      mint: config_marker,
      extra_signatories: [operator_payment_keyhash],
    },
  )
}

test failed_bad_datum_v2() fail {
  // Incorrect action violating the rule:
  //   Outputs:
  //     - exactly one output to the contract address containing:
  //       - a datum of type `ConfigDatum`

  let bad_contract_output =
    Output { ..good_contract_output, datum: InlineDatum(BadDatum(42)) }

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_bootstrap_input],
      outputs: [bad_contract_output, output_placeholder],
      mint: config_marker,
      extra_signatories: [operator_payment_keyhash],
    },
  )
}

test failed_bad_minting_policy_id() fail {
  // Incorrect action violating the rule:
  //   Minting:
  //     - exactly one `contract_policy_id.contract_config_marker`

  let bad_mint = from_asset("wrong policy", contract_config_marker, 1)

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_bootstrap_input],
      outputs: [good_contract_output, output_placeholder],
      mint: bad_mint,
      extra_signatories: [operator_payment_keyhash],
    },
  )
}

test failed_bad_minting_asset_name() fail {
  // Incorrect action violating the rule:
  //   Minting:
  //     - exactly one `contract_policy_id.contract_config_marker`

  let bad_mint = from_asset(contract_policy_id, "wrong asset name", 1)

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_bootstrap_input],
      outputs: [good_contract_output, output_placeholder],
      mint: bad_mint,
      extra_signatories: [operator_payment_keyhash],
    },
  )
}

test failed_bad_minting_amount() fail {
  // Incorrect action violating the rule:
  //   Minting:
  //     - exactly one `contract_policy_id.contract_config_marker`

  let bad_mint = from_asset(contract_policy_id, contract_config_marker, 2)

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_bootstrap_input],
      outputs: [good_contract_output, output_placeholder],
      mint: bad_mint,
      extra_signatories: [operator_payment_keyhash],
    },
  )
}

test failed_bad_minting_extra_asset() fail {
  // Incorrect action violating the rule:
  //   Minting:
  //     - exactly one `contract_policy_id.contract_config_marker`

  let bad_mint =
    merge(config_marker, from_asset(contract_policy_id, "wrong asset name", 1))

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_bootstrap_input],
      outputs: [good_contract_output, output_placeholder],
      mint: bad_mint,
      extra_signatories: [operator_payment_keyhash],
    },
  )
}

test failed_bad_signature() fail {
  // Incorrect action violating the rule:
  //   Additional signers:
  //     - a signature corresponding to the `contract_operator_credential` field in the datum

  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_bootstrap_input],
      outputs: [good_contract_output, output_placeholder],
      mint: config_marker,
      extra_signatories: ["wrong keyhash"],
    },
  )
}
