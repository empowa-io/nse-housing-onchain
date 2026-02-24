use aiken/interval.{entirely_after, entirely_before}
use cardano/address.{Address}
use cardano/assets.{from_asset, from_lovelace, merge, negate}
use cardano/transaction.{
  InlineDatum, Input, Output, Transaction, placeholder as tx_placeholder,
}
use config.{contract_config_marker}
use default.{
  base_platform_fee_decimal_part, base_platform_fee_min_amount,
  base_platform_fee_percent, config_marker, contract_address,
  contract_order_min_ada_amount, contract_policy_id, input_placeholder,
  listing_operator_payment_keyhash, maker_address, maker_payment_cred,
  maker_payment_keyhash, operator_payment_keyhash, order_marker,
  output_placeholder, platform_address, taker_address, taker_payment_keyhash,
}
use nse_housing
use types.{ConfigDatum, OrderCanceling, OrderDatum, Sell}

const approved_policy_id = "approved policy"

const approved_asset_name = "approved asset name"

const order_asset_amount = 42

const order_price_per_unit = 10

const timeout = 10

const fee = 10

const conf_datum =
  ConfigDatum {
    platform_fee_percent: base_platform_fee_percent,
    platform_fee_decimal: base_platform_fee_decimal_part,
    platform_fee_min_amount: base_platform_fee_min_amount,
    platform_fee_address: platform_address,
    contract_operator_keyhash: operator_payment_keyhash,
    listing_operator_keyhash: listing_operator_payment_keyhash,
    contract_order_min_ada: contract_order_min_ada_amount,
    is_market_open: True,
  }

const good_config_reference_input =
  Input {
    ..input_placeholder,
    output: Output {
      ..output_placeholder,
      address: contract_address,
      value: config_marker,
      datum: InlineDatum(conf_datum),
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
    order_maker_address: maker_address,
  }

const order_subject =
  from_asset(approved_policy_id, approved_asset_name, order_asset_amount)

const order_ada = from_lovelace(contract_order_min_ada_amount)

const sell_order_input =
  Input {
    ..input_placeholder,
    output: Output {
      ..output_placeholder,
      address: contract_address,
      datum: InlineDatum(good_sell_order_datum_with_timeout),
      value: order_marker
        |> merge(order_subject)
        |> merge(order_ada),
    },
  }

const good_maker_output =
  Output {
    ..output_placeholder,
    address: Address(maker_payment_cred, None),
    value: order_subject
      |> merge(order_ada),
  }

const good_maker_buy_output =
  Output {
    ..good_maker_output,
    value: from_lovelace(
      order_asset_amount * order_price_per_unit + contract_order_min_ada_amount,
    ),
  }

// RUN  aiken check -S -m tests/order_cancel

// TODO: add output index check
// TODO: cancel order when market is closed (operator only)

// Test suite for the order canceling action
//  - An order before the timeout expires can be closed either by the contract operator or the order owner
//      - The order can be closed at any moment on demand
//  - An order past the timeout can be closed without authorization

// There are no attack vectors with serious impact, but authorization must be enforced carefully

// A correct order canceling transaction must contain:
//   Reference inputs[1]:
//     - Reference to the contract valid `config eUTxO`
//   Inputs[>=1]:
//      - Exactly one input from the contract address containing the order eUTxO (`contract_policy_id.contract_order_marker` + OrderDatum)
//      - Any number of user inputs if needed (not validated)
//   Outputs[>=1]:
//      - the output to the address associated with the `order_maker_keyhash` keyhash in the order datum that holds the funds locked in the order
//        - index 0
//      - any number of outputs to other addresses if needed (not validated)
//   Minting:
//     - exactly -1 `contract_policy_id.contract_order_marker`
//   Validity range[optional]:
//     - may be omitted if cancellation is performed by an authorized party
//     - For unauthorized closure, if `timeout` in the datum points to some date, the lower bound must be after that date
//   Additional signers:    
//     a) a signature corresponding to the `order_maker_keyhash` field in the spent utxo datum
//     b) OR a signature corresponding to the `contract_operator_keyhash` field in the config utxo datum
//     c) OR nothing if timeout passed
// Validatiors: Minting + Spending

fn try(tx: Transaction, utxo: Input) -> Bool {
  let contract_datum =
    when utxo.output.datum is {
      InlineDatum(datum) -> Some(datum)
      _ -> None
    }

  and {
    nse_housing.exchange.mint(OrderCanceling, contract_policy_id, tx),
    nse_housing.exchange.spend(
      contract_datum,
      OrderCanceling,
      utxo.output_reference,
      tx,
    ),
  }
}

// Success cases

test success_order_canceling_authorized_owner() {
  // Successful attempt to cancel the order by its owner

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [sell_order_input, input_placeholder],
      outputs: [good_maker_output, output_placeholder],
      mint: negate(order_marker),
      extra_signatories: [maker_payment_keyhash],
    },
    sell_order_input,
  )
}

test success_order_canceling_authorized_operator() {
  // Successful attempt to cancel the order by the contract operator

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [sell_order_input, input_placeholder],
      outputs: [good_maker_output, output_placeholder],
      mint: negate(order_marker),
      extra_signatories: [operator_payment_keyhash],
    },
    sell_order_input,
  )
}

test success_order_canceling_authorized_operator_stopped_market() {
  // Successful attempt to cancel the order by the contract operator

  let config_ref =
    Input {
      ..good_config_reference_input,
      output: Output {
        ..good_config_reference_input.output,
        datum: InlineDatum(ConfigDatum { ..conf_datum, is_market_open: False }),
      },
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [config_ref],
      inputs: [sell_order_input, input_placeholder],
      outputs: [good_maker_output, output_placeholder],
      mint: negate(order_marker),
      extra_signatories: [operator_payment_keyhash],
    },
    sell_order_input,
  )
}

test success_order_canceling_unauthorized() {
  // Successful attempt to cancel the order without authorization (after timeout)

  let sell_order_input =
    Input {
      ..sell_order_input,
      output: Output {
        ..sell_order_input.output,
        datum: InlineDatum(good_sell_order_datum_with_timeout),
      },
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [sell_order_input, input_placeholder],
      outputs: [good_maker_output, output_placeholder],
      mint: negate(order_marker),
      validity_range: entirely_after(timeout),
    },
    sell_order_input,
  )
}

test fail_order_canceling_unauthorized_unlimited_order() fail {
  // fail attempt to cancel the order without authorization (no timeout)

  let sell_order_input =
    Input {
      ..sell_order_input,
      output: Output {
        ..sell_order_input.output,
        datum: InlineDatum(
          OrderDatum {
            ..good_sell_order_datum_with_timeout,
            order_timeout_date: 0,
          },
        ),
      },
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [sell_order_input, input_placeholder],
      outputs: [good_maker_output, output_placeholder],
      mint: negate(order_marker),
      validity_range: entirely_after(timeout),
    },
    sell_order_input,
  )
}

// Failed cases

test fail_no_config_reference() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[1]:
  //     - Reference to the contract valid `config eUTxO`

  // The user forgot to include the config reference
  try(
    Transaction {
      ..tx_placeholder,
      inputs: [sell_order_input, input_placeholder],
      outputs: [good_maker_output, output_placeholder],
      mint: negate(order_marker),
      extra_signatories: [maker_payment_keyhash],
    },
    sell_order_input,
  )
}

test fail_bad_config_reference_utxo() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[1]:
  //     - Reference to the contract valid `config eUTxO`

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
      reference_inputs: [bad_config_reference_input],
      inputs: [sell_order_input, input_placeholder],
      outputs: [good_maker_output, output_placeholder],
      mint: negate(order_marker),
      extra_signatories: [maker_payment_keyhash],
    },
    sell_order_input,
  )
}

test fail_bad_config_reference_address() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[1]:
  //     - Reference to the contract valid `config eUTxO`

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
      reference_inputs: [bad_config_reference_input],
      inputs: [sell_order_input, input_placeholder],
      outputs: [good_maker_output, output_placeholder],
      mint: negate(order_marker),
      extra_signatories: [maker_payment_keyhash],
    },
    sell_order_input,
  )
}

test fail_many_orders_at_once() fail {
  // Incorrect action violating the rule:
  //   Inputs[>=1]:
  //      - Exactly one input from the contract address containing the order eUTxO (`contract_policy_id.contract_order_marker` + OrderDatum)

  // Attempt to close several orders at once
  // Technically feasible, but it would complicate the contract where simplicity is preferable
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [sell_order_input, sell_order_input, input_placeholder],
      outputs: [good_maker_output, good_maker_output, output_placeholder],
      mint: negate(order_marker)
        |> merge(negate(order_marker)),
      extra_signatories: [maker_payment_keyhash],
    },
    sell_order_input,
  )
}

test fail_bad_order_utxo() fail {
  // Incorrect action violating the rule:
  //   Inputs[>=1]:
  //      - Exactly one input from the contract address containing the order eUTxO (`contract_policy_id.contract_order_marker` + OrderDatum)

  // Attempt to withdraw an incorrect eUTxO, for example a configuration one
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [good_config_reference_input, input_placeholder],
      outputs: [good_maker_output, output_placeholder],
      mint: negate(config_marker),
      extra_signatories: [maker_payment_keyhash],
    },
    good_config_reference_input,
  )
}

test fail_bad_user_output_address() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //      - Exactly one output to the address associated with the `order_maker_keyhash` keyhash in the order datum

  // User specified an output address that is not linked to the keyhash in the order datum

  let bad_maker_output = Output { ..good_maker_output, address: taker_address }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [sell_order_input, input_placeholder],
      outputs: [bad_maker_output, output_placeholder],
      mint: negate(order_marker),
      extra_signatories: [maker_payment_keyhash],
    },
    sell_order_input,
  )
}

test fail_bad_user_output_value() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //      - First one -  the output to the address associated with the `order_maker_keyhash` keyhash in the order datum that holds the funds locked in the order

  // User/operator transferred less than the remaining assets from the order to the first transaction output

  let bad_maker_output =
    Output {
      ..good_maker_output,
      value: from_asset(
        approved_policy_id,
        approved_asset_name,
        order_asset_amount - 1,
      )
        |> merge(order_ada)
        |> merge(from_lovelace(-fee)),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [sell_order_input, input_placeholder],
      outputs: [bad_maker_output, output_placeholder],
      mint: negate(order_marker),
      extra_signatories: [maker_payment_keyhash],
    },
    sell_order_input,
  )
}

test fail_bad_user_sell_output_coin() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //      - First one -  the output to the address associated with the `order_maker_keyhash` keyhash in the order datum that holds the funds locked in the order

  // User/operator transferred less than the remaining ada from the order to the first transaction output
  // We need to guarantee this cannot happen accidentally or intentionally
  // Especially since an expired order can be removed without authorization
  let drain = 1

  let bad_maker_output =
    Output {
      ..good_maker_output,
      value: order_subject
        |> merge(order_ada)
        |> merge(from_lovelace(-fee))
        |> merge(from_lovelace(-drain)),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [sell_order_input, input_placeholder],
      outputs: [bad_maker_output, output_placeholder],
      mint: negate(order_marker),
      extra_signatories: [maker_payment_keyhash],
    },
    sell_order_input,
  )
}

test fail_bad_user_buy_output_coin() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=1]:
  //      - First one -  the output to the address associated with the `order_maker_keyhash` keyhash in the order datum that holds the funds locked in the order

  // User/operator transferred less than the remaining ada from the order to the first transaction output
  // We need to guarantee this cannot happen accidentally or intentionally
  // Especially since an expired order can be removed without authorization

  let bad_maker_output =
    Output { ..good_maker_buy_output, value: from_lovelace(1) }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [sell_order_input, input_placeholder],
      outputs: [bad_maker_output, output_placeholder],
      mint: negate(order_marker),
      extra_signatories: [maker_payment_keyhash],
    },
    sell_order_input,
  )
}

test fail_no_order_marker_burning() fail {
  // Incorrect action violating the rule:
  //   Minting:
  //     - exactly -1 `contract_policy_id.contract_order_marker`

  // User forgot to burn the order marker when closing
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [sell_order_input, input_placeholder],
      outputs: [good_maker_output, output_placeholder],
      extra_signatories: [maker_payment_keyhash],
    },
    sell_order_input,
  )
}

test fail_positive_minting() fail {
  // Incorrect action violating the rule:
  //   Minting:
  //     - exactly -1 `contract_policy_id.contract_order_marker`

  // User attempts to mint some asset on behalf of the contract
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [sell_order_input, input_placeholder],
      outputs: [good_maker_output, output_placeholder],
      mint: from_asset(contract_policy_id, "not allowed asset", 1),
      extra_signatories: [maker_payment_keyhash],
    },
    sell_order_input,
  )
}

test fail_config_burning() fail {
  // Incorrect action violating the rule:
  //   Minting:
  //     - exactly -1 `contract_policy_id.contract_order_marker`

  // User attempts to burn the config
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [sell_order_input, good_config_reference_input, input_placeholder],
      outputs: [good_maker_output, output_placeholder],
      mint: from_asset(contract_policy_id, contract_config_marker, -1),
      extra_signatories: [maker_payment_keyhash],
    },
    sell_order_input,
  )
}

test fail_unauthorized_canceling_before_timeout() fail {
  // Incorrect action violating the rule:
  //   Validity range[optional]:
  //     - For unauthorized closure, if `timeout` in the datum points to some date, the lower bound must be after that date

  // Attempt to cancel an order without authorization before the timeout expires
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [sell_order_input, input_placeholder],
      outputs: [good_maker_output, output_placeholder],
      mint: negate(order_marker),
      validity_range: entirely_before(timeout),
    },
    sell_order_input,
  )
}

test fail_incorrect_extra_signature() fail {
  // Incorrect action violating the rule:
  //   Additional signers:    
  //     a) a signature corresponding to the `order_maker_keyhash` field in the spent utxo datum
  //     b) OR a signature corresponding to the `contract_operator_keyhash` field in the config utxo datum

  // Attempt to use a signature that does not belong to the owner or operator
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [sell_order_input, input_placeholder],
      outputs: [good_maker_output, output_placeholder],
      mint: negate(order_marker),
      extra_signatories: [taker_payment_keyhash],
    },
    sell_order_input,
  )
}
