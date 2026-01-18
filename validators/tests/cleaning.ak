use aiken/collection/list
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
  Bootstrap, Buy, Cleaning, ConfigDatum, ListingDatum, OrderChanging, OrderDatum,
  OrderExecution, OrderPlacing, Sell,
}

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

const good_config_reference_input =
  Input {
    ..input_placeholder,
    output: Output {
      ..output_placeholder,
      address: contract_address,
      value: config_marker,
      datum: InlineDatum(good_conf_datum),
    },
  }

const good_garbage_input1 =
  Input {
    output_reference: OutputReference("hash", 0),
    output: Output {
      ..output_placeholder,
      address: contract_address,
      value: from_lovelace(10_000_000)
        |> merge(from_asset("some policy", "some asset name", 42)),
    },
  }

const good_garbage_input2 =
  Input {
    output_reference: OutputReference("hash", 1),
    output: Output {
      ..output_placeholder,
      address: contract_address,
      value: from_lovelace(30_000_000),
    },
  }

// Test suite for the contract address cleaning action
//  - For various reasons, garbage can accumulate at the contract address:
//      - Garbage is defined as UTXOs created without the smart contract's involvement.
//      - UTXOs that do not contain markers with contract_policy_id: contract_order_marker|contract_config_marker|contract_listing_marker
//  - Such UTXOs can be considered lost forever, or the contract operator can be granted the authority to clean them up.
//  - The operator may remove such a UTXO from the contract address if they sign the transaction with their authorization key.

// This mechanism does not validate outputs and could, in theory, allow the platform operator to appropriate order contents.
// It is crucial to restrict their capabilities to cleaning garbage UTXOs only, and nothing else.

// A correct order changing transaction must contain:
//   Reference inputs[2]:
//     - Reference to the contract valid `config eUTxO`
//   Inputs[>=1]:
//      - Any number of UTXOs from the contract address that can be considered garbage:
//          - UTXOs that do not contain markers with contract_policy_id: contract_order_marker|contract_config_marker|contract_listing_marker.
//      - Any number of inputs from any other addresses
//   Minting:
//     - minting is prohibited as such and will not be possible because the Mint validator will not support the corresponding mode
//   Additional signers:
//     - a signature corresponding to the `contract_operator_credential` field in the config UTXO datum

// Validatiors: Spending only

fn try(tx: Transaction, utxos: List<Input>) -> Bool {
  // reduce(self: List<a>, zero: b, with: fn(b, a) -> b) -> b

  list.reduce(
    utxos,
    True,
    fn(res, utxo) {
      let datum: Data = utxo.output.datum
      let spending_validation =
        nse_housing.exchange.spend(
          Some(datum),
          Cleaning,
          utxo.output_reference,
          tx,
        )

      and {
        res,
        spending_validation,
      }
    },
  )
}

// Success cases
test success_cleaning() {
  // Successful garbage cleanup attempt
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [good_garbage_input1, good_garbage_input2, input_placeholder],
      extra_signatories: [operator_payment_keyhash],
    },
    [good_garbage_input1, good_garbage_input2],
  )
}

// Failed cases
test fail_no_config_ref_input() fail {
  // Incorrect action violating the rule:
  // A correct order changing transaction must contain:
  //   Reference inputs[2]:
  //     - Reference to the contract valid `config eUTxO`

  // The user did not include the config to bypass authentication
  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_garbage_input1, good_garbage_input2, input_placeholder],
      extra_signatories: [operator_payment_keyhash],
    },
    [good_garbage_input1, good_garbage_input2],
  )
}

test fail_order_marker_on_input() fail {
  // Incorrect action violating the rule:
  // A correct order changing transaction must contain:
  //   Inputs[>=1]:
  //     - UTXOs that do not contain markers with contract_policy_id:
  //          a) contract_order_marker

  // Attempt to remove a UTXO that contains contract_order_marker

  let bad_garbage_input =
    Input {
      ..good_garbage_input1,
      output: Output { ..good_garbage_input1.output, value: order_marker },
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [good_garbage_input1, bad_garbage_input, input_placeholder],
      extra_signatories: [operator_payment_keyhash],
    },
    [good_garbage_input1, bad_garbage_input],
  )
}

test fail_config_marker_on_input() fail {
  // Incorrect action violating the rule:
  // A correct order changing transaction must contain:
  //   Inputs[>=1]:
  //     - UTXOs that do not contain markers with contract_policy_id:
  //          b) contract_config_marker

  // Attempt to remove a UTXO that contains contract_config_marker

  let bad_garbage_input =
    Input {
      ..good_garbage_input1,
      output: Output { ..good_garbage_input1.output, value: config_marker },
    }
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [good_garbage_input1, bad_garbage_input, input_placeholder],
      extra_signatories: [operator_payment_keyhash],
    },
    [good_garbage_input1, bad_garbage_input],
  )
}

test fail_listing_marker_on_input() fail {
  // Incorrect action violating the rule:
  // A correct order changing transaction must contain:
  //   Inputs[>=1]:
  //     - UTXOs that do not contain markers with contract_policy_id:
  //          c) contract_listing_marker.

  // Attempt to remove a UTXO that contains contract_listing_marker

  let bad_garbage_input =
    Input {
      ..good_garbage_input1,
      output: Output { ..good_garbage_input1.output, value: listing_marker },
    }
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [good_garbage_input1, bad_garbage_input, input_placeholder],
      extra_signatories: [operator_payment_keyhash],
    },
    [good_garbage_input1, bad_garbage_input],
  )
}

test fail_tx_contains_minting_by_contract() fail {
  // Incorrect action violating the rule:
  // A correct order changing transaction must contain:
  //   Minting:
  //     - minting is prohibited as such and will not be possible because the Mint validator will not support the corresponding mode

  // Attempt to mint something on behalf of the contract

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [good_garbage_input1, good_garbage_input2, input_placeholder],
      extra_signatories: [operator_payment_keyhash],
      mint: from_asset(contract_policy_id, "any asset name", 42),
    },
    [good_garbage_input1, good_garbage_input2],
  )
}

test fail_tx_contains_minting_by_3rd_party() fail {
  // Incorrect action violating the rule:
  // A correct order changing transaction must contain:
  //   Minting:
  //     - minting is prohibited as such and will not be possible because the Mint validator will not support the corresponding mode

  // Attempt to mint something on behalf of a third-party policy
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [good_garbage_input1, good_garbage_input2, input_placeholder],
      extra_signatories: [operator_payment_keyhash],
      mint: from_asset("unknown policy", "any asset name", 42),
    },
    [good_garbage_input1, good_garbage_input2],
  )
}

test fail_missing_operator_signature() fail {
  // Incorrect action violating the rule:
  // A correct order changing transaction must contain:
  //   Additional signers:
  //     - a signature corresponding to the `contract_operator_credential` field in the config UTXO datum

  // The user did not provide the operator signature and is trying to bypass authentication
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [good_garbage_input1, good_garbage_input2, input_placeholder],
    },
    [good_garbage_input1, good_garbage_input2],
  )
}
