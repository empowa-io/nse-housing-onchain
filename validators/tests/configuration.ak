use cardano/assets.{from_asset, from_lovelace}
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
use types.{Bootstrap, ConfigDatum, Configuration}

const good_mint = from_asset(contract_policy_id, contract_config_marker, 1)

const operator_keyhash_new = "new operator"

const listing_verification_key_new = "new listing vkey"

const good_conf_datum_old =
  ConfigDatum {
    fee_size: base_fee_size,
    contract_operator_credential: operator_payment_keyhash,
    listing_verification_key,
    is_market_open: False,
  }

const good_conf_datum_new =
  ConfigDatum {
    fee_size: base_fee_size * 2,
    contract_operator_credential: operator_keyhash_new,
    listing_verification_key: listing_verification_key_new,
    is_market_open: True,
  }

const good_contract_output =
  Output {
    ..output_placeholder,
    address: contract_address,
    value: good_mint,
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
//       - 1 token `contract_policy_id.contract_config_marker`
//       - a datum of type `ConfigDatum`
//     - any number of outputs to other addresses if needed
//   Minting:
//     - forbidden
//   Additional signers:
//     - a signature corresponding to the `contract_operator_credential` field in the spent utxo datum
//     - a signature corresponding to the `contract_operator_credential` field in the contract tx output datum

// Validatiors: Spending only

test success_and_operator_changed() {
  // Successful configureation where the operator correctly changes the configuration eUTXO
  // Needs two extra signatures
  let tx =
    Transaction {
      ..tx_placeholder,
      inputs: [good_contract_config_input, input_placeholder],
      outputs: [good_contract_output, output_placeholder],
      extra_signatories: [operator_payment_keyhash, operator_keyhash_new],
    }

  nse_housing.nse_housing.spend(
    Some(good_conf_datum_old),
    Configuration,
    good_contract_config_input.output_reference,
    tx,
  )
}

test success_and_operator_not_changed() {
  // Successful configureation where the operator correctly changes the configuration eUTXO
  // Needs Only one signature
  let tx =
    Transaction {
      ..tx_placeholder,
      inputs: [good_contract_config_input, input_placeholder],
      outputs: [good_contract_config_input.output, output_placeholder],
      extra_signatories: [operator_payment_keyhash],
    }

  nse_housing.nse_housing.spend(
    Some(good_conf_datum_old),
    Configuration,
    good_contract_config_input.output_reference,
    tx,
  )
}

test failed_operator_changed_without_signature() fail {
  // Incorrect action violating the rule:
  //   Additional signers:
  //     - a signature corresponding to the `contract_operator_credential` field in the `spent utxo datum`
  //     - a signature corresponding to the `contract_operator_credential` field in the `contract tx output datum`
  //
  // Case where the operator tries to transfer control to another party without their signature.
  // If allowed, there is a risk of losing control because ownership of the new keys is not confirmed.
  // A minor typo could mean losing control of the contract forever.

  let tx =
    Transaction {
      ..tx_placeholder,
      inputs: [good_contract_config_input, input_placeholder],
      outputs: [good_contract_output, output_placeholder],
      extra_signatories: [operator_payment_keyhash],
    }

  nse_housing.nse_housing.spend(
    Some(good_conf_datum_old),
    Configuration,
    good_contract_config_input.output_reference,
    tx,
  )
}

test failed_bad_inputs() fail {
  // Incorrect action violating the rule:
  //   Inputs:
  //     - exactly one input with `contract_policy_id.contract_config_marker` inside

  let bad_input = input_placeholder

  let tx =
    Transaction {
      ..tx_placeholder,
      inputs: [bad_input, input_placeholder],
      outputs: [good_contract_config_input.output, output_placeholder],
      extra_signatories: [operator_payment_keyhash],
    }

  nse_housing.nse_housing.spend(
    Some(good_conf_datum_old),
    Configuration,
    good_contract_config_input.output_reference,
    tx,
  )
}

test failed_bad_outputs() fail {
  // Incorrect action violating the rule:
  //   Outputs:
  //     - exactly one output to the contract address containing:
  //       - 1 token `contract_policy_id.contract_config_marker`
  let bad_contract_output =
    Output { ..good_contract_output, value: from_lovelace(0) }

  let tx =
    Transaction {
      ..tx_placeholder,
      inputs: [good_contract_config_input, input_placeholder],
      outputs: [bad_contract_output, output_placeholder],
      extra_signatories: [operator_payment_keyhash],
    }

  nse_housing.nse_housing.spend(
    Some(good_conf_datum_old),
    Configuration,
    good_contract_config_input.output_reference,
    tx,
  )
}

test failed_bootstrap_bad_datum_v1() fail {
  // Incorrect action violating the rule:
  //   Outputs:
  //     - exactly one output to the contract address containing:
  //       - a datum of type `ConfigDatum`

  let bad_contract_output = Output { ..good_contract_output, datum: NoDatum }

  let tx =
    Transaction {
      ..tx_placeholder,
      inputs: [good_contract_config_input, input_placeholder],
      outputs: [bad_contract_output, output_placeholder],
      extra_signatories: [operator_payment_keyhash],
    }

  nse_housing.nse_housing.spend(
    Some(good_conf_datum_old),
    Configuration,
    good_contract_config_input.output_reference,
    tx,
  )
}

test failed_bootstrap_bad_datum_v2() fail {
  // Incorrect action violating the rule:
  //   Outputs:
  //     - exactly one output to the contract address containing:
  //       - a datum of type `ConfigDatum`

  let bad_contract_output =
    Output { ..good_contract_output, datum: InlineDatum(BadDatum(42)) }

  let tx =
    Transaction {
      ..tx_placeholder,
      inputs: [good_contract_config_input, input_placeholder],
      outputs: [bad_contract_output, output_placeholder],
      extra_signatories: [operator_payment_keyhash],
    }

  nse_housing.nse_housing.spend(
    Some(good_conf_datum_old),
    Configuration,
    good_contract_config_input.output_reference,
    tx,
  )
}

test failed_minting_presents() fail {
  // Incorrect action violating the rule:
  //   Minting:
  //     - forbidden

  let tx =
    Transaction {
      ..tx_placeholder,
      inputs: [good_contract_config_input, input_placeholder],
      outputs: [good_contract_config_input.output, output_placeholder],
      mint: from_asset("any policy", "any asset name", 1),
      extra_signatories: [operator_payment_keyhash],
    }

  nse_housing.nse_housing.spend(
    Some(good_conf_datum_old),
    Configuration,
    good_contract_config_input.output_reference,
    tx,
  )
}
