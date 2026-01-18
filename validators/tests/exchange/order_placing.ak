use aiken/interval.{after}
use cardano/assets.{from_asset, from_lovelace, merge}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, Transaction,
  placeholder as tx_placeholder,
}
use config.{
  contract_config_marker, contract_order_marker, contract_order_min_ada,
}
use default.{
  base_platform_fee_decimal_part, base_platform_fee_min_amount,
  base_platform_fee_percent, contract_address, contract_policy_id,
  input_placeholder, listing_marker, listing_operator_payment_keyhash,
  maker_payment_keyhash, operator_payment_keyhash, order_marker,
  output_placeholder, platform_address, taker_address,
}
use nse_housing
use types.{Buy, ConfigDatum, ListingDatum, OrderDatum, OrderPlacing, Sell}

const approved_policy_id = "approved policy"

const approved_asset_name = "approved asset name"

const order_asset_amount = 42

const order_price_per_unit = 10

const timeout = 10

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

const good_listing_reference_input_no_wildcard =
  Input {
    ..input_placeholder,
    output: Output {
      ..good_listing_output,
      datum: InlineDatum(good_listing_datum_no_wildcard),
    },
  }

const good_listing_reference_input_wildcard =
  Input {
    ..input_placeholder,
    output: Output {
      ..good_listing_output,
      datum: InlineDatum(good_listing_datum_wildcard),
    },
  }

const good_sell_order_datum_with_timeout =
  OrderDatum {
    order_type: Sell,
    traded_asset_policy_id: approved_policy_id,
    traded_asset_name: approved_asset_name,
    traded_asset_amount: order_asset_amount,
    traded_asset_price: order_price_per_unit,
    partial_fulfillment_allowed: True,
    order_timeout_date: timeout,
    order_maker_credential: maker_payment_keyhash,
  }

const good_sell_order_datum =
  OrderDatum {
    order_type: Sell,
    traded_asset_policy_id: approved_policy_id,
    traded_asset_name: approved_asset_name,
    traded_asset_amount: order_asset_amount,
    traded_asset_price: order_price_per_unit,
    partial_fulfillment_allowed: True,
    order_timeout_date: 0,
    order_maker_credential: maker_payment_keyhash,
  }

const good_buy_order_datum =
  OrderDatum {
    order_type: Buy,
    traded_asset_policy_id: approved_policy_id,
    traded_asset_name: approved_asset_name,
    traded_asset_amount: order_asset_amount,
    traded_asset_price: order_price_per_unit,
    partial_fulfillment_allowed: True,
    order_timeout_date: 0,
    order_maker_credential: maker_payment_keyhash,
  }

const good_order_subject =
  from_asset(approved_policy_id, approved_asset_name, order_asset_amount)

const good_order_ada = from_lovelace(contract_order_min_ada)

const good_sell_order_output =
  Output {
    ..output_placeholder,
    address: contract_address,
    datum: InlineDatum(good_sell_order_datum),
    value: order_marker
      |> merge(good_order_subject)
      |> merge(good_order_ada),
  }

const good_buy_order_output =
  Output {
    ..good_sell_order_output,
    datum: InlineDatum(good_buy_order_datum),
    value: order_marker
      |> merge(
          from_lovelace(
            order_asset_amount * order_price_per_unit + contract_order_min_ada,
          ),
        ),
  }

const good_sell_order_output_with_timeout =
  Output {
    ..good_sell_order_output,
    datum: InlineDatum(good_sell_order_datum_with_timeout),
  }

type BadDatum {
  val: Int,
}

// TODO: check if `good_order_ada` were broken
// TODO: check more than 2 references
// TODO: traded_asset_price: 0
// TODO: add output index check
// TODO: place_order when market is closed

// Test suite for the order placing action
// Order placing is not tied to the platform UI and can be performed by any user, including via CLI

// Mostly checks that protect against human error in case the operator makes a mistake
// It also covers potential attack vectors.

// A correct order placing transaction must contain:
//   Inputs: (not validated)
//   Reference inputs[2]:
//     - Reference to the `listing eUTxO` allowing interaction with the asset being listed in the order
//     - Reference to the contract valid `config eUTxO`
//   Outputs[>=1]:
//     - exactly one output to the contract address containing:
//       - index 0
//       - 1 token `contract_policy_id.contract_order_marker`
//       - a datum of type `OrderDatum`
//       - the required amount of locked assets depending on the order type (Buy/Sell)
//       - `contract_order_min_ada` ADA (returned to the owner after the order is closed/executed)
//     - any number of outputs to other addresses if needed (not validated)
//   Minting:
//     - exactly 1 `contract_policy_id.contract_order_marker`
//   Validity range[optional]:
//     - may be omitted if `timeout` in the datum is 0
//     - if `timeout` in the datum points to some date, the upper bound must be before that date
//   Additional signers:
//     - a signature corresponding to the `order_maker_credential` field in the spent utxo datum

// Validatiors: Minting only

fn try(tx: Transaction) -> Bool {
  nse_housing.exchange.mint(OrderPlacing, contract_policy_id, tx)
}

// Success cases

test success_sell_no_wildcard() {
  // Successful transaction placing a sell order for 42 listed assets

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      outputs: [good_sell_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test success_sell_wildcard() {
  // Successful transaction placing a sell order for 42 listed assets

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      outputs: [good_sell_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test success_buy_no_wildcard() {
  // Successful transaction placing a buy order for 42 listed assets

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      outputs: [good_buy_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test success_buy_wildcard() {
  // Successful transaction placing a buy order for 42 listed assets

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      outputs: [good_buy_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

// Failed cases

test failed_no_config_ref() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[2]:
  //     - Reference to the contract `config eUTxO`

  // The user forgot to attach the config to the transaction
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_listing_reference_input_wildcard],
      outputs: [good_sell_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test fail_bad_config_reference_utxo() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[2]:
  //     - Reference to the contract `config eUTxO`

  // The user provided a link to another utxo at the contract address instead of the config
  let bad_config_reference_input =
    Input {
      ..good_config_reference_input,
      output: Output {
        ..good_config_reference_input.output,
        value: from_asset("wrong policy", "wrong asset name", 1),
      },
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        bad_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      outputs: [good_sell_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test failed_bad_config_ref_address() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[2]:
  //     - Reference to the contract `config eUTxO`

  // This prevents an attempt to provide the contract with a fake config from a different address
  // No other config compromise paths are expected, because it:
  //  - cannot be created with an invalid datum structure or without `contract_policy_id.contract_config_marker 1`
  //  - cannot be created outside the contract address or moved away from it
  // The only realistic attack is trying to slip in a forged config from outside

  let bad_config_reference_input =
    Input {
      ..good_config_reference_input,
      output: Output {
        ..good_config_reference_input.output,
        address: taker_address,
        value: from_asset("unknown policy", contract_config_marker, 1),
      },
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        bad_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      outputs: [good_sell_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test failed_no_listing_ref() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[2]:
  //     - Reference to the `listing eUTxO` allowing interaction with the asset being listed in the order

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      outputs: [good_sell_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test failed_bad_listing_ref() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[2]:
  //     - Reference to the `listing eUTxO` allowing interaction with the asset being listed in the order

  // This prevents an attempt to provide the contract with a fake listing
  // A listing can be stored at any address, contains no special tokens, but:
  //  - must contain a valid signature in the datum
  //  - the signature is computed as sha256(listed_policy_id [+ listed_asset_name])
  //  - the signature verification key is stored in the config eUTxO

  let bad_listing_reference_input =
    Input {
      ..good_listing_reference_input_no_wildcard,
      output: Output {
        ..good_listing_reference_input_no_wildcard.output,
        datum: InlineDatum(
          ListingDatum {
            ..good_listing_datum_no_wildcard,
            listed_policy_id: "bad policy",
          },
        ),
      },
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, bad_listing_reference_input,
      ],
      outputs: [good_sell_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test failed_no_order_output() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //     - exactly one output to the contract address containing

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      outputs: [output_placeholder, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test failed_many_contract_outputs() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //     - exactly one output to the contract address containing

  // The contract API forbids placing more than one output to the contract address

  let extra_contract_output =
    Output { ..output_placeholder, address: contract_address }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      outputs: [
        good_sell_order_output, extra_contract_output, output_placeholder,
      ],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test failed_bad_order_output_no_marker() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //     - exactly one output to the contract address containing:
  //       - 1 token `contract_policy_id.contract_order_marker`

  // Did the user accidentally send the marker to the change output?
  let bad_order_output =
    Output {
      ..good_sell_order_output,
      value: good_order_subject
        |> merge(good_order_ada),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      outputs: [bad_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test failed_bad_order_output_no_datum() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //     - exactly one output to the contract address containing:
  //       - a datum of type `OrderDatum`

  let bad_order_output = Output { ..good_sell_order_output, datum: NoDatum }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      outputs: [bad_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test failed_bad_order_output_bad_datum() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //     - exactly one output to the contract address containing:
  //       - a datum of type `OrderDatum`

  let bad_order_output =
    Output { ..good_sell_order_output, datum: InlineDatum(BadDatum(42)) }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      outputs: [bad_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test failed_bad_sell_order_output_no_assets() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //     - exactly one output to the contract address containing:
  //       - the required amount of locked assets depending on the order type (Buy/Sell)

  // Scenario where the seller for some reason did not attach the assets declared in the order
  let bad_order_output =
    Output {
      ..good_sell_order_output,
      value: order_marker
        |> merge(good_order_ada),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      outputs: [bad_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test failed_bad_sell_order_output_not_enough_assets() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //     - exactly one output to the contract address containing:
  //       - the required amount of locked assets depending on the order type (Buy/Sell)

  // Scenario where the assets attached to the order are fewer than declared in its datum
  let bad_order_output =
    Output {
      ..good_sell_order_output,
      value: order_marker
        |> merge(
            from_asset(
              approved_policy_id,
              approved_asset_name,
              order_asset_amount - 1,
            ),
          )
        |> merge(good_order_ada),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      outputs: [bad_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test failed_bad_sell_order_output_extra_assets() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //     - exactly one output to the contract address containing:
  //       - the required amount of locked assets depending on the order type (Buy/Sell)

  // Scenario where the assets attached to the order are more than declared in its datum

  let bad_order_output =
    Output {
      ..good_sell_order_output,
      value: order_marker
        |> merge(
            from_asset(
              approved_policy_id,
              approved_asset_name,
              order_asset_amount + 1,
            ),
          )
        |> merge(good_order_ada),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      outputs: [bad_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test failed_bad_buy_order_output_not_enough_locked_ada() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //     - exactly one output to the contract address containing:
  //       - the required amount of locked assets depending on the order type (Buy/Sell)

  // Scenario where the buyer for some reason did not attach enough ADA to purchase the assets declared in the order
  // Or attached less than required. Since ADA is always present in the value, it cannot be missing (unlike assets)
  let bad_order_output =
    Output {
      ..good_buy_order_output,
      value: order_marker
        |> merge(good_order_subject)
        |> merge(
            from_lovelace(
              ( order_asset_amount - 1 ) * order_price_per_unit + contract_order_min_ada,
            ),
          ),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      outputs: [bad_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test failed_bad_buy_order_output_extra_ada() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //     - exactly one output to the contract address containing:
  //       - the required amount of locked assets depending on the order type (Buy/Sell)

  // Scenario where the ADA attached to the order is more than required to purchase the assets declared in the datum

  let bad_order_output =
    Output {
      ..good_buy_order_output,
      value: order_marker
        |> merge(good_order_subject)
        |> merge(
            from_lovelace(
              ( order_asset_amount + 1 ) * order_price_per_unit + contract_order_min_ada,
            ),
          ),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      outputs: [bad_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test failed_bad_order_no_min_ada() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //       - `contract_order_min_ada` ADA (returned to the owner after the order is closed/executed)

  // Scenario where, when selling, the seller did not attach `min_order_ada`

  let bad_order_output =
    Output {
      ..good_sell_order_output,
      value: order_marker
        |> merge(good_order_subject),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      outputs: [bad_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test failed_no_order_marker_in_order_output() fail {
  // Incorrect action violating the rule:
  //   Minting:
  //     - exactly 1 `contract_policy_id.contract_order_marker`

  // A situation where the marker is not minted is impossible per se, otherwise the contract would not be involved
  // But a situation where the minted marker is sent to the wrong output is entirely possible...

  let bad_order_output =
    Output {
      ..good_sell_order_output,
      value: good_order_subject
        |> merge(good_order_ada),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      outputs: [bad_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test failed_extra_marker_mint() fail {
  // Incorrect action violating the rule:
  //   Minting:
  //     - exactly 1 `contract_policy_id.contract_order_marker`

  // Attempt to place more than one order, or a single order with more than one marker
  // Or an attempt to "steal" the order marker from the smart contract intentionally or by mistake
  // No difference: any variant requires minting more than one marker and must be caught at this point
  let bad_mint = from_asset(contract_policy_id, contract_order_marker, 2)

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      outputs: [good_sell_order_output, output_placeholder],
      mint: bad_mint,
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test failed_bad_order_timeout() fail {
  // Incorrect action violating the rule:
  //   Time range[optional]:
  //     - if `timeout` in the datum points to some date, the upper bound must be before that date

  // User messed up the timeout? Better to reject the transaction than create an already-expired order

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      outputs: [good_sell_order_output_with_timeout, output_placeholder],
      mint: order_marker,
      validity_range: after(timeout),
      extra_signatories: [maker_payment_keyhash],
    },
  )
}

test failed_missed_extra_signature() fail {
  // Incorrect action violating the rule:
  //   Additional signers:
  //     - a signature corresponding to the `order_maker_credential` field in the spent utxo datum

  // The user forgot to require a signature by the key specified in the datum and may:
  //  - lose control over the order
  //  - lose funds, because the key specified in the datum is tied to the address where the payout will go
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      outputs: [good_sell_order_output, output_placeholder],
      mint: order_marker,
    },
  )
}

test failed_bad_extra_signature() fail {
  // Incorrect action violating the rule:
  //   Additional signers:
  //     - a signature corresponding to the `order_maker_credential` field in the spent utxo datum

  // The user provided an incorrect signature that does not match the key in the datum, so they may:
  //  - lose control over the order
  //  - lose funds, because the key specified in the datum is tied to the address where the payout will go
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      outputs: [good_sell_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: ["wrong keyhash"],
    },
  )
}
