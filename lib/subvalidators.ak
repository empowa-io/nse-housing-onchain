use aiken/collection/list
use aiken/interval.{Interval, is_entirely_before}
use aiken/math.{max, pow}
use cardano/address.{Address, Script}
use cardano/assets.{lovelace_of, policies, quantity_of, zero}
use cardano/transaction.{Input, Output, OutputReference, Transaction}
use config.{
  contract_bootstrap_utxo_hash, contract_bootstrap_utxo_index,
  contract_order_min_ada,
}
use helpers.{
  find_outputs_by_address, read_config_datum, read_listing_datum,
  read_order_datum, to_outputs, validate_asset_listing, validate_authorization,
  validate_marked_input, validate_marked_output, validate_markers_mint,
  validate_order_output,
}
use types.{
  Buy, ConfigDatum, ContractMode, Delisting, Listing, ListingDatum, Marker,
  OrderDatum, Sell,
}

/// Comprehensive validator for contract configuration changes
pub fn validate_config_update(tx: Transaction, config_marker: Marker) -> Bool {
  expect Transaction {
    inputs: tx_inputs,
    outputs: [contract_config_output, ..rest_outputs],
    mint: minted_value,
    ..
  } = tx
  // First extract policy_id from the marker
  let Marker(contract_policy_id, ..) = config_marker
  // Build the contract address
  let contract_address = Address(Script(contract_policy_id), None)
  // Get the operator keyhash specified in the new configuration UTXO
  let ConfigDatum { contract_operator_keyhash: new_operator_keyhash, .. } =
    contract_config_output |> read_config_datum()
  // Then extract UTXOs from inputs belonging to the contract, if any
  let contract_inputs_outs =
    tx_inputs |> to_outputs() |> find_outputs_by_address(contract_address)
  // Ensure the transaction has at most one output to the contract address
  expect [] = rest_outputs |> find_outputs_by_address(contract_address)
  // Determine config type: initial (bootstrap) or repeat, based on presence of a contract input
  let bootstrap_phase =
    when contract_inputs_outs is {
      [] -> True
      _ -> False
    }

  // Check whether the operator from the previous config approved this transaction
  let tx_approved_by_prev_operator =
    // If there were no contract inputs, assume no previous config exists and this is bootstrapping
    if bootstrap_phase {
      // In that case, just verify the transaction has at most one input and that input is the configured UTXO
      expect [bootstrap_input] = tx_inputs
      let expected_bootstrap_utxo_ref =
        OutputReference(
          contract_bootstrap_utxo_hash,
          contract_bootstrap_utxo_index,
        )
      // Since UTXOs are single-use, this operation is tamper-resistant and needs no additional signatures
      bootstrap_input.output_reference == expected_bootstrap_utxo_ref
    } else {
      // If a previous config is expected in the transaction inputs, try to read it
      // Also ensure there is exactly one contract-owned input
      expect [
        ConfigDatum { contract_operator_keyhash: prev_operator_keyhash, .. },
      ] = contract_inputs_outs |> list.map(read_config_datum)
      // Then check whether the transaction was signed by the key from that config
      tx |> validate_authorization(prev_operator_keyhash)
    }

  // Then check that marker minting for the configuration UTXO is correct
  let is_minting_fine =
    if bootstrap_phase {
      // In bootstrap, we must mint it
      validate_markers_mint(minted_value, config_marker, 1)
    } else {
      // In reconfiguration, any minting is forbidden
      minted_value == zero
    }

  // Perform overall validation of the marked output (marking correctness and output address)
  let is_config_output_ok =
    contract_config_output
      |> validate_marked_output(config_marker, strict_mode: True)

  // And require approval by the operator in the new config to ensure control isn't lost after the update
  let tx_approved_by_new_operator =
    tx |> validate_authorization(new_operator_keyhash)

  and {
    tx_approved_by_prev_operator?,
    tx_approved_by_new_operator?,
    is_config_output_ok?,
    is_minting_fine?,
  }
}

/// Comprehensive validator for contract listing updates
pub fn validate_listing_update(
  tx: Transaction,
  mode: ContractMode,
  config_marker: Marker,
  listing_marker: Marker,
) -> Bool {
  let Transaction {
    reference_inputs: tx_ref_inputs,
    inputs: tx_inputs,
    outputs: tx_outputs,
    mint: tx_mint,
    ..
  } = tx
  // Read policy_id from the marker and build the contract address
  let Marker(contract_policy_id, ..) = config_marker
  let contract_adress = Address(Script(contract_policy_id), None)

  // This sub-validator is comprehensive: it handles both listing and delisting
  // Here we extract outputs that likely contain listings and count markers to mint or burn
  let (listings, markers_count) =
    when mode is {
      Listing -> {
        let listings = tx_outputs |> find_outputs_by_address(contract_adress)
        (listings, list.length(listings))
      }

      Delisting -> {
        let listings =
          tx_inputs |> to_outputs() |> find_outputs_by_address(contract_adress)
        (listings, -list.length(listings))
      }
      _ -> fail
    }

  // Then read the referenced config
  expect [config_ref_input] = tx_ref_inputs
  let config_is_valid =
    validate_marked_input(config_ref_input, config_marker, True)
  // And extract the listing operator keyhash for further validation
  let ConfigDatum { listing_operator_keyhash, .. } =
    config_ref_input.output |> read_config_datum()

  // Walk the presumed listing outputs to ensure nothing extra is present
  let all_listings_are_valid =
    listings
      |> list.reduce(
          True,
          fn(result, listing_output) {
            // First try to read the datum from each
            let ListingDatum { listed_policy_id, listed_asset_name } =
              listing_output |> read_listing_datum()
            // then ensure policy_id and asset_name are set correctly, plus the general marked-output check
            and {
              result,
              (listed_policy_id != "")?,
              (listed_asset_name != Some(""))?,
              (listing_output
                |> validate_marked_output(listing_marker, strict_mode: True))?,
            }
          },
        )

  // Ensure the transaction has correct minting/burning (only markers in the required amount)
  let are_markers_ok =
    validate_markers_mint(tx_mint, listing_marker, markers_count)

  // And that the transaction is approved by the listing operator
  let is_action_authorized =
    tx |> validate_authorization(listing_operator_keyhash)

  and {
    all_listings_are_valid?,
    config_is_valid?,
    are_markers_ok?,
    is_action_authorized?,
  }
}

/// Comprehensive validator for deals
pub fn validate_deal(
  contract_utxo: Output,
  config: ConfigDatum,
  listing: ListingDatum,
  tx_validity_range: Interval,
  order_marker: Marker,
  tx_outputs: List<Output>,
) -> (Bool, Bool) {
  // First, extract the validated UTXO data
  let Output { address: contract_address, .. } = contract_utxo
  // Then the order parameters
  let OrderDatum {
    order_type: order_type_init,
    traded_asset_policy_id: traded_asset_policy_id_init,
    traded_asset_name: traded_asset_name_init,
    traded_asset_amount: traded_asset_amount_init,
    traded_asset_price: traded_asset_price_init,
    partial_fulfillment_allowed: partial_fulfillment_allowed_init,
    order_timeout_date: order_timeout_date_init,
    order_maker_address: order_maker_address_init,
  } = contract_utxo |> read_order_datum()
  let ConfigDatum {
    platform_fee_percent,
    platform_fee_decimal,
    platform_fee_min_amount,
    platform_fee_address,
    ..
  } = config

  // Then read the required transaction outputs (there may also be an optional contract output for partial fulfillment)
  expect [maker_output,
    taker_output, platform_fee_output, ..rest_outputs] = tx_outputs
  let Output { address: maker_address, .. } = maker_output

  // Also validate the maker address:
  let is_maker_address_correct = maker_address == order_maker_address_init
  // Validate if traded asset listed
  let is_traded_asset_listed =
    validate_asset_listing(
      traded_asset_policy_id_init,
      traded_asset_name_init,
      listing,
    )

  // And the fee address as well:
  let is_platform_address_correct =
    platform_fee_output.address == platform_fee_address
  // And that timeouts are respected
  let is_validity_range_ok = or {
      order_timeout_date_init == 0,
      tx_validity_range |> is_entirely_before(order_timeout_date_init),
    }
  // Precompute the fee percentage
  let base_fee = platform_fee_percent / pow(10, platform_fee_decimal)
  // Then check that the deal outputs are correct and compute the deal size
  let (is_deal_fair, deal_amount) =
    when order_type_init is {
      Buy -> {
        let maker_income =
          maker_output.value
            |> quantity_of(traded_asset_policy_id_init, traded_asset_name_init)
        let maker_lovelace_income = maker_output.value |> lovelace_of()
        let taker_income = taker_output.value |> lovelace_of()
        let platform_fee = platform_fee_output.value |> lovelace_of()
        // For a buy, the maker receives tokens, while the taker and platform receive ada
        // Our goal is to ensure everything is fair
        let is_deal_fair = and {
            // The buyer always receives not only tokens but also some ada, so comparison is >=
            (maker_lovelace_income >= if maker_income == traded_asset_amount_init {
              // If the order was fully filled, the buyer must get their deposit back
              contract_order_min_ada
            } else {
              // If not, then they must not
              0
            })?,
            // Token amount must exactly match the taker payment including the platform fee
            // Since the taker always pays the fee, we must use the amount before fee deduction
            (maker_income == ( taker_income + platform_fee ) / traded_asset_price_init)?,
            // And the fee itself must be correct
            (platform_fee == max(
              maker_income * traded_asset_price_init / ( 100 * base_fee ),
              platform_fee_min_amount,
            ))?,
          }
        (is_deal_fair, maker_income)
      }
      Sell -> {
        let maker_income = maker_output.value |> lovelace_of()
        let taker_income =
          taker_output.value
            |> quantity_of(traded_asset_policy_id_init, traded_asset_name_init)
        let platform_fee = platform_fee_output.value |> lovelace_of()
        let base_maker_income = taker_income * traded_asset_price_init
        // For a sell, the maker and platform receive ada, while the taker receives tokens
        // Our goal is to ensure everything is fair
        let is_deal_fair = and {
            // The maker must receive a specific amount of ada
            (maker_income == if taker_income == traded_asset_amount_init {
              // If the order was fully filled, the buyer must get their deposit back
              base_maker_income + contract_order_min_ada
            } else {
              // If not, then just the order payment
              base_maker_income
            })?,
            // The taker gets the amount of tokens corresponding to the payment received by the maker
            // We ignore the fee here because it doesn't affect outputs; it just adds to taker input spending
            (taker_income == maker_income / traded_asset_price_init)?,
            // The platform must receive its fee
            (platform_fee == max(
              taker_income * traded_asset_price_init / ( 100 * base_fee ),
              platform_fee_min_amount,
            ))?,
          }
        (is_deal_fair, taker_income)
      }
    }
  // Then check whether a deal of this amount is allowed
  let (is_deal_allowed, is_deal_partial) =
    if deal_amount < traded_asset_amount_init && partial_fulfillment_allowed_init {
      // If the deal is partially fulfilled and that is allowed, check that there is a correct contract output with the updated order
      expect [new_order_output, ..rest_outputs] = rest_outputs
      // Then check that it is formed and populated correctly:
      let is_new_order_valid =
        validate_order_output(
          new_order_output,
          order_marker,
          listing,
          tx_validity_range,
          Some(traded_asset_amount_init - deal_amount),
        )
      // Then check that the updated order datum has no changes except the asset amount
      let is_new_order_datum_not_corrupted = {
        let OrderDatum {
          order_type: order_type_new,
          traded_asset_policy_id: traded_asset_policy_id_new,
          traded_asset_name: traded_asset_name_new,
          traded_asset_amount: traded_asset_amount_new,
          traded_asset_price: traded_asset_price_new,
          partial_fulfillment_allowed: partial_fulfillment_allowed_new,
          order_timeout_date: order_timeout_date_new,
          order_maker_address: order_maker_address_new,
        } = new_order_output |> read_order_datum()
        and {
          (order_type_new == order_type_init)?,
          (traded_asset_policy_id_new == traded_asset_policy_id_init)?,
          (traded_asset_name_new == traded_asset_name_init)?,
          (traded_asset_amount_new == traded_asset_amount_init - deal_amount)?,
          (traded_asset_price_new == traded_asset_price_init)?,
          (partial_fulfillment_allowed_new == partial_fulfillment_allowed_init)?,
          (order_timeout_date_new == order_timeout_date_init)?,
          (order_maker_address_new == order_maker_address_init)?,
        }
      }
      // Then make sure there are no more contract outputs left
      expect [] = rest_outputs |> find_outputs_by_address(contract_address)
      (and {
          is_new_order_valid?,
          is_new_order_datum_not_corrupted?,
        }, True)
    } else if deal_amount == traded_asset_amount_init {
      // If the deal amount equals the order amount
      // Make sure there are no more contract or maker outputs left
      (and {
          ([] == ( rest_outputs |> find_outputs_by_address(contract_address) ))?,
          ([] == ( rest_outputs |> find_outputs_by_address(maker_address) ))?,
        }, False)
    } else {
      // All other cases are invalid
      (False, False)
    }
  // Then ensure that the maker received nothing except ada + traded_asset
  let is_maker_output_ok =
    ( maker_output.value |> policies() ) == when order_type_init is {
      Buy -> ["", traded_asset_policy_id_init]
      Sell -> [""]
    }

  (and {
      is_traded_asset_listed?,
      is_maker_address_correct?,
      is_maker_output_ok?,
      is_platform_address_correct?,
      is_validity_range_ok?,
      is_deal_allowed?,
      is_deal_fair?,
    }, is_deal_partial)
}
