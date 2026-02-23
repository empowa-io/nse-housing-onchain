use aiken/collection/list.{has}
use aiken/interval.{is_entirely_after}
use cardano/address.{Address, VerificationKey}
use cardano/assets.{PolicyId, from_asset, merge, policies, zero}
use cardano/transaction.{Output, OutputReference, Transaction}
use config.{contract_listing_marker, contract_order_marker}
use helpers.{
  build_markers, discover_contract_utxo_addr_pid, find_outputs_by_address,
  find_outputs_by_marker, read_config_datum, read_listing_datum,
  read_order_datum, to_outputs, validate_authorization, validate_markers_mint,
  validate_order_output,
}
use subvalidators.{
  validate_config_update, validate_deal, validate_listing_update,
}
use types.{
  Bootstrap, Cleaning, ConfigDatum, Configuration, ContractMode, Delisting,
  Listing, OrderCanceling, OrderChanging, OrderDatum, OrderExecution,
  OrderPlacing,
}

validator exchange {
  mint(redeemer: ContractMode, contract_policy_id: PolicyId, tx: Transaction) {
    let (contract_utxo, contract_address, _) =
      discover_contract_utxo_addr_pid(tx, contract_policy_id)

    let (config_marker, listing_marker, order_marker) =
      build_markers(contract_policy_id)

    let Transaction {
      reference_inputs: tx_ref_inputs,
      inputs: tx_inputs,
      outputs: tx_outputs,
      validity_range: tx_validity_range,
      mint: tx_mint,
      ..
    } = tx

    when redeemer is {
      Bootstrap ->
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
        //     - a signature corresponding to the `contract_operator_keyhash` field in the datum

        validate_config_update(tx, config_marker)
      Listing ->
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
        validate_listing_update(tx, redeemer, config_marker, listing_marker)

      Delisting ->
        // A correct delisting transaction must contain:
        //   Reference inputs[1]:
        //     - Reference to the contract valid `config eUTxO`
        //   Inputs[>=1]:
        //     - one or many inputs from the contract address containing:
        //       - 1 token `contract_policy_id.contract_listing_marker` per input
        //   Outputs[>=0]:
        //     - any number of outputs to other addresses if needed (not validated)
        //      - no outputs containing `contract_policy_id.contract_listing_marker`
        //   Minting:
        //     - exactly -1 `contract_policy_id.contract_listing_marker` per listing input
        //   Additional signers:
        //     - a signature corresponding to the `listing_operator_credential` field in the reference utxo datum
        validate_listing_update(tx, redeemer, config_marker, listing_marker)
      OrderPlacing -> {
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
        //     - a signature corresponding to the `order_maker_address` field in the spent utxo datum
        let ref_utxos = tx_ref_inputs |> to_outputs()
        expect [contract_output, ..rest] = tx_outputs

        expect [ConfigDatum { is_market_open, .. }] =
          ref_utxos
            |> find_outputs_by_marker(config_marker, strict_mode: True)
            |> list.map(read_config_datum)

        expect [listing_data] =
          ref_utxos
            |> find_outputs_by_marker(listing_marker, strict_mode: True)
            |> list.map(read_listing_datum)
        expect OrderDatum {
          order_maker_address: Address {
            payment_credential: VerificationKey(order_maker_keyhash),
            ..
          },
          ..
        } = contract_output |> read_order_datum()

        let is_order_output_valid =
          validate_order_output(
            contract_output,
            order_marker,
            listing_data,
            tx_validity_range,
            expected_asset_amount: None,
          )
        let only_one_contract_output =
          [] == ( rest |> find_outputs_by_address(contract_address) )

        let marker_minted_properly =
          validate_markers_mint(tx_mint, order_marker, 1)

        let is_action_authorized =
          validate_authorization(tx, order_maker_keyhash)

        and {
          is_market_open?,
          is_order_output_valid?,
          only_one_contract_output?,
          marker_minted_properly?,
          is_action_authorized?,
        }
      }
      OrderExecution ->
        // Minting during order execution is optional, so we just check whether the contract is involved in validating the UTXO spend and delegate to it
        and {
          validate_markers_mint(tx_mint, order_marker, -1),
          contract_utxo != None,
        }
      OrderCanceling -> {
        // A correct order canceling transaction must contain:
        //   Reference inputs[1]:
        //     - Reference to the contract valid `config eUTxO`
        //   Inputs[>=1]:
        //      - Exactly one input from the contract address containing the order eUTxO (`contract_policy_id.contract_order_marker` + OrderDatum)
        //      - Any number of user inputs if needed (not validated)
        //   Outputs[>=1]:
        //      - the output to the address associated with the `order_maker_address` keyhash in the order datum that holds the funds locked in the order
        //        - index 0
        //      - any number of outputs to other addresses if needed (not validated)
        //   Minting:
        //     - exactly -1 `contract_policy_id.contract_order_marker`
        //   Validity range[optional]:
        //     - may be omitted if cancellation is performed by an authorized party
        //     - For unauthorized closure, if `timeout` in the datum points to some date, the upper bound must be after that date
        //   Additional signers:    
        //     a) a signature corresponding to the `order_maker_address` field in the spent utxo datum
        //     b) OR a signature corresponding to the `contract_operator_keyhash` field in the config utxo datum
        // Validatiors: Minting + Spending
        let ref_utxos = tx_ref_inputs |> to_outputs()
        expect [maker_output, ..rest] = tx_outputs
        expect [ConfigDatum { is_market_open, contract_operator_keyhash, .. }] =
          ref_utxos
            |> find_outputs_by_marker(config_marker, strict_mode: True)
            |> list.map(read_config_datum)
        expect [order_input_output] =
          tx_inputs
            |> to_outputs()
            |> find_outputs_by_address(contract_address)

        let Output { value: order_value, .. } = order_input_output
        let OrderDatum { order_maker_address, order_timeout_date, .. } =
          order_input_output |> read_order_datum()
        expect Address {
          payment_credential: VerificationKey(order_maker_keyhash),
          ..
        } = order_maker_address
        let is_maker_output_address_valid =
          maker_output.address == order_maker_address
        let is_maker_output_value_valid =
          maker_output.value == (
            order_value
              |> merge(
                  from_asset(contract_policy_id, contract_order_marker, -1),
                )
          )
        let only_one_maker_output =
          [] == ( rest |> find_outputs_by_address(order_maker_address) )
        let marker_minted_properly =
          validate_markers_mint(tx_mint, order_marker, -1)
        let is_action_authorized_by_user =
          validate_authorization(tx, order_maker_keyhash)
        let is_action_authorized_by_operator =
          validate_authorization(tx, contract_operator_keyhash)
        let is_tx_outdated = and {
            tx_validity_range |> is_entirely_after(order_timeout_date),
            order_timeout_date != 0,
          }
        let is_action_authorized = or {
            (is_action_authorized_by_user && is_market_open)?,
            is_action_authorized_by_operator?,
            is_tx_outdated?,
          }
        and {
          is_market_open?,
          is_maker_output_address_valid?,
          is_maker_output_value_valid?,
          only_one_maker_output?,
          marker_minted_properly?,
          is_action_authorized?,
        }
      }
      _ -> False
    }
  }

  spend(_, redeemer: ContractMode, spent_utxo: OutputReference, tx: Transaction) {
    let Transaction {
      reference_inputs: tx_ref_inputs,
      inputs: tx_inputs,
      outputs: tx_outputs,
      validity_range: tx_validity_range,
      mint: tx_mint,
      ..
    } = tx

    expect (Some(contract_utxo), contract_address, contract_policy_id) =
      discover_contract_utxo_addr_pid(tx, spent_utxo)
    let (config_marker, listing_marker, order_marker) =
      build_markers(contract_policy_id)
    when redeemer is {
      Configuration ->
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

        validate_config_update(tx, config_marker)

      Delisting ->
        // Since the delisting process requires both Spend and Mint checks,
        // validation can be implemented in just one sub-validator without code duplication.
        // During delisting, markers must be burned, so the transaction must include
        // burning markers on behalf of the contract.
        // If this requirement is met, allow spending the UTXO, because the Mint
        // sub-validator will be invoked next and perform the full validation.
        // And the mint check is much cheaper (it has no utxo multiplier for mem\cpu)
        assets.quantity_of(tx_mint, contract_policy_id, contract_listing_marker) < 0
      Cleaning -> {
        // A correct order changing transaction must contain:
        //   Reference inputs:
        //     - Reference to the contract valid `config eUTxO`
        //   Inputs[>=1]:
        //      - Any number of UTXOs from the contract address that can be considered garbage:
        //          - UTXOs that do not contain markers with contract_policy_id: contract_order_marker|contract_config_marker|contract_listing_marker.
        //      - Any number of inputs from any other addresses
        //   Minting:
        //     - minting is prohibited as such and will not be possible because the Mint validator will not support the corresponding mode
        //   Additional signers:
        //     - a signature corresponding to the `contract_operator_keyhash` field in the config UTXO datum
        //  
        //   Here we cannot shift the check to Mint, and with multiple UTXOs
        //   we would multiply resource usage and cost. Fortunately, this
        //   sub-validator is very simple and cheap.

        expect [config_ref] =
          tx_ref_inputs
            |> to_outputs()
            |> find_outputs_by_marker(config_marker, strict_mode: True)

        let ConfigDatum { contract_operator_keyhash, .. } =
          config_ref |> read_config_datum()

        let Output { value: contract_utxo_value, .. } = contract_utxo

        let utxo_is_garbage =
          !(contract_utxo_value
            |> policies()
            |> has(contract_policy_id))

        let mint_is_empty = tx_mint == zero

        let is_action_authorized =
          validate_authorization(tx, contract_operator_keyhash)

        and {
          utxo_is_garbage?,
          mint_is_empty?,
          is_action_authorized?,
        }
      }
      OrderChanging -> {
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
        //     - a signature corresponding to the `order_maker_address` field in the spent utxo datum
        //     - a signature corresponding to the `order_maker_address` field in the contract output utxo datum
        let ref_utxos = tx_ref_inputs |> to_outputs()

        expect [ConfigDatum { is_market_open, .. }] =
          ref_utxos
            |> find_outputs_by_marker(config_marker, strict_mode: True)
            |> list.map(read_config_datum)

        expect [listing_data] =
          ref_utxos
            |> find_outputs_by_marker(listing_marker, strict_mode: True)
            |> list.map(read_listing_datum)

        expect [contract_utxo] =
          tx_inputs |> to_outputs() |> find_outputs_by_address(contract_address)
        expect [contract_output, ..rest] = tx_outputs

        expect OrderDatum {
          order_maker_address: Address {
            payment_credential: VerificationKey(new_order_maker_keyhash),
            ..
          },
          ..
        } = contract_output |> read_order_datum()

        expect OrderDatum {
          order_maker_address: Address {
            payment_credential: VerificationKey(old_order_maker_keyhash),
            ..
          },
          ..
        } = contract_utxo |> read_order_datum()

        let is_order_output_valid =
          validate_order_output(
            contract_output,
            order_marker,
            listing_data,
            tx_validity_range,
            expected_asset_amount: None,
          )
        let only_one_contract_output =
          [] == ( rest |> find_outputs_by_address(contract_address) )

        let tx_has_no_mint = tx_mint == zero

        let is_action_authorized_by_old_owner =
          validate_authorization(tx, old_order_maker_keyhash)

        let is_action_authorized_by_new_owner =
          validate_authorization(tx, new_order_maker_keyhash)

        let is_action_authorized = and {
            is_action_authorized_by_old_owner,
            is_action_authorized_by_new_owner,
          }

        and {
          is_market_open?,
          is_order_output_valid?,
          only_one_contract_output?,
          tx_has_no_mint?,
          is_action_authorized?,
        }
      }
      OrderExecution -> {
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
        let ref_utxos = tx_ref_inputs |> to_outputs()
        expect [config_data] =
          ref_utxos
            |> find_outputs_by_marker(config_marker, strict_mode: True)
            |> list.map(read_config_datum)
        expect [listing_data] =
          ref_utxos
            |> find_outputs_by_marker(listing_marker, strict_mode: True)
            |> list.map(read_listing_datum)

        expect [contract_utxo] =
          tx_inputs |> to_outputs() |> find_outputs_by_address(contract_address)

        let ConfigDatum { is_market_open, .. } = config_data
        let (is_deal_valid, is_deal_partial) =
          validate_deal(
            contract_utxo,
            config_data,
            listing_data,
            tx_validity_range,
            order_marker,
            tx_outputs,
          )
        // Check that there is no extra minting in the transaction
        let is_minting_ok =
          when is_deal_partial is {
            True -> tx_mint == zero
            False -> tx_mint |> validate_markers_mint(order_marker, -1)
          }
        and {
          is_market_open?,
          is_deal_valid?,
          is_minting_ok?,
        }
      }
      OrderCanceling ->
        // Since the order canceling process requires both Spend and Mint checks,
        // validation can be implemented in just one sub-validator without code duplication.
        // During order canceling, markers must be burned, so the transaction must include
        // burning markers on behalf of the contract.
        // If this requirement is met, allow spending the UTXO, because the Mint
        // sub-validator will be invoked next and perform the full validation.
        // And the mint check is much cheaper (it has no utxo multiplier for mem\cpu)
        assets.quantity_of(tx_mint, contract_policy_id, contract_order_marker) < 0
      _ -> False
    }
  }

  else(_) {
    fail
  }
}
