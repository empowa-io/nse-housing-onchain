use aiken/interval.{entirely_before}
use cardano/assets.{from_asset, from_lovelace, merge, negate, zero}
use cardano/transaction.{
  InlineDatum, Input, NoDatum, Output, Transaction,
  placeholder as tx_placeholder,
}
use config.{contract_config_marker, contract_listing_marker}
use default.{
  base_platform_fee_decimal_part, base_platform_fee_min_amount,
  base_platform_fee_percent, config_marker, contract_address,
  contract_order_min_ada_amount, contract_policy_id, input_placeholder,
  listing_marker, listing_operator_payment_keyhash, maker_address,
  operator_payment_keyhash, order_marker, output_placeholder, platform_address,
  taker_address,
}
use helpers.{calc_fee}
use nse_housing
use types.{Buy, ConfigDatum, ListingDatum, OrderDatum, OrderExecution, Sell}

const approved_policy_id = "approved policy"

const approved_asset_name = "approved asset name"

const order_asset_amount = 42

const order_price_per_unit = 1_000_000_000

const deal_amount_asset = 10

const timeout = 10

const fee_calc =
  calc_fee(base_platform_fee_percent, base_platform_fee_decimal_part, _)

const platform_fee_full_exec_amount =
  from_lovelace(fee_calc(order_asset_amount * order_price_per_unit))

const platform_fee_partial_exec_amount =
  from_lovelace(fee_calc(deal_amount_asset * order_price_per_unit))

const good_order_min_ada = from_lovelace(contract_order_min_ada_amount)

const good_order_full_asset_value =
  from_asset(approved_policy_id, approved_asset_name, order_asset_amount)

const good_order_full_ada_value =
  from_lovelace(
    order_asset_amount * order_price_per_unit + contract_order_min_ada_amount,
  )

const good_order_partial_sell_asset_value =
  from_asset(
    approved_policy_id,
    approved_asset_name,
    order_asset_amount - deal_amount_asset,
  )

const good_order_partial_buy_ada_value =
  from_lovelace(
    ( order_asset_amount - deal_amount_asset ) * order_price_per_unit + contract_order_min_ada_amount,
  )

const good_deal_ada_value_partial_exec =
  from_lovelace(deal_amount_asset * order_price_per_unit)

const good_deal_asset_value_partial_exec =
  from_asset(approved_policy_id, approved_asset_name, deal_amount_asset)

const good_conf_datum =
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

const good_sell_order_datum_before =
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

const good_sell_order_datum_after =
  OrderDatum {
    order_type: Sell,
    traded_asset_policy_id: approved_policy_id,
    traded_asset_name: approved_asset_name,
    traded_asset_amount: order_asset_amount - deal_amount_asset,
    traded_asset_price: order_price_per_unit,
    partial_fulfillment_allowed: True,
    order_timeout_date: timeout,
    order_maker_address: maker_address,
  }

const good_buy_order_datum_before =
  OrderDatum {
    order_type: Buy,
    traded_asset_policy_id: approved_policy_id,
    traded_asset_name: approved_asset_name,
    traded_asset_amount: order_asset_amount,
    traded_asset_price: order_price_per_unit,
    partial_fulfillment_allowed: True,
    order_timeout_date: 0,
    order_maker_address: maker_address,
  }

const good_buy_order_datum_after =
  OrderDatum {
    order_type: Buy,
    traded_asset_policy_id: approved_policy_id,
    traded_asset_name: approved_asset_name,
    traded_asset_amount: order_asset_amount - deal_amount_asset,
    traded_asset_price: order_price_per_unit,
    partial_fulfillment_allowed: True,
    order_timeout_date: 0,
    order_maker_address: maker_address,
  }

const good_platform_fee_output_full_exec =
  Output {
    ..output_placeholder,
    address: platform_address,
    value: platform_fee_full_exec_amount,
  }

const good_platform_fee_output_partiall_exec =
  Output {
    ..output_placeholder,
    address: platform_address,
    value: platform_fee_partial_exec_amount,
  }

const good_sell_order_input =
  Input {
    ..input_placeholder,
    output: Output {
      ..output_placeholder,
      address: contract_address,
      datum: InlineDatum(good_sell_order_datum_before),
      value: good_order_full_asset_value,
    },
  }

const good_sell_maker_output_full_exec =
  Output {
    ..output_placeholder,
    address: maker_address,
    value: good_order_full_ada_value,
  }

const good_sell_taker_output_full_exec =
  Output {
    ..output_placeholder,
    address: taker_address,
    value: good_order_full_asset_value,
  }

const good_sell_order_output_partial_exec =
  Output {
    ..output_placeholder,
    address: contract_address,
    datum: InlineDatum(good_sell_order_datum_after),
    value: order_marker
      |> merge(good_order_partial_sell_asset_value)
      |> merge(good_order_min_ada),
  }

const good_sell_maker_output_partial_exec =
  Output {
    ..output_placeholder,
    address: maker_address,
    value: good_deal_ada_value_partial_exec,
  }

const good_sell_taker_output_partial_exec =
  Output {
    ..output_placeholder,
    address: taker_address,
    value: good_deal_asset_value_partial_exec,
  }

const good_buy_order_input =
  Input {
    ..input_placeholder,
    output: Output {
      ..output_placeholder,
      address: contract_address,
      datum: InlineDatum(good_buy_order_datum_before),
      value: good_order_full_ada_value,
    },
  }

const good_buy_maker_output_full_exec =
  Output {
    ..output_placeholder,
    address: maker_address,
    value: good_order_full_asset_value
      |> merge(good_order_min_ada),
  }

const good_buy_taker_output_full_exec =
  Output {
    ..output_placeholder,
    address: taker_address,
    value: good_order_full_ada_value
      |> merge(negate(platform_fee_full_exec_amount))
      |> merge(negate(from_lovelace(contract_order_min_ada_amount))),
  }

const good_buy_order_output_partial_exec =
  Output {
    ..output_placeholder,
    address: contract_address,
    datum: InlineDatum(good_buy_order_datum_after),
    value: order_marker
      |> merge(good_order_partial_buy_ada_value),
  }

const good_buy_maker_output_partial_exec =
  Output {
    ..output_placeholder,
    address: maker_address,
    value: good_deal_asset_value_partial_exec
      |> merge(from_lovelace(1)),
  }

const good_buy_taker_output_partial_exec =
  Output {
    ..output_placeholder,
    address: taker_address,
    value: good_deal_ada_value_partial_exec
      |> merge(negate(platform_fee_partial_exec_amount)),
  }

type BadDatum {
  val: Int,
}

// Test suite for the order exetution action
//  - An order can be accepted by any Cardano user; authorization is not required
//  - The only sufficient condition is meeting the order terms on price and asset\ada amount
//  - It is important to remember that the order may have a partial redemption option
//  - Technically, partial execution is an action almost identical to reconfiguration, except the config updates only partially and as a result of payment
//  - Full execution/completion is an action similar to closure.

// The main attack vector is an attempt to trick the contract to obtain the order contents without the corresponding costs
// User errors can also occur, but their nature is such that they cannot be distinguished from an attack

// A correct order execution transaction must contain:
//   Reference inputs[2]:
//     - Reference to the contract valid `config eUTxO`
//     - Reference to the `listing eUTxO` allowing interaction with the asset being listed in the order
//   Inputs[>=1]:
//      - Exactly one input from the `contract_address` containing the order eUTxO (`contract_policy_id.contract_order_marker` + OrderDatum)
//      - Any number of user inputs if needed (not validated)
//   Outputs[>=3]:
//     - exactly one output to the `maker_address` containing:
//       - index 0
//       - the amount of assets/ada paid by the taker depending on the contract type (Buy/Sell)
//       - [optional] the order's `contract_order_min_ada` if the order was closed
//     - output to the `taker_address` containing:
//       - index 1
//       - the amount of assets/ada paid to the taker depending on the contract type (Buy/Sell)
//     -exactly one output to the platform address containing:
//       - platform fee equals (base_platform_fee_percent/10^base_platform_fee_decimal_part)% payed by the taker
//          - but not less than `platform_fee_min_amount` value, e.g. because we have to respect Cardano's min ada...
//       - index 2
//     - [optional] exactly one output to the `contract_address` containing:
//       - index 3
//       - 1 token `contract_policy_id.contract_order_marker`
//       - a datum of type `OrderDatum` (correctly describing the current state of the order)
//       - the required amount of locked assets depending on the order type (Buy/Sell)
//       - `contract_order_min_ada` ADA (returned to the owner after the order is closed/executed)
//       - for PARTIAL payments only
//    - any number of outputs to other addresses if needed (not validated)
//   Minting:
//     - positive minting is forbidden in any case
//     - if the order was not fully executed, burning is forbidden
//     - if the order was closed entirely, the token `contract_policy_id.contract_order_marker` must be burned
//   Validity range:
//     - Invalid after the timeout specified in the input datum
//        - Not required if timeout equals 0, but it still does no harm

//   Partial execution of an order is available only if this is explicitly specified in the order settings!

// The order datum will change during partial redemption, but in a limited way:
//  - only the quantity of the asset being sold/purchased, only by the amount sent to the taker
//  - Changing the remaining fields is strictly forbidden

// Validatiors: Spending [+ Minting]
// This operation includes some combinatorics of variants, so the tests are split not only into successful and unsuccessful but also grouped by subtypes

// Success cases

fn try(tx: Transaction, utxo: Input) {
  let contract_datum =
    when utxo.output.datum is {
      InlineDatum(datum) -> Some(datum)
      _ -> None
    }
  let spending_validation =
    nse_housing.exchange.spend(
      contract_datum,
      OrderExecution,
      utxo.output_reference,
      tx,
    )

  if tx.mint == zero {
    spending_validation
  } else {
    and {
      spending_validation?,
      nse_housing.exchange.mint(OrderExecution, contract_policy_id, tx)?,
    }
  }
}

test success_sell_full_execution() {
  // Successful attempt at full execution of an order to sell assets
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_full_exec, good_sell_taker_output_full_exec,
        good_platform_fee_output_full_exec, output_placeholder,
      ],
      mint: negate(order_marker),
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test success_sell_partial_execution() {
  // Successful attempt at partial execution of an order to sell assets
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        good_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test success_buy_full_execution() {
  // Successful attempt at full execution of an order to buy assets
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_buy_order_input, input_placeholder],
      outputs: [
        good_buy_maker_output_full_exec, good_buy_taker_output_full_exec,
        good_platform_fee_output_full_exec, output_placeholder,
      ],
      mint: negate(order_marker),
      validity_range: entirely_before(timeout),
    },
    good_buy_order_input,
  )
}

test success_buy_partial_execution() {
  // Successful attempt at partial execution of an order to buy assets
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_buy_order_input, input_placeholder],
      outputs: [
        good_buy_maker_output_partial_exec, good_buy_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        good_buy_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_buy_order_input,
  )
}

// Failed common cases (doesn't matter buy or sell, full or partial)
test fail_garbage_at_order_output() fail {
  // The contract output containing the order must not contain foreign assets
  let bad_sell_order_output_partial_exec =
    Output {
      ..good_sell_order_output_partial_exec,
      value: good_sell_order_output_partial_exec.value
        |> merge(from_asset("unknown policy", "unknown asset name", 1)),
    }
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        bad_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_garbage_at_maker_output() fail {
  // The maker output receiving payment must not contain foreign assets
  let bad_sell_maker_output_partial_exec =
    Output {
      ..good_sell_maker_output_partial_exec,
      value: good_sell_maker_output_partial_exec.value
        |> merge(from_asset("unknown policy", "unknown asset name", 1)),
    }
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        bad_sell_maker_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        good_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_missed_platform_fee() fail {
  // Incorrect action violating the rule:
  //     -exactly one output to the platform address containing:
  //       - platform fee equals (base_platform_fee_percent/10^base_platform_fee_decimal_part)% payed by the taker
  //          - but not less than `platform_fee_min_amount` value, e.g. because we have to respect Cardano's min ada...
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_partial_exec, good_sell_taker_output_partial_exec,
        good_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_missed_config_utxo_ref() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[2]:
  //     - Reference to the contract valid `config eUTxO`

  // The user forgot to attach the config to the transaction
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_listing_reference_input_wildcard],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_full_exec, good_sell_taker_output_full_exec,
        good_platform_fee_output_full_exec, output_placeholder,
      ],
      mint: negate(order_marker),
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_missed_listing_utxo_ref() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[2]:
  //     - Reference to the `listing eUTxO` allowing interaction with the asset being listed in the order

  // The user forgot to attach the utxo with the listing to the transaction
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [good_config_reference_input],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_full_exec, good_sell_taker_output_full_exec,
        good_platform_fee_output_full_exec, output_placeholder,
      ],
      mint: negate(order_marker),
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_no_ref_utxos() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[2]:

  // The user did not attach the reference utxos
  try(
    Transaction {
      ..tx_placeholder,
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_full_exec, good_sell_taker_output_full_exec,
        good_platform_fee_output_full_exec, output_placeholder,
      ],
      mint: negate(order_marker),
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_bad_config_ref_address() fail {
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
        bad_config_reference_input, good_listing_reference_input_wildcard,
        input_placeholder,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_full_exec, good_sell_taker_output_full_exec,
        good_platform_fee_output_full_exec, output_placeholder,
      ],
      mint: negate(order_marker),
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_bad_listing_ref() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[2]:
  //     - Reference to the `listing eUTxO` allowing interaction with the asset being listed in the order

  let bad_listing_reference_input =
    Input {
      ..good_listing_reference_input_no_wildcard,
      output: Output {
        ..good_listing_reference_input_no_wildcard.output,
        value: from_asset("bad policy_id", contract_listing_marker, 1),
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
        input_placeholder,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_full_exec, good_sell_taker_output_full_exec,
        good_platform_fee_output_full_exec, output_placeholder,
      ],
      mint: negate(order_marker),
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_incorrect_listing_ref() fail {
  // Incorrect action violating the rule:
  //   Reference inputs[2]:
  //     - Reference to the `listing eUTxO` allowing interaction with the asset being listed in the order
  // The listing is valid, but it does not correspond to the asset in the order.

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
        input_placeholder,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_full_exec, good_sell_taker_output_full_exec,
        good_platform_fee_output_full_exec, output_placeholder,
      ],
      mint: negate(order_marker),
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_many_order_inputs() fail {
  // Incorrect action violating the rule:
  //   Inputs[>=1]:
  //      - Exactly one input from the `contract_address` containing the order eUTxO (`contract_policy_id.contract_order_marker` + OrderDatum)

  // The user tries to process several orders at once in one transaction
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, good_buy_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_full_exec, good_sell_taker_output_full_exec,
        good_platform_fee_output_full_exec, output_placeholder,
      ],
      mint: negate(order_marker),
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_no_marker_burning_after_full_exec() fail {
  // Incorrect action violating the rule:
  //   Minting:
  //     - if the order was closed entirely, the token `contract_policy_id.contract_order_marker` must be burned

  // The user forgot to burn the order marker when fully redeeming it, which means the marker will leave the contract address
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_full_exec, good_sell_taker_output_full_exec,
        good_platform_fee_output_full_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_marker_burning_after_partial_exec() fail {
  // Incorrect action violating the rule:
  //   Minting:
  //     - if the order was not fully executed, burning is forbidden

  // The user tried to burn the order marker during its partial redemption, making the order invalid
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        good_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
      mint: negate(order_marker),
    },
    good_sell_order_input,
  )
}

test fail_extra_assets_minted() fail {
  // Incorrect action violating the rule:
  //   Minting:
  //     - positive minting is forbidden in any case

  // The user tried to mint an additional `order_marker` or any token on behalf of the contract
  // There is no point in checking which token is being minted because any positive minting is forbidden
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_full_exec, good_sell_taker_output_full_exec,
        good_platform_fee_output_full_exec, output_placeholder,
      ],
      mint: order_marker,
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_not_only_marker_was_burned() fail {
  // Incorrect action violating the rule:
  //   Minting:
  //     - if the order was not fully executed, burning is forbidden
  //     - if the order was closed entirely, the token `contract_policy_id.contract_order_marker` must be burned

  // Attempt to burn any other token besides the spent order, for example, the config
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_full_exec, good_sell_taker_output_full_exec,
        good_platform_fee_output_full_exec, output_placeholder,
      ],
      mint: negate(order_marker)
        |> merge(negate(config_marker)),
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_no_validity_range() fail {
  // Incorrect action violating the rule:
  //   Validity range:
  //     - Invalid after the timeout specified in the input datum
  //        - Not required if timeout equals 0, but it still does no harm

  // The user forgot to specify `validity_range`
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_full_exec, good_sell_taker_output_full_exec,
        good_platform_fee_output_full_exec, output_placeholder,
      ],
      mint: negate(order_marker),
    },
    good_sell_order_input,
  )
}

test fail_bad_outputs_count() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:

  // The number of outputs is less than two, which is already an error because there must be two sides - buyer and seller
  // For example, the buyer decided to take both the assets and the payment for them...
  // The test uses a correct buyer output, but there is no point in creating an incorrect one if only the count is validated here
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        output_placeholder, good_sell_taker_output_full_exec,
        good_platform_fee_output_full_exec,
      ],
      mint: negate(order_marker),
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_partial_execution_when_full_only_allowed() fail {
  // Incorrect action violating the rule:
  //  - Partial execution of an order is available only if this is explicitly specified in the order settings!

  // Attempt at partial execution of an order for which this action is prohibited
  // It does not matter whether it is a buy or sell; what matters is violating a setting common to both cases
  let good_sell_order_datum_before_full_only =
    OrderDatum {
      ..good_sell_order_datum_before,
      partial_fulfillment_allowed: False,
    }

  let good_sell_order_input_full_only =
    Input {
      ..good_sell_order_input,
      output: Output {
        ..good_sell_order_input.output,
        datum: InlineDatum(good_sell_order_datum_before_full_only),
      },
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input_full_only, input_placeholder],
      outputs: [
        good_sell_maker_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        good_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_order_reconfiguration_attempt_change_owner() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - [optional] exactly one output to the `contract_address` containing:
  //       - a datum of type `OrderDatum` (correctly describing the current state of the order)

  // An attacker may try to override the order Datum to make its terms more favorable to themselves
  // In this case - change of the owner

  let bad_sell_order_output_partial_exec =
    Output {
      ..good_sell_order_output_partial_exec,
      datum: InlineDatum(
        OrderDatum {
          ..good_sell_order_datum_after,
          order_maker_address: taker_address,
        },
      ),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        bad_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_order_reconfiguration_attempt_change_price() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - [optional] exactly one output to the `contract_address` containing:
  //       - a datum of type `OrderDatum` (correctly describing the current state of the order)

  // An attacker may try to override the order Datum to make its terms more favorable to themselves
  // In this case - change of the price

  let bad_sell_order_output_partial_exec =
    Output {
      ..good_sell_order_output_partial_exec,
      datum: InlineDatum(
        OrderDatum {
          ..good_sell_order_datum_after,
          traded_asset_price: order_price_per_unit - 1,
        },
      ),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        bad_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_order_reconfiguration_attempt_change_asset_amount() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - [optional] exactly one output to the `contract_address` containing:
  //       - a datum of type `OrderDatum` (correctly describing the current state of the order)

  // An attacker may try to override the order Datum to make its terms more favorable to themselves
  // In this case - change of the order volume to take the "extra" for themselves
  // It is important to note that this particular change is usually legitimate if it matches the trade size

  let bad_sell_order_output_partial_exec =
    Output {
      ..good_sell_order_output_partial_exec,
      datum: InlineDatum(
        OrderDatum {
          ..good_sell_order_datum_after,
          traded_asset_amount: order_asset_amount - deal_amount_asset - 1,
        },
      ),
    }
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        bad_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_order_reconfiguration_attempt_change_policy_id() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - [optional] exactly one output to the `contract_address` containing:
  //       - a datum of type `OrderDatum` (correctly describing the current state of the order)

  // An attacker may try to override the order Datum to make its terms more favorable to themselves
  // In this case - change of the `policy_id` in order to substitute the asset with a fake one

  let bad_sell_order_output_partial_exec =
    Output {
      ..good_sell_order_output_partial_exec,
      datum: InlineDatum(
        OrderDatum {
          ..good_sell_order_datum_after,
          traded_asset_policy_id: "bad policy_id",
        },
      ),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        bad_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_order_reconfiguration_attempt_change_asset_name() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - [optional] exactly one output to the `contract_address` containing:
  //       - a datum of type `OrderDatum` (correctly describing the current state of the order)

  // An attacker may try to override the order Datum to make its terms more favorable to themselves
  // In this case - change of the asset name

  let bad_sell_order_output_partial_exec =
    Output {
      ..good_sell_order_output_partial_exec,
      datum: InlineDatum(
        OrderDatum {
          ..good_sell_order_datum_after,
          traded_asset_name: "Bad asset name",
        },
      ),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        bad_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_order_reconfiguration_attempt_change_order_type() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - [optional] exactly one output to the `contract_address` containing:
  //       - a datum of type `OrderDatum` (correctly describing the current state of the order)

  // An attacker may try to override the order Datum to make its terms more favorable to themselves
  // In this case - change of the order type

  let bad_sell_order_output_partial_exec =
    Output {
      ..good_sell_order_output_partial_exec,
      datum: InlineDatum(
        OrderDatum { ..good_sell_order_datum_after, order_type: Buy },
      ),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        bad_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_order_reconfiguration_attempt_change_partial_execution_mode() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - [optional] exactly one output to the `contract_address` containing:
  //       - a datum of type `OrderDatum` (correctly describing the current state of the order)

  // An attacker may try to override the order Datum to make its terms more favorable to themselves
  // In this case - change of `partial_fulfillment_allowed`

  let bad_sell_order_output_partial_exec =
    Output {
      ..good_sell_order_output_partial_exec,
      datum: InlineDatum(
        OrderDatum {
          ..good_sell_order_datum_after,
          partial_fulfillment_allowed: False,
        },
      ),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        bad_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_order_reconfiguration_attempt_change_timeout() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - [optional] exactly one output to the `contract_address` containing:
  //       - a datum of type `OrderDatum` (correctly describing the current state of the order)

  // An attacker may try to override the order Datum to make its terms more favorable to themselves
  // In this case - change of the timeout

  let bad_sell_order_output_partial_exec =
    Output {
      ..good_sell_order_output_partial_exec,
      datum: InlineDatum(
        OrderDatum {
          ..good_sell_order_datum_after,
          order_timeout_date: timeout + 1,
        },
      ),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        bad_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_bad_outputs_ordering_V1() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - exactly one output to the `maker_address` containing:
  //       - index 0
  //     - exactly one output to the `taker_address` containing:
  //       - index 1
  //     - [optional] exactly one output to the `contract_address` containing:
  //       - index 2

  // For some reason the outputs order was mixed up
  // In general, strict output ordering is not required, and the contract could include automatic search for the needed ones
  //  - But why complicate the logic where we can simply make the API stricter?
  //    - Especially since the contract does not work for free...

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_order_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        good_sell_maker_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_bad_outputs_ordering_V2() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - exactly one output to the `maker_address` containing:
  //       - index 0
  //     - exactly one output to the `taker_address` containing:
  //       - index 1
  //     - [optional] exactly one output to the `contract_address` containing:
  //       - index 2

  // For some reason the outputs order was mixed up
  // In general, strict output ordering is not required, and the contract could include automatic search for the needed ones
  //  - But why complicate the logic where we can simply make the API stricter?
  //    - Especially since the contract does not work for free...

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_order_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        good_sell_maker_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_bad_contract_output_stolen_marker() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - [optional] exactly one output to the `contract_address` containing:
  //       - 1 token `contract_policy_id.contract_order_marker`

  // The user directed the token `contract_policy_id.contract_order_marker` to the wrong output
  //  -It does not matter whether it is a buy or sell; validation checks the fact of the token being on the contract output
  let bad_sell_order_output_partial_exec =
    Output {
      ..good_sell_order_output_partial_exec,
      value: good_sell_order_output_partial_exec.value
        |> merge(negate(order_marker)),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        bad_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_bad_contract_output_no_datum() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - [optional] exactly one output to the `contract_address` containing:
  //       - a datum of type `OrderDatum` (correctly describing the current state of the order)

  // The user forgot to attach a datum to the updated order after partial execution
  //  -It does not matter whether it is a buy or sell; validation checks the presence of the datum on the contract output
  let bad_sell_order_output_partial_exec =
    Output { ..good_sell_order_output_partial_exec, datum: NoDatum }
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        bad_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_bad_contract_output_wrong_datum() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - [optional] exactly one output to the `contract_address` containing:
  //       - a datum of type `OrderDatum` (correctly describing the current state of the order)

  // The user attached an incorrect datum to the updated order after partial execution
  //  -It does not matter whether it is a buy or sell; validation checks the datum type on the contract output
  let bad_sell_order_output_partial_exec =
    Output {
      ..good_sell_order_output_partial_exec,
      datum: InlineDatum(BadDatum(42)),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        bad_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

// Failed trading operation
// A set of tests related to attempts to deceive the contract for profit across different order types
// Transactions here have a 100% correct structure but incorrect data on the outputs

test fail_sell_bad_maker_output_stolen_funds_partial_exec() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - exactly one output to the `maker_address` containing:
  //       - the amount of assets/ada paid by the taker depending on the contract type (Buy/Sell)
  //     - exactly one output to the `taker_address` containing:
  //       - the amount of assets/ada paid to the taker depending on the contract type (Buy/Sell)

  // The buyer tries to deceive the seller by sending them not the amount (ada) they were supposed to
  //  - by sending it to themselves
  let bad_sell_maker_output_partial_exec =
    Output {
      ..good_sell_maker_output_partial_exec,
      value: good_sell_maker_output_partial_exec.value
        |> merge(from_lovelace(-1)),
    }

  let bad_sell_taker_output_partial_exec =
    Output {
      ..good_sell_taker_output_partial_exec,
      value: good_sell_taker_output_partial_exec.value
        |> merge(from_lovelace(1)),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        bad_sell_maker_output_partial_exec, bad_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        good_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_sell_bad_maker_output_funds_sent_to_contract_partial_exec() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - exactly one output to the `maker_address` containing:
  //       - the amount of assets/ada paid by the taker depending on the contract type (Buy/Sell)
  //     - exactly one output to the `taker_address` containing:
  //       - the amount of assets/ada paid to the taker depending on the contract type (Buy/Sell)

  // The buyer tries to deceive the seller by sending them not the amount (ada) they were supposed to
  //  - by sending it to the contract (by mistake?)
  let bad_sell_maker_output_partial_exec =
    Output {
      ..good_sell_maker_output_partial_exec,
      value: good_sell_maker_output_partial_exec.value
        |> merge(from_lovelace(-1)),
    }

  let bad_sell_order_output_partial_exec =
    Output {
      ..good_sell_order_output_partial_exec,
      value: good_sell_order_output_partial_exec.value
        |> merge(from_lovelace(1)),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        bad_sell_maker_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        bad_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_sell_bad_maker_output_stolen_funds_full_exec() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - exactly one output to the `maker_address` containing:
  //       - the amount of assets/ada paid by the taker depending on the contract type (Buy/Sell)
  //     - exactly one output to the `taker_address` containing:
  //       - the amount of assets/ada paid to the taker depending on the contract type (Buy/Sell)

  // The buyer tries to deceive the seller by sending them not the amount (ada) they were supposed to
  //  - by sending it to themselves
  let bad_sell_maker_output_full_exec =
    Output {
      ..good_sell_maker_output_full_exec,
      value: good_sell_maker_output_full_exec.value
        |> merge(from_lovelace(-1)),
    }

  let bad_sell_taker_output_full_exec =
    Output {
      ..good_sell_taker_output_full_exec,
      value: good_sell_taker_output_full_exec.value
        |> merge(from_lovelace(1)),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        bad_sell_maker_output_full_exec, bad_sell_taker_output_full_exec,
        good_platform_fee_output_full_exec, output_placeholder,
      ],
      mint: negate(order_marker),
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_buy_bad_maker_output_stolen_funds_partial_exec() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - exactly one output to the `maker_address` containing:
  //       - the amount of assets/ada paid by the taker depending on the contract type (Buy/Sell)
  //     - exactly one output to the `taker_address` containing:
  //       - the amount of assets/ada paid to the taker depending on the contract type (Buy/Sell)

  // The buyer tries to deceive the seller by sending them not the amount (asset) they were supposed to
  //  - by sending it to themselves
  let deviation = from_asset(approved_policy_id, approved_asset_name, 1)
  let bad_buy_maker_output_partial_exec =
    Output {
      ..good_buy_maker_output_partial_exec,
      value: good_buy_maker_output_partial_exec.value
        |> merge(negate(deviation)),
    }

  let bad_buy_taker_output_partial_exec =
    Output {
      ..good_buy_taker_output_partial_exec,
      value: good_buy_taker_output_partial_exec.value
        |> merge(deviation),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_buy_order_input, input_placeholder],
      outputs: [
        bad_buy_maker_output_partial_exec, bad_buy_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        good_buy_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_buy_order_input,
  )
}

test fail_buy_bad_maker_output_funds_sent_to_contract_partial_exec() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - exactly one output to the `maker_address` containing:
  //       - the amount of assets/ada paid by the taker depending on the contract type (Buy/Sell)
  //     - exactly one output to the `taker_address` containing:
  //       - the amount of assets/ada paid to the taker depending on the contract type (Buy/Sell)

  // The buyer tries to deceive the seller by sending them not the amount (asset) they were supposed to
  //  - by sending it to the contract (by mistake?)
  let deviation = from_asset(approved_policy_id, approved_asset_name, 1)

  let bad_buy_maker_output_partial_exec =
    Output {
      ..good_buy_maker_output_partial_exec,
      value: good_buy_maker_output_partial_exec.value
        |> merge(negate(deviation)),
    }

  let bad_buy_order_output_partial_exec =
    Output {
      ..good_buy_order_output_partial_exec,
      value: good_buy_order_output_partial_exec.value
        |> merge(deviation),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_buy_order_input, input_placeholder],
      outputs: [
        bad_buy_maker_output_partial_exec, good_buy_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        bad_buy_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_buy_order_input,
  )
}

test fail_buy_bad_maker_output_stolen_funds_full_exec() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - exactly one output to the `maker_address` containing:
  //       - the amount of assets/ada paid by the taker depending on the contract type (Buy/Sell)
  //     - exactly one output to the `taker_address` containing:
  //       - the amount of assets/ada paid to the taker depending on the contract type (Buy/Sell)
  // The buyer tries to deceive the seller by sending them not the amount (ada) they were supposed to
  //  - by sending it to themselves
  let deviation = from_asset(approved_policy_id, approved_asset_name, 1)
  let bad_buy_maker_output_full_exec =
    Output {
      ..good_buy_maker_output_full_exec,
      value: good_buy_maker_output_full_exec.value
        |> merge(negate(deviation)),
    }

  let bad_buy_taker_output_full_exec =
    Output {
      ..good_buy_taker_output_full_exec,
      value: good_buy_taker_output_full_exec.value
        |> merge(deviation),
    }
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_buy_order_input, input_placeholder],
      outputs: [
        bad_buy_maker_output_full_exec, bad_buy_taker_output_full_exec,
        good_platform_fee_output_full_exec, output_placeholder,
      ],
      mint: negate(order_marker),
      validity_range: entirely_before(timeout),
    },
    good_buy_order_input,
  )
}

test fail_stolen_order_min_ada_partial_exec() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - [optional] exactly one output to the `contract_address` containing:
  //       - `contract_order_min_ada` ADA (returned to the owner after the order is closed/executed)

  // Attempt to reduce the ada amount on the order by the `min_order_ada` deposit
  // It does not matter, buy or sell
  let bad_sell_order_output_partial_exec =
    Output {
      ..good_sell_order_output_partial_exec,
      value: good_sell_order_output_partial_exec.value
        |> merge(negate(good_order_min_ada)),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        bad_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_stolen_order_min_ada_full_exec() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - [optional] exactly one output to the `contract_address` containing:
  //       - `contract_order_min_ada` ADA (returned to the owner after the order is closed/executed)

  // Attempt of the taker to appropriate `min_order_ada` after its closure
  // It does not matter, buy or sell
  let bad_sell_maker_output_full_exec =
    Output {
      ..good_sell_maker_output_full_exec,
      value: good_sell_maker_output_full_exec.value
        |> merge(negate(good_order_min_ada)),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        bad_sell_maker_output_full_exec, good_sell_taker_output_full_exec,
        good_platform_fee_output_full_exec, output_placeholder,
      ],
      mint: negate(order_marker),
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_sell_order_output_stolen_ada() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - [optional] exactly one output to the `contract_address` containing:
  //       - the required amount of locked assets depending on the order type (Buy/Sell)

  // Attempt of the taker to form an order with less ada than specified in its Datum to steal the rest
  // - Only during partial execution

  let bad_sell_order_output_partial_exec =
    Output {
      ..good_sell_order_output_partial_exec,
      value: good_sell_order_output_partial_exec.value
        |> merge(from_asset(approved_policy_id, approved_asset_name, -1)),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_partial_exec, good_sell_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        bad_sell_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_buy_order_output_stolen_assets() fail {
  // Incorrect action violating the rule:
  //   Outputs[>=2]:
  //     - [optional] exactly one output to the `contract_address` containing:
  //       - the required amount of locked assets depending on the order type (Buy/Sell)

  // Attempt of the taker to form an order with less ada than specified in its Datum to steal the rest
  // - Only during partial execution
  let bad_buy_order_output_partial_exec =
    Output {
      ..good_buy_order_output_partial_exec,
      value: good_buy_order_output_partial_exec.value
        |> merge(from_lovelace(-1)),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_buy_order_input, input_placeholder],
      outputs: [
        good_buy_maker_output_partial_exec, good_buy_taker_output_partial_exec,
        good_platform_fee_output_partiall_exec,
        bad_buy_order_output_partial_exec, output_placeholder,
      ],
      validity_range: entirely_before(timeout),
    },
    good_buy_order_input,
  )
}

test fail_market_closed() fail {
  // The market is closed by the Operator
  let config_ref_input =
    Input {
      ..good_config_reference_input,
      output: Output {
        ..good_config_reference_input.output,
        datum: InlineDatum(
          ConfigDatum { ..good_conf_datum, is_market_open: False },
        ),
      },
    }
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        config_ref_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_full_exec, good_sell_taker_output_full_exec,
        good_platform_fee_output_full_exec, output_placeholder,
      ],
      mint: negate(order_marker),
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_bad_platform_fee() fail {
  // User attempts to underpay the platform fee
  let bad_platform_fee_output =
    Output {
      ..good_platform_fee_output_full_exec,
      value: platform_fee_full_exec_amount
        |> merge(from_lovelace(-1)),
    }

  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_full_exec, good_sell_taker_output_full_exec,
        bad_platform_fee_output, output_placeholder,
      ],
      mint: negate(order_marker),
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}

test fail_zero_platform_fee() fail {
  // User did not include a platform fee output at all
  try(
    Transaction {
      ..tx_placeholder,
      reference_inputs: [
        good_config_reference_input, good_listing_reference_input_wildcard,
      ],
      inputs: [good_sell_order_input, input_placeholder],
      outputs: [
        good_sell_maker_output_full_exec, good_sell_taker_output_full_exec,
        output_placeholder,
      ],
      mint: negate(order_marker),
      validity_range: entirely_before(timeout),
    },
    good_sell_order_input,
  )
}
