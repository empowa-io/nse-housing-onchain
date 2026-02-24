
<!-- TOC -->
* [CONTRACT API Rules](#contract-api-rules)
  * [Bootstrap transaction](#bootstrap-transaction)
  * [Reconfiguration transaction](#reconfiguration-transaction-)
  * [Listing transaction](#listing-transaction)
  * [Delisting transaction](#delisting-transaction)
  * [Order Placing transaction](#order-placing-transaction)
  * [Order Changing transaction](#order-changing-transaction)
  * [Order Execution transaction](#order-execution-transaction)
  * [Order Canceling transaction](#order-canceling-transaction)
  * [Cleaning transaction](#cleaning-transaction)
<!-- TOC -->

# CONTRACT API Rules

## Bootstrap transaction
- Inputs [1]:
  - exactly one input using `contract_bootstrap_utxo_hash#contract_bootstrap_utxo_index`
- Outputs [>= 1]:
  - exactly one output to the contract address containing:
    - index `0`
    - `1` token `contract_policy_id.contract_config_marker`
    - a datum of type `ConfigDatum`
  - any number of outputs to other addresses if needed (not validated)
- Minting [1]:
  - exactly one `contract_policy_id.contract_config_marker`
- Additional signers:
  - a signature corresponding to the `contract_operator_keyhash` field in the datum
- Validators:
  - Minting only

## Reconfiguration transaction 
- Inputs [>=1]:
  - exactly one input with `contract_policy_id.contract_config_marker` inside
  - any other inputs if needed
- Outputs:
  - exactly one output to the contract address containing:
    - index `0`
    - `1` token `contract_policy_id.contract_config_marker`
    - a datum of type `ConfigDatum`
  - any number of outputs to other addresses if needed
- Minting:
  - forbidden
- Additional signers:
  - a signature corresponding to the `contract_operator_keyhash` field in the spent utxo datum
  - a signature corresponding to the `contract_operator_keyhash` field in the contract tx output datum
- Validators:
  - Spending only

## Listing transaction
- Reference inputs [1]:
  - reference to the contract valid `config eUTxO`
- Outputs [>=1]:
  - one or many outputs to the contract address containing:
    - `1` token `contract_policy_id.contract_listing_marker` per output
    - a valid datum of type `ListingDatum`
  - any number of outputs to other addresses if needed (not validated)
- Minting:
  - exactly `1` `contract_policy_id.contract_listing_marker` per contract output
- Additional signers:
  - a signature corresponding to the `listing_operator_credential` field in the reference utxo datum
- Validators:
  - Minting only

## Delisting transaction
- Reference inputs [1]:
  - reference to the contract valid `config eUTxO`
- Inputs [>=1]:
  - one or many inputs from the contract address containing:
    - `1` token `contract_policy_id.contract_listing_marker` per input
- Outputs [>=0]:
  - any number of outputs to other addresses if needed (not validated)
  - no outputs containing `contract_policy_id.contract_listing_marker`
- Minting:
  - exactly `-1` `contract_policy_id.contract_listing_marker` per listing input
- Additional signers:
  - a signature corresponding to the `listing_operator_credential` field in the reference utxo datum
- Validators:
  - Minting + Spending

## Order Placing transaction
- Inputs:
  - not validated
- Reference inputs [2]:
  - reference to the `listing eUTxO` allowing interaction with the asset being listed in the order
  - reference to the contract valid `config eUTxO`
- Outputs [>=1]:
  - exactly one output to the contract address containing:
    - index `0`
    - `1` token `contract_policy_id.contract_order_marker`
    - a datum of type `OrderDatum`
    - the required amount of locked assets depending on the order type (`Buy`/`Sell`)
    - `contract_order_min_ada` ADA (returned to the owner after the order is closed/executed)
  - any number of outputs to other addresses if needed (not validated)
- Minting:
  - exactly `1` `contract_policy_id.contract_order_marker`
- Validity range [optional]:
  - may be omitted if `timeout` in the datum is `0`
  - if `timeout` in the datum points to some date, the upper bound must be before that date
- Additional signers:
  - a signature corresponding to the `order_maker_keyhash` field in the spent utxo datum
- Validators:
  - Minting only

## Order Changing transaction
- Reference inputs [1]:
  - reference to the contract valid `config eUTxO`
  - reference to the `listing eUTxO` allowing interaction with the asset being listed in the order
- Inputs [>=1]:
  - exactly one input from the contract address containing the order eUTxO (`contract_policy_id.contract_order_marker` + `OrderDatum`)
  - any number of user inputs if needed (not validated)
- Outputs [>=1]:
  - exactly one output to the contract address containing:
    - index `0`
    - `1` token `contract_policy_id.contract_order_marker`
    - a datum of type `OrderDatum`
      - `traded_asset_price` must be `> 0`
    - the required amount of locked assets depending on the order type (`Buy`/`Sell`)
    - `contract_order_min_ada` ADA (returned to the owner after the order is closed/executed)
  - any number of outputs to other addresses if needed (not validated)
- Minting:
  - forbidden
- Additional signers:
  - a signature corresponding to the `order_maker_keyhash` field in the spent utxo datum
  - a signature corresponding to the `order_maker_keyhash` field in the contract output utxo datum
- Validators:
  - Spending only

## Order Execution transaction
- Reference inputs [2]:
  - reference to the contract valid `config eUTxO`
  - reference to the `listing eUTxO` allowing interaction with the asset being listed in the order
- Inputs [>=1]:
  - exactly one input from the `contract_address` containing the order eUTxO (`contract_policy_id.contract_order_marker` + `OrderDatum`)
  - any number of user inputs if needed (not validated)
- Outputs [>=3]:
  - exactly one output to the `maker_address` containing:
    - index `0`
    - the amount of assets/ada paid by the taker depending on the contract type (`Buy`/`Sell`)
    - [optional] the order's `contract_order_min_ada` if the order was closed
  - output to the `taker_address` containing:
    - index `1`
    - the amount of assets/ada paid to the taker depending on the contract type (`Buy`/`Sell`)
  - exactly one output to the platform address containing:
    - platform fee equals `(base_platform_fee_percent / 10^base_platform_fee_decimal_part)%` paid by the taker
    - but not less than `platform_fee_min_amount`
    - index `2`
  - [optional] exactly one output to the `contract_address` containing:
    - index `3`
    - `1` token `contract_policy_id.contract_order_marker`
    - a datum of type `OrderDatum` (correctly describing the current state of the order)
    - the required amount of locked assets depending on the order type (`Buy`/`Sell`)
    - `contract_order_min_ada` ADA (returned to the owner after the order is closed/executed)
    - for partial payments only
  - any number of outputs to other addresses if needed (not validated)
- Minting:
  - positive minting is forbidden in any case
  - if the order was not fully executed, burning is forbidden
  - if the order was closed entirely, the token `contract_policy_id.contract_order_marker` must be burned
- Validity range:
  - invalid after the timeout specified in the input datum
  - not required if timeout equals `0`, but allowed
- Extra rules:
  - partial execution of an order is available only if this is explicitly specified in the order settings
  - during partial redemption, only the quantity of the traded asset may change (by the amount sent to taker)
  - changing remaining datum fields is strictly forbidden
- Validators:
  - Spending [+ Minting]

## Order Canceling transaction
- Reference inputs [1]:
  - reference to the contract valid `config eUTxO`
- Inputs [>=1]:
  - exactly one input from the contract address containing the order eUTxO (`contract_policy_id.contract_order_marker` + `OrderDatum`)
  - any number of user inputs if needed (not validated)
- Outputs [>=1]:
  - the output to the address associated with `order_maker_keyhash` in the order datum that holds the funds locked in the order
    - index `0`
  - any number of outputs to other addresses if needed (not validated)
- Minting:
  - exactly `-1` `contract_policy_id.contract_order_marker`
- Validity range [optional]:
  - may be omitted if cancellation is performed by an authorized party
  - for unauthorized closure, if `timeout` in the datum points to some date, the lower bound must be after that date
- Additional signers:
  - signature of `order_maker_keyhash` from spent utxo datum
  - OR signature of `contract_operator_keyhash` from config utxo datum
  - OR nothing if timeout passed
- Validators:
  - Minting + Spending

## Cleaning transaction
- Reference inputs:
  - reference to the contract valid `config eUTxO`
- Inputs [>=1]:
  - any number of UTXOs from the contract address that can be considered garbage:
    - UTXOs that do not contain markers with `contract_policy_id`: `contract_order_marker`, `contract_config_marker`, `contract_listing_marker`
  - any number of inputs from any other addresses
- Minting:
  - prohibited (Mint validator does not support this mode)
- Additional signers:
  - a signature corresponding to the `contract_operator_keyhash` field in the config UTXO datum
- Validators:
  - Spending only
