
use cardano/assets.{from_asset, from_lovelace, merge, negate}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output,  Transaction,
  placeholder as tx_placeholder,
}
use config.{
   
  contract_config_marker,  contract_order_min_ada,
}
use default.{
  base_platform_fee_decimal_part, base_platform_fee_min_amount,
  base_platform_fee_percent, config_marker, contract_address, input_placeholder,
  listing_marker, listing_operator_payment_keyhash, maker_payment_keyhash,
   operator_payment_keyhash, order_marker,
  output_placeholder, platform_address, taker_address, 
  taker_payment_keyhash,
}
use nse_housing
use types.{Buy, ConfigDatum, ListingDatum, OrderChanging, OrderDatum, Sell}

const approved_policy_id = "approved policy"

const approved_asset_name = "approved asset name"

const order_asset_amount = 42

const order_price_per_unit = 10

const timeout = 10

const good_order_subject =
  from_asset(approved_policy_id, approved_asset_name, order_asset_amount)

const good_order_ada = from_lovelace(contract_order_min_ada)

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
      value: config_marker,
      datum: InlineDatum(good_conf_datum),
    },
  }

const good_listing_output =
  Output { ..output_placeholder, value: listing_marker }

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

const good_sell_order_datum =
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

const good_sell_order_input =
  Input { ..input_placeholder, output: good_sell_order_output }

const good_buy_order_datum_new_owner =
  OrderDatum {
    order_type: Sell,
    traded_asset_policy_id: approved_policy_id,
    traded_asset_name: approved_asset_name,
    traded_asset_amount: order_asset_amount,
    traded_asset_price: order_price_per_unit,
    partial_fulfillment_allowed: True,
    order_timeout_date: timeout,
    order_maker_credential: taker_payment_keyhash,
  }

const good_buy_order_output_new_owner =
  Output {
    ..good_buy_order_output,
    datum: InlineDatum(good_buy_order_datum_new_owner),
  }

type BadDatum {
  val: Int,
}

// TODO: check if `good_order_ada` were broken
// TODO: check more than 2 references
// TODO: traded_asset_price: 0
// TODO: add output index check
// TODO: change order when market is closed

// Test suite for the order changing action
//  - Order owner may change its configuration at any moment
//  - Operator is not allowed to do so(!)
//  - Action is almost the same as `order placing`, except there is no marker mint
//  - Technically this is a combination of `order canceling` + `order placing` in one transaction

// Main attack vector is an unauthorized attempt or a desync between order settings and its contents
// Most checks here guard against potential user mistakes

// A correct order changing transaction must contain:
//   Reference inputs[1]:
//     - Reference to the contract valid `config eUTxO`
//     - Reference to the `listing eUTxO` allowing interaction with the asset being listed in the order
//   Inputs[>=1]:
//      - Exactly one input from the contract address containing the order eUTxO (`contract_policy_id.contract_order_marker` + OrderDatum)
//      - Any number of user inputs if needed (not validated)
//   Outputs[>=1]:
//     - exactly one output to the contract address containing:
//       - index 0
//       - 1 token `contract_policy_id.contract_order_marker`
//       - a datum of type `OrderDatum`
//       - the required amount of locked assets depending on the order type (Buy/Sell)
//       - `contract_order_min_ada` ADA (returned to the owner after the order is closed/executed)
//      - any number of outputs to other addresses if needed (not validated)
//   Minting:
//     - forbidden
//   Additional signers:    
//     - a signature corresponding to the `order_maker_credential` field in the spent utxo datum
//     - a signature corresponding to the `order_maker_credential` field in the contract output utxo datum
// Validatiors: Spending only

fn try(tx: Transaction, utxo: Input) -> Bool {
  let datum: Data = utxo.output.datum
  nse_housing.exchange.spend(
    Some(datum),
    OrderChanging,
    utxo.output_reference,
    tx,
  )
}

// Success cases

test success_order_changing() {
  // Successful attempt to change the order
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [good_buy_order_output, output_placeholder],
      extra_signatories: [maker_payment_keyhash],
    },
    good_sell_order_input,
  )
}

test success_order_changing_new_owner() {
  // Successful attempt to change the order and set a new owner
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [good_buy_order_output_new_owner, output_placeholder],
      extra_signatories: [maker_payment_keyhash, taker_payment_keyhash],
    },
    good_sell_order_input,
  )
}

// Failed cases

test fail_no_config_reference() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[1]:
  //     - Reference to the contract valid `config eUTxO`
  // User forgot to attach the config to the transaction

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_listing_reference_input_no_wildcard],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [good_buy_order_output, output_placeholder],
      extra_signatories: [maker_payment_keyhash],
    },
    good_sell_order_input,
  )
}

test fail_bad_config_reference_utxo() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[1]:
  //     - Reference to the contract valid `config eUTxO`
  // Provided a reference to another UTxO instead of the config

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
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [good_buy_order_output, output_placeholder],
      extra_signatories: [maker_payment_keyhash],
    },
    good_sell_order_input,
  )
}

test fail_bad_config_reference_address() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[1]:
  //     - Reference to the contract valid `config eUTxO`

  // Attempt to spoof the config with a UTxO from a different address
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
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [good_buy_order_output, output_placeholder],
      extra_signatories: [maker_payment_keyhash],
    },
    good_sell_order_input,
  )
}

test fail_no_listing_reference() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[1]:
  //     - Reference to the `listing eUTxO` allowing interaction with the asset being listed in the order
  // User did not attach the authorizing listing

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [good_buy_order_output, output_placeholder],
      extra_signatories: [maker_payment_keyhash],
    },
    good_sell_order_input,
  )
}

test fail_bad_listing_reference() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[1]:
  //     - Reference to the `listing eUTxO` allowing interaction with the asset being listed in the order

  // Supplying an invalid listing UTxO
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
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [good_buy_order_output, output_placeholder],
      extra_signatories: [maker_payment_keyhash],
    },
    good_sell_order_input,
  )
}

test fail_many_orders_at_once() fail {
  // Incorrect action violating the rule:
  //   Inputs[>=1]:
  //      - Exactly one input from the contract address containing the order eUTxO (`contract_policy_id.contract_order_marker` + OrderDatum)
  // Attempt to change multiple orders in one transaction, which the API forbids

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      inputs: [good_sell_order_input, good_sell_order_input, input_placeholder],
      outputs: [
        good_buy_order_output, good_buy_order_output, output_placeholder,
      ],
      extra_signatories: [maker_payment_keyhash],
    },
    good_sell_order_input,
  )
}

test fail_bad_order_utxo() fail {
  // Incorrect action violating the rule:
  //   Inputs[>=1]:
  //      - Exactly one input from the contract address containing the order eUTxO (`contract_policy_id.contract_order_marker` + OrderDatum)

  // Attempt to use a non-order input for the change
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      inputs: [good_config_reference_input, input_placeholder],
      outputs: [good_buy_order_output, output_placeholder],
      extra_signatories: [maker_payment_keyhash],
    },
    good_config_reference_input,
  )
}

test fail_no_order_output() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //     - exactly one output to the contract address containing:
  // User failed to create a new order output at the contract

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [output_placeholder, output_placeholder],
      extra_signatories: [maker_payment_keyhash],
    },
    good_sell_order_input,
  )
}

test fail_many_contract_outputs() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //     - exactly one output to the contract address containing:
  // Attempt to place multiple outputs at the contract address

  let extra_contract_output =
    Output { ..output_placeholder, address: contract_address }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_buy_order_output, extra_contract_output, output_placeholder,
      ],
      extra_signatories: [maker_payment_keyhash],
    },
    good_sell_order_input,
  )
}

test fail_missing_order_marker_in_output() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //     - exactly one output to the contract address containing:
  //       - 1 token `contract_policy_id.contract_order_marker`
  // Order marker accidentally sent to the wrong output

  let bad_order_output =
    Output {
      ..good_buy_order_output,
      value: from_lovelace(
        order_asset_amount * order_price_per_unit + contract_order_min_ada,
      ),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [bad_order_output, output_placeholder],
      extra_signatories: [maker_payment_keyhash],
    },
    good_sell_order_input,
  )
}

test fail_missing_order_datum() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //     - exactly one output to the contract address containing:
  //       - a datum of type `OrderDatum`
  // User forgot to attach the new order datum

  let bad_order_output = Output { ..good_buy_order_output, datum: NoDatum }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [bad_order_output, output_placeholder],
      extra_signatories: [maker_payment_keyhash],
    },
    good_sell_order_input,
  )
}

test fail_bad_order_datum_type() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //     - exactly one output to the contract address containing:
  //       - a datum of type `OrderDatum`
  // Datum does not match the expected order structure

  let bad_order_output =
    Output { ..good_buy_order_output, datum: InlineDatum(BadDatum(42)) }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [bad_order_output, output_placeholder],
      extra_signatories: [maker_payment_keyhash],
    },
    good_sell_order_input,
  )
}

test fail_sell_order_output_no_assets() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //     - exactly one output to the contract address containing:
  //       - the required amount of locked assets depending on the order type (Buy/Sell)
  // Buyer supplied only min-ADA without paying for the order

  let bad_order_output =
    Output {
      ..good_buy_order_output,
      value: order_marker
        |> merge(good_order_ada),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [bad_order_output, output_placeholder],
      extra_signatories: [maker_payment_keyhash],
    },
    good_sell_order_input,
  )
}

test fail_buy_order_output_not_enough_ada() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //     - exactly one output to the contract address containing:
  //       - the required amount of locked assets depending on the order type (Buy/Sell)
  // Buyer attached less ADA than required to purchase the specified assets

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
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [bad_order_output, output_placeholder],
      extra_signatories: [maker_payment_keyhash],
    },
    good_sell_order_input,
  )
}

test fail_buy_order_output_extra_ada() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //     - exactly one output to the contract address containing:
  //       - the required amount of locked assets depending on the order type (Buy/Sell)
  // Buyer attached extra ADA above the required amount

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
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [bad_order_output, output_placeholder],
      extra_signatories: [maker_payment_keyhash],
    },
    good_sell_order_input,
  )
}

test fail_bad_order_no_min_ada() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //       - `contract_order_min_ada` ADA (returned to the owner after the order is closed/executed)
  // Author forgot to include the minimal ADA on the order output

  let bad_order_output =
    Output {
      ..good_buy_order_output,
      value: order_marker
        |> merge(from_lovelace(order_asset_amount * order_price_per_unit)),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [bad_order_output, output_placeholder],
      extra_signatories: [maker_payment_keyhash],
    },
    good_sell_order_input,
  )
}

test fail_positive_minting() fail {
  // Incorrect action violating the rule:
  //   Minting:
  //     - forbidden
  // Attempt to mint anything in the order change transaction

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [good_buy_order_output, output_placeholder],
      mint: order_marker,
      extra_signatories: [maker_payment_keyhash],
    },
    good_sell_order_input,
  )
}

test fail_negative_minting() fail {
  // Incorrect action violating the rule:
  //   Minting:
  //     - forbidden
  // Attempt to burn something in the order change transaction

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [good_buy_order_output, output_placeholder],
      mint: negate(order_marker),
      extra_signatories: [maker_payment_keyhash],
    },
    good_sell_order_input,
  )
}

test fail_missing_maker_signature() fail {
  // Incorrect action violating the rule:
  //   Additional signers:
  //     - a signature corresponding to the `order_maker_credential` field in the spent utxo datum
  // Order owner did not sign the change

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [good_buy_order_output, output_placeholder],
    },
    good_sell_order_input,
  )
}

test fail_bad_extra_signature() fail {
  // Incorrect action violating the rule:
  //   Additional signers:
  //     - a signature corresponding to the `order_maker_credential` field in the spent utxo datum

  // Operator cannot change someone else's order alone
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_no_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [good_buy_order_output, output_placeholder],
      extra_signatories: [operator_payment_keyhash],
    },
    good_sell_order_input,
  )
}

test fail_missing_new_owner_signature() fail {
  // Incorrect action violating the rule:
  //   Additional signers:
  //     - a signature corresponding to the `order_maker_credential` field in the contract output utxo datum
  // New owner is specified in the datum but did not sign the transaction

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [good_buy_order_output_new_owner, output_placeholder],
      extra_signatories: [maker_payment_keyhash],
    },
    good_sell_order_input,
  )
}

test fail_missing_previous_owner_signature() fail {
  // Incorrect action violating the rule:
  //   Additional signers:
  //     - a signature corresponding to the `order_maker_credential` field in the spent utxo datum
  // Previous owner did not sign the transfer of the order to the new owner

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [good_buy_order_output_new_owner, output_placeholder],
      extra_signatories: [taker_payment_keyhash],
    },
    good_sell_order_input,
  )
}
